package SEnglishT_to_TCzechT::Transform_passive_constructions;

use utf8;
use strict;
use warnings;
use List::MoreUtils qw(all);
use List::Util qw(first);

use base qw(TectoMT::Block);

# TODO: edit this list
my %IS_RAISING_VERB = map { $_ => 1 } qw(
    expect suppose believe allow require think assume permit estimate
    report forbid say intend);

sub process_bundle {
    my ( $self, $bundle ) = @_;
    my %to_be_deleted;
    NODE:
    foreach my $cs_node ( $bundle->get_tree('TCzechT')->get_descendants() ) {
        next NODE if !$cs_node->get_attr('is_passive');
        my $en_node = $cs_node->get_source_tnode() or next NODE;
        my $en_lemma = $en_node->get_attr('t_lemma');
        next NODE if !$IS_RAISING_VERB{$en_lemma};
        my @cs_children = $cs_node->get_children( { ordered => 1 } );
        next NODE if @cs_children != 2;
        my ( $cs_noun, $cs_verb ) = @cs_children;
        my ( $en_noun, $en_verb ) = map { $_->get_source_tnode() } @cs_children;
        next NODE if !$en_noun || !$en_verb;
        next NODE if $en_noun->get_attr('formeme') ne 'n:subj';
        next NODE if $en_verb->get_attr('formeme') ne 'v:to+inf';

        $cs_node->set_attr( 'is_passive', 0 );
        $cs_node->set_attr( 'voice',      'reflexive_diathesis' );
        my $perspron = $cs_node->create_child(
            {   attributes => {
                    t_lemma        => '#PersPron',
                    t_lemma_origin => 'rule-Transform_passive_constructions',
                    formeme        => 'n:1',                                    #TODO is this needed?
                    formeme_origin => 'rule-Transform_passive_constructions',
                    'gram/gender'  => 'neut',
                    'gram/numer'   => 'sg',
                    'functor'      => 'ACT',
                    'nodetype'     => 'complex',
                    }
            }
        );
        $perspron->shift_before_node($cs_node);

        $cs_verb->set_attr( 'gram/tense',     'post' );
        $cs_verb->set_attr( 'formeme',        'v:že+fin' );
        $cs_verb->set_attr( 'formeme_origin', 'rule-Transform_passive_constructions' );
        my $cor_node = first { $_->get_attr('t_lemma') eq '#Cor' } $cs_verb->get_children();
        $to_be_deleted{$cor_node} = $cor_node if $cor_node;

        $cs_noun->shift_before_subtree($cs_verb);
        $cs_noun->set_parent($cs_verb);
        $cs_noun->set_attr( 'formeme',        'n:1' );
        $cs_noun->set_attr( 'formeme_origin', 'rule-Transform_passive_constructions' );
    }

    foreach my $node ( values %to_be_deleted ) {
        $node->disconnect();
    }

    return;
}

1;

__END__

=over

=item SEnglishT_to_TCzechT::Transform_passive_constructions

 "Prices are expected to grow." -> "Očekává se, že ceny porostou."

 # Other realization are not implemented yet, e.g.:
 "Peter is expected to agree." -> "Od Petra se čeká, že bude souhlasit."
    
=back

=cut

# Copyright 2010 Martin Popel
# This file is distributed under the GNU General Public License v2. See $TMT_ROOT/README.
