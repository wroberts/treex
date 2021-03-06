package Treex::Block::P2A::TigerET;
use Moose;
use Treex::Core::Common;
use utf8;
extends 'Treex::Core::Block';

sub _is_terminal {
    return defined $_[0]->lemma;
} # _is_terminal


sub _terminals {
    my ($p_root) = @_;
    return grep _is_terminal($_), $p_root->get_descendants;
} # terminals


#------------------------------------------------------------------------------
# Call this function for a p-node that does not project to any a-node, i.e.
# a nonterminal that does not have a head. All a-nodes in its subtree are
# orphans because we do not have a head to attach them to. The function returns
# the list of the orphaned a-nodes.
#------------------------------------------------------------------------------
sub _orphans {
    my ($pnode, $anode_from_pnode) = @_;
    # Having a corresponding a-node means:
    # either it is a terminal
    # or it is a nonterminal and we have been able to determine its head.
    my @orphans = map $anode_from_pnode->{$_->id} ? $_ : _orphans($_,$anode_from_pnode),
                  $pnode->get_children;
    return @orphans;
} # _orphans;


sub _left_neighbor {
    my $node = shift;
    my $parent = $node->get_parent;
    my @pchildren = $parent->get_children;
    my $index = 0;
    $index++ until $pchildren[$index] == $node;
    return $pchildren[$index - 1];
} # _left_neighbor

{ my %rank;
sub rank {
    my $pnode = shift;
    my $proot = $pnode->get_root;
    if (not exists $rank{$pnode}) {
        undef %rank;
        $rank{$proot->id} = 0;
        $rank{$_->id} = 1 + $rank{$_->get_parent->id}
            for $proot->get_descendants;
    }
    return $rank{$pnode->id};
}} # rank


## Reads the estonian p-tree, builds corresponding a-tree.
sub process_zone {
    my $self   = shift;
    my $zone   = shift;
    my $p_root = $zone->get_ptree;
    my ($a_root, @anodes);
    if ($zone->has_atree) {
        $a_root = $zone->get_atree;
        @anodes = $a_root->get_descendants( { ordered => 1 } );
    } else {
        $a_root  = $zone->create_atree();
        @anodes = ();
        my %anode_from_pnode;
        # Prepare a-nodes for all terminal p-nodes.
        foreach my $terminal (_terminals($p_root)) {
            # The node may have been orphan due to error in the TIGER-XML input data.
            # In such case its current edge label is 'ORPHAN'.
            # Let's attempt to estimate better edge label now.
            # We could not do that in Read::Tiger because that block is general and does not know about the Estonian treebank labels.
            if($terminal->edgelabel() eq 'ORPHAN' && $terminal->wild->{pos} eq 'v' && $terminal->wild->{morph} =~ m/^main/)
            {
                $terminal->set_edgelabel('P');
            }
            my $conll_feat = $terminal->wild->{morph};
            $conll_feat =~ s/,/|/g;
            my $anode = $a_root->create_child(
                {
                    form  => $terminal->form,
                    lemma => $terminal->lemma,
                    tag   => $terminal->wild->{pos} . '/' . $terminal->wild->{morph},
                    'conll/cpos'   => $terminal->wild->{pos},
                    'conll/pos'    => $terminal->wild->{pos},
                    'conll/feat'   => $conll_feat,
                    'conll/deprel' => $terminal->edgelabel,
                    # The p-tree cannot preserve the word order. It assumes that phrase structures are projective but in Tiger it need not be the case.
                    ord   => $terminal->wild->{span1},
                }
            );
            $anode_from_pnode{$terminal->id} = $anode;
            $anode->wild->{function} = $terminal->edgelabel;
            push @anodes, $anode;
        }
        # Figure out dependencies between a-nodes.
        foreach my $pnode (sort { rank($b) <=> rank($a) } $p_root->descendants) {
            if (my @children = $pnode->get_children) {
                my $phead = find_head($pnode, @children);
                if ($phead) {
                    # The head-finding procedure may have identified problematic coordinations that we want to know about later during PDT style normalization.
                    # The normalization block will look for them at the root of the a-tree.
                    # At this moment they are stored at the phead because the head-finding procedure knows nothing about the a-tree.
                    if($phead->wild->{coord})
                    {
                        foreach my $coordination (@{$phead->wild->{coord}})
                        {
                            my @p_conjunct_ids = map {$_->id()} @{$coordination};
                            push(@{$a_root->wild->{coord}}, [map $anode_from_pnode{$_}->id, @p_conjunct_ids]);
                        }
                        delete($phead->wild->{coord});
                    }
                    # Attach the non-head children to the head in the a-tree.
                    my $ahead = $anode_from_pnode{$phead->id};
                    # Associate the parent nonterminal with the same a-node as the head child.
                    $anode_from_pnode{$pnode->id} = $ahead;
                    if ($ahead)
                    {
                        if ($ahead->wild->{function} =~ /^[DH]$/
                            and $phead->get_parent->edgelabel()
                            and $phead->get_parent->edgelabel() !~ /^[DH]$/)
                        {
                            $ahead->wild->{function} = $phead->get_parent->edgelabel();
                        }
                        # Loop over all children (nonterminals and terminals) of the current nonterminal p-node.
                        foreach my $child (grep $_ != $phead, @children) {
                            my $achild = $anode_from_pnode{$child->id};
                            if ($achild) {
                                $achild->set_parent($ahead);
                                $achild->wild->{function} = $child->edgelabel();
                            } else {
                                # The child nonterminal does not project to any a-node because we were not able to find its head.
                                # All a-nodes corresponding to nodes in its subtree are orphans.
                                # Make the current a-head their head.
                                my @orphans = _orphans($child, \%anode_from_pnode);
                                log_info("ORPHANS\t" . scalar @orphans . "\t" . $child->get_address);
                                $anode_from_pnode{$_->id}->set_parent($ahead)
                                    for @orphans;
                            }
                        }
                    }
                    else
                    {
                        my $label = $phead->form();
                        if(!defined($label))
                        {
                            $label = $phead->phrase() ? $phead->phrase() : '';
                        }
                        log_warn("No a-head for p-head '$label'\t".$phead->get_address());
                    }
                } else {
                    my $edgelabels = join(' ', map $_->edgelabel(), @children);
                    my $nodelabels = join(' ', map {$_->form() ? $_->form() : $_->phrase()} (@children));
                    log_warn("No head found\t" . $pnode->phrase() . ": $edgelabels ($nodelabels)\t" . $pnode->get_address);
                }
            }
        }
    }
} # process_zone



