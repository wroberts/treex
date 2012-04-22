package Treex::Tool::ReferentialIt::Features;

use Moose;
use Treex::Tool::Coreference::NADA;
use Treex::Block::Eval::AddPersPronIt;

has 'feature_names' => (
    is          => 'ro',
    required    => 1,
    isa         => 'ArrayRef[Str]',
    lazy        => 1,
    builder     => '_build_feature_names',
);

has '_nada_resolver' => (
    is => 'ro',
    isa => 'Treex::Tool::Coreference::NADA',
    required => 1,
    builder => '_build_nada_resolver',
);

has '_nada_probs' => (
    is => 'rw',
    isa => 'HashRef[Num]',
);

has '_en2cs_links' => (
    is => 'rw',
    isa => 'HashRef[Treex::Core::Node]',
);

sub _build_feature_names {
    my ($self) = @_;

    my @feat = qw/
        has_v_to_inf
        is_be_adj_err
        is_cog_verb
        is_cog_ed_verb_err
        nada_prob
    /;
}

sub _build_nada_resolver {
    my ($self) = @_;
    return Treex::Tool::Coreference::NADA->new();
}


sub create_instance {
    my ($self, $tnode, $en2cs_node) = @_;

    my $instance = {};

    my $alex = $tnode->get_lex_anode();

    my $verb;
    if ( ($tnode->gram_sempos || "") eq "v" ) {
        $verb = $tnode;
    }
    else {
        ($verb) = grep { ($_->gram_sempos || "") eq "v" } $tnode->get_eparents( { or_topological => 1} );
    }
    return 0 if (!defined $verb);
    
    $instance->{has_v_to_inf} = Treex::Block::Eval::AddPersPronIt::has_v_to_inf($verb);
    $instance->{is_be_adj} = Treex::Block::Eval::AddPersPronIt::is_be_adj($verb);
    $instance->{is_cog_verb} = Treex::Block::Eval::AddPersPronIt::is_cog_verb($verb);
    $instance->{is_be_adj_err} = Treex::Block::Eval::AddPersPronIt::is_be_adj_err($verb);
    $instance->{is_cog_ed_verb_err} = Treex::Block::Eval::AddPersPronIt::is_cog_ed_verb_err($verb);
    $instance->{has_cs_to} = Treex::Block::Eval::AddPersPronIt::has_cs_to($verb, $self->_en2cs_links->{$tnode});

    my ($it) = grep { $_->lemma eq "it" } $tnode->get_anodes;
    $instance->{en_has_ACT} = Treex::Block::Eval::AddPersPronIt::en_has_ACT($verb, $tnode, $it);
    $instance->{en_has_PAT} = Treex::Block::Eval::AddPersPronIt::en_has_PAT($verb, $tnode, $it);
    $instance->{make_it_to} = Treex::Block::Eval::AddPersPronIt::make_it_to($verb, $tnode);

    # TODO must be quantized
    $instance->{nada_prob} = $self->_nada_probs->{$alex->id};

    return $instance;
}

sub init_zone_features {
    my ($self, $zone) = @_;
    my $atree = $zone->get_atree;
    
    my $nada_probs = $self->_process_sentence_with_NADA( $atree );
    $self->_set_nada_probs( $nada_probs );
        
    # TODO #################  HACK ##########
    my $cs_src_tree = $zone->get_bundle->get_tree('cs','t','src');
    my %en2cs_node = Treex::Block::Eval::AddPersPronIt::get_en2cs_links($cs_src_tree);
    $self->_set_en2cs_links( \%en2cs_node );
}

sub _process_sentence_with_NADA {
    my ($self, $atree) = @_;
    my @ids = map {$_->id} $atree->get_descendants({ordered => 1});
    my @words = map {$_->form} $atree->get_descendants({ordered => 1});
    
    my $result = $self->_resolver->process_sentence(@words);
    my %it_ref_probs = map {$ids[$_] => $result->{$_}} keys %$result;
    
    return \%it_ref_probs;
}


1;
#TODO adjust POD
__END__

=encoding utf-8

=head1 NAME 

Treex::Tool::Coreference::CorefFeatures

=head1 DESCRIPTION

A role for coreference features, encapsulating unary features related to 
the anaphor (candidate), antecedent candidates' as well as binary features
related to both participants of the coreference relation. If generalized more,
this role might serve as an interface to features of any binary (or binarized) 
relation.

=head1 PARAMETERS

=over

=item feature_names

Names of features that should be used for training/resolution. This list is, 
however, not obeyed inside this class. Method C<create_instance> returns all 
features that are extracted here, providing no filtering. It is a job of the 
calling method to decide whether to check the returned instances if they comply 
with the required list of features and possibly filter them.

=head1 METHODS

=over

# TODO

=back

=head1 AUTHORS

Michal Novák <mnovak@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2012 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
