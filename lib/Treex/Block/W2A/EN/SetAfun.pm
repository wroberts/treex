package Treex::Block::W2A::EN::SetAfun;
use Moose;
use Treex::Moose;
extends 'Treex::Core::Block';

has '+language' => ( default => 'en' );

use Readonly;

sub process_atree {
    my ( $self, $a_root ) = @_;

    # Process heads of main clauses + the terminal punctuation (AuxK).
    # Then recursively process the whole tree.
    # (Rarely, there can be more terminal punctuations.!)
    # (There may be more heads and this is in case of coordinations.)
    foreach my $subroot ( $a_root->get_echildren() ) {
        $subroot->set_afun( get_afun_for_subroot($subroot) );
        process_subtree($subroot);
    }

    return 1;
}

sub get_afun_for_subroot {
    my ($subroot) = @_;
    my $afun = $subroot->afun;
    return $afun if $afun;
    return 'AuxK' if $subroot->form =~ /^[.?!]$/;
    return 'Pred' if $subroot->tag  =~ /^(V|MD)/;
    return 'ExD';
}

# For our actual purposes define nouns as tokens with tags
# NN, NNS, NNP, NNPS, PRP, PRP$, WP, WP$, CD, WDT or $.
my $NOUN_REGEX = qr/^(NN|PRP|WP|CD$|WDT$|\$)/;

sub process_subtree {
    my ($node) = @_;
    foreach my $subject ( find_subjects_of($node) ) {
        $subject->set_afun('Sb');
    }

    foreach my $child ( $node->get_echildren() ) {
        if ( !$child->afun ) {
            $child->set_afun( get_afun($child) );
        }
        process_subtree($child);
    }
    return;
}

# Marks auxiliary verbs "be, do, will, have" with afun=AuxV
# and returns the subject of $node if any.
# In case of coordinated subjects, returns all such subjects.
# The first step (marking AuxV) is done here,
# because it is needed for finding subjects.
sub find_subjects_of {
    my ($node) = @_;
    my $tag = $node->tag;

    # Only verbs can have subjects (and auxiliary verb children)
    return if $tag !~ /^(V|MD)/;

    # Mark all auxiliary verbs
    my @echildren = $node->get_echildren( { ordered => 1 } );
    my @left_echildren = grep { $_->precedes($node) } @echildren;
    foreach my $auxV ( grep { is_aux_verb( $_, $tag ) } @left_echildren ) {
        $auxV->set_afun('AuxV');
    }

    # If there are some subjects already recognized, we are finished.
    # This could happen when $node is AuxV - look 8 lines further.
    return if any { ( $_->afun || '' ) eq 'Sb' } @echildren;

    # Existential "there" is always a subject
    my $there = first { $_->tag eq 'EX' } @echildren;
    return $there if $there;

    # Get all noun children preceding the verb
    # Include also grandchildren under afun=AuxV and tag=MD, so we can handle:
    # "How do(afun=AuxV, parent=feel) you(afun=Sb, parent=do) feel?"
    # "Should(tag=MD, parent=happen) that(tag=DT,parent=Should) happen,..."
    # "You(parent=can) can(tag=MD,parent=go) go."
    # (It is not our business now, whether the modal verb should depend
    # on the main verb or vice versa. Parsers may give such outputs.)
    my @left_nouns =
        grep { $_->tag =~ /^(NN|PRP|WP|CD$|\$)/ }
        map { is_aux_or_modal_verb($_) ? $_->get_children() : $_ }
        @left_echildren;

    # Most common case: just one noun before verb -> subject
    return $left_nouns[0] if @left_nouns == 1;

    # More than 1 noun before verb:
    if ( @left_nouns > 1 ) {

        # It can be a coordination "Peter and Paul went there."
        my @coordinated = grep { $_->get_parent()->is_coap_root() } @left_nouns;
        return @coordinated if @coordinated;

        # Otherwise try the nearest noun before verb "This summer, it was ..."
        return $left_nouns[-1];
    }

    # No left nouns found, so get also some noun-like children -
    # "which" or "that" in relative clauses can be also subjects.
    @left_nouns = grep { $_->tag =~ /^(WDT|DT)/ } @left_echildren;
    return $left_nouns[0]  if @left_nouns == 1;
    return $left_nouns[-1] if @left_nouns;

    # "'It is reveresed', said Peter."
    if ( any { $_->tag =~ /^(V|MD)/ && $_->get_children() } @left_echildren ) {
        my $noun = first { $_->tag =~ $NOUN_REGEX } @echildren;
        return $noun if $noun;
    }

    return;
}

