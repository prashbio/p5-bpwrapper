=encoding utf8

=head1 NAME

Bio::BPWrapper::TreeManipulations - Functions for biotree

=head1 SYNOPSIS

    use Bio::BPWrapper::TreeManipulations;
    # Set options hash ...
    initialize(\%opts);
    write_out(\%opts);

=cut

# Package global variables
my ($in, $out, $aln, %opts, $file, $in_format, $out_format, @nodes,
    $tree, $print_tree, $rootnode, @otus);

###################### subroutine ######################

package Bio::BPWrapper::TreeManipulations;

use strict;
use warnings;
use v5.10;
use Bio::BPWrapper;
use Bio::TreeIO;
use Bio::Tree::Tree;
use Bio::Tree::Node;
use Bio::Tree::TreeFunctionsI;
use Data::Dumper;

if ($ENV{'DEBUG'}) { use Data::Dumper }

use vars qw(@ISA @EXPORT @EXPORT_OK);

@ISA         = qw(Exporter);

@EXPORT      = qw(print_tree_shape edge_length_abundance swap_otus getdistance
                  sister_pairs countOTU reroot clean_tree delete_otus initialize
                  write_out bin);

=head1 SUBROUTINES

=head2 initialize()

Sets up most of the actions to be performed on an alignment.

Call this right after setting up an options hash.

Sets package variables: C<$in_format>, C<@nodes>, C<$tree>, C<$out_format>, and C<$out>.


=cut

sub initialize {
    my $opts_ref = shift;
    Bio::BPWrapper::common_opts($opts_ref);
    %opts = %{$opts_ref};

    $in_format = $opts{"input"} // 'newick';  # This doesn't work...or does it?
    $out_format = $opts{"output"} // "newick";
    $print_tree = 0;    # Trigger printing the tree.
    my $file = shift || "STDIN";

    $in = Bio::TreeIO->new(-format => $in_format, ($file eq "STDIN") ? (-fh => \*STDIN) : (-file => $file));
    $tree = $in->next_tree(); # get the first tree (and ignore the rest)

    $out      = Bio::TreeIO->new(-format => $out_format);
    @nodes    = $tree->get_nodes;
    $rootnode = $tree->get_root_node;
    foreach (@nodes) { push @otus, $_ if $_->is_Leaf }
}

sub pars_binary {
    my $trait_table_file = $opts{"ci"};
    open BIN, "<", $trait_table_file || die "no trait file: $trait_table_file\n";
    my ($sites, @colnames, @rownames);
    my $first_line = 1;
    while(<BIN>) {
	chomp;
	my @data = split /\t/, $_;
	if ($first_line) {
	    shift @data;
	    @colnames = @data;
	    $first_line = 0;
	    next;
	}

	my $otu = shift @data;
	push @rownames, $otu;
	die "check colnames\n" unless @colnames == @data;
	for(my $i=0; $i<=$#colnames; $i++) {
	    $sites->{$otu}->{$colnames[$i]} = $data[$i] ? 1:0; # force binary
	}
    }
    close BIN;

     foreach my $otu (@otus) {
#    die "otu id not found in rownames\n" unless &_check_id($node->id, \@rownames);
	foreach my $trait_name (@colnames) {
	    $otu->add_tag_value($trait_name, [$sites->{$otu->id}->{$trait_name}]);
	}
    }
#    print Dumper(\@otus); exit;

# Fitch algorithm: post-order traversal
    my @informative;
    for (my $i=0; $i<=$#colnames; $i++) {
	next unless &_is_informative($colnames[$i], $i);
	push @informative, $colnames[$i];
	$rootnode->add_tag_value($colnames[$i], &_fitch_parsimony($rootnode, $i, \@colnames));
	&_penny_parsimony($rootnode, $i, \@colnames) if @{$rootnode->get_tag_values($colnames[$i])} == 2; # only when root state unresolved
	my $ci = &_consistency_index($i, \@colnames);
	print join "\t", ($i+1, $colnames[$i], $ci);
	print "\n";
    }
}

