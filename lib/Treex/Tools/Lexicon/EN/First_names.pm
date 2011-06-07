package Treex::Tools::Lexicon::EN::First_names;
use utf8;
use strict;
use warnings;
use autodie;

#TODO: Better way how to make it automatically download.
my $FN = 'data/models/lexicon/en/first_names.tsv';
use Treex::Core::Resource;
Treex::Core::Resource::require_file_from_share($FN, 'Treex::Tools::Lexicon::EN::First_names');

my %GENDER_OF;
open my $F, '<:utf8', $ENV{TMT_ROOT}."share/$FN";
while(<$F>){
    chomp;
    my ($name, $f_or_m) = split /\t/, $_;
    $GENDER_OF{$name} = $f_or_m;
}
close $F;

sub gender_of {
    my ($first_name) = @_;
    return $GENDER_OF{lc $first_name};
}

1;

__END__

=head1 NAME

Treex::Tools::Lexicon::EN::First_names

=head1 SYNOPSIS

 use Treex::Tools::Lexicon::EN::First_names;
 print Treex::Tools::Lexicon::EN::First_names::gender_of('John'); # prints m
 print Treex::Tools::Lexicon::EN::First_names::gender_of('Mary'); # prints f
       Treex::Tools::Lexicon::EN::First_names::gender_of('XYZW'); # returns undef

=head1 DESCRIPTION

This module should include support for miscellaneous queries
involving English lexicon and morphology.  

=cut

# Copyright 2010 Martin Popel
# This file is distributed under the GNU General Public License v2. See $TMT_ROOT/README.