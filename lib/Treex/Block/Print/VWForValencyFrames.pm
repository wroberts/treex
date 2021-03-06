package Treex::Block::Print::VWForValencyFrames;

use Moose;
use Treex::Core::Common;
use Treex::Tool::Vallex::ValencyFrame;
use Treex::Tool::FeatureExtract;

extends 'Treex::Block::Write::BaseTextWriter';

has '+extension' => ( default => '.vw' );

has '+language' => ( required => 1 );

has 'valency_dict_name' => ( is => 'ro', isa => 'Str', default => 'engvallex.xml' );

has 'valency_dict_prefix' => ( is => 'ro', isa => 'Str', default => 'en-v#' );

has 'restrict_frames_file' => ( is => 'ro', isa => 'Str', default => '' );

has 'features_file' => ( is => 'ro', isa => 'Str', required => 1 );

has '_feat_extract' => ( is => 'rw', default => 0 );

has 'vallex_mapping_file' => ( is => 'ro', isa => 'Str', default => '' );

has 'vallex_mapping_by_lemma' => ( is => 'ro', isa => 'Bool', default => 0 );

has '_vallex_mapping' => ( is => 'ro', isa => 'Maybe[HashRef]', lazy_build => 1, builder => '_build_vallex_mapping' );

has '_restrict_frames' => ( is => 'ro', isa => 'Maybe[HashRef]', lazy_build => 1, builder => '_build_restrict_frames' );

#
#
#

sub BUILD {
    my ($self) = @_;

    $self->_set_feat_extract( Treex::Tool::FeatureExtract->new( { features_file => $self->features_file } ) );
}

sub _get_file {
    my ( $self, $file ) = @_;

    if ( !-f $file ) {
        $file = Treex::Core::Resource::require_file_from_share( $file, ref($self) );
    }
    if ( !-f $file ) {
        log_fatal 'File ' . $file . ' does not exist.';
    }
    return $file;
}

sub _build_vallex_mapping {

    my ($self) = @_;
    return undef if ( not $self->vallex_mapping_file );

    my $mapping_file = $self->_get_file( $self->vallex_mapping_file );

    my %mapping = ();
    my $prefix = $self->valency_dict_prefix // '';
    open( my $fh, '<:utf8', $mapping_file );
    while ( my $line = <$fh> ) {
        chomp $line;
        my ( $frame_id, $lemma, $score ) = split /\t/, $line;
        $score //= 1;
        $mapping{$lemma}{$prefix.$frame_id} = $score;
        
#         if ( !defined( $mapping{$lemma} ) ) {
#             $mapping{$lemma} = [];
#         }
#         push @{ $mapping{$lemma} }, $prefix . $frame_id;
    }
    close($fh);
    return \%mapping;
}

sub _build_restrict_frames {

    my ($self) = @_;
    return undef if ( not $self->restrict_frames_file );

    my $restrict_file = $self->_get_file( $self->restrict_frames_file );

    my %restrict = ();
    open( my $fh, '<:utf8', $restrict_file );
    while ( my $line = <$fh> ) {
        next if $line =~ /^#/;
        chomp $line;
        my ( $lemma, $frames_str ) = split /\t/, $line;
        my %frames = map { $_ => 1 } split / /, $frames_str;
        $restrict{$lemma} = \%frames;
    }
    close($fh);
    return \%restrict;
}

sub process_ttree {

    my ( $self, $ttree ) = @_;

    # Get all needed informations for each node and save it to the ARFF storage
    my @tnodes  = $ttree->get_descendants( { ordered => 1 } );
    my $word_id = 1;
    my $sent_id = $ttree->get_document->file_stem . $ttree->get_document->file_number . '##' . $ttree->id;
    $sent_id =~ s/[-_]root$//;

    foreach my $tnode (@tnodes) {

        # skip non-verbs, verbs with unset valency frame
        next if ( ( ( $tnode->gram_sempos || '' ) ne 'v' ) or ( not $tnode->val_frame_rf ) );

        # try to get features
        my ($feat_str) = $self->get_feats_and_class( $tnode, $sent_id, $word_id++ );

        # if there are features (i.e. more different valency frames to predict), print them out
        if ($feat_str) {
            print { $self->_file_handle } $feat_str;
        }
    }

    return;
}

