package Treex::Tool::TranslationModel::Features::EN_coref;
use strict;
use warnings;

sub _node_and_parent {
    my ( $tnode, $prefix, $coref_style ) = @_;
    return if $tnode->is_root();

    # features from the given tnode
    my %feats = (
        lemma     => $tnode->t_lemma,
        formeme   => $tnode->formeme,
        voice     => $tnode->voice,
        negation  => $tnode->gram_negation,
        tense     => $tnode->gram_tense,
        number    => $tnode->gram_number,
        person    => $tnode->gram_person,
        degcmp    => $tnode->gram_degcmp,
        sempos    => $tnode->gram_sempos,
        is_member => $tnode->is_member,
    );
    my $short_sempos = $tnode->gram_sempos;
    if ( defined $short_sempos ) {
        $short_sempos =~ s/\..+//;
        $feats{short_sempos} = $short_sempos;
    }

    # features from tnode's parent
    my ($tparent) = $tnode->get_eparents( { or_topological => 1 } );
    if ( !$tparent->is_root ) {
        $feats{precedes_parent} = $tnode->precedes($tparent);
    }

    if ( defined $coref_style && ($coref_style eq 'replace_child_parent' || $coref_style =~ /^add_/ ))  {
	    _replace_add_lemma_for_perspron(\%feats, $tnode, $coref_style);
    }

    # features from a-layer
    if (my $anode = $tnode->get_lex_anode) {
        $feats{tag} = $anode->tag;
        $feats{capitalized} = 1 if $anode->form =~ /^\p{IsUpper}/;
    }

    # features from n-layer (named entity type)
    if ( my $n_node = $tnode->get_n_node() ) {
        $feats{ne_type} = $n_node->ne_type;
    }

    my %f;
    while ( my ( $key, $value ) = each %feats ) {
        if ( defined $value ) {
	    if ( $key eq 'lemma' &&  ref($value) eq 'ARRAY' ) {
		my @values = map{$prefix.$key.'_'.$_}@$value;
		foreach my $v ( @values ) {
		    $f{ $v } = 1;	     
		}
	    }	
	    else {
                $f{ $prefix . $key } = $value;
	    }
	}
    }
    return %f;
}

sub _replace_add_lemma_for_perspron {
    my ($feats, $tnode, $coref_style) = @_;

    return if ($feats->{lemma} ne "#PersPron");
    
    my @chain = $tnode->get_coref_chain({ordered => 1});
    @chain = grep {$_->t_lemma ne "#PersPron" && $_->t_lemma ne "#Cor"} @chain;
    my @antes = grep {!scalar $_->get_coref_gram_nodes} @chain;

    return if (!@antes);

    my $anode = $tnode->get_lex_anode;
    my $lemma = $tnode->t_lemma;
    if (defined $anode) {
        $lemma = $anode->lemma;
    } 
    if ( $coref_style =~ /^replace/ ) {
        print STDERR "Replacing: " . $lemma . " -> " . $antes[0]->t_lemma . "\n";
        $feats->{lemma} = $antes[0]->t_lemma;
    }
    elsif ( $coref_style =~ /^add_ant/ ) {
        $feats->{lemma} = [ $tnode->t_lemma ];
        if ( $coref_style eq 'add_ant_closest' ) {
            print STDERR "Adding closest: " . $lemma . " -> " . $antes[0]->t_lemma . "\n";
            push @{$feats->{lemma}}, $antes[0]->t_lemma;
        }
        else {
            foreach my $ante ( @antes ) {
                print STDERR "Adding all: " . $lemma . " -> " . $ante->t_lemma . "\n";
                push @{$feats->{lemma}}, $ante->t_lemma;
            }
        }
    }
    #elsif ( $coref_style =~ /^add_children_of/ ) {
    #    my @children = ();
    #    if ( $coref_style eq 'add_children_of_closest_ant' ) {
    #        @children = $antes[0]->get_echildren;
    #    foreach my $child ( @children ) {
    #        print STDERR "Adding children of the closest ant: " . $lemma . " -> " . $child->t_lemma . "\n";
    #        push @{$feats->{lemma}}, $child->t_lemma;
    #    }
    #}
    #elsif ( $coref_style eq 'add_children_of_all_ant' ) {
    #    my @children = map {$_->get_echildren} @antes;

    #}
}

