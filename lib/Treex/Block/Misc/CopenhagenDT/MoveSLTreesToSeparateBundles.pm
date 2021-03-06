package Treex::Block::Misc::CopenhagenDT::MoveSLTreesToSeparateBundles;

use utf8;
use Moose;
use Treex::Core::Common;
extends 'Treex::Core::Block';

sub process_bundle {
    my ( $self, $bundle ) = @_;

    my $SourceLanguage = $bundle->wild->{SourceLanguage};
    my @danish_trees = $bundle->get_zone($SourceLanguage)->get_atree->get_children;

    my $doc = $bundle->get_document;

    foreach my $tree (@danish_trees) {
        my $new_bundle = $doc->create_bundle();
        $new_bundle->{wild} = $bundle->{wild};

        my $new_zone = $new_bundle->create_zone($SourceLanguage);

        my $new_atree_root = $new_zone->create_atree;
        $tree->set_parent($new_atree_root);
    }

    return;
}

1;

=over

=item Treex::Block::Misc::CopenhagenDT::MoveDanishTreesToSeparateBundles

Create a new bundle for each Danish tree contained in the
first bundle megatree, and move the tree from the first bundle
to the new bundle. Danish is the hub language, so it must
be treated differently from other languages;

=back

=cut

# Copyright 2012 Zdenek Zabokrtsky
# This file is distributed under the GNU GPL v2 or later. See $TMT_ROOT/README.