# Return all features as a VW string + the correct class (or undef, if not available)
# tag each class with its label + optionally sentence/word id, if they are set
sub get_feats_and_class {
    my ( $self, $tnode, $sent_id, $word_id ) = @_;

    my ( $class, $classes ) = $self->_get_classes($tnode);

    # skip weird cases
    if ( $class and ( not any { $_ eq $class } @$classes ) ) {
        log_warn 'Correct class not found in Vallex for given lemma: ' . $class . ' ' . $tnode->t_lemma . ' ' . $tnode->id . ' // ' . join( ' ', @$classes );
        return ( undef, undef );
    }
    if ( @$classes == 1 ) {
        return ( undef, $classes->[0] );    # just return first class if there is nothing to predict
    }

    # get all features, formatted for VW
    my $feats = $self->_feat_extract->get_features_vw($tnode);

    # check Vallex mapping for the aligned t-lemma
    my %vallex_mapped  = ();
    my $mapping_suffix = '';
    if ( $self->_vallex_mapping ) {
        my $aligned_lemma = $self->_feat_extract->_get_data( $tnode, 'aligned->t_lemma' );
        if ( defined( $self->_vallex_mapping->{$aligned_lemma} ) ) {
            #%vallex_mapped = map { $_ => 1 } @{ $self->_vallex_mapping->{$aligned_lemma} };
            %vallex_mapped = %{ $self->_vallex_mapping->{$aligned_lemma} };
        }
        if ( $self->vallex_mapping_by_lemma ) {
            $mapping_suffix = '_' . $tnode->t_lemma;
        }
    }

    # TODO make this filtering better somehow
    $feats = [ grep { $_ !~ /^(val_frame\.rf|parent|number_of_senses)[=:]/ } @$feats ];

    # prepare instance tag
    my $inst_id = '';
    if ( $sent_id and $word_id ) {
        $inst_id = $sent_id . '-' . $word_id;
        $inst_id =~ s/##.*-s/-s/;
        $inst_id .= '=';
    }

    # format for the output
    my $feat_str = 'shared |S ' . join( ' ', @$feats ) . "\n";

    for ( my $i = 0; $i < @$classes; ++$i ) {
        my $cost = '';
        my $tag  = '\'' . $inst_id . $classes->[$i];
        if ($class) {
            $cost = ':' . ( $classes->[$i] eq $class ? 0 : 1 );
            if ( $classes->[$i] eq $class ) {
                $tag .= '--correct';
            }
        }
        $feat_str .= ( $i + 1 ) . $cost . ' ' . $tag;
        my $mapped_score = $vallex_mapped{ $classes->[$i] };
        if ( $mapped_score ) {
            $feat_str .= ' |M vallex_mapping' . $mapping_suffix;
            # The following line adds not only the binary feature mapping yes/no, but also the $mapped_score
            #$feat_str .= " |M vallex_mapping$mapping_suffix map_prob:$mapped_score";
        }
        $feat_str .= ' |T val_frame_rf=' . $classes->[$i] . "\n";
    }
    $feat_str .= "\n";
    return ( $feat_str, $class // $classes->[0] );    # return feature string output + correct or first class
}

# Return possible classes and the right class (or undef, if not defined)
sub _get_classes {
    my ( $self, $tnode ) = @_;

    my $lemma  = lc $tnode->t_lemma;
    my $sempos = $tnode->gram_sempos // 'v';          # sempos: default to verbs, use just 1st part
    $sempos =~ s/\..*//;

    # Try using both underscores and spaces to find the valency frame
    my (@frames) = Treex::Tool::Vallex::ValencyFrame::get_frames_for_lemma( $self->valency_dict_name, $self->language, $lemma, $sempos );
    if ( !@frames and $lemma =~ /_/ ) {
        $lemma =~ s/_/ /g;
        @frames = Treex::Tool::Vallex::ValencyFrame::get_frames_for_lemma( $self->valency_dict_name, $self->language, $lemma, $sempos );
    }

    # Restrict frames only to those actually used in the training data (if such restriction is available)
    $lemma =~ s/ /_/g;
    if ( $self->_restrict_frames and $self->_restrict_frames->{$lemma} ) {
        my $restrict = $self->_restrict_frames->{$lemma};
        @frames = grep { $restrict->{ $_->id } } @frames;
    }

    # TODO try @frames = ( $frames[0] );
    my @frame_ids = map { $self->valency_dict_prefix . $_->id } @frames;
    return $tnode->val_frame_rf, \@frame_ids;
}

1;

__END__
