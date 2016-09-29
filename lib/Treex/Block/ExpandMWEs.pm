package Treex::Block::ExpandMWEs;
use utf8;
use Moose;
use Treex::Core::Common;
use XML::LibXML;

extends 'Treex::Core::Block';

use Data::Dumper;

sub set_order {
    my ( $tlast, $tnode, $tchild ) = @_;
    if (defined $tlast) {
        if ($tlast != $tnode) {
            $tchild->shift_after_subtree($tlast);
        } else {
            $tchild->shift_after_node($tlast);
        }
    } else {
        # put it immediately before the parent's first
        # child (or, if there are no children, immediately
        # before the parent)
        #
        # this branch only happens for the first created
        # left child
        #if ($tnode->get_children()) {
        #    $tchild->shift_before_subtree(($tnode->get_children())[0]);
        #} else {
            $tchild->shift_before_node($tnode);
        #}
    }
}

sub process_tnode {
    my ( $self, $tnode ) = @_;

    if ($tnode->t_lemma =~ m"^<MWE .*</MWE>$"i) {
        log_info "ExpandMWEs: " . $tnode->t_lemma;
        # interpret the t_lemma string as an XML tree.  for this, we
        # need to stick the XML tag onto the front.
        my $xmlstring = '<?xml version="1.0" encoding="UTF-8"?>' . "\n" . $tnode->t_lemma;
        # parse the XML into a DOM object
        my $parser = XML::LibXML->new();
        my $doc    = $parser->parse_string($xmlstring);
        my $root = $doc->getDocumentElement;
        log_info "loaded XML, root name is: " . $root->nodeName;
        log_info "MWE instance: " . $root->getAttribute('mwe');

        my $troot = $tnode;

        # get children of troot, sort into left and right
        # these will be arguments to the MWE
        my @tchildren = grep {defined($_)} $troot->get_children( { ordered => 1 } );
        my @tleft = grep { $_->ord() <= $troot->ord } @tchildren;
        my @tright = grep { $_->ord() >= $troot->ord } @tchildren;
        log_info "root's children " . scalar(@tchildren) . ": " . join(', ', map {$_->get_attr('t_lemma')} @tchildren);
        log_info "left children " . scalar(@tleft) . ": " . join(', ', map {$_->get_attr('t_lemma')} @tleft);
        log_info "right children " . scalar(@tright) . ": " . join(', ', map {$_->get_attr('t_lemma')} @tright);
        # we also use indices into the tleft and tright to show where
        # we are in these lists
        my $tlefti = my $trighti = 0;

        # this is a stack-based loop (instead of recursion) to expand
        # the treelet.  we start with the top nodes on the stack (xml
        # node and treex node, respectively)
        my @todo = ([$root, $troot]);
        while (@todo) {
            log_info 'todo stack is: ' . join(' ', map {$_->[0]->nodeName . " " . ($_->[1]->get_attr('t_lemma') // 'new')} @todo);
            my @cval = @{shift @todo};
            my $xmlnode = $cval[0];
            my $tnode = $cval[1];
            log_info "working on: " . $xmlnode->nodeName . " " . ($tnode->get_attr('t_lemma') // 'new');

            #print $todo[0]->[0]->nodeName, " ", $todo[0]->[1]->t_lemma, "\n";
            #print Dumper(@cval), "\n";

            # copy attributes of xmlnode into tnode
            if ($tnode == $troot) {
                # for the root, just copy the t_lemma
                log_info "set tnode lemma to " . $xmlnode->getAttribute('t_lemma');
                $tnode->set_t_lemma($xmlnode->getAttribute('t_lemma'));
            } else {
                # for all other nodes, copy all attributes except for "ord"
                for my $attr ($xmlnode->attributes()) {
                    log_info "set tnode attribute " . $attr->nodeName . " to " . $attr->value;
                    $tnode->set_attr( $attr->nodeName, $attr->value ) if $attr->nodeName ne 'ord';
                }
            }

            # this variable points to the rightmost child that we've
            # created (or argument that we've moved into position).
            # it's used as a way to make sure that we put children of
            # treelet nodes into the correct locations in the tree.
            my $tlast = undef;

            # we now loop over LEFT and RIGHT conditions
            #   human-readable label of which side we're branching on
            #   regular expression
            #   initial value of tlast
            #   which index into the children array we want to use (reference)
            #   which array of children (left or right) to use
            for ([ 'left', qr{^l}, undef, \$tlefti, \@tleft ],
                 [ 'right', qr{^r}, $tnode, \$trighti, \@tright ]) {
                my @searchparams = @{$_};
                my $branchname = $searchparams[0];
                my $xmlregex = $searchparams[1];
                my $tlast = $searchparams[2];
                my $cidxref = $searchparams[3];
                @tchildren = @{$searchparams[4]};
                log_info "condition: $branchname $xmlregex ${$cidxref} $#tchildren";

                # loop over left/right children of the XML node
                for my $xmlchild (grep {$_->nodeName =~ m{$xmlregex}} $xmlnode->childNodes()) {
                    log_info "XML node's child " . $xmlchild->nodeName;
                    # is this child new, or expected?
                    if ($xmlchild->nodeName !~ /x$/) {
                        log_info "new child, creating child of '" . ($tnode->get_attr('t_lemma') // 'new') . "'";
                        # new; create a new child of tnode
                        my $tchild = $tnode->create_child();
                        # set the order
                        set_order($tlast, $tnode, $tchild);
                        # add this to todo
                        push @todo, [$xmlchild, $tchild];
                        # update tlast to point to the new child
                        $tlast = $tchild;
                    } else {
                        # expected; are there left/right children of tnode
                        # which could be this node?
                        my @cands = @tchildren[${$cidxref},-1];
                        log_info "cands last index is $#cands";
                        log_info "cidxref ref " . Dumper($cidxref);
                        log_info "cidxref " . Dumper(${$cidxref});
                        log_info "cands " . Dumper(@cands);
                        log_info "tchildren " . Dumper(@tchildren);
                        # SIMPLE CHECKING: just check for the presence of a node
                        if (@cands) {
                            # OK
                            log_info "tnode undefined" if !defined($tnode);
                            log_info "cands[0] undefined" if !defined($cands[0]);
                            log_info "found expected child of node " . ($tnode->get_attr('t_lemma') // 'new') . " with formeme " . $xmlchild->getAttribute('formeme') . ": " . ($cands[0]->get_attr('t_lemma') // 'new') . " with formeme " . ($cands[0]->get_attr('formeme') // 'none');
                            # move the node into location
                            $cands[0]->set_parent($tnode) if $tnode != $troot;
                            set_order($tlast, $tnode, $cands[0]);
                            # increment the children index
                            ${$cidxref} += 1;
                            # move tlast
                            $tlast = $cands[0];
                        } else {
                            # ERROR, say something
                            log_info "ERROR: expected child of node " . ($tnode->get_attr('t_lemma') // 'new') . " with formeme " . $xmlchild->getAttribute('formeme');
                            # don't move tlast
                        }
                    }
                }
            }
        }

        # warn about any unused arguments here
        if ($tlefti <= $#tleft) {
            log_info "warning unused left arguments: " . join(', ', map {$_->get_attr('t_lemma')} @tleft[$tlefti,-1]);
        }
        if ($trighti <= $#tright) {
            log_info "warning unused right arguments: " . join(', ', map {$_->get_attr('t_lemma')} @tright[$trighti,-1]);
        }
    }
}