sub _fitch_parsimony {
    my ($node,$index, $refcol)=@_; #warn $node->internal_id, "\t", $node->id() || "inode", "\n";
    my $ref_node_state;
    my @colnames = @{$refcol};
    if ($node->is_Leaf) {
#       warn $node->id, "\t", Dumper($node->get_tag_values($colnames[$index])), "\n";
        return $node->get_tag_values($colnames[$index]);
    } else {
        my @child = $node->each_Descendent;
        my ($ref0, $ref1);
        if ($child[0]->is_Leaf) { # child 0 is an OTU
            $ref0 = $child[0]->get_tag_values($colnames[$index]);
            if ($child[1]->is_Leaf) { # both child 0 & 1 are an OTU
                $ref1 = $child[1]->get_tag_values($colnames[$index]);
#               warn "got sis otu for inode ", $node->internal_id(), "\n";
                $ref_node_state = &_intersect_or_union($ref0, $ref1);
#               warn Dumper($node->get_tag_values($colnames[$index]));
            } else { # child 0 is an OTU, child 1 is an inode
                $ref_node_state = &_intersect_or_union($ref0, &_fitch_parsimony($child[1], $index, \@colnames));
            }
        } else { # child 0 is an inode
            if ($child[1]->is_Leaf) { # child 1 is an inode child 1 is an OTU
                $ref1 = $child[1]->get_tag_values($colnames[$index]);
#               warn "got sis otu for inode ", $node->internal_id(), "\n";
                $ref_node_state = &_intersect_or_union(&_fitch_parsimony($child[0], $index, \@colnames), $ref1);
            } else { # both inodes
                $ref_node_state = &_intersect_or_union(&_fitch_parsimony($child[0], $index, \@colnames), &_fitch_parsimony($child[1], $index, \@colnames));
            }
        }
        $node->add_tag_value($colnames[$index], $ref_node_state);
        return $ref_node_state;
    }
}

sub _intersect_or_union { # from Perl Cookbook
    my ($ref1, $ref2) = @_;
    my (%union, %isect);
    foreach my $e (@$ref1, @$ref2) {
        $union{$e}++ && $isect{$e}++; # Perl Cookbook ideom
    }
 #   warn Dumper(\%union, \%isect);

    if (@$ref1 == @$ref2) { # (0) U (0); (0) U (1); (1) U (1); (0,1) U (0,1)
        return [keys %union];
    } else { # (0) I (0,1); (1) I (0,1)
        return [keys %isect];
    }
}

sub _penny_parsimony {
    my $nd = shift;
    my $index = shift;
    my $refcol = shift;
    my @colnames = @{$refcol};
    my $ref_states = $nd->get_tag_values($colnames[$index]);
    my $ref_new;
    my $pa;
    return if $nd->is_Leaf;
    if ($pa = $nd->ancestor()) {
        my $ref_pa_state = $pa->get_tag_values($colnames[$index]);
        $ref_new = &_intersect_or_union($ref_states, $ref_pa_state); # intersect with with parent
    } else { # is the root
        $ref_new = [1]; # resolve root state using Penny parsimony: one gain only
    }
    $nd->add_tag_value($colnames[$index], $ref_new); # resolve root state using Penny parsimony: one gain only
    &_penny_parsimony($_, $index, \@colnames) for $nd->each_Descendent();
}

sub _is_informative {
    my $col_id = shift;
    my $index = shift;
    my @sts = map {$_->get_tag_values($col_id)->[0]} @otus;
    my %seen;
    $seen{$_}++ for @sts;
    if (keys %seen == 1) { #warn "$index: $col_id is constant\n";
        return 0 }
    foreach (keys %seen) {
        if ($seen{$_} == 1) { #warn "$index: $col_id is singleton\n";
            return 0 }
    }
#   warn "$index: $col_id is informative\n";
    return 1;
}

