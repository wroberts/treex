package Treex::Block::CollapseMWEs;
use utf8;
use Moose;
use Treex::Core::Common;
use Treex::Core::Resource;
use Treex::Tool::Algorithm::TreeUtils;
#use JSON;
use XML::LibXML;
#use Treex::Block::T2T::CopyTtree;
# Treex::Block::T2T::CopyTtree::ATTRS_TO_COPY
my @ATTRS_TO_COPY = qw(ord t_lemma functor formeme is_member nodetype is_generated subfunctor
    is_name_of_person is_clause_head is_relclause_head is_dsp_root is_passive is_parenthesis is_reflexive
    voice sentmod tfa gram/sempos gram/gender gram/number gram/degcmp
    gram/verbmod gram/deontmod gram/tense gram/aspect gram/resultative
    gram/dispmod gram/iterativeness gram/indeftype gram/person gram/numertype
    gram/politeness gram/negation gram/definiteness gram/diathesis clause_number);


extends 'Treex::Core::Block';

has 'phrase_list_path' => ( is => 'ro', isa => 'Str', default => '/data/mwes2.txt' );
has 'output_path' => ( is => 'ro', isa => 'Str', default => '/data/mwes2.txt' );
has 'comp_thresh' => ( is => 'ro', isa => 'Num', default => 0.5 );
has '_trie' => ( is => 'ro', isa => 'HashRef', builder => '_build_trie', lazy => 1);

sub BUILD {
    my ($self) = @_;
    return;
}

sub process_start {
    my ($self) = @_;
    $self->_trie;
}

my $INFO_LABEL = "__INFO__";

# http://stackoverflow.com/q/5667443/1062499
sub my_fopen {
  my $mode = shift;
  my $filename = shift;
  if ($filename =~ /\.gz$/) {
      $mode =~ s/^(\+?[<>])/$1:gzip/;
      #if ($mode eq "<") {
      #    open my $fh, "<:gzip:utf8", $path  or die "Could not open file $path!\n";
      #
      #    open(my $fp, "-|", "/usr/bin/gzcat $filename");
      #    #my $fp = gzopen($filename, "rb") ;
      #    return $fp;
      #}
      #if ($mode eq ">") {
      #    open(my $fp, "|-", "/usr/bin/gzip > $filename");
      #    #my $fp = gzopen($filename, "wb") ;
      #    return $fp;
      #}
  }
  open(my $fp, $mode, $filename);
  return $fp;
}

sub _build_trie {
    my ($self) = @_;

    log_info "Loading the MWE list with compositionality <= $self->{'comp_thresh'}...";
    log_info "Building a trie for searching...";

    my $path = $self->phrase_list_path;#require_file_from_share($self->phrase_list_path);
    #open my $fh, "<:gzip:utf8", $path  or die "Could not open file $path!\n";
    my $fh = my_fopen "<:utf8", $path or die "Could not open file $path!\n";

    my $linecount = 0;
    my $trie = {};
    while (my $line = <$fh>) {
        chomp $line;
        #print $line . "\n";
        my ($compo, $mwe) = split /\t/, $line;
        if ($compo > $self->comp_thresh) {last;}
        _insert_phrase_to_trie($trie, $mwe, $compo);
        $linecount += 1;
    }
    close $fh;
    log_info "Loaded $linecount MWEs into trie.";
    return $trie;
}

sub _insert_phrase_to_trie {
    my ($trie, $phrase, $id) = @_;

    return if ($phrase =~ /^\s*$/);

    #my @words = map {lc($_)} (split / +/, $phrase);
    my @words = split / +/, $phrase;
    my $next_word = shift @words;
    while (defined $next_word && defined $trie->{$next_word}) {
        #log_info "NEXT_WORD_GET: " . $next_word if ($debug);
        $trie = $trie->{$next_word};
        $next_word = shift @words;
    }

    # there is a tail of remaining words
    if (defined $next_word) {
        my $suffix_hash = {};
        while ($next_word) {
            #log_info "NEXT_WORD_SET: " . $next_word if ($debug);
            $trie->{$next_word} = {};
            $trie = $trie->{$next_word};
            $next_word = shift @words;
        }
        my $info = [$id, $phrase];
        $trie->{$INFO_LABEL} = $info;
    }
    # all words are indexed in a trie
    else {
        my $info = $trie->{$INFO_LABEL};
        if (!defined $info) {
            $info = [$id, $phrase];
            $trie->{$INFO_LABEL} = $info;
        }
        # else: this phrase is already stored - skip it
    }
}

