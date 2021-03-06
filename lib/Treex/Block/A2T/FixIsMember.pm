package Treex::Block::A2T::FixIsMember;
use Moose;
use Treex::Core::Common;
extends 'Treex::Core::Block';

sub process_ttree {
    my ( $self, $t_root ) = @_;
    my @all_nodes = $t_root->get_descendants();

    # (1) every member must be in coap
    foreach my $node ( grep { $_->is_member } @all_nodes ) {
        if ( !$node->get_parent()->is_coap_root() ) {
            $node->set_is_member(undef);
        }
    }

    # (2) there should be at least two members in every co/ap
    foreach my $node ( grep { $_->is_coap_root() } @all_nodes ) {
        unless ( grep { $_->is_member } $node->get_children ) {

            # mostly it's a childless PREC
            if ( $node->get_children <= 1 ) {
                $node->set_functor('PREC');
                # fix the node type as well
                $node->set_nodetype('atom');
            }
            # if there are at least two children, let's assume it really is a coordination             
            else {
                map { $_->set_is_member(1) } $node->get_children;
            }
        }
    }

    return 1;
}

1;

=over

=item Treex::Block::A2T::FixIsMember

The attribute C<is_member> (or, in some cases, C<functor>) is fixed:
(1) is_member can be set only below coap nodes, (2) below each
coap node there have to be at least two nodes with set is_member.

=back

=cut

# Copyright 2008 Zdenek Zabokrtsky

# This file is distributed under the GNU General Public License v2. See $TMT_ROOT/README.