sub _consistency_index { # ratio of minimum (1 for a binary trait) to actural changes
    my $index = shift;
    my $ci = 0;
    my $refcol = shift;
    my @colnames = @{$refcol};
    foreach my $nd (@nodes) {
        next if $nd eq $rootnode;
        my $pa = $nd->ancestor();
        my $state = $nd->get_tag_values($colnames[$index])->[0]; # assuming fully resolved (only one state)
        my $pa_state = $pa->get_tag_values($colnames[$index])->[0];
        if ($state ne $pa_state) {
#            if ($state) {
#                push @{$gain_loss{'gain'}->{$nd->internal_id}}, $colnames[$index];
#                $fam_events{$colnames[$index]}->{$nd->internal_id}->{'gain'}++;
#            } else {
#                push @{$gain_loss{'loss'}->{$nd->internal_id}}, $colnames[$index];
#                $fam_events{$colnames[$index]}->{$nd->internal_id}->{'loss'}++;
#            }
            $ci++;
        }
    }
    return sprintf "%.4f", 1/$ci;
}

sub _check_id {
    my $st = shift;
    my $ref = shift;
    foreach my $id (@$ref) {
	return 1 if $st eq $id;
    }
    return 0;
}

sub print_tree_shape {
    my @matrix;
    my (%leaf, %inode);
    my $ct_leaf = 0;
    my $ct_inode = 0;
    for my $nd (@nodes) {
	if ($nd->is_Leaf()) {
	    $leaf{$nd->id} = ++$ct_leaf;
	} else {
	    $inode{$nd->internal_id} = ++$ct_inode;
	}
    }

    for my $nd (@nodes) {
	next if $nd->is_Leaf() || $nd eq $rootnode;
	my @dscs = $nd->each_Descendent;
	die $nd->internal_id . ": node has more than two descendants\n" unless @dscs == 2;
	my $id1 = $dscs[0]->is_Leaf
	    ? -1 * $leaf{$dscs[0]->id} : $inode{$dscs[0]->internal_id};
	my $id2 = $dscs[1]->is_Leaf
	    ? -1 * $leaf{$dscs[1]->id} : $inode{$dscs[1]->internal_id};
	if ($nd eq $rootnode) { # root at first
	    unshift @matrix, [ ($id1, $id2) ];
	} else {
	    push @matrix, [ ($id1, $id2) ]
	}
    }
    for (my $i = $#matrix; $i >=0; $i--) {
	print $matrix[$i]->[0], "\t", $matrix[$i]->[1], "\n";
    };
    #    print Dumper(\%leaf, \%inode);
}

sub edge_length_abundance {
    my @inodes;
    my @brs;
    push (@inodes, $_) for _walk_up($rootnode);

    for my $nd (@inodes) {
	next if $nd eq $rootnode;
        my $id = $nd->internal_id;
	my $ct_otus = 0;
        if ($nd->is_Leaf) {
	    $ct_otus = 1;
	} else {
	    foreach (&_each_leaf($nd)) {
		$ct_otus++;
	    }
	}
        push @brs, { 'id' => $id, 'num_tips' => $ct_otus, 'br_len' => $nd->branch_length() }
    }

    my $ct_tips = 0;
    foreach my $nd (@nodes) {
	$ct_tips ++ if $nd->is_Leaf();
    }

    for (my $k=1; $k<=$ct_tips; $k++) {
	my $total = 0;
	my @nds = grep { $_->{num_tips} == $k }  @brs;
	if (@nds) { $total += $_->{br_len} for @nds }
	printf "%d\t%.6f\n", $k, $total/$tree->total_branch_length();
    }
}

sub swap_otus {
    my @otus;
    my $otu_ct = 0;
    foreach (@nodes) {
	next unless $_->is_Leaf();
	push @otus, $_;
	$otu_ct++;
    }
    @otus = sort {$a->id() cmp $b->id() } @otus;
    my $ref_otu;
    if ($opts{'swap-otus'}) {
	$ref_otu = $tree->find_node($opts{'swap-otus'}) || die "node not found\n";
    } else {
	$ref_otu = $otus[0];
    }

    foreach my $nd (@otus) {
	next if $nd eq $ref_otu;
	my $nd_id = $nd->id();
	my $ref_id = $ref_otu->id();
	$nd->id("new_".$ref_id);
	$ref_otu->id("new_".$nd_id);
	say $tree->as_text($out_format);
	$nd->id($nd_id);
	$ref_otu->id($ref_id);
    }
}

# Get the distance between nodes
sub getdistance {
    my @dnodes = _name2node($opts{'dist'});
    if (scalar(@dnodes) != 2) { say "Error: Provide exactly two nodes/leaves to use with --dist" }
    else { say $tree->distance(-nodes => \@dnodes) }
}

