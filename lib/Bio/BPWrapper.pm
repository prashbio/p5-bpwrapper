#!/usr/bin/env perl
# Copyright (c) 2016 by Weigang Qui Lab

package Bio::BPWrapper;

our $VERSION = '1.01';
use strict; use warnings;

use constant PROGRAM => 'Bio::BPWrapper';

sub show_version() {
    PROGRAM . ", version $Bio::BPWrapper::VERSION";
}

unless (caller) {
    print show_version, "\n";
    print "Pssst... this is a module. See trepan.pl to invoke.\n"
}
1;

__END__
=pod

=for comment
This file is shared by both BPWrapper.pod in the BPWrapper.pm after its __END__
BPWrapper.pod is useful in the Github wiki:
https://github.com/rocky/p5-bwrapper/wiki/BPWrapper
where we can immediately see the results and others can contribute.

=begin html

=head1 Bio::BPWrapper

=head2 Introduction

Here we provide Perl Module Bio::BPWrapper, command-line utilities and Perl Modules which wrap L<Bio::Perl>. See the L<Qui Lab Bioutils wiki|http://diverge.hunter.cuny.edu/labwiki/Bioutils> for more detailed information.

=head2  What is this?

The main suite of is a series of command-line scripts written in Perl that provide convenient command-line access to popular I<Bio::Perl> methods.

Designed as UNIX utilities, these tools aim to circumvent a constant need (and urge) to write one-off I<Bio::Perl> scripts for routine manipulations of sequences, alignments and trees. And, of course, command-line tools are super-fast ways for data manipulation and exploration For the virtues of command-line tools see the O'Reilly Book: L<Data Science at Command Line by Jeroen Janssens|http://www.oreilly.com/pub/e/3115>.

There are a few interconnected command-line scripts:

=over

=item bioseq

a wrapper of BioPerl class L<Bio::Seq> with additional methods

=item bioaln

a wrapper of L<Bio::SimpleAlign> which inherits I<Bio::Seq> and additional methods)

=item biopop

a wrapper of L<Bio::PopGen> which can be converted from L<Bio::SimpleAlign> and additional methods)

=item biotree

a wrapper of L<Bio::TreeIO>, L<Bio::Tree::Tree>, and L<Bio::Tree::Node> with additional methods

=back

These utilities have been in development since Fall 2002 in Dr Weigang Qiu's lab at Hunter College of the City University of New York.

We welcome and encourage all developers to contribute any BioPerl-based utilities to this repository.
