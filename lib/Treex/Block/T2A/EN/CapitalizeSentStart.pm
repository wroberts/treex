package Treex::Block::T2A::EN::CapitalizeSentStart;
use utf8;
use Moose;
use Treex::Core::Common;
extends 'Treex::Block::T2A::CapitalizeSentStart';

has '+opening_punct' => ( isa => 'Str', is => 'ro', default => '({[‘“«‹|*"\'' );

1;

__END__

=encoding utf-8

=head1 NAME 

Treex::Block::T2A::EN::CapitalizeSentStart

=head1 DESCRIPTION

Capitalize the first letter of the first (non-punctuation)
token in the sentence, and do the same for direct speech sections.

This contains just English-specific settings for L<Treex::Block::T2A::CapitalizeSentStart>. 

=head1 AUTHORS 

Ondřej Dušek <odusek@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2014 by Institute of Formal and Applied Linguistics, Charles University in Prague
This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