sub _child {
    my ( $tnode, $prefix, $coref_style ) = @_;
    my %feats = (
        lemma   => $tnode->t_lemma,
        formeme => $tnode->formeme,
    );

    if ( $coref_style =~ /^replace/ || $coref_style =~ /^add/ ) {
	    _replace_add_lemma_for_perspron(\%feats, $tnode, $coref_style);
    }

    if ( my $n_node = $tnode->get_n_node() ) {
        $feats{ne_type} = $n_node->ne_type;
    }
    if (my $anode = $tnode->get_lex_anode) {
        $feats{tag} = $anode->tag;
        $feats{capitalized} = 1 if $anode->form =~ /^\p{IsUpper}/;
    }


    my %f;
    while ( my ( $key, $value ) = each %feats ) {
        if ( defined $value ) {
            if ( $key eq 'lemma' &&  ref($value) eq 'ARRAY' ) {
                my @values = map{$prefix.$key.'_'.$_}@$value;
                foreach my $v ( @values ) {
                    $f{ $v } = 1;                   
                }
            }
            else {
                $f{ $prefix . $key . '_' . $value } = 1;
            }
        }
    }
    return %f;
}

sub _prev_and_next {
    my ( $tnode, $prefix ) = @_;
    if ( !defined $tnode ) {
        return ( $prefix . 'lemma' => '_SENT_' );
    }
    return ( $prefix . 'lemma' => $tnode->t_lemma, );

}

sub features_from_src_tnode {
    my ( $node, $arg_ref, $coref_style ) = @_;
    my ($parent) = $node->get_eparents( { or_topological => 1 } );

    my %features = (
        _node_and_parent( $node,   '' , undef ),
        _node_and_parent( $parent, 'parent_' , $coref_style ),
        _prev_and_next( $node->get_prev_node, 'prev_' ),
        _prev_and_next( $node->get_next_node, 'next_' ),
        ( map { _child( $_, 'child_' , $coref_style ) } $node->get_echildren( { or_topological => 1 } ) ),
    );

    if ( $node->get_children( { preceding_only => 1 } ) ) {
        $features{has_left_child} = 1;
    }

    if ( $node->get_children( { following_only => 1 } ) ) {
        $features{has_right_child} = 1;
    }

    # We don't have a grammateme gram/definiteness so far, so let's hack it
    AUX:
    foreach my $aux ( $node->get_aux_anodes ) {
        my $form = lc( $aux->form );
        if ( $form eq 'the' ) {
            $features{determiner} = 'the';
            last AUX;
        }
        elsif ( $form =~ /^an?$/ ) {
            $features{determiner} = 'a';
        }
    }
    if ( $arg_ref && $arg_ref->{encode} ) {
        encode_features_for_tsv( \%features );
    }
    return \%features;
}

sub encode_features_for_tsv {
    my ($feats_ref) = @_;
    my @keys = keys %{$feats_ref};
    foreach my $key (@keys) {
        my $new_key   = encode_string_for_tsv($key);
        my $value     = $feats_ref->{$key};
        my $new_value = encode_string_for_tsv($value);
        if ( $new_key ne $key ) {
            delete $feats_ref->{$key};
        }
        $feats_ref->{$new_key} = $new_value;
    }
    return;
}

# We need to escape spaces and equal signs,
# so features can be stored in name=value format (space-separated).
sub encode_string_for_tsv {
    my ($string) = @_;
    $string =~ s/%/%25/g;
    $string =~ s/ /%20/g;
    $string =~ s/=/%3D/g;
    return $string;
}

1;
