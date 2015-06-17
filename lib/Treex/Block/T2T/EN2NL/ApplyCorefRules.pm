package Treex::Block::T2T::EN2NL::ApplyCorefRules;

use utf8;
use Moose;
use Treex::Core::Common;

use Treex::Tool::Coreference::NodeFilter::PersPron;

extends 'Treex::Core::Block';

sub process_tnode {
    my ($self, $tnode) = @_;

    my $src_tnode = $tnode->src_tnode;
    return if (!$src_tnode);

    # English personal and possessive pronouns
    if (Treex::Tool::Coreference::NodeFilter::PersPron::is_3rd_pers($src_tnode, {expressed => 1, reflexive => -1})) {
        my $src_anode = $src_tnode->get_lex_anode;
        my $src_form = $src_anode ? $src_anode->lemma : "-";

        my $src_gender = $src_tnode->gram_gender;
        # translating "she", "her" or "he", "him"
        if (defined $src_gender && $src_gender ne "neut") {
            $tnode->set_gram_gender($src_gender);
            $tnode->set_gram_number($src_tnode->gram_number);
            log_info "Non-neut gender of a personal pronoun: " . $src_form . " " . $tnode->get_address;
        }
        else {
            log_info "Neut gender of a personal pronoun, no antecedent: " . $src_form . " " . $tnode->get_address;
            my ($ante) = $tnode->get_coref_text_nodes();
            if (defined $ante) {
                log_info "Neut gender of a personal pronoun, having an antecedent: " . $src_form . " " . $tnode->get_address;
                $tnode->set_gram_gender($ante->gram_gender);
            }
        }
    }

}


1;

__END__

=encoding utf-8

=head1 NAME 

Treex::Block::T2T::EN2NL::ApplyCorefRules

=head1 DESCRIPTION


=head1 AUTHORS

Michal Novák <mnovak@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2015 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