sub _match_phrases_in_atree {
    my ($self, $all_anodes, $trie) = @_;

    #print "@all_anodes";
    #print join(' ', map {$_->form} @all_anodes) . "\n";

    my @matches = ();
    my @unproc_trie_nodes = ();
    my @unproc_anodes = ();

    foreach my $anode (@$all_anodes) {
        unshift @unproc_trie_nodes, $trie;

        my $word = $anode->form;

        @unproc_trie_nodes = map {$_->{$word}} @unproc_trie_nodes;
        #@unproc_trie_nodes = grep {defined $_} @unproc_trie_nodes;
        my @found = map {defined $_ ? 1 : 0} @unproc_trie_nodes;
        unshift @unproc_anodes, [];
        #print "$word: @unproc_trie_nodes\n" if @unproc_trie_nodes;
        @unproc_anodes = grep {defined $_}
        map { if ($found[$_]) {
            [ @{$unproc_anodes[$_]}, $anode ]
              } else {
                  undef;
          }
        } 0 .. $#unproc_anodes;
        @unproc_trie_nodes = grep {defined $_} @unproc_trie_nodes;

        #print "$word: @unproc_trie_nodes\n" if @unproc_trie_nodes;
        my @new_matches = map {[@{$unproc_trie_nodes[$_]->{$INFO_LABEL}},
                                $anode->ord() - scalar(@{$unproc_anodes[$_]}),
                                scalar(@{$unproc_anodes[$_]}),
                                $unproc_anodes[$_]]}
        grep {defined $unproc_trie_nodes[$_]->{$INFO_LABEL}} 0 .. $#unproc_trie_nodes;
        #print "$word: @new_matches\n" if @new_matches;
        push @matches, @new_matches;
    }
    return \@matches;
}

sub process_atree {
    my ( $self, $atree ) = @_;

    #my $bundle = $ttree->get_bundle();
    #my $atree = $bundle->get_tree( $ttree->language, q(a), $ttree->selector );

    #my @all_anodes = $ttree->get_descendants();
    #print "@all_anodes";
    #print "ttree nodes " . join(' ', map {$_->t_lemma} @all_anodes) . "\n";

    my @all_anodes = $atree->get_descendants({ordered=>1});
    #print "@all_anodes";
    # print "atree nodes " . join(' ', map {$_->form} @all_anodes) . "\n";

    my $matches = $self->_match_phrases_in_atree(\@all_anodes, $self->_trie);

    # sort matches again on compositionality, increasing; resolve ties
    # by sorting matches on order, increasing
    my @sorted_matches = sort {$a->[0] <=> $b->[0] || $a->[2] <=> $b->[2]} @$matches;

    # create a hash to keep track of which a-nodes in this sentence
    # have been "marked" as belonging to a MWE
    my %marked_anode_ords = ();

    foreach my $match (@sorted_matches) {
        # print "MATCH\n";
        # retrieve the anodes matching the MWE candidate
        my @anodes = @{$match->[4]};
        #print "anodes: " . join(' ', map {$_->form} @anodes) . "\n";
        #print "left ord(): " . $match->[2] . "\n";
        #print "MWE length: " . $match->[3] . "\n";
        # retrieve the indices (ord() values) of the anodes which make up this MWE candidate
        my @anode_idxs = ($match->[2] .. $match->[2] + $match->[3] - 1);
        # check if these overlap with
        if (any {$marked_anode_ords{$_}} @anode_idxs){
            #print "MWE candidate overlaps with something already picked, skipping\n";
            next;
        }
        # find the t-nodes which map onto those a-nodes
        my @tnodes = map {$_->get_referencing_nodes('a/lex.rf')} @anodes;
        #print "num tnodes: " . scalar(@tnodes) . "\n";
        #print "tnodes: " . join(' ', map {$_->t_lemma} @tnodes) . "\n";
        # we can only collapse things if there are multiple t-nodes
        if (scalar(@tnodes) <= 1) {
            # print "too few nodes for processing\n";
            next;
        }
        # determine if the t-nodes we have found are in a single treelet
        #my ($head, $added_nodes_rf) = find_connected_treelet(@tnodes);
        my $head = check_is_connected_treelet(@tnodes);
        if (!$head){
            # print "could not find connected treelet\n";
            next;
        }
        # print "found $head\n";
        # we've found a MWE candidate; mark its anodes as belonging to a MWE candidate
        foreach (@anode_idxs) {$marked_anode_ords{$_} = 1;}

        # reproduce input format: compo \t MWE
        log_info "UBERMWE: $match->[0]\t$match->[1]";

        # store treelet configuration
        my $repr = $self->build_collapsed_repr($head, @tnodes);

        $self->reconnect_descendants($head, @tnodes);

        $self->collapse_composite_node($head, @tnodes);

        # encode treelet configuration into head node
        $self->rewrite_head_node($head, $repr);
    }
}

