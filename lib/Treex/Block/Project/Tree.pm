package Treex::Block::Project::Tree;
use Moose;
use Treex::Core::Common;
use Treex::Block::Print::AlignmentStatistics;

extends 'Treex::Core::Block';

has layer => ( isa => 'Treex::Type::Layer', is => 'ro', default => 'a' );
has source_language =>
  ( isa => 'Treex::Type::LangCode', is => 'ro', required => 1 );
has source_selector =>
  ( isa => 'Treex::Type::Selector', is => 'ro', default => q{} );
has alignment_type => (
	isa     => 'Str',
	is      => 'ro',
	default => '.*',
	documentation =>
	  'Use only alignments whose type is matching this regex. Default is ".*".'
);
has alignment_direction => (
	is      => 'ro',
	isa     => enum( [qw(src2trg trg2src)] ),
	default => 'trg2src',
	documentation =>
'Default trg2src means alignment from <language,selector> to <source_language,source_selector> tree. src2trg means the opposite direction.',
);
has modifier_dir => ( isa => 'Str', is => 'ro', default => 'mod_next' );
has chunk_head   => ( isa => 'Str', is => 'ro', default => 'last' );

# for projection summary
has _conserved_dep_edges_count => ( isa => 'Int', is => 'rw', default => 0 )
  ;    # parent aligns to parent & child aligns to child
has _total_source_nodes    => ( isa => 'Int', is => 'rw', default => 0 );
has _total_target_nodes    => ( isa => 'Int', is => 'rw', default => 0 );
has _total_unaligned_nodes => ( isa => 'Int', is => 'rw', default => 0 );

# wild attributes
# 'parent_guessed'
# 'guess_heuristic'

my %done;

