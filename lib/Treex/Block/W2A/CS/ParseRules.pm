package Treex::Block::W2A::CS::ParseRules;
use Moose;
use Treex::Core::Common;
use utf8;
extends 'Treex::Core::Block';

sub process_atree {
    my ( $self, $aroot ) = @_;

    my @anodes = $aroot->get_descendants( { ordered => 1 } );

    # put syntactic adjectives below following nouns
    # and put prepositions above following nouns
    # TODO: handle Pnoms as well
    my $last_N = undef;
    foreach my $anode (reverse @anodes) {
        if ( $anode->tag =~ /^N/ ) {
            # noun
            $last_N = $anode; 
        } elsif ( $anode->tag =~ /^A|(P[8DLSWZ])|(C[dhkrwz])/
            && lc( $anode->lemma ) ne 'ten'
            && defined $last_N
        ) {
            # syntactic adjective
            $anode->set_parent($last_N);
            $anode->set_afun('Atr');
        } elsif ( $anode->tag =~ /^R/ && defined $last_N ) {
            # preposition
            $last_N->set_parent($anode);
            $anode->set_afun('AuxP');
            # the left side of last_N is now fixed
            $last_N = undef;
        } else {
            # the nounphrase must be contiguous,
            # here it has been broken by something
            # TODO: maybe coordinations are also OK?
            # what about commas?
            $last_N = undef;
        }
    }

    return;
}

1;

=pod

=encoding utf-8

=head1 NAME

Treex::Block::W2A::CS::ParseRules

=head1 DESCRIPTION

A simple partial rule-based parser to be used with Depfix.
Only parses what is relevant for Depfix corrections.
The idea is that the parse trees generated by MST parser are so bad,
as the SMT outputs are very bad,
that rule based parsing may actually perform better.

TODO: implement parse rules needed by all Depfix corrections.

TODO: use information from source side (projection).

=head1 AUTHORS

Rudolf Rosa <rosa@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2015 by Institute of Formal and Applied Linguistics, Charles
University in Prague

This file is distributed under the GNU General Public License v2.
See $TMT_ROOT/README for details on Treex licencing.
