package SEnglishA_to_SEnglishT::Fill_is_name_of_person;

use utf8;
use strict;
use warnings;

use base qw(TectoMT::Block);

sub process_bundle {
    my ( $self, $bundle ) = @_;
    my $t_root = $bundle->get_tree('SEnglishT');
    my @tnodes = $t_root->get_descendants;

    # Get all t-nodes recognized by named entity recognizer as personal names
    my @personal_tnodes = grep {
        my $n = $_->get_n_node();
        defined $n && $n->get_attr('ne_type') =~ /^p/
    } @tnodes;

    # Mark all the nodes except Mr., Mrs., and Ms.
    foreach my $tnode (@personal_tnodes) {
        if ( $tnode->t_lemma !~ /^(M(r|s|rs)|Judge)\.?$/ ) {
            $tnode->set_attr( 'is_name_of_person', 1 );
        }
    }
    return;
}

1;

=over

=item SEnglishA_to_SEnglishT::Fill_is_name_of_person

Attribute C<is_name_of_person> is filled according to named enities stored in n-tree.

=back

=cut

# Copyright 2010 Martin Popel
# This file is distributed under the GNU General Public License v2. See $TMT_ROOT/README.
