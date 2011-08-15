package Treex::Block::Filter::CzEng::TrainMaxEntModel;
use Moose;
use Treex::Core::Common;
use AI::MaxEntropy;
use AI::MaxEntropy::Model;
extends 'Treex::Block::Filter::CzEng::Train';

sub process_document {
    my ( $self, $document ) = @_;
    my $maxent = AI::MaxEntropy->new();

    # train
    open( my $anot_hdl, $self->{annotation} ) or log_fatal $!;
    my @bundles = $document->get_bundles();
    for ( my $i = 0; $i < $self->{use_for_training}; $i++ ) {
        log_fatal "Not enough sentences for training" if $i >= scalar @bundles;
        my @features = $self->get_features($bundles[$i]);
        my $anot     = <$anot_hdl>;
        $anot = ( split( "\t", $anot ) )[0];
        log_fatal "Error reading annotation file $self->{annotation}" if ! defined $anot;
        $maxent->see( \@features => $anot );
    }
    my $model = $maxent->learn();
    $model->save( $self->{outfile} );

    # evaluate
    my ( $x, $p, $tp );
    for ( my $i = $self->{use_for_training}; $i < scalar @bundles; $i++ ) {
        my @features = $self->get_features($bundles[$i]);
        my $anot     = <$anot_hdl>;
        $anot = ( split( "\t", $anot ) )[0];
        log_fatal "Error reading annotation file $self->{annotation}" if ! defined $anot;
        $x++ if $anot eq 'x';
        my $prediction = $model->predict( \@features );
        $p++ if $prediction eq 'x';
        $tp++ if $prediction eq $anot;
    }
    log_info sprintf( "Precision = %.03f, Recall = %.03f\n", $tp / $p, $tp / $x );

    return 1;
}

return 1;

=over

=item Treex::Block::Filter::CzEng::TrainMaxEntModel

Given a manually annotated document and results of all filters,
train a maximum entropy model and store it in 'outfile'.

=back

=cut

# Copyright 2011 Ales Tamchyna

# This file is distributed under the GNU General Public License v2. See $TMT_ROOT/README.
