package Treex::Block::HamleDT::PL::Harmonize;
use Moose;
use Treex::Core::Common;
use utf8;
extends 'Treex::Block::HamleDT::Harmonize';

has iset_driver =>
(
    is            => 'ro',
    isa           => 'Str',
    required      => 1,
    default       => 'pl::ipipan',
    documentation => 'Which interset driver should be used to decode tags in this treebank? '.
                     'Lowercase, language code :: treebank code, e.g. "cs::pdt". '.
                     'The driver must be available in "$TMT_ROOT/libs/other/tagset".'
);

my $debug = 0;



#------------------------------------------------------------------------------
# Reads the Polish tree, converts morphosyntactic tags to the PDT tagset,
# converts deprel tags to afuns, transforms tree to adhere to PDT guidelines.
# ### TODO ###
# - improve deprel_to_afun(),
#   - handling of complements of all types (incl. subordination)
#   - NumArgs
#   - PrepArgs (seem to be working quite well)
#   - eliminate 'NR's
#   - tabularize
# - improve coordination restructuring
#   (in particular for the sentence-level coordination with no 'pred' deprel)
# - test -> solve remaining problems
#------------------------------------------------------------------------------
sub process_zone
{
    my $self   = shift;
    my $zone   = shift;

    my $root = $self->SUPER::process_zone($zone);
#    $self->process_args($root);
    $self->attach_final_punctuation_to_root($root);
    $self->restructure_coordination($root, $debug);
    $self->process_prep_sub_arg_cloud($root);
    $self->check_afuns($root);
}



#------------------------------------------------------------------------------
# Different source treebanks may use different attributes to store information
# needed by Interset drivers to decode the Interset feature values. By default,
# the CoNLL 2006 fields CPOS, POS and FEAT are concatenated and used as the
# input tag. If the morphosyntactic information is stored elsewhere (e.g. in
# the tag attribute), the Harmonize block of the respective treebank should
# redefine this method. Note that even CoNLL 2009 differs from CoNLL 2006.
#------------------------------------------------------------------------------
sub get_input_tag_for_interset
{
    my $self   = shift;
    my $node   = shift;
    my $conll_pos  = $node->conll_pos();
    my $conll_feat = $node->conll_feat();
    # Compose a tag string in the form expected by the pl::ipipan Interset driver.
    $conll_feat =~ s/\|/:/g;
    return "$conll_pos:$conll_feat";
}



# ### TODO ### - currently not used
# # http://zil.ipipan.waw.pl/FunkcjeZaleznosciowe
# # http://ufal.mff.cuni.cz/pdt2.0/doc/manuals/cz/a-layer/html/ch03s02.html
# my %deprel2afun = (# "arguments"
#                  comp         => '',         # "complement" - adjectival/adverbial/nominal/prepositional; -> Atv/Adv/Atr/from_preposition
#                  comp_fin     => '',         # "clausal complement"; -> Atv?/Adv/Atr/Obj?/Subj?
# 		   comp_inf     => '',         # "infinitival complement"; -> Adv/Atr/Obj?/Subj?
# 		   obj          => 'Obj',      # "object"
# 		   obj_th       => 'Obj',      # "dative object"
# 		   pd           => '',         # "predicative complement"; -> 'Pnom' if the parent is the verb "to be", otherwise 'Obj'
# 		   subj         => 'Sb',       # "subject"
# 		   # "non-arguments"
# 		   adjunct      => '',         # any modifier; -> Adv/Atr/...
# 		   app          => 'Apposition',     # "apposition" ### second part depends on the first part (unlike in PDT, but same as in HamleDT (?))
# 		   complm       => 'AuxC',     # "complementizer" - introduces a complement clause (but is a child of its predicate, not a parent as in PDT)
# 		   mwe          => 'AuxY',     # "multi-word expression"
# 		   pred         => 'Pred',     # "predicate"
# 		   punct        => '',         # "punctuation marker"; -> AuxX/AuxG/AuxK
# 		   abbrev_punct => 'AuxG',     # "abbreviation mareker"
# 		   # "non-arguments (morphologicaly motivated)"
# 		   aglt         => 'AuxV',     # "mobile inflection" - verbal enclitic marked for number, person and gender
# 		   aux          => 'AuxV',     # "auxiliary"
# 		   cond         => 'AuxV',     # "conditional clitic"
# 		   imp          => 'AuxV',     # "imperative marker"
# 		   neg          => 'AuxZ',     # "negation marker"; ### AuxV
# 		   refl         => '',         # "reflexive marker"; -> AuxR/AuxT
# 		   # "coordination"
# 		   conjunct     => '',         # "coordinated conjunct"; is_member = 1, afun from the conjunction
# 		   coord        => 'Coord',    # "coordinating conjunction"
# 		   coord_punct  => '',         # "punctuation conjunction"; ->AuxX/AuxG
# 		   pre_coord    => 'AuxY',     # "pre-conjunction" - first, dependent part of a two-part correlative conjunction
# 		   # other
# 		   ne           => '',         # named entity
#    );

