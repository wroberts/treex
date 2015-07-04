package Treex::Block::T2T::EN2CS::SetRelatLemmaByAnte;
use Moose;
use Treex::Core::Common;
extends 'Treex::Core::Block';

sub process_tnode {
    my ($self, $tnode) = @_;

    my $i = $tnode->gram_indeftype;
    return if !defined $i or $i ne 'relat';

    my ($ante) = $tnode->get_coref_nodes;
    if (defined $ante && $ante->formeme =~ /^v/) {
        $tnode->set_t_lemma("což");
    }
}

1;

__END__

=encoding utf-8

=head1 NAME

Treex::Block::T2T::EN2CS::SetRelatLemmaByAnte

=head1 DESCRIPTION


=head1 AUTHORS

Michal Novák <mnovak@ufal.mff.cuni.cz>


=head1 COPYRIGHT AND LICENSE

Copyright © 2015 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
