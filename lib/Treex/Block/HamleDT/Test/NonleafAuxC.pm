package Treex::Block::HamleDT::Test::NonleafAuxC;
use Moose;
use Treex::Core::Common;
extends 'Treex::Block::Test::BaseTester';

sub process_anode {
    my ( $self, $anode ) = @_;
    if (( $anode->afun || '' ) eq 'AuxC'
        && !$anode->get_echildren
        && ( $anode->get_parent->afun || '' ) ne 'AuxC'
        )
    {
        $self->complain($anode);
    }
    return;
}

1;

=over

=item Treex::Block::HamleDT::Test::NonleafAuxC

AuxC must not be a leaf node (unless governed by some other AuxC
within a complex subordinating conjunction).

=back

=cut

# Copyright 2011 Zdenek Zabokrtsky
# This file is distributed under the GNU GPL v2 or later. See $TMT_ROOT/README.