#------------------------------------------------------------------------------
# Try to convert dependency relation tags to analytical functions.
# http://zil.ipipan.waw.pl/FunkcjeZaleznosciowe
# http://ufal.mff.cuni.cz/pdt2.0/doc/manuals/cz/a-layer/html/ch03s02.html
# There are 25 distinct dependency relation tags: abbrev_punct adjunct aglt app
# aux comp comp_fin comp_inf complm cond conjunct coord coord_punct imp mwe ne
#  neg obj obj_th pd pre_coord pred punct refl subj; not including errors
# (twice 'interp' instead of 'punct' and once 'ne_' instead of 'ne')
# ### TODO ### - add comments to the individual conditions
#------------------------------------------------------------------------------
sub deprel_to_afun
{
    my $self   = shift;
    my $root   = shift;
    my @nodes  = $root->get_descendants();
    for my $node (@nodes)
    {
	my $deprel = $node->conll_deprel;
	my $parent = $node->get_parent();

# 	if ( $deprel2afun{$deprel} ) {
#             $node->set_afun( $deprel2afun{$deprel} );
#         }
#         else {
#             $node->set_afun('NR');
#         }

        # the deprels are sorted by their frequency in the data

        # adjunct - 'a non-subcategorised dependent with the modifying function'
        if ($deprel eq 'adjunct')
        {
            # parent is a verb, an adjective or an adverb -> Adv
            if ($parent->get_iset('pos') =~ m/^(verb)|(adj)|(adv)$/ )
            {
                $node->set_afun('Adv');
            }
            # parent is a noun -> Atr
            elsif ($parent->is_noun())
            {
                $node->set_afun('Atr');
            }
            # otherwise -> NR
            else
            {
                $node->set_afun('NR');
            }
        }
        # complement
        elsif ($deprel eq 'comp')
        {
            # parent is a preposition -> PrepArg - solved by a separate subroutine
            if ($parent->is_adposition())
            {
                $node->set_afun('PrepArg');
            }
            # parent is a numeral -> Atr (counted noun in genitive is governed by the numeral, like in Czech)
            elsif ($parent->is_numeral())
            {
                $node->set_afun('Atr');
            }
            # parent is a noun -> Atr
            elsif ($parent->is_noun())
            {
                $node->set_afun('Atr');
            }
            # parent is a verb
            elsif ($parent->is_verb())
            {
                # node is an adverb -> Adv
                if ($node->is_adverb())
                {
                    $node->set_afun('Adv');
                }
                # node is an adjective -> Atv
                elsif ($node->get_iset('pos') eq 'adj')
                {
                    $node->set_afun('Atv');
                }
                # node is a syntactic noun -> Obj
                elsif ($node->is_noun() or $node->conll_pos =~ m/(inf)|(ger)|(num)/)
                {
                    $node->set_afun('Obj');
                }
                # node is a preposition and for the moment it should hold the function of the whole prepositional phrase (which will later be propagated to the argument of the preposition)
                # this should work the same way as noun phrases -> Obj
                elsif ($node->is_adposition())
                {
                    $node->set_afun('Obj');
                }
                # otherwise -> NR
                else
                {
                    $node->set_afun('NR');
                }
            }
            # otherwise -> NR
            else
            {
                $node->set_afun('NR');
            }
        }
        # comp_inf ... infinitival complement
        # comp_fin ... clausal complement
        # similar to comp
        # TODO
        elsif ($deprel =~ m/^comp_(inf|fin)$/)
        {
            if ($parent->is_adposition())
            {
                $node->set_afun('PrepArg');
            }
            elsif ($parent->is_noun())
            {
                $node->set_afun('Atr');
            }
            elsif ($parent->is_verb() || $parent->is_adjective())
            {
                if ($node->is_adverb())
                {
                    $node->set_afun('Adv');
                }
                elsif ($node->is_adjective())
                {
                    $node->set_afun('Atv');
                }
                else
                {
                    $node->set_afun('Obj')
                }
            }
            else
            {
                $node->set_afun('NR');
            }
        }
        # punct ... punctuation marker
        elsif ($deprel eq 'punct')
        {
            # comma gets AuxX
            if ($node->form eq ',')
            {
                $node->set_afun('AuxX');
            }
            # all other symbols get AuxG
            else
            {
                $node->set_afun('AuxG');
            }
            # AuxK is assigned later in attach_final_punctuation_to_root()
        }
        # pred ... predicate
        elsif ($deprel eq 'pred')
        {
            $node->set_afun('Pred');
        }
        # subj ... subject
        elsif ($deprel eq 'subj')
        {
            $node->set_afun('Sb');
        }
        # conjunct
        elsif ($deprel eq 'conjunct')
        {
            # node is a coordination argument - solved in a separate subroutine
            $node->set_afun('CoordArg');
            # node is a conjunct
            $node->wild()->{'conjunct'} = 1;
            # parent must be a coordinator (does it?)
            $parent->wild()->{'coordinator'} = 1;
        }
        # obj ... object
        # obj_th ... dative object
        elsif ($deprel =~ m/^obj/)
        { # 'obj' and 'obj_th'
            $node->set_afun('Obj');
        }
        # refl ... reflexive marker
        # TODO: how to decide between AuxT and Obj?
        elsif ($deprel eq 'refl')
        {
            $node->set_afun('AuxT');
        }
        # neg ... negation marker
        elsif ($deprel eq 'neg')
        {
            $node->set_afun('Neg');
        }
        # pd ... predicative complement
        elsif ($deprel eq 'pd')
        {
            $node->set_afun('Pnom');
        }
        # ne ... named entity
        elsif ($deprel eq 'ne')
        {
            $node->set_afun('Atr');
            # ### TODO ### interpunkce by mela dostat AuxG; struktura! - hlava by mela byt nejpravejsi uzel
        }
        # complm ... complementizer
        elsif ($deprel eq 'complm')
        {
            $node->set_afun('AuxP');
        }
        # aglt ... mobile inflection
        elsif ($deprel eq 'aglt')
        {
            $node->set_afun('AuxV');
        }
        # aux ... auxiliary
        elsif ($deprel eq 'aux')
        {
            $node->set_afun('AuxV');
        }
        # mwe ... multi-word expression
        elsif ($deprel eq 'mwe')
        {
            $node->set_afun('AuxY');
        }
        # coord_punct ... punctuation conjunction
        elsif ($deprel eq 'coord_punct')
        {
            $node->wild()->{'coordinator'} = 1;
            if ($node->form eq ',')
            {
                $node->set_afun('AuxX');
            }
            else
            {
                $node->set_afun('AuxG');
            }
        }
        # app .. apposition
        # dependent on the first part of the apposition
        elsif ($deprel eq 'app')
        {
            $node->set_afun('Apposition');
        }
        # coord ... coordinating conjunction
        # coordinates two sentences (in other cases, the conjunction bears the relation to its parent)
        elsif ($deprel eq 'coord')
        {
            $node->wild()->{'coordinator'} = 1;
            $node->set_afun('Pred');
        }
        # abbrev_punct ... abbreviation marker
        elsif ($deprel eq 'abbrev_punct')
        {
            $node->set_afun('AuxG');
        }
        # cond ... conditional clitic
        elsif ($deprel eq 'cond')
        {
            $node->set_afun('AuxV');
        }
        # imp ... imperative marker
        elsif ($deprel eq 'imp')
        {
            $node->set_afun('AuxV');
        }
        # pre_coord ... pre-conjunction; first part of a correlative conjunction
        elsif ($deprel eq 'pre_coord')
        {
            $node->set_afun('AuxY');
        }
        else
        {
            $node->set_afun('NR');
        }
    }
    # Make sure that all nodes now have their afuns.
    for my $node (@nodes)
    {
        my $afun = $node->afun();
        if ( !$afun )
        {
            $self->log_sentence($root);
            # If the following log is warn, we will be waiting for tons of warnings until we can look at the actual data.
            # If it is fatal however, the current tree will not be saved and we only will be able to examine the original tree.
            log_fatal( "Missing afun for node " . $node->form() . "/" . $node->tag() . "/" . $node->conll_deprel() );
        }
    }
}



