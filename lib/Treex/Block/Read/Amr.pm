package Treex::Block::Read::Amr;
use feature qw(switch);
use Moose;
use Treex::Core::Common;
extends 'Treex::Block::Read::BaseTextReader';

sub next_document {
    my ($self) = @_;
    my $text = $self->next_document_text();
    return if !defined $text;
    
    $text =~ s/[\n|\s]+/ /g;

    my @chars = split ('', $text);

    my $state = 'Void';
    my $value = '';
    my $lemma = '';
    my $word = '';
    my $modifier = '';
    my $param = '';
    my %param2id = {};
    my $ord = 0;
    my $brackets_match = 0;
    my $sentencecount = 0;

    my ($bundle, $zone, $tree, $currentNode);

    my $doc = $self->new_document();
    foreach my $arg (@chars) {
      given($arg) {
        when ('(') {
          if ($state eq 'Void') {
            %param2id = {};
            $bundle = $doc->create_bundle;
            #$zone = $document->create_zone( $self->language, $self->selector );
            $zone = $bundle->create_zone($self->language, $self->selector );
            $tree = $zone->create_ttree();
            $currentNode = $tree->create_child({ord => $ord});
            $currentNode->wild->{modifier} = 'root';
            $ord++;
          }
          $state = 'Param';
          $value = '';
          $brackets_match++;
        }
        
        when('/') {
          if ($state eq 'Param' && $value) {
            $param = $value;
            $state = 'Word';
          }
          $value = '';
        }
        
        when(':') {
          if ($state eq 'Word' && $value) {
            $lemma = '';
            $word = $value;
            if ($param) {
              $lemma = $param;
            }
            if ($lemma) {
              $lemma .= '/' . $word;
            } else {
              $lemma = $word;
            }
            if ($lemma) {
              $currentNode->set_attr('t_lemma', $lemma);
            }
            if ($param) {
              if (exists($param2id{$param})) {
                $currentNode->add_coref_text_nodes($doc->get_node_by_id($param2id{$param}));
              } else {
                $param2id{$param} = $currentNode->get_attr('id');
              }
            }
            $param = '';
            $word = '';
            $value = '';
          }
          if ($state eq 'Param' && $value) {
            $param = $value;
            if ($param) {
              $currentNode->set_attr('t_lemma', $param);
            }
            if ($param) {
              if (exists($param2id{$param})) {
                $currentNode->add_coref_text_nodes($doc->get_node_by_id($param2id{$param}));
              } else {
                $param2id{$param} = $currentNode->get_attr('id');
              }
            }
            $currentNode = $currentNode->get_parent();
            $param = '';
            $word = '';
            $value = '';
          }
          $state = 'Modifier';
        }
        when(' ') {
          if ($state eq 'Modifier' && $value) {
            $modifier = $value;
            my $newNode = $currentNode->create_child({ord => $ord});
            $ord++;
            $currentNode = $newNode;
            if ($modifier) {
              $currentNode->wild->{modifier} = $modifier;
              $modifier = '';
            }
            $value = '';
            $state = 'Param';
          }
        }
        
        when('"') {
          if ($state eq 'Word' && $value) {
            $currentNode->{t_lemma} = $value;
            $value = '';
            $currentNode = $currentNode->get_parent();
          }
          if ($state eq 'Param') {
            $state = 'Word';
          }
        }
        
        when(')') {
          $lemma = '';
          if ($state eq 'Param') {
            $param = $value;
          }
          if ($state eq 'Word') {
            $word = $value;
          }
          $lemma = $param;
          if ($word) {
            $lemma .= ($lemma?'/':'') . $word;
          }
          if ($lemma) {
            $currentNode->set_attr('t_lemma', $lemma);
          }
          if ($param) {
            if (exists($param2id{$param})) {
              $currentNode->add_coref_text_nodes($doc->get_node_by_id($param2id{$param}));
            } else {
              $param2id{$param} = $currentNode->get_attr('id');
            }
          }
         
          $currentNode = $currentNode->get_parent();
          $value = '';
          $word = '';
          $param = '';
          $brackets_match--;
          if ($brackets_match eq 0) {
            $state = 'Void';
            $ord = 0;
            $sentencecount++;
          }
        }
        
        default {
          $value .= $arg;
        }
        
      }
    }

    return $doc;
}

1;

__END__

=head1 NAME

Treex::Block::Read::Amr

=head1 DESCRIPTION

converts AMR bracketed file format to the treex format that can be viewed or
edited with TrEd
We actually reuse the standard t-layer instead of creating a proper layer on
its own.
code: Roman Sudarikov
info: Ondrej Bojar, bojar@ufal.mff.cuni.cz

=head1 ATTRIBUTES

=over

=item from

space or comma separated list of filenames

=back

=head1 METHODS

=over

=item next_document

Loads a document.

=back

=head1 AUTHOR

Roman Sudarikov

=head1 COPYRIGHT AND LICENSE

Copyright © 2011 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.