#------------------------------------------------------------------------------
# Determines the head among the children of a p-node.
#------------------------------------------------------------------------------
sub find_head
{
    my $pnode = shift;
    my @children = @_;
    my @pheads;
    # The main functions denoting the head are:
    # H ... head
    # P ... predicator
    # The head of coordination is the coordinating conjunction ('CO').
    for my $child (@children) {
        my $edgelabel = $child->edgelabel();
        if($edgelabel =~ /^(?:[HP]|Vm(?:ain)?)$/
            or ('CO' eq $edgelabel and grep 'CJT' eq $_->edgelabel(), @children))
        {
            push @pheads, $child
        }
    }
    # Special cases
    if(!@pheads)
    {
        my $els = ' '.join(' ', sort(map {$_->edgelabel()} (@children))).' ';
        my $tags = ' '.join(' ', map {$_->wild->{pos} ? $_->wild->{pos} : $_->phrase() ? $_->phrase() : 'UNKNOWN'} (@children)).' ';
        # Eesmärk - viia telekaabel kuue kuuga 50000 Tallinna kodusse.
        # The goal - to bring cable television in six months to 50000 Tallinn homes.
        # The root acl (adverbial clause) phrase is composed of:
        # - Eesmärk/noun/S
        # - -/punc/--
        # - icl/C (complement infinite clause)
        # - ./punc/FST
        # Solution: 'Eesmärk' is the head (the icl is apposition adjunct).
        if($els =~ m/ [AC] (.* )?S /)
        {
            @pheads = grep {$_->edgelabel() eq 'S'} @children;
            #log_info("PHRASE ".join(',', map {$_->edgelabel()} @children)." solved by making S the head.");
        }
        # Ei!
        # No!
        # The exclamation mark has the edge label 'EM' that has not been defined.
        # Anyhow, the adverb 'ei' shall become the head.
        elsif($els eq ' A EM ')
        {
            @pheads = grep {$_->edgelabel() eq 'A'} @children;
            #log_info("PHRASE ".join(',', map {$_->edgelabel()} @children)." solved by making A the head.");
        }
        # sigaret sigareti järel
        # cigarette after cigarette
        # sigaret/n/A (pp/A sigareti/n/D järel/prp/H)
        elsif($els eq ' A A '
              && $children[0]->wild->{pos} && $children[0]->wild->{pos} eq 'n'
              && $children[1]->phrase() && $children[1]->phrase() =~ m/^pp/)
        {
            @pheads = ($children[0]);
        }
        # nagu/conj-s/SUB (np/C pikantne prantsuse film)
        # as savory French film
        # Solution: the subordinating conjunction 'nagu' is the head.
        elsif($els eq ' C SUB ')
        {
            @pheads = grep {$_->edgelabel() eq 'SUB'} @children;
            #log_info("PHRASE ".join(',', map {$_->edgelabel()} @children)." solved by making SUB the head.");
        }
        # mitte/adv/A niivõrd/adv/A np/A kui/conj-s/A np/A
        # not so much X as Y
        # Y rather than X
        # Solution: 'kui' is the head.
        elsif($els eq ' A A A A A '
              && lc(join(' ', map {$_->form() ? $_->form() : $_->phrase()} (@children))) =~ m/^mitte niivõrd .+ kui .+$/)
        {
            @pheads = ($children[3]);
            #log_info("PHRASE ".join(',', map {$_->edgelabel()} @children)." solved by making 'kui' the head.");
        }
        # jah/b/B jaa/b/B
        # yeah yeah
        # b = B = discourse particle
        # Solution: coordination without conjunction. Last conjunct is the head.
        elsif($els =~ m/^( B)+ $/)
        {
            @pheads = ($children[-1]);
        }
        elsif($els eq ' D D ')
        {
            # Ta/pron-pers/S siseneb/v-fin/P (np/A (adjp/D vastas/adv/D olevasse/adj/D) kabinetti/n/H) ./punc/FST
            # He enters opposite office.
            # (np/D mitu/pron-def/H meetrit/n/D) edasi/pst/D
            # several meters on
            # on several meters
            # The postposition 'edasi' should be the head but erroneously it is tagged as dependent.
            # (adjp/D erutusest hingeldav) politseinink/n/D
            # breathless of-excitement policeman
            if($tags eq ' adv adj ' ||
               $tags eq ' pron-dem n ' ||
               $tags =~ m/np.* (prp|pst)/ ||
               $tags =~ m/adjp.* n $/)
            {
                @pheads = ($children[1]);
            }
        }
        # oma tavalist kolmekümne kahe minutilist bensiinilõhnalist ja ühel lõigul kergelt hingeldamapanevat maršruuti
        # their usual thirty two minutes gas-smelling and one section slightly pant-putting route
        # edge labels: D D D D D
        # constituents: (oma) (tavalist) (kolmekümne-kahe-minutilist) (bensiini...) (maršruuti)
        # Solution: the noun (last constituent) is the head.
        elsif($els eq ' D D D D D ' &&
              $tags =~ m/^ pron-poss adj adjp.* par.* n $/)
        {
            @pheads = ($children[-1]);
        }
    }
    # There should be just one head.
    if(scalar(@pheads)>1) {
        # Special cases
        # kaks konkureerivat kaabelTV firmade liitu
        # two competing cable-TV companies union
        # kaks/num/H konkureerivat/adj/D (np/S kaabelTV firmade) liitu/n/H
        # There should be one more nonterminal level but there is not:
        # (np (np kaks konkureerivat (np kaabelTV firmade)) liitu)
        # Anyway, the noun 'liitu' should be the head here.
        if(scalar(@pheads)==2 && $pheads[0]->wild->{pos} eq 'num' && $pheads[1]->wild->{pos} eq 'n')
        {
            #log_info("Two heads (".join(', ', map {$_->form()} (@pheads))."); selected ".$pheads[1]->form());
            shift(@pheads);
        }
        # If there are more than one conjunction in coordination (they could also be parts of a multi-word conjunction)
        # use the last one as the head.
        elsif(join('', map {$_->edgelabel()} (@pheads)) =~ m/^(CO)+$/)
        {
            #log_info("Multiple conjunction heads (".join(', ', map {$_->form()} (@pheads))."); selected ".$pheads[-1]->form());
            @pheads = ($pheads[-1]);
        }
        # Two "main" verbs (is it an error? I would not say they both are main):
        # said kirjutatud
        # were written
        # Solution: the finite verb is the head, the participle is dependent.
        elsif(scalar(@pheads)==2
              && join('', map {$_->edgelabel()} (@pheads)) =~ m/^(Vm)+$/
              && $pheads[0]->wild->{morph} =~ m/,indic,/
              && $pheads[1]->wild->{morph} =~ m/,partic,/)
        {
            #log_info("Multiple conjunction heads (".join(', ', map {$_->form()} (@pheads))."); selected ".$pheads[0]->form());
            pop(@pheads);
        }
        # Multiple predicates in spoken data indicate repetitions.
        # nhh/b/B Marel/prop/A on/v-fin/P ka/adv/A (np/S nelisada/num/H pööret/n/D) on/v-fin/P seal/adv/A ./punc/--
        # hmm Marel is also four-hundred revolutions is there.
        # Solution: as in coordination without conjunction, the last predicate is the head.
        elsif(join('', map {$_->edgelabel()} (@pheads)) =~ m/^P+$/)
        {
            #log_info("Multiple conjunction heads (".join(', ', map {$_->form()} (@pheads))."); selected ".$pheads[-1]->form());
            @pheads = ($pheads[-1]);
        }
        else
        {
            my $edgelabels = join (' ', sort map $_->edgelabel(), @children);
            log_warn("Too many heads\t$edgelabels\t" . $pnode->get_address());
        }
    }
    # If more than one head was found, use the last one.
    my $phead = $pheads[-1];
    $phead = $children[0] if 1 == @children;

    # No head found. Try to search only among "important" nodes.
    if (not $phead) {
        my @candidates = grep $_->edgelabel() !~ /^(?:--|FST|PNC|B)$/, @children;
        $phead = $candidates[0] if 1 == @candidates;
    }

    # numerical constructions of type A D
    if (not $phead
        and 2 == @children
        and my ($num) = grep { 'A' eq $_->edgelabel()
                   and 'num' eq $_->wild->{pos}
                 } @children) {
        $phead = $num;
    }

    # multiword conjunction A SUB
    if (not $phead
        and 2 == @children
        and 'A:SUB' eq join ':', sort map $_->edgelabel(), @children) {
        $phead = $children[0];
    }

    # coordination without conjunction is not marked, find
    # the graphical symbol and make it the coordination
    my @cjt;
    if (not $phead
        and @cjt = grep 'CJT' eq $_->edgelabel(), @children
        and @cjt > 1) {
        # Get the closest left sibling of the last conjunct.
        # If it is punctuation make it coordination head.
        my $coord = _left_neighbor($cjt[-1]);
        if ($coord
            and $coord->edgelabel()
            and $coord->wild->{pos}
            and 'punc' eq $coord->wild->{pos}) {
            $phead = $coord;
        } else {
            # Otherwise make the last conjunct the coordination head.
            $phead = $cjt[-1];
            # Remember problematic coordinations (lists of conjuncts) for later processing and normalization.
            # JŠ was storing them at the root of the a-tree but we want to keep this function independent of the a-tree.
            # So we store it at the coordination head instead.
            # If the caller is building an a-tree, it is its own business to propagate the information further (and translate p-nodes to a-nodes).
            #push @{ $aroot->wild->{coord} }, [map $anode_from_pnode->{$_->id}->id, @cjt];
            push(@{$phead->wild->{coord}}, \@cjt);
        }
    }

    # no head was found, try to find it by phrase name
    if (not $phead) {
        my $phrase = $pnode->phrase();
        if(!$phrase)
        {
            log_warn("Missing phrase label: ".$pnode->get_address());
            $phrase = 'UNKNOWN';
        }
        my %head_of_phrase
            = ( pp   => '^(?:pst|prp)',
                np   => '^n',
                adjp => '^adj',
                acl  => '^A');
        my $find = $head_of_phrase{$phrase};
        if ($find
            and my @found = grep $_->wild->{pos} && $_->wild->{pos} =~ /$find/
                            || $_->edgelabel() && $_->edgelabel() =~ /$find/, @children) {
            $phead = $found[0] if 1 == @found;
            #log_info("PHRASE:\t$phrase / $find " . scalar @found . "\t" . $pnode->get_address);
        }
    }

    # Set the head-indicating attribute of the head node.
    $phead->set_is_head(1) if($phead);
    return $phead;
}



#-------------------------------------------------------------------------------

1;

=over

=item Treex::Block::P2A::TigerET

Converts phrase-based Estonian Treebank in Tiger format to dependency format.

=back

=cut

# Copyright 2011 Jan Štěpánek <stepanek@ufal.mff.cuni.cz>, Daniel Zeman <zeman@ufal.mff.cuni.cz>
# This file is distributed under the GNU General Public License v2. See $TMT_ROOT/README.
