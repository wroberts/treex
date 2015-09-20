package Treex::Block::HamleDT::Test::UD::UnconvertedDependencies;
use Moose;
use Treex::Core::Common;
extends 'Treex::Block::Test::BaseTester';

sub process_anode
{
    my $self = shift;
    my $node = shift;
    my $deprel = $node->deprel();
    if($deprel =~ m/^dep:.*$/)
    {
        $self->complain($node, $deprel);
    }
}

1;

=over

=item Treex::Block::HamleDT::Test::UD::UnconvertedDependencies

If the Prague-to-UD conversion fails to convert an afun, the value will propagate
to the output data as an extension of C<dep>. For example, in the beginning we
were not able to convert C<AuxA>, which was not an official HamleDT 2.0 afun
but it appeared in the data anyway. It got to UD as C<dep:auxa>.

=back

=cut

# Copyright 2015 Dan Zeman
# This file is distributed under the GNU GPL v2 or later. See $TMT_ROOT/README.
