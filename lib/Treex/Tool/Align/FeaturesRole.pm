package Treex::Tool::Align::FeaturesRole;

use Moose::Role;
use Moose::Util::TypeConstraints;
use Treex::Core::Common;

requires '_unary_features';
requires '_binary_features';

has 'node1_label' => (is => 'ro', isa => 'Str', default => 'n1');
has 'node2_label' => (is => 'ro', isa => 'Str', default => 'n2');

my $SELF_LABEL = "__SELF__";

sub cat {
    my ($self, $feats, $name) = @_;

    my $val1 = $feats->{$self->node1_label . "_" . $name} // "";
    my $val2 = $feats->{$self->node2_label . "_" . $name} // "";
    return $val1 . "_" . $val2;
}

sub eq {
    my ($self, $feats, $name) = @_;

    my $val1 = $feats->{$self->node1_label . "_" . $name} // "";
    my $val2 = $feats->{$self->node2_label . "_" . $name} // "";
    return $val1 eq $val2 ? 1 : 0;
}

sub feat_hash_to_sparse_list {
    my ($hash) = @_;
    my @list = map {
        my $key = $_;
        if (ref($hash->{$key}) eq "ARRAY") {
            map {[$key, $_]} @{$hash->{$key}};
        }
        else {
            [$key, $hash->{$key}];
        }
    } keys %$hash;
    @list = grep {defined $_->[1]} @list;
    return \@list;
}

sub _unary_features_prefixed {
    my ($self, $node, $type) = @_;
    my $feats = $self->_unary_features( $node );
    my %new_feats = map {$type . "_" . $_ => $feats->{$_}} keys %$feats;
    return \%new_feats;
}

sub create_instances {
    my ($self, $node1, $cands) = @_;
    
    my $node1_unary_h = $self->_unary_features_prefixed( $node1, $self->node1_label );
    my $node1_unary_l = feat_hash_to_sparse_list($node1_unary_h);

    my @cand_feats = ();
    my $ord = 1;
    foreach my $cand (@$cands) {
        if ($cand != $node1) {
            my $cand_unary_h = $self->_unary_features_prefixed( $cand, $self->node2_label );
            # TODO for convenience we merge the two hashes into a single one => should be passed separately
            my $both_unary_h = {%$cand_unary_h, %$node1_unary_h};
            my $cand_binary_h = $self->_binary_features( $both_unary_h, $node1, $cand, $ord);
            my $cand_unary_l = feat_hash_to_sparse_list($cand_unary_h);
            my $cand_binary_l = feat_hash_to_sparse_list($cand_binary_h);
            push @cand_feats, [@$cand_unary_l, @$cand_binary_l];
        }
        # pushing empty instance for the anaphor as candidate (it is entirely described by shared features)
        else {
            push @cand_feats, [[$SELF_LABEL,1]];
        }
        $ord++;
    }

    return [\@cand_feats, $node1_unary_l];
}

1;
