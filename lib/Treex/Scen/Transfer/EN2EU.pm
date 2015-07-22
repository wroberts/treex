package Treex::Scen::Transfer::EN2EU;
use Moose;
use Treex::Core::Common;


has domain => (
     is => 'ro',
     isa => enum( [qw(general IT)] ),
     default => 'general',
     documentation => 'domain of the input texts',
);

has hmtm => (
     is => 'ro',
     isa => 'Bool',
     default => 1,
     documentation => 'Apply HMTM (TreeViterbi) with TreeLM reranking',
);

has gazetteer => (
     is => 'ro',
     isa => 'Bool',
     default => undef,
     documentation => 'Use W2A::EN::GazeteerMatch A2T::ProjectGazeteerInfo T2T::EN2EU::TrGazeteerItems',
);

sub BUILD {
    my ($self) = @_;
    if (!defined $self->gazetteer){
        $self->{gazetteer} = $self->domain eq 'IT' ? 1 : 0;
    }
    return;
}


sub get_scenario_string {
    my ($self) = @_;
    
    my $TM_DIR= 'data/models/translation/en2eu';
    
    my $scen = join "\n",
    'Util::SetGlobal language=eu selector=tst',
    'T2T::CopyTtree source_language=en source_selector=src',
    #$self->gazetteer eq 'IT' ? 'T2T::EN2EU::TrGazeteerItems' : (),
    'T2T::EN2EU::TrLTryRules',
    "T2T::TrFAddVariants static_model=$TM_DIR/Pilot1_formeme.static.gz discr_model=$TM_DIR/Pilot1_formeme.maxent.gz",
    "T2T::TrLAddVariants static_model=$TM_DIR/Pilot1_tlemma.static.gz discr_model=$TM_DIR/Pilot1_tlemma.maxent.gz",
    'Util::DefinedAttr tnode=t_lemma,formeme message="after simple transfer"',
    #$self->domain eq 'IT' ? 'T2T::EN2ES::TrL_ITdomain' : (),
    'T2T::SetClauseNumber',
    ;

    return $scen;
}

1;

__END__


=encoding utf-8

=head1 NAME

Treex::Scen::Transfer::EN2EU - English-to-Basque TectoMT transfer (no analysis, no synthesis)

=head1 SYNOPSIS

 # From command line
 treex Scen::Transfer::EN2EU Write::Treex to=translated.treex.gz -- en_ttrees.treex.gz
 
 treex --dump_scenario Scen::Transfer::EN2EU

=head1 DESCRIPTION

This scenario expects input English text analyzed to t-trees in zone en_src.
The output (translated Basque t-trees) will be in zone eu_tst.

=head1 PARAMETERS

currently none

=head1 SEE ALSO

L<Treex::Scen::EN2EU> -- end-to-end translation scenario

=head1 AUTHORS

Gorka Labaka <gorka.labaka@ehu.eus>

=head1 COPYRIGHT AND LICENSE

Copyright © 2015 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.