package Treex::Block::HamleDT::GRC::Harmonize;
use Moose;
use Treex::Core::Common;
use utf8;
extends 'Treex::Block::HamleDT::HarmonizePDT';

#------------------------------------------------------------------------------
# Reads the Ancient Greek CoNLL trees, converts morphosyntactic tags to the positional
# tagset and transforms the tree to adhere to PDT guidelines.
#------------------------------------------------------------------------------
sub process_zone
{
    my $self = shift;
    my $zone = shift;
    my $root = $self->SUPER::process_zone($zone);
    ###!!! TODO: grc trees sometimes have conjunct1, coordination, conjunct2 as siblings. We should fix it, but meanwhile we just delete afun=Coord from the coordination.
    $self->check_apos_coord_membership($root);
    $self->check_afuns($root);
}

sub check_apos_coord_membership {
    my $self  = shift;
    my $root  = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        my $afun = $node->afun();
        if ($afun =~ /^(Apos|Coord)$/) {
            $self->identify_coap_members($node);
        }
    }
}

#------------------------------------------------------------------------------
# Convert dependency relation tags to analytical functions.
# http://ufal.mff.cuni.cz/pdt2.0/doc/manuals/cz/a-layer/html/ch03s02.html
#------------------------------------------------------------------------------
sub deprel_to_afun
{
    my $self  = shift;
    my $root  = shift;
    my @nodes = $root->get_descendants();

    foreach my $node (@nodes)
    {
        my $deprel = $node->conll_deprel();
        my $form   = $node->form();
        my $pos    = $node->conll_pos();

        # default assignment
        my $afun = $deprel;

        if ( $afun =~ /_CO$/ ) {
            $node->set_is_member(1);
        }

        # Remove all contents after first underscore
        if ( $afun =~ /^(([A-Za-z]+)(_AP)(_.+)?)$/ ) {
            $afun =~ s/^([A-Za-z]+)(_AP)(_.+)?$/$1_Ap/;
            $afun =~ s/^ExD_Ap/ExD/;
        }
        else {
            $afun =~ s/^([A-Za-z]+)(_.+)$/$1/;
        }

        #
        if ( $deprel =~ /^ADV/ ) {
            $afun = "Adv";
        }
        elsif ( $deprel =~ /^APOS/ ) {
            $afun = "Apos";
        }
        elsif ( $deprel =~ /^ATR/ ) {
            $afun = "Atr";
        }
        elsif ( $deprel =~ /^ATV/ ) {
            $afun = "Atv";
        }
        elsif ( $deprel =~ /^AtvV/ ) {
            $afun = "AtvV";
        }
        elsif ( $deprel =~ /^COORD/ ) {
            $afun = "Coord";
        }
        elsif ( $deprel =~ /^OBJ/ ) {
            $afun = "Obj";
        }
        elsif ( $deprel =~ /^OCOMP/ ) {
            $afun = "Obj";
        }
        elsif ( $deprel =~ /^PNOM/ ) {
            $afun = "Pnom";
        }
        elsif ( $deprel =~ /^PRED/ ) {
            $afun = "Pred";
        }
        elsif ( $deprel =~ /^SBJ/ ) {
            $afun = "Sb";
        }
        elsif ( $deprel =~ /^(UNDEFINED|XSEG|_ExD0_PRED)$/ ) {
            $afun = "Atr";
        }
        elsif ( $deprel =~ /^AuxP-CYCLE/ ) {
            $afun = "AuxP";
        }
        $node->set_afun($afun);
    }

    foreach my $node (@nodes) {
        # "and" and "but" have often deprel PRED
        if ($node->form =~ /^(και|αλλ’|,)$/ and grep {$_->is_member} $node->get_children) {
            $node->set_afun("Coord");
        }

        # no is_member allowed directly below root
        if ($node->is_member and $node->get_parent->is_root) {
            $node->set_is_member(0);
        }

    }
    # Coordination of prepositional phrases or subordinate clauses:
    # In PDT, is_member is set at the node that bears the real afun. It is not set at the AuxP/AuxC node.
    # In HamleDT (and in Treex in general), is_member is set directly at the child of the coordination head (preposition or not).
    $self->get_or_load_other_block('HamleDT::Pdt2TreexIsMemberConversion')->process_zone($root->get_zone());
}

1;

=over

=item Treex::Block::HamleDT::GRC::Harmonize

Converts Ancient Greek dependency treebank to the HamleDT (Prague) style.
Most of the deprel tags follow PDT conventions but they are very elaborated
so we have shortened them.

1. Morphological conversion             -> No

2. DEPREL conversion                    -> Yes

3. Structural conversion to match PDT   -> Yes



=back

=cut

# Copyright 2011, 2014 Dan Zeman <zeman@ufal.mff.cuni.cz>
# Copyright 2011 Loganathan Ramasamy <ramasamy@ufal.mff.cuni.cz>

# This file is distributed under the GNU General Public License v2. See $TMT_ROOT/README.
