package Treex::Block::Write::Redirectable;

use Moose::Role;
use autodie;    # die if the output file cannot be opened
use File::Path;
use File::Basename;
use Treex::Core::Common; # log_info

has to => (
    isa           => 'Str',
    is            => 'ro',
    documentation => 'the destination filename (use - for standard output)',
);

has clobber => (
    isa           => 'Bool',
    is            => 'ro',
    default       => 0,
    documentation => 'allow overwriting output files',
);

has encoding => (
    isa           => 'Str',
    is            => 'ro',
    default       => 'utf8',
    documentation => 'Output encoding. \'utf8\' by default.',
);

has _file_handle => (
    isa           => 'FileHandle',
    is            => 'rw',
    documentation => 'the open output file handle',
);
has _lastfilename => (
    isa           => 'Str',
    is            => 'rw',
    documentation => 'Last output filename, to keep stream open if unchanged.',
);

around 'process_document' => sub {
    my $orig = shift;
    my $self = shift;

    my $document = $_[0];
    my $filename;
    
    $filename = $document->full_filename . ($document->compress ? ".gz" : "");

    # Now allow to overwrite the defailt name
    if ($self->to) {
        $filename = $self->to;
    }

    if (defined $self->_lastfilename
        && $filename eq $self->_lastfilename) {
        # nothing to do, keep writing to the old filename
    } else {
        # need to switch output stream
        close $self->_file_handle
            if defined $self->_file_handle
                && (! defined $self->_lastfilename || $self->_lastfilename ne "-");

        # open the new output stream
        log_info "Saving to $filename";
        log_fatal "Won't overwrite $filename (use clobber=1 to force)."
            if ! $self->clobber && -e $filename;
        $self->_file_handle($self->my_save($filename));
    }
    $self->_lastfilename($filename);

    # call the main process_document
    $self->$orig(@_);
};

sub my_save {
  my $self = shift;
  my $f = shift;
  if ($f eq "-") {
    binmode(STDOUT, ":".$self->encoding);
    return \*STDOUT;
  }

  my $opn;
  my $hdl;
  # file might not recognize some files!
  if ($f =~ /\.gz$/) {
    $opn = "| gzip -c > '$f'";
  } elsif ($f =~ /\.bz2$/) {
    $opn = "| bzip2 > '$f'";
  } else {
    $opn = ">$f";
  }
  mkpath( dirname($f) );
  open $hdl, $opn or log_fatal "Can't write to '$opn': $!";
  binmode($hdl, ":".$self->encoding);
  return $hdl;
}

# Storing a file handle in a lexical variable will cause the file handle
# to be automatically closed when the variable goes out of scope.
# So we don't need to close $self->_file_handle in DEMOLISH.

1;
__END__

=encoding utf-8

=head1 NAME 

Treex::Block::Write::Redirectable

=head1 DESCRIPTION

A Moose role for Write blocks that can be redirected to a file. All blocks using this role must C<print> using the 
C<_file_handle> attribute. 

=head1 PARAMETERS

=over

=item C<to>

The name of the output file, STDOUT by default.

=item C<encoding>

The output encoding, C<utf8> by default.

=back

=head1 AUTHOR

Ondřej Dušek <odusek@ufal.mff.cuni.cz>
Ondřej Bojar <bojar@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2011 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