sub sister_pairs {
    my @otus;
    my $otu_ct = 0;
    foreach (@nodes) {
	next unless $_->is_Leaf();
	push @otus, $_;
	$otu_ct++;
    }

    @otus = sort {$a->id() cmp $b->id() } @otus;
    for (my $i = 0; $i < $otu_ct; $i++) {
	my $pa_i = $otus[$i]->ancestor();
	for (my $j = $i+1; $j < $otu_ct; $j++) {
	    my $pa_j = $otus[$j]->ancestor();
	    print $otus[$i]->id, "\t", $otus[$j]->id, "\t";
	    print $pa_i eq $pa_j ? 1 : 0;
	    print "\n";
	}
    }
}

=head2 countOTU()

Print total number of OTUs (leaves).

=cut

sub countOTU {
	my $otu_ct = 0;
	foreach (@nodes) { $otu_ct++ if $_->is_Leaf() }
	say $otu_ct
}

=head2 reroot()

Reroot tree to node in C<$opts{'reroot'}> by creating new branch.

=cut

sub reroot {
    my $outgroup_id = $opts{'reroot'};
    my $outgroup    = $tree->find_node($outgroup_id);
#    my $newroot     = $outgroup->create_node_on_branch(-FRACTION => 0.5, -ANNOT => {id => 'newroot'});
    $tree->reroot($outgroup);
    $print_tree = 1;
}

sub clean_tree {
    foreach my $nd (@nodes) {
	$nd->branch_length(0) if $opts{'clean-br'};
	if ($opts{'clean-boot'}) {
	    $nd->bootstrap(0);
	    $nd->id('') unless $nd->is_Leaf;
	}
    }
    $print_tree = 1;
}

sub delete_otus {
    my $ref_otus = &_get_otus();
    my @otus_to_retain = &_remove_otus($ref_otus, $opts{'del-otus'});
#    print Dumper(\@otus_to_retain);
    $opts{'subset'} = join ",", @otus_to_retain;
    &subset();
}

sub _get_otus {
    my @list;
    foreach my $nd (@nodes) { push @list, $nd if $nd->is_Leaf }
    return \@list;
}

sub _remove_otus {
    my $ref = shift;
    my $str = shift;
    my @list;
    my @otus_to_remove = split /\s*,\s*/, $str;
    my %to_del;
    foreach (@otus_to_remove) { $to_del{$_} = 1 }
    
    foreach my $nd (@$ref) {
	push @list, $nd->id() unless $to_del{$nd->id()};
    }
    return @list;
}

sub multi2bi {
    foreach my $nd (@nodes) {
#	next if $nd eq $rootnode;
	&_add_node($nd);
    }
    $print_tree = 1;
}

sub _add_node {
    my $node = shift;
#    warn "processing\t", $node->internal_id, "\n";
    my @desc = $node->each_Descendent;
    return if scalar(@desc) <= 2;
#    warn "multifurcating node:\t", $node->internal_id, " ... add a new node\n";
    shift @desc; # retain the first descent
#    my $new_node = $node->create_node_on_branch(-FRACTION => 0.5, -FORCE => 1, -ANNOT=>{ -id => "new_id" });
    my $new_node = Bio::Tree::Node->new(-id => "new", -branch_length => 0);
    $node->add_Descendent($new_node);
#    warn "\ta new node created:\t", $new_node->id, "\n";
    foreach (@desc) {
	$node->remove_Descendent($_); # remove from grand-parent
#	warn "\t\tremove descendant:\t", $_->internal_id, "\n";
	$new_node->add_Descendent($_); # re-attarch to parent
#	warn "\t\tadd descendant to the new node:\t", $_->internal_id, "\n";
    }
    &_add_node($new_node);
}

