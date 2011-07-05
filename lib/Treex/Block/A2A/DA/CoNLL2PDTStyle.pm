package Treex::Block::A2A::DA::CoNLL2PDTStyle;
use Moose;
use Treex::Core::Common;
use utf8;
extends 'Treex::Block::A2A::CoNLL2PDTStyle';



#------------------------------------------------------------------------------
# Reads the Danish tree, converts morphosyntactic tags to the PDT tagset,
# converts deprel tags to afuns, transforms tree to adhere to PDT guidelines.
#------------------------------------------------------------------------------
sub process_zone
{
    my $self = shift;
    my $zone = shift;
    my $a_root = $self->SUPER::process_zone($zone);
    # Adjust the tree structure.
    $self->attach_final_punctuation_to_root($a_root);
    #$self->process_auxiliary_particles($a_root);
    #$self->process_auxiliary_verbs($a_root);
    $self->restructure_coordination($a_root);
    #$self->mark_deficient_clausal_coordination($a_root);
}



#------------------------------------------------------------------------------
# Try to convert dependency relation tags to analytical functions.
# http://copenhagen-dependency-treebank.googlecode.com/svn/trunk/manual/cdt-manual.pdf
# (especially the part SYNCOMP in 3.1)
# http://ufal.mff.cuni.cz/pdt2.0/doc/manuals/cz/a-layer/html/ch03s02.html
#------------------------------------------------------------------------------
sub deprel_to_afun
{
    my $self = shift;
    my $root = shift;
    my @nodes = $root->get_descendants();
    foreach my $node (@nodes)
    {
        my $deprel = $node->conll_deprel();
        if($deprel eq 'ROOT')
        {
            if($node->get_iset('pos') eq 'verb')
            {
                $node->set_afun('Pred');
            }
            else
            {
                $node->set_afun('ExD');
            }
        }
    }
}



#------------------------------------------------------------------------------
# Detects coordination in Danish trees.
# - The first member is the root.
# - The first conjunction is attached to the root and s-tagged 'coord'.
# - The second member is attached to the conjunction and s-tagged 'conj'.
# - More than two members: commas and middle members attached to the first
#   member (tagged 'pnct' and 'conj'), last member attached to the conjunction.
# - I haven't seen shared modifiers but they're probably attached to the first
#   member. Private modifiers are attached to the member they modify.
# - Deficient coordination: sentence-initial conjunction is the root of the
#   sentence, tagged ROOT. The main verb is attached to it and tagged 'conj'.
#------------------------------------------------------------------------------
sub detect_coordination
{
    my $self = shift;
    my $root = shift;
    my $coords = shift; # reference to array where detected coordinations are collected
    # Depth-first search.
    # If a non-first member is found, find all nodes involved in the coordination.
    # Make sure that any members further to the right are not later recognized as different coordination.
    # However, search their descendants for nested coordinations.
    my @children = $root->children();
    my @members0 = grep {$_->conll_deprel() =~ m/^(conj|coord)$/} (@children);
    my @delimiters;
    my @sharedmod;
    if(@members0)
    {
        # If there is a coordination, the current root is its first member.
        unshift(@members0, $root);
        # In case of 'coord', the node we currently have is the conjunction and the actual member is its child.
        my @members;
        foreach my $member (@members0)
        {
            if($member->conll_deprel() eq 'coord')
            {
                # There should be only one child of the conjunction but let's be prepared for more.
                my @conj_children = grep {$_->conll_deprel() eq 'conj'} ($member->children());
                push(@members, @conj_children);
            }
            else # conll_deprel eq 'conj' or this is the first member and conll_deprel is anything
            {
                push(@members, $member);
            }
        }
        # Punctuation and conjunction children are supporting the coordination.
        @delimiters = grep {$_->conll_deprel() =~ m/^(pnct|coord)$/} (@children);
        # Any left modifiers of the first member will be considered shared modifiers of the coordination.
        # Any right modifiers of the first member occurring after the second member will be considered shared modifiers, too.
        # Note that the DDT structure does not provide for the distinction between shared modifiers and private modifiers of the first member.
        my $ord0 = $root->ord();
        my $ord1 = $#members>=1 ? $members[1]->ord() : -1;
        @sharedmod = grep {($_->ord() < $ord0 || $ord1>=0 && $_->ord() > $ord1) && $_->conll_deprel() !~ m/^(conj|coord|pnct)$/} (@children);
        push(@{$coords},
        {
            'members' => \@members,
            'delimiters' => \@delimiters,
            'shared_modifiers' => \@sharedmod,
            'parent' => $root->parent(),
            'afun' => $root->afun()
        });
        # Call this function recursively on descendants. Carefully!
        # Call it on all modifiers under the first member (shared or private).
        # Call it on all private modifiers of the other members.
        # Don't call it on the members themselves (one node cannot be member of two coordinations).
        # Don't call it on delimiting punctuation, it should not have any children.
        # Especially don't call it on the final conjunction! Its child is tagged 'conj' but it is the last member of the current coordination.
        foreach my $member (@members)
        {
            # The children of the first member include other members and delimiters. Filter them out.
            my @mchildren = grep {$_->conll_deprel() !~ m/^(conj|coord|pnct)$/} ($member->children());
            foreach my $child (@mchildren)
            {
                $self->detect_coordination($child, $coords);
            }
        }
    }
    # Call recursively on all children if no coordination detected now.
    else
    {
        foreach my $child (@children)
        {
            $self->detect_coordination($child, $coords);
        }
    }
}



1;



=over

=item Treex::Block::A2A::DA::CoNLL2PDTStyle

Converts trees coming from Danish Dependency Treebank via the CoNLL-X format to the style of
the Prague Dependency Treebank. Converts tags and restructures the tree.

=back

=cut

# Copyright 2011 Dan Zeman <zeman@ufal.mff.cuni.cz>

# This file is distributed under the GNU General Public License v2. See $TMT_ROOT/README.
