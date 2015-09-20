package Treex::Block::HamleDT::Util::ExtractSurfaceNGrams;
use Moose;
use Treex::Core::Common;

extends 'Treex::Core::Block';

sub process_atree {
    my $self = shift;
    my $a_root = shift;
    my $language = $a_root->get_zone->language();
    my $fn = $a_root->get_document->loaded_from();
    for my $anode ( $a_root->get_descendants( { ordered => 1 } ) ) {
        my $ord = $anode->ord() || '_';
        my $form = $anode->form() || '_';
        my $id = $anode->get_id();
        my $iset_feats = $anode->iset()->as_string_conllx();
        my $p_ord = $anode->get_parent()->ord() || '_';
        print join("\t",
                   $language, $ord, $form, $iset_feats, $p_ord, $fn, $id
               ), "\n";
    }
    print "$language\t\n";
}

1;

__END__

=encoding utf-8

=head1 NAME

Treex::Block::HamleDT::Util::ExtractSurfaceNGrams;

=head1 DESCRIPTION

Prints the sentence in a pseudo-CoNNL format.
(Language, order, form, Interset features, parent order, filename, node id.)

=head1 AUTHOR

Jan Mašek <masek@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2014 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