# Subset a tree
sub subset {
	# Collect the subset of nodes from STDIN or from $_
    my @keep_nodes;
	if ($opts{'subset'}) { @keep_nodes = _name2node($opts{'subset'}) }
	else { my $ar = $_[0]; @keep_nodes = @$ar }

	# Collect list of descendents
    my @descendents;
    for my $nd (@keep_nodes) { push @descendents, $_ for $nd->get_all_Descendents }

    # Collect list of ancestors
    my @ancestors;
    my $tmp;
    for (@keep_nodes) {
	$tmp = $_;
        while ($tmp->ancestor) {
	    push @ancestors, $tmp->ancestor;
	    $tmp = $tmp->ancestor
	}
    }

    # Make a hash of nodes to keep
    my %keep = map { $_->internal_id => $_ } @keep_nodes;
    $keep{$_->internal_id} = $_ for @descendents;
    $keep{$_->internal_id} = $_ for @ancestors;

    # Remove all nodes but those in %keep
    for (@nodes) { $tree->remove_Node($_) unless exists($keep{$_->internal_id}) }

    # Clean up internal single-descendent nodes
    my @desc;
    my $nd_len;
    my $desc_len;
    for my $nd ($tree->get_nodes) {
	next if $nd == $rootnode;
	@desc = $nd->each_Descendent;
	next unless scalar(@desc) == 1;
	$nd_len   = $nd->branch_length()      || 0;
	$desc_len = $desc[0]->branch_length() || 0;
	$desc[0]->branch_length($nd_len + $desc_len);
	$nd->ancestor->add_Descendent($desc[0]);
	$tree->remove_Node($nd)
    }

    # Take care of the a single-descendent root node
    @desc = $rootnode->each_Descendent;
    if (scalar(@desc) == 1) {
	$rootnode->add_Descendent($_) for $desc[0]->each_Descendent;
	$tree->remove_Node($desc[0])
    }
    $print_tree = 1
}

# Print OTU names and lengths
sub print_leaves_lengths {
    foreach (@nodes) { say $_->id(), "\t", $_->branch_length() if $_->is_Leaf() }
}

# Get LCA
sub getlca {
    my @lca_nodes;
	if (_name2node($opts{'lca'})) { @lca_nodes = _name2node($opts{'lca'}) }
	else { my $ar = $_[0]; @lca_nodes = @$ar }
    my @nd_pair;
    my $lca;

    $nd_pair[0] = $lca_nodes[0];
    if (@lca_nodes > 1) {
        for (my $index = 1; $index < @lca_nodes; $index++) {
            $nd_pair[1] = $lca_nodes[$index];
            $lca = $tree->get_lca(-nodes => \@nd_pair);
            $nd_pair[0] = $lca
        }
		if (_name2node($opts{'lca'})) { say $lca->internal_id } else { return $lca }
    } elsif (@lca_nodes == 1) {
		if (_name2node($opts{'lca'})) { say $lca_nodes[0]->ancestor->internal_id }
		else { return $lca_nodes[0]->ancestor->internal_id }
	}
}

# Label nodes with their internal ID's
sub label_nodes {
    for (@nodes) {
        next if $_ == $rootnode;
        my $suffix = defined($_->id) ? "_" . $_->id : "";
        $_->id($_->internal_id . $suffix)
    }
    $print_tree = 1
}

# Print half-tree id distances between all pairs of nodes
sub listdistance {
    my (@leaves, @sortedleaf_names, @leafnames);
    foreach (@nodes) { push(@leaves, $_) if $_->is_Leaf() }

    # Make an alphabetical list of OTU names
    push @sortedleaf_names, $_->id foreach sort {lc($a->id) cmp lc($b->id)} @leaves;

    @leaves = ();

    #Rebuld leaf array with new alphabetical order
    push @leaves, $tree->find_node(-id => $_) foreach @sortedleaf_names;

    # Prints a half-matrix of distance values
    my $i = 1;
    for my $firstleaf (@leaves) {
        my @dnodes;
        for (my $x = $i; $x < scalar(@leaves); $x++) {
            @dnodes = ($firstleaf, $leaves[$x]);
            say join "\t", ($firstleaf->id(), $leaves[$x]->id(), $tree->distance(-nodes => \@dnodes))
        }
        $i++
    }
}

=head2 bin()

Divides tree into number of specified segments and counts branches up
to height the segment. Prints: bin_number, branch_count, bin_floor,
bin_ceiling.

=cut

