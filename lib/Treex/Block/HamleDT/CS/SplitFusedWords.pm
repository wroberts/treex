package Treex::Block::HamleDT::CS::SplitFusedWords;
use Moose;
use Treex::Core::Common;
use utf8;
extends 'Treex::Core::Block';



#------------------------------------------------------------------------------
# Splits certain tokens to syntactic words according to the guidelines of the
# Universal Dependencies.
#------------------------------------------------------------------------------
sub process_zone
{
    my $self = shift;
    my $zone = shift;
    my $root = $zone->get_atree();
    $self->split_fused_words($root);
}



#------------------------------------------------------------------------------
# Splits fused subordinating conjunction + conditional auxiliary to two nodes:
# abych, abys, aby, abychom, abyste
# kdybych, kdybys, kdyby, kdybychom, kdybyste
# Note: In theory there are other fused words that should be split (udělals,
# tos, sis, ses, cos, tys, žes, proň, oň, naň) but they do not appear in the
# PDT 3.0 data.
#------------------------------------------------------------------------------
sub split_fused_words
{
    my $self  = shift;
    my $root  = shift;
    my @nodes = $root->get_descendants({ordered => 1});
    foreach my $node (@nodes)
    {
        # Remember the index of the token.
        # When splitting occurs, we will have to re-index nodes with new integers but we will want to use the original indices when printing the CoNLL-U file.
        my $ord = $node->ord();
        $node->wild()->{decord} = $ord;
        my $parent = $node->parent();
        if($node->form() =~ m/^(a|kdy)(bych|bys|by|bychom|byste)$/i)
        {
            my $w1 = $1;
            my $w2 = $2;
            $w1 =~ s/^(a)$/$1by/i;
            $w1 =~ s/^(kdy)$/$1ž/i;
            my ($pchar, $person, $nchar, $number);
            if($w2 =~ m/^(bych|bychom)$/i)
            {
                $pchar = '1';
                $person = '1';
            }
            elsif($w2 =~ m/^(bys|byste)$/i)
            {
                $pchar = '2';
                $person = '2';
            }
            else
            {
                $pchar = '-';
                $person = '3';
            }
            if($w2 =~ m/^(bych|bys)$/i)
            {
                $nchar = 'S';
                $number = 'sing';
            }
            elsif($w2 =~ m/^(bychom|byste)$/i)
            {
                $nchar = 'P';
                $number = 'plur';
            }
            else
            {
                $nchar = '-';
                $number = '';
            }
            my @new_nodes = $self->split_fused_token
            (
                $node,
                {'form' => $w1, 'lemma'  => lc($w1), 'tag' => 'J,-------------',
                                'iset'   => {'pos' => 'conj', 'conjtype' => 'sub'},
                                'deprel' => 'mark'},
                {'form' => $w2, 'lemma'  => 'být',   'tag' => 'Vc-'.$nchar.'---'.$pchar.'-------',
                                'iset'   => {'pos' => 'verb', 'verbtype' => 'aux', 'verbform' => 'fin', 'mood' => 'cnd', 'number' => $number, 'person' => $person},
                                'deprel' => 'aux'}
            );
            foreach my $child ($new_nodes[0]->children())
            {
                # The second node is conditional auxiliary and it should depend on the participle of the content verb.
                if(($parent->is_root() || !$parent->is_participle()) && $child->is_participle())
                {
                    $new_nodes[1]->set_parent($child);
                    last;
                }
            }
        }
        elsif($node->form() =~ m/^(.+)(ť)$/i && $node->iset()->verbtype() eq 'verbconj')
        {
            my $w1 = $1;
            my $w2 = $2;
            my $iset_hash = $node->iset()->get_hash();
            delete($iset_hash->{verbtype});
            my @new_nodes = $self->split_fused_token
            (
                $node,
                {'form' => $w1, 'lemma'  => $node->lemma(), 'tag' => $node->tag(),
                                'iset'   => $iset_hash,
                                'deprel' => $node->conll_deprel()},
                {'form' => $w2, 'lemma'  => 'neboť', 'tag' => 'J^-------------',
                                'iset'   => {'pos' => 'conj', 'conjtype' => 'coor'},
                                'deprel' => 'cc'}
            );
            $new_nodes[1]->set_parent($new_nodes[0]);
        }
    }
}



#------------------------------------------------------------------------------
# Splits a node of a fused token into multiple new nodes, then deletes the old
# one.
#------------------------------------------------------------------------------
sub split_fused_token
{
    my $self = shift;
    my $fused_node = shift;
    my $parent = $fused_node->parent();
    my $root = $fused_node->get_root();
    my @new_node_descriptions = @_; # array of hash references
    my @new_nodes;
    foreach my $nn (@new_node_descriptions)
    {
        my $node = $parent->create_child();
        $node->set_form($nn->{form});
        $node->set_lemma($nn->{lemma});
        $node->set_tag($nn->{tag});
        $node->iset()->set_hash($nn->{iset});
        # The parent should not be root but it may happen if something in the previous transformations got amiss.
        if($parent->is_root())
        {
            $node->set_conll_deprel('root');
        }
        else
        {
            $node->set_conll_deprel($nn->{deprel});
        }
        push(@new_nodes, $node);
    }
    # We do not expect any children but since it is not guaranteed, let's make sure they are moved to $n1.
    my @children = $fused_node->children();
    foreach my $child (@children)
    {
        $child->set_parent($new_nodes[0]);
    }
    # Save information about the group in every new node.
    my $ord = $fused_node->ord();
    for(my $i = 0; $i <= $#new_nodes; $i++)
    {
        my $nn = $new_nodes[$i];
        my $nnw = $nn->wild();
        # We want the new node's ord to be between the fused node's ord and the next node's ord.
        # But we cannot set ord to a decimal number. Type control will not allow it. So we will use a wild attribute.
        $nn->_set_ord($ord);
        $nnw->{fused_ord} = $ord.'.'.($i+1);
        ###!!! Later we will want to make these attributes normal (not wild).
        $nnw->{fused_form} = $fused_node->form();
        ###!!! Adding these results in the "Out of memory" error.
        #$nnw->{fused_start} = $new_nodes[0];
        #$nnw->{fused_end} = $new_nodes[-1];
        $nnw->{fused} = ($i == 0) ? 'start' : ($i == $#new_nodes) ? 'end' : 'middle';
    }
    # Delete the fused node.
    $fused_node->remove();
    # Recompute node ordering so that all ords in the tree are integers again.
    my @nodes = sort {my $r = $a->ord() <=> $b->ord(); unless($r) {$r = $a->wild->{fused_ord} <=> $b->wild->{fused_ord}} $r} $root->get_descendants({ordered => 0});
    for(my $i = 0; $i<=$#nodes; $i++)
    {
        $nodes[$i]->_set_ord($i+1);
        delete($nodes[$i]->wild->{fused_ord});
    }
    return @new_nodes;
}



1;

=over

=item Treex::Block::HamleDT::CS::SplitFusedWords

Splits certain tokens to syntactic words according to the guidelines of the
Universal Dependencies.

=back

=cut

# Copyright 2014, 2015 Dan Zeman <zeman@ufal.mff.cuni.cz>

# This file is distributed under the GNU General Public License v2. See $TMT_ROOT/README.