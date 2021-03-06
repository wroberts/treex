package Treex::Block::HamleDT::Test::AuxKAtEnd;
use utf8;
use Moose;
use Treex::Core::Common;
extends 'Treex::Block::Test::BaseTester';

# Tests if the punctuation at the end of sentence (hanged on the root) is AuxK

sub process_atree {
    my ( $self, $a_root ) = @_;

    my $last_subtree = ($a_root->get_descendants({ordered=>1}))[-1];
    if ($last_subtree->afun !~ /Aux[XK]/) {
        return; # sentence does not have punctuation at all
    }

    # if it has punctuation at the end, test if it's AuxK
    foreach my $a_node  ($a_root->get_children()) {
        if ($a_node->afun eq "AuxK") {
            return; # ending punctuation found => does not complain
        }
    }

    $self->complain($a_root);
}

# (C) 2012 Jindřich Libovický <jlibovicky@gmail.com>

1;