sub bin {
	my $treeheight = _treeheight(\$tree);
	my $bincount = $opts{'ltt'};
	my $binsize = $treeheight/$bincount;
	my @bins;
	while ($treeheight > 0) {
		unshift @bins, $treeheight;
		$treeheight -= $binsize
	}
	# Handle imperfect division. When approaching 0, if a tiny number is found, such as 2e-17, assign it as 0 and ignore negatives that may follow.
	for (@bins) { shift @bins if $_ < 1e-10 }
	unshift @bins, 0;

	for (my $i=0; $i+1<@bins; $i++) {
		my $branchcount = 1; # branch from root
		# Starting from the root, add a branch for each found descendent
		$branchcount += _binrecursive(\$rootnode, $bins[$i+1]);
		printf "%3d\t%3d\t%.4f\t%.4f\n", $i+1, $branchcount, $bins[$i], $bins[$i+1];
	}
}

sub print_all_lengths{
    for (@nodes) {
        next if $_ == $rootnode;
	my $p_node = $_->ancestor();
	my ($p_id, $c_id);
	$p_id = $p_node->internal_id;
	$c_id = $_->is_Leaf ? $_->id() : $_->internal_id;
	say $p_id, "\t",  $c_id, "\t", $_->branch_length;
    }
}

sub random_tree{
	my @otus = _each_leaf($rootnode);
	my @sample;
	my $sample_size = $opts{"random"} == 0 ? int(scalar(@otus) / 2) : $opts{"random"};

	die "Error: sample size ($sample_size) exceeds number of OTUs (", scalar(@otus), ")" if $sample_size > scalar(@otus);

	# Use Reservoir Sampling to pick random otus.
	my @sampled = (1 .. $sample_size);
	for ($sample_size + 1 .. scalar(@otus)) {
		$sampled[rand(@sampled)] = $_ if rand() < $sample_size/$_
    }
	push @sample, $otus[--$_] for @sampled;
	&subset(\@sample)
}

# Depth to the root for a node
sub depth_to_root {
    say $_->depth for _name2node($opts{'depth'})
}

# Remove Branch Lenghts
#sub remove_brlengths {
#    foreach (@nodes) { $_->branch_length(0) if defined $_->branch_length }
#    $print_tree = 1
#}

sub alldesc {
    my @inodes;
    my $inode_id = $opts{'otus-desc'};

    if ($inode_id eq 'all') { push (@inodes, $_) for _walk_up($rootnode) }
    else { push @inodes, $tree->find_node(-internal_id => $inode_id) }

    for my $nd (@inodes) {
        print $nd->internal_id, " ";
        if ($nd->is_Leaf) { print $nd->id } else { print $_->id, " " for _each_leaf($nd) }
        print "\n"
    }
}

# Walks from starting OTU
sub walk {
    my $startleaf = $tree->find_node($opts{'walk'});
    my $curnode   = $startleaf->ancestor;
    my $last_curnode = $startleaf;
    my @decs;
    my %visited;
    my $totlen = 0;
    my @dpair;
    my $vcount = 0;

    $visited{$startleaf} = 1;

    while ($curnode) {
        $visited{$curnode} = 1;
        @dpair = ($last_curnode, $curnode);
        $totlen += $tree->distance(-nodes => \@dpair);
        _desclen($curnode, \%visited, \$totlen, \$vcount);
        $last_curnode = $curnode;
        $curnode = $curnode->ancestor
    }
}

# works for RAxML bipartition output and FastTree output with bootstrap values as node names
sub delete_low_boot_support {
   my $cutoff = $opts{'del-low-boot'} || die 'spcify cutoff, e.g., 0.75 or 75\n'; # default 75
   &_remove_branch($rootnode, \$cutoff);
   $print_tree = 1;
}