sub process_zone {
	my ( $self, $zone ) = @_;
	my $source_zone =
	  $zone->get_bundle()
	  ->get_zone( $self->source_language, $self->source_selector );
	my ( $tree, $source_tree ) =
	  map { $_->get_tree( $self->layer ) } ( $zone, $source_zone );

	# 1) Init
	# 'mod_prev' - modifies previous node
	# 'mod_next' - modifies next node
	# This prevents creating cycles later,
	# and also non-aligned nodes will have a reasonable default parent.
	my @nodes = $tree->get_descendants( { ordered => 1 } );
	if ( $self->modifier_dir eq 'mod_prev' ) {
		if ( scalar(@nodes) >= 2 ) {
			foreach my $i ( 1 .. $#nodes ) {
				$nodes[$i]->set_parent( $nodes[ $i - 1 ] );
			}
		}
	}
	elsif ( $self->modifier_dir eq 'mod_next' ) {
		if ( scalar(@nodes) >= 2 ) {
			foreach my $i ( 0 .. ( $#nodes - 1 ) ) {
				$nodes[$i]->set_parent( $nodes[ $i + 1 ] );
			}
		}
	}

	# 2) Project dependencies using recursive DFS of the $source_tree.
	$self->project_subtree( $source_tree, $tree );

	# 3) Get alignment statistics
	my $alignment_stats = Treex::Block::Print::AlignmentStatistics->new(
		{
			source_language     => $self->source_language,
			source_selector     => $self->source_selector,
			language            => $self->language,
			selector            => $self->selector,
			alignment_type      => $self->alignment_type,
			alignment_direction => $self->alignment_direction,
			_file_handle	=> \*STDOUT,
			statistics => 1,
		}
	);
	my $local_stat_rf = $alignment_stats->get_local_stat($source_tree, $tree);
	$self->_set_total_unaligned_nodes($self->_total_unaligned_nodes + $local_stat_rf->{'tgt_unaligned'});
	$self->_set_total_source_nodes($self->_total_source_nodes + $local_stat_rf->{'src_len'});
	$self->_set_total_target_nodes($self->_total_target_nodes + $local_stat_rf->{'tgt_len'});

	# Free memory
	%done = ();
	return;
}

sub project_subtree {
	my ( $self, $src_root, $trg_root ) = @_;
	foreach my $src_node ( $src_root->get_children( { ordered => 1 } ) ) {
		my @trg_nodes;
		if ( $self->alignment_direction eq 'trg2src' ) {
			@trg_nodes = grep {
				$_->is_aligned_to( $src_node,
					'^' . $self->alignment_type . '$' )
			  } $src_node->get_referencing_nodes( 'alignment', $self->language,
				$self->selector );
		}
		else {
			@trg_nodes = $src_node->get_aligned_nodes_of_type(
				'^' . $self->alignment_type . '$',
				$self->language, $self->selector );
		}
		@trg_nodes = grep { !$done{$_} } @trg_nodes;
		if (@trg_nodes) {
			my $head_trg_node =
			    @trg_nodes == 1
			  ? $trg_nodes[0]
			  : $self->choose_head( \@trg_nodes );
			if ( !$trg_root->is_descendant_of($head_trg_node)
				&& ( $head_trg_node != $trg_root ) )
			{
				$head_trg_node->set_parent($trg_root);
				$done{$head_trg_node} = 1;
				foreach my $another_trg_node ( grep { $_ != $head_trg_node }
					@trg_nodes )
				{
					if ( !$head_trg_node->is_descendant_of($another_trg_node)
						&& ( $another_trg_node != $head_trg_node ) )
					{
						$another_trg_node->set_parent($head_trg_node);
						$done{$another_trg_node} = 1;
						$another_trg_node->wild()->{'parent_guessed'} = 1;
						$another_trg_node->wild()->{'guess_heuristic'} =
						  'find_chunk_head';
					}
				}
				if ( scalar(@trg_nodes) == 1 ) {
					if ( $done{$head_trg_node} ) {
						$self->_set_conserved_dep_edges_count(
							$self->_conserved_dep_edges_count() + 1 )
						  if ( $src_node->get_parent eq $src_root );
					}
				}
				$self->project_subtree( $src_node, $head_trg_node );
			}
			else {
				log_warn
				  'The proposed attachment leads to cycle, thus ignoring it.';
				$head_trg_node->wild()->{'parent_guessed'}  = 1;
				$head_trg_node->wild()->{'guess_heuristic'} = 'avoid_cycle';
				$self->project_subtree( $src_node, $trg_root );
			}
		}
		else {
			$self->project_subtree( $src_node, $trg_root );
		}
	}
	return;
}

sub choose_head {
	my ( $self, $nodes_ref ) = @_;
	my @nodes = @{$nodes_ref};
	my @ns = sort { $a->ord <=> $b->ord } @nodes;
	if ( $self->chunk_head eq 'first' ) {
		return $ns[0];
	}
	elsif ( $self->chunk_head eq 'last' ) {
		return $ns[$#ns];
	}
}

sub process_end {
	my ($self) = @_;
	print "Number of nodes in the source\t:\t" . $self->_total_source_nodes . "\n";
	print "Number of nodes in the target\t:\t" . $self->_total_target_nodes . "\n";
	print "Number of conserved edges\t:\t"
	  . $self->_conserved_dep_edges_count . "\n";
	print "Conserved edges proportion (wrf target)\t:\t"
	  . ( ( $self->_conserved_dep_edges_count / $self->_total_target_nodes ) *
		  100.0 )
	  . "\n";
	print "Unaligned nodes proportion (wrf target)\t:\t"
	  . (
		( $self->_total_unaligned_nodes / $self->_total_target_nodes ) * 100.0 )
	  . "\n";  
}

1;

__END__

=encoding utf-8

=head1 NAME

Treex::Block::Project::Tree - project dependencies via alignment

=head1 SYNOPSIS

 # Project dependencies from en to cs t-trees.
 # Before: cs t-trees are flat, alignment links go from cs to en.
 Project::Tree layer=t language=cs source_language=en
 # After: cs t-trees have "the same" dependency structure as en t-trees.
 
 # Project dependencies from en to cs a-trees.
 # Before: cs a-trees are flat, alignment links go from en to cs.
 Project::Tree layer=a language=cs source_language=en alignment_direction=src2trg

 # You can constrain types of alignment links to be used by specifying regex pattern.
 Project::Tree layer=a language=cs source_language=en alignment_type=(manual|gdfa)
 
=head1 DESCRIPTION

Project dependency trees (a-trees or t-trees) via alignment links from one zone to another.
Only the structure is projected, no dependency labels (afun, conll_deprel) nor other attributes.

=head1 METHODS TO OVERRIDE

=head2 $head_node = $self->choose_head(@nodes)

If the source node is aligned to more target nodes, one of the target nodes is chosen as the head.
The other nodes will become children of the head.
This implementation simply chooses the first node as the head.
This behavior may be overridden in (language-specific) subclasses, e.g. to decide based on PoS tag.

=head1 AUTHOR

Martin Popel <popel@ufal.mff.cuni.cz>
Loganathan Ramasamy <ramasamy@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2012 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
