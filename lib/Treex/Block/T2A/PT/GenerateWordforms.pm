package Treex::Block::T2A::PT::GenerateWordforms;
use Moose;
use Treex::Core::Common;
extends 'Treex::Core::Block';

use Treex::Tool::Lexicon::Generation::PT;


has lxsuite_key => ( isa => 'Str', is => 'ro', required => 1 );
has lxsuite_host => ( isa => 'Str', is => 'ro', required => 1 );
has lxsuite_port => ( isa => 'Int', is => 'ro', required => 1 );
has generator => ( is => 'rw' );


sub process_anode {
    my ( $self, $anode ) = @_;
    return if defined $anode->form;
    $anode->set_form($self->generator->best_form_of_lemma($anode->lemma, $anode->iset));
    return;
}

sub BUILD {
    my ( $self, $argsref ) = @_;
	$self->set_generator(Treex::Tool::Lexicon::Generation::PT->new($argsref));
}

1;

__END__

=encoding utf-8

=head1 NAME 

Treex::Block::T2A::PT::GenerateWordforms - client for LX-Center

=head1 DESCRIPTION

Portuguese verbal conjugation and noun declination.
This block is just a client for a remote LX-Center server.

=head1 AUTHORS

João Rodrigues

=head1 COPYRIGHT AND LICENSE

Copyright © 2014 by Institute of Formal and Applied Linguistics, Charles University in Prague
This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