sub mid_point_root {
    my (@leaves, @sortedleaf_names, @leafnames);
    foreach (@nodes) { push(@leaves, $_) if $_->is_Leaf() }

    my $maxL=0;
    my ($node1, $node2);
    for (my $i=0; $i<$#leaves; $i++){
        my $firstleaf = $leaves[$i];
        for (my $j=$i+1; $j<scalar(@leaves); $j++){
            my $secondleaf = $leaves[$j];
            my $dis = $tree->distance(-nodes=>[$firstleaf, $secondleaf]);
	   # print $firstleaf->id, "\t", $secondleaf->id, "\t", $dis, "\n";
            if ($dis>=$maxL){
                $maxL = $dis;
                $node1 = $firstleaf;
                $node2 = $secondleaf;
            }
        }
    }

#    print Dumper($node1);

    if (!$maxL) { $print_tree = 1; return }

    my $nd = &_get_all_parents($node1,0,$maxL);
    $nd = &_get_all_parents($node2,0,$maxL) unless $nd;
    my ($node, $sumL) = @{$nd};

    my $nodeL = $node->branch_length();
    my $pnode = $node->ancestor();
    my $nodeL_new = $nodeL - $sumL + $maxL/2;

    $tree->reroot_at_midpoint($node);
    $pnode->branch_length($node->branch_length()*2-$nodeL_new);
    $node->branch_length($nodeL_new); 

    $print_tree = 1;
}

sub _get_all_parents {
    my $nd = shift;
    my $sumL = shift;
    my $mL = shift;
    $sumL += $nd->branch_length();
    return [$nd, $sumL] if $sumL >= $mL/2;
    return if $nd->ancestor() eq $rootnode;
    &_get_all_parents($nd->ancestor(), $sumL, $mL);
}

=head2 write_out()

Performs the bulk of the actions actions set via
L<C<initialize(\%opts)>|/initialize>.

Call this after calling C<#initialize(\%opts)>.

=cut

sub write_out {
    my $opts = shift;
    mid_point_root() if $opts->{'mid-point'};
    pars_binary() if $opts->{'ci'};
    getdistance() if $opts->{'dist'};
    delete_low_boot_support() if $opts->{'del-low-boot'};
    say $tree->total_branch_length() if $opts->{'length'};
    countOTU() if $opts->{'otus-num'};
    $print_tree = 1 if defined($opts->{'output'});
    reroot() if $opts->{'reroot'};
    subset() if $opts->{'subset'};
    print_leaves_lengths() if $opts->{'otus-all'};
    getlca() if $opts->{'lca'};
    label_nodes() if $opts->{'label-nodes'};
    listdistance() if $opts->{'dist-all'};
    bin() if $opts->{'ltt'};
    print_all_lengths() if $opts->{'length-all'};
    random_tree() if defined($opts->{'random'});
    depth_to_root() if $opts->{'depth'};
    alldesc() if $opts->{'otus-desc'};
    walk() if $opts->{'walk'};
    multi2bi() if $opts->{'multi2bi'};
    clean_tree() if $opts->{'clean-br'} || $opts->{'clean-boot'};
    delete_otus() if $opts->{'del-otus'};
    sister_pairs() if $opts->{'sis-pairs'};
    swap_otus() if $opts->{'swap-otus'};
    edge_length_abundance() if $opts->{'ead'};
    print_tree_shape() if $opts->{'tree-shape'};
    say $tree->as_text($out_format) if $print_tree;
}

################# internal subroutines ##############

sub _remove_branch {
    my $nd = shift;
    my $ref = shift;
    my $bootcut = $$ref;
    return if $nd->is_Leaf();
    my @desc = $nd->each_Descendent();
    my $pa = $nd->ancestor();
    foreach my $ch (@desc) {
	if (!$nd->id()) { # no boostrap as node id (in-group branch)
	    &_remove_branch($ch, $ref);
	    next;
	} 
	if ($nd->id() < $bootcut) {
	    $pa->remove_Descendent($nd); # remove the current node
	    $pa->add_Descendent($ch); # elevate the child node
	    $ch->branch_length($ch->branch_length() + $nd->branch_length()); # increment branch length
	}
	&_remove_branch($ch, $ref);
    }    
}

sub _name2node {
    my $str = shift;
    my @node_names = split /\s*,\s*/, $str;
    my $nd;
    my @node_objects;
    for my $node_name (@node_names) {
        $nd = $tree->find_node(-id => $node_name) || $tree->find_node(-internal_id => $node_name);
        if ($nd) { push @node_objects, $nd } else { say "Node/leaf '$node_name' not found. Ignoring..." }
    }
    return @node_objects
}

