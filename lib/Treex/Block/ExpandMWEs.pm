package Treex::Block::ExpandMWEs;
use utf8;
use Moose;
use Treex::Core::Common;
use XML::LibXML;

extends 'Treex::Core::Block';

sub process_ttree {
    my ( $self, $ttree ) = @_;

    my @all_tnodes = $ttree->get_descendants({ordered=>1});
    foreach my $tnode (@all_tnodes) {
        if ($tnode->t_lemma =~ m"^<MWE .*</MWE>$") {
            log_info $tnode->t_lemma;
            # interpret the t_lemma string as an XML tree
            # we need to stick the XML tag onto the front
            my $xmlstring = '<?xml version="1.0" encoding="UTF-8"?>' . "\n" . $tnode->t_lemma;
            # parse the XML into a DOM object
            my $parser = XML::LibXML->new( );
            my $doc    = $parser->parse_string($xmlstring);
            print $doc->getDocumentElement->nodeName . "\n";
        }
    }
}
