package Treex::Block::MarkMWEs;
use utf8;
use Moose;
use Treex::Core::Common;
use Treex::Core::Resource;
use Treex::Tool::Algorithm::TreeUtils;

extends 'Treex::Core::Block';

has 'phrase_list_path' => ( is => 'ro', isa => 'Str', default => '/data/mwes.txt' );
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

sub _build_trie {
    my ($self) = @_;

    log_info "Loading the MWE list with compositionality <= $self->comp_thresh...";
    log_info "Building a trie for searching...";

    my $path = $self->phrase_list_path;#require_file_from_share($self->phrase_list_path);
    open my $fh, "<:gzip:utf8", $path  or die "Could not open file $path!\n";

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

        $self->reconnect_descendants($head, @tnodes);

        $self->collapse_composite_node($head, @tnodes);

        $self->rewrite_head_node($head, $match);
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
    # TODO: store treelet configuration
}

sub collapse_composite_node{
    my ($self, $head, @nodes) = @_;
    foreach my $node (@nodes) {
        next if ($node == $head);
        # print "delete " . $node->t_lemma . "\n";
        next if $node->isa('Treex::Core::Node::Deleted');
        $node->remove({children=>q(remove)});
        # TODO: store treelet configuration
    }
}

sub rewrite_head_node{
    my ($self, $head, $match) = @_;
    my $mwe = $match->[1];
    $mwe =~ s/\s+/_/g;
    #print "MWE candidate is: $mwe\n";
    #$head->t_lemma = $mwe;
    $head->set_t_lemma($mwe);
    # TODO: encode treelet configuration into head node
}

1;

=encoding utf-8

=head1 NAME

Treex::Block::MarkMWEs - reduce multiword expressions to single composite t-nodes

=head1 DESCRIPTION

Some description.

=head1 AUTHOR

Will Roberts <will.roberts@anglistik.hu-berlin.de>

=head1 COPYRIGHT AND LICENSE

Copyright © 2015 by Will Roberts

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