# _each_leaf ($node): returns a list of all OTU's descended from this node, if any
sub _each_leaf {
	my @leaves;
	for ($_[0]->get_all_Descendents) { push (@leaves, $_) if $_->is_Leaf }
	return @leaves
}

# main routine to walk up from root
sub _wu {
	my (@lf, @nd);
	my $curnode       = $_[0];
	my @decs          = $_[0]->each_Descendent;
	my $visitref      = $_[1];
	my %visited       = %$visitref;
	my $node_list_ref = $_[2];
#	my $ref_ct_otu    = $_[3];
#	my $ref_tatal_br_len = $_[4];

	for (@decs) {
#	    $ref_total_br_len += $_->branch_length;
	    if ($_->is_Leaf) {
		push @lf, $_;
#		$$ref_ct_otu++;
	    } else {
		push @nd, $_
	    }
	}

	for (@lf) { if (!exists($visited{$_})) { $visited{$_} = 1; push @$node_list_ref, $_ } }
	for (@nd) {
		next if exists($visited{$_});
		$visited{$_} = 1;
		push @$node_list_ref, $_;
		_wu($_, \%visited, $node_list_ref)
	}
}

# Walk Up: "Walks" up from a given node and returned an order array representing the order that each node descended from the given node was visited.
sub _walk_up {
	my %visited;
	my @node_list = $_[0];
	_wu($_[0], \%visited, \@node_list);
	return @node_list
}

sub _treeheight {
	my $height = 0;
	my $tree = $_[0];
	for ($$tree->get_nodes) { $height = $_->depth if $_->depth > $height }
	return $height
}

sub _binrecursive {

    my $branchcount = 0;
    my $noderef = $_[0];
    my $upper = $_[1];
    my @desc = $$noderef->each_Descendent;
    $branchcount-- unless $$noderef->is_Leaf;

    for (@desc) {
	$branchcount++;
	$branchcount += _binrecursive(\$_, $upper) if $_->depth <= $upper
    }
    return $branchcount
}

# Starting at a node that has 2 descendents, print the distance from start to desc if it's a leaf or call itself passing the internal-node descendent
# Input: basenode, internal node
sub _desclen {
    # startlear, curnode
    my (@dpair, @lf, @nd);
    my $curnode   = $_[0];
    my @decs      = $_[0]->each_Descendent;
    my $visitref  = $_[1];
    my $totlen    = $_[2];
    my $vcountref = $_[3];
    my %visited   = %$visitref;
    my $dist;

    for (@decs) { if ($_->is_Leaf) { push @lf, $_ } else { push @nd, $_ } }
    for (@lf) {
	next if exists($visited{$_});
	$visited{$_} = 1;
	$dpair[0] = $curnode;
	$dpair[1] = $_;
	$dist = $tree->distance(-nodes => \@dpair);
	$$totlen += $dist;
	$$vcountref++;
	say	$_->id, "\t$$totlen\t$$vcountref"
    }

    for (@nd) {
	next if exists($visited{$_});
	$visited{$_} = 1;
	$dpair[0] = $curnode;
	$dpair[1] = $_;
	$dist = $tree->distance(-nodes => \@dpair);
	$$totlen += $dist;
	_desclen($_, \%visited, $totlen, $vcountref)
    }
}

1;

__END__

=head1 SEE ALSO

=over 4

=item *

L<bioatree>: command-line tool for tree manipulations

=item *

L<Qui Lab wiki page|http://diverge.hunter.cuny.edu/labwiki/Bioutils>

=item *

L<Github project wiki page|https://github.com/bioperl/p5-bpwrapper/wiki>

=back

=head1 CONTRIBUTORS

=over 4

=item *
William McCaig <wmccaig at gmail dot com>

=item *
Girish Ramrattan <gramratt at gmail dot com>

=item  *
Che Martin <che dot l dot martin at gmail dot com>

=item  *
Yözen Hernández yzhernand at gmail dot com

=item *
Levy Vargas <levy dot vargas at gmail dot com>

=item  *
L<Weigang Qiu|mailto:weigang@genectr.hunter.cuny.edu> (Maintainer)

=item *
Rocky Bernstein

=back

=cut