# Is $node one of auxiliary verbs: be, do, will, have?
# This subroutine is called only on nodes that precede their eff. parent.
sub is_aux_verb {
    my ( $node, $ep_tag ) = @_;
    my $lemma = $node->lemma;

    # "It has(parent=been) been(tag=VBN) 2 percent."
    return 1 if $lemma eq 'have' && $ep_tag eq 'VBN';

    # "It has(parent=incr.) been(parent=incr.) increasing(tag=VBG)."
    return 1 if $lemma eq 'have' && $ep_tag eq 'VBG' && before_been($node);

    # "It will(tag=MD, parent=be) be(tag=VB) 3 percent."
    # "It will(tag=MD, parent=gone) be gone(tag=VBN)."
    # "It will(tag=MD, parent=going) be going(tag=VBG)..."
    return 1 if $lemma eq 'will' && $ep_tag =~ /^VB[NG]?/ && $node->tag eq 'MD';

    # "It did/does(parent=change) not change(tag=VB/VBP)."
    return 1 if $lemma eq 'do' && $ep_tag =~ /^VBP?$/;

    # "It was(parent=incr.) increasing(tag=VBG)/increased(tag=VBN)."
    return 1 if $lemma eq 'be' && $ep_tag =~ /VB[NG]/;
    return 0;
}

sub is_aux_or_modal_verb {
    my ($node) = @_;
    return 1 if $node->afun eq 'AuxV';
    return $node->tag eq 'MD';
}

sub before_been {
    my ($node) = @_;
    my $next_node = $node->get_next_node() or return 0;
    return $next_node->form eq 'been';
}

# Handle remaining afuns, i.e. all except Aux[CPV] and Sb.
sub get_afun {
    my ($node) = @_;
    my $tag = $node->tag;

    # Possesive 's
    return 'Atr' if $tag eq 'POS';

    # Particles of phrasal verbs
    return 'AuxV' if $tag eq 'RP';

    # Punctuation
    # AuxK = terminal punctuation of a sentence
    # AuxG = other graphic symbols
    # AuxX = comma (not serving as Coord)
    my $form = $node->form;
    return 'AuxK' if $form =~ /[?!]/;
    return 'AuxX' if $form eq ',';
    return 'AuxG' if $form =~ /^[.()[\]{}]$/;    # TODO add :-/... (that's not an emoticon)

    # Articles a, an, the
    my $lemma = $node->lemma;
    return 'AuxA' if $lemma =~ /^(an?|the)$/;

    # Negation
    return 'Neg' if $lemma eq 'not';

    # Determiners (except the already solved articles)
    my ($eparent) = $node->get_eparents();
    my ( $ep_tag, $ep_lemma ) = $eparent->get_attrs( 'm/tag', 'm/lemma' );
    my $ep_is_noun = ( $ep_tag =~ $NOUN_REGEX );
    my $precedes_ep = $node->precedes($eparent);
    if ( $tag eq 'DT' ) {
        return 'Atr' if $ep_is_noun && $precedes_ep;
        return 'Adv' if $ep_tag =~ /^JJ/;
        return 'Obj' if $ep_tag =~ /^V/;
    }

    # Adjectives and possesive pronouns ("your", "mine")
    if ( $tag =~ /^(JJ|PRP\$)/ ) {
        return 'Pnom' if $ep_lemma eq 'be' && !$precedes_ep;
        return 'Atr' if $ep_is_noun;
        return 'NR';
    }

    # Adverbs
    if ( $tag =~ /^RB/ ) {
        return 'Atr' if $ep_is_noun;
        return 'Adv';
    }

    # Nouns/Verbs/Numerals/Predeterminers as Atr
    if ( $tag =~ $NOUN_REGEX || $tag =~ /^(V|MD|CD|PDT)/ ) {
        return 'Atr' if $ep_is_noun;
    }

    # Nouns/determiners/verbs under preposition
    my $grandpa = $eparent->get_parent();
    my $i_am_noun = $tag =~ $NOUN_REGEX;
    if ( ( $i_am_noun || $tag =~ /^(DT|V|MD)/ ) && $ep_tag =~ /^(IN|TO)/ && $grandpa ) {
        my $grandpa_tag = $grandpa->tag || '_root';
        return 'Adv' if $grandpa_tag =~ /^(V|MD)/;
        return 'Atr' if $grandpa_tag =~ $NOUN_REGEX;
        return 'Adv' if $i_am_noun;
    }

    # Nouns under verbs (but subjects are already solved)
    if ( $i_am_noun && $ep_tag =~ /^(V|MD)/ ) {

        # Adverbials are usually expressed by prepositional phrases
        # with a few exceptions - namely temporal modifiers expressed by nouns.
        # This is just a heuristics - we guess wrong cases like
        # "Do you remember that year?", but there's no English Vallex to help.
        return 'Adv' if $lemma =~ /^(year|month|week|spring|summer|autumn|winter)$/;    #&& $node->get_siblings();
        return 'Obj' if !$precedes_ep || $tag =~ /^W/;
        return 'NR';
    }

    # Verbs under verbs
    return 'Adv' if $tag =~ /^(V|MD)/ && $ep_tag =~ /^(V|MD)/;

    # And the rest - we don't know
    return 'NR';
}

1;

__END__

#TODO: to avoid having our music(afun=Obj,parent=compared) compared to

=over

=item Treex::Block::W2A::EN::SetAfun

Fill the afun attribute by several heuristic rules.
Before applying this block, afun values C<Coord> (coordinating conjunction),
C<AuxC> (subordination conjunction) and C<AuxP> (preposition) must be already filled.
This block doesn't change already filled afun values.

=back

=cut

# Copyright 2009 Martin Popel
# This file is distributed under the GNU General Public License v2. See $TMT_ROOT/README.