sub check_is_connected_treelet{
    my (@nodes) = @_;

    # hash to act as a set of nodes contained in the treelet
    my %in_treelet = map {($_,1)} @nodes;

    my $top_node = undef;
    foreach my $node (@nodes) {
        my $parent = $node->get_parent();
        if (!exists $in_treelet{$parent}){
            return if (defined $top_node);
            $top_node = $node;
        }
    }
    return $top_node;
}
#use Devel::Peek;
sub build_collapsed_repr{
    my ($self, $head, @nodes) = @_;

    # hash to act as a set of nodes contained in the treelet
    my %in_treelet = map {($_,1)} @nodes;

    my $dom = XML::LibXML::Document->new( "1.0", "UTF-8" );
    my $root = $dom->createElement( "MWE" );
    $dom->setDocumentElement( $root );
    # format: (CURRENT, XMLNODE)
    my @todo = ([$head, $root]);
    while (@todo) {
        my @cval = @{shift @todo};
        my $current = $cval[0];
        my $xmlnode = $cval[1];
        #binmode(STDOUT);
        #print "current ", Dumper($current->t_lemma);
        #Dump($current->t_lemma);
        # encode current into xmlnode
        if ($current == $head) {
            # for the top node, we just record the lemma
            $xmlnode->setAttribute( "t_lemma", $head->t_lemma );
        } else {
            if ($in_treelet{$current}) {
                # for all nodes under the head which are part of the
                # MWE, we encode all of the node's non-undef
                # properties
                for (grep {$current->get_attr($_)}  @ATTRS_TO_COPY) {
                    $xmlnode->setAttribute( $_ =~ s./.-.r, $current->get_attr($_) );
                }
            } else {
                # for nodes which are not part of the MWE, we just
                # encode their formeme
                $xmlnode->setAttribute( "formeme", $current->get_attr("formeme") );
            }
        }
        #binmode(STDOUT);
        #print "xmlnode ", $xmlnode->toString(0, "UTF-8"), "\n";
        # push onto @todo, if we are still in the MWE
        if ($in_treelet{$current}) {
            my @children = sort { $a->ord() <=> $b->ord() } $current->get_children();
            for (@children) {
                my $childtagname = "";
                if ($in_treelet{$_}) {
                    $childtagname = ($_->ord() < $current->ord()) ? "l" : "r";
                } else {
                    $childtagname = ($_->ord() < $current->ord()) ? "lx" : "rx";
                }
                my $xmlchild = $xmlnode->addNewChild( '', $childtagname );
                push @todo, [$_, $xmlchild];
            }
        }
    }
    my $repr = $root->toString(0, "UTF-8");
    #binmode(STDOUT);
    #print $repr, "\n";
    open(my $fh, '>>', $self->output_path) or die "Could not open file '$self->output_path'";
    binmode($fh);
    say $fh $repr;
    close $fh;
    #print $dom->toString(0);
    return $repr;
}

sub reconnect_descendants {
    # find all nodes under this MWE which are not going to be collapsed
    my ($self, $head, @nodes) = @_;

    # hash to act as a set of nodes contained in the treelet
    my %in_treelet = map {($_,1)} @nodes;

    # start with a list of all nodes under the head node
    my @descs = $head->get_descendants({ordered=>1});
    foreach my $desc (@descs) {
        next if $in_treelet{$desc};
        my $parent = $desc->get_parent();
        if ($in_treelet{$parent} && $parent != $head) {
            $self->reconnect_descendant($desc, $head, @nodes);
        }
    }
    return;
}

sub reconnect_descendant{
    my ($self, $desc, $head, @nodes) = @_;
    #print $desc{t_lemma} . "\n";
    #print $desc . "\n";
    #print $head . "\n";
    #print $head->t_lemma . "\n";
    # print "reconnect " . $desc->t_lemma . " to " . $head->t_lemma . "\n";
    $desc->set_parent($head);
}

sub collapse_composite_node{
    my ($self, $head, @nodes) = @_;
    foreach my $node (@nodes) {
        next if ($node == $head);
        # print "delete " . $node->t_lemma . "\n";
        next if $node->isa('Treex::Core::Node::Deleted');

        my ($ali_trg_tnodes_rf, $ali_types_rf) = $node->get_directed_aligned_nodes();
        for my $i (0 .. $#{$ali_trg_tnodes_rf}) {
            my $anode = $ali_trg_tnodes_rf->[$i];
            my $atypes = $ali_types_rf->[$i];
            print "node $anode aligned to $node with types $atypes\n";
            #   $head->add_aligned_node($anode, $atype)
        }

        $node->remove({children=>q(remove)});
    }
}

sub rewrite_head_node{
    my ($self, $head, $repr) = @_;
    $head->set_t_lemma($repr);
}

1;

=encoding utf-8

=head1 NAME

Treex::Block::CollapseMWEs - reduce multiword expressions to single composite t-nodes

=head1 DESCRIPTION

Some description.

=head1 AUTHOR

Will Roberts <will.roberts@anglistik.hu-berlin.de>

=head1 COPYRIGHT AND LICENSE

Copyright © 2015 by Will Roberts

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