#------------------------------------------------------------------------------
# Detects coordination structure according to current annotation (dependency
# links between nodes and labels of the relations). Expects the Polish style
# of the Prague family(?) - the head of the coordination bears the label of the
# relation between the coordination and its parent. The afuns of conjuncts just
# mark them as conjuncts; the shared modifiers are distinguished by having
# a different afun. The method assumes that nothing has been normalized yet.
# Expects the coordinators and conjuncts to have the respective attribute in
# wild()
# ### TODO ### - check/correct; might be better to move into the PL::Harmonize?
#------------------------------------------------------------------------------
#------------------------------------------------------------------------------
# Detects coordination in the shape we expect to find it in the Polish
# treebank.
#------------------------------------------------------------------------------
# sub detect_coordination {
#     my $self = shift;
#     my $node = shift;
#     my $coordination = shift;
#     my $debug = shift;
#     $self->detect_polish($coordination, $node);
#     # The caller does not know where to apply recursion because it depends on annotation style.
#     # Return all conjuncts and shared modifiers for the Prague family of styles.
#     # Return orphan conjuncts and all shared and private modifiers for the other styles.
#     my @recurse = $coordination->get_conjuncts();
#     push(@recurse, $coordination->get_shared_modifiers());
#     return @recurse;
# }

sub detect_coordination {
    my $self = shift;
    my $node = shift;  # suspected root node of coordination
    my $coordination = shift;
    my $debug = shift;
    log_fatal("Missing node") unless (defined($node));
    my @children = $node->children();
    my @conjuncts = grep {$_->wild()->{'conjunct'}} (@children);
    return unless (@conjuncts);
    $coordination->set_parent($node->parent());
    $coordination->add_delimiter($node, $node->get_iset('pos') eq 'punc');
    $coordination->set_afun($node->afun());
    for my $child (@children) {
        if ($child->wild()->{'conjunct'}) {
            my $orphan = 0;
            $coordination->add_conjunct($child, $orphan);
        }
        elsif ($child->wild()->{'coordinator'}) {
            my $symbol = 1;
            $coordination->add_delimiter($child, $symbol);
        }
        else {
            $coordination->add_shared_modifier($child);
        }
    }
    my @recurse = $coordination->get_conjuncts();
    push(@recurse, $coordination->get_shared_modifiers());
    return @recurse;
}


### NOT FINISHED - WORK IN PROGRESS ###

1;

=over

=item Treex::Block::HamleDT::PL::Harmonize

Converts trees coming from Polish Dependency Treebank via the CoNLL-X format to the style of
the HamleDT/Prague. Converts tags and restructures the tree.

=back

=cut

# Copyright 2013 Jan Mašek <honza.masek@gmail.com>

# Copyright 2015 Dan Zeman <zeman@ufal.mff.cuni.cz>

# This file is distributed under the GNU General Public License v2. See $TMT_ROOT/README.
