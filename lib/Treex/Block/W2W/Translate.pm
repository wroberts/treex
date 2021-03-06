package Treex::Block::W2W::Translate;
use Moose;
use Treex::Core::Common;
use utf8;
extends 'Treex::Core::Block';

use Treex::Tool::GoogleTranslate::APIv2;

#use Moose::Util::TypeConstraints;

has '+language' => ( required => 1 );
has 'language_for_google' => ( is => 'rw', isa => 'Str', default => '' );

has 'target_language' => ( is => 'rw', isa => 'Str', default => 'en' );
has 'target_selector' => ( is => 'rw', isa => 'Str', default => 'GT' );

has auth_token         => ( is => 'rw', isa => 'Maybe[Str]', default => undef );
has auth_token_in_file => ( is => 'rw', isa => 'Maybe[Str]', default => undef );

has sid => ( is => 'rw', isa => 'Maybe[Str]', default => undef );

has overwrite => (
    is => 'rw',
    isa => enum(['skip', 'replace', 'concatenate']),
    default => 'skip',
);

# TODO: retries

# translator API
has _translator => (
    is       => 'ro',
    isa      => 'Treex::Tool::GoogleTranslate::APIv2',
    init_arg => undef,
    builder  => '_build_translator',
    lazy     => 1,
);

# hashref of sids to be translated, or undef to translate all
has _sids => (
    is       => 'ro',
    isa      => 'Maybe[HashRef]',
    init_arg => undef,
    builder  => '_build_sids',
    lazy     => 1,
);

sub _build_translator {
    my $self = shift;

    my $translator = Treex::Tool::GoogleTranslate::APIv2->new(
        {
            auth_token         => $self->auth_token,
            auth_token_in_file => $self->auth_token_in_file,
            src_lang           =>
                ($self->language_for_google
                    ||
                $self->language),
            tgt_lang           => $self->target_language,
        }
    );

    return $translator;
}

sub _build_sids {
    my ($self) = @_;

    my $sids;
    if ( defined $self->sid ) {
        my @sids_array = split / /, $self->sid;
        $sids = {};
        foreach my $sid (@sids_array) {
            $sids->{$sid} = 1;
        }
    }

    return $sids;
}

# TODO use batch translation for batches of reasonably lomng sentences
sub process_zone {
    my ( $self, $zone ) = @_;

    my $sid = $zone->get_bundle->id;
    if ( defined $self->_sids && !defined $self->_sids->{$sid} ) {

        # translate only the sentences with the given ids
        return;
    }

    if ( $self->has_translation( $zone ) ) {
        if ( $self->overwrite eq 'skip' ) {
            log_info "$sid: there already is a translation, skipping...";
            return;
        }
        elsif ( $self->overwrite eq 'replace' ) {
            $self->delete_translation( $zone );
            log_info "$sid: there already is a translation, deleting...";
            # and continue translating
        }
        else {
            # concatenate
            log_info "$sid: there already is a translation, concatenating...";
            # and continue translating
        }
    }
    my $translation = $self->get_translation( $zone );
    $self->set_translation( $translation, $zone );

    return;
}

sub has_translation {
    my ($self, $zone) = @_;

    return ($self->old_translation($zone) ne '');
}

sub old_translation {
    my ($self, $zone) = @_;

    my $translation = '';
    my $translation_zone = $zone->get_bundle->get_zone(
            $self->target_language,
            $self->target_selector
        );
    if ( defined $translation_zone && defined $translation_zone->sentence()) {
        $translation = $translation_zone->sentence();
    }

    return $translation;
}

sub delete_translation {
    my ( $self, $zone ) = @_;

    $zone->get_bundle->get_or_create_zone(
        $self->target_language,
        $self->target_selector
    )->set_sentence('');

    return;
}

sub get_translation {
    my ( $self, $zone ) = @_;

    return $self->_translator->translate_simple($zone->sentence);
}

sub set_translation {
    my ( $self, $translation, $zone, $nolog ) = @_;

    my $sid = $zone->get_bundle->id;

    if ( $translation ne '' ) {

        # success
        $zone->get_bundle->get_or_create_zone(
            $self->target_language,
            $self->target_selector
        )->set_sentence(
            $self->concatenate(
                $self->old_translation($zone),
                $translation
            )
        );

        if ( !defined $nolog ) {
            log_info "Translated $sid " .
                $self->language . ":'" . $zone->sentence . "'" .
                " to " . $self->target_language . ":'$translation'";
        }
        return 1;
    }
    else {

        # failure
        log_warn "$sid: No translation generated - no translation saved!";
        return 0;
    }
}

sub concatenate {
    my ($self, $old, $new) = @_;
    
    if ( defined $old && $old ne '' ) {
        return "$old $new";
    }
    else {
        return $new;
    }
}

1;

=head1 NAME 

Treex::Block::W2W::Translate

Translates the sentence using Google Translate.

=head1 DESCRIPTION

Uses L<Treex::Tool::GoogleTranslate::APIv1> and actually is only its thin
wrapper - please see its POD for details.

(Probably could be called L<Treex::Block::W2W::GoogleTranslate> but such a
block already exists and I am not touching it not to break anything.)

=head1 SYNOPSIS
 
 # translate all Bulgarian sentences in the file to English, into en_GT zone
 treex -s W2W::Translate language=bg -- bg_file.treex.gz

 # translate to Czech, to cs_GOOGLE selector
 treex -s W2W::Translate language=bg target_language=cs target_selector=GOOGLE -- bg_file.treex.gz

 # translate only first 5 sentences
 treex -s W2W::Translate language=bg sid='s1 s2 s3 s4 s5' -- bg_file.treex.gz

=head1 PARAMETERS

=over

=item language

Source language. Required.

=item language_for_google

Set if the language identifier used by Google Translate is different from
your language identifier.
See L<https://developers.google.com/translate/v2/using_rest#language-params>
for a list of languages supported by Google Translate and their codes.

Defaults to empty string, i.e. use C<language> for Google as well.

=item target_language

Defaults to C<en>.

=item target_selector

Defaults to C<GT>.

=item sid

List of sentence ids to translate, separated by spaces.
If set, only the sentences with the given ids will be translated.
Defaults to C<undef> - all sentences are translated by default.

=item auth_token

Your AUTH_TOKEN from Google.
If not set, it will be attempted to read it from C<auth_token_in_file>.
If this is not successful, a C<log_fatal> will be issued.

If you have registered for the University Research
Program for Google Translate, you can get one using your email, password and the
following procedure (copied from official manual):

Here is an example using curl to get an authentication token:

  curl -d "Email=username@domain&Passwd=password&service=rs2"
  https://www.google.com/accounts/ClientLogin

Make sure you remember to substitute in your username@domain and password.
Also, be warned that your username and password may be stored in your
history file (e.g., .bash_history) and you should take precautions to remove
it when finished. 

=item auth_token_in_file

File containing the C<auth_token>.
Defaults to C<~/.gta> (cross-platform solution is used, i.e. C<~> is the user
home directory as returned by L<File::HomeDir>).

=item overwrite

What happens if the translation (with the given target language and selector) is
already set. Supported values are:

=over

=item skip

Do not perform the translation at all. (Useful e.g. if you have partially translated
files.)
This is the default.

=item replace

Delete the old translation. Is deleted even if translation fails (to ensure
consistency).

=item concatenate

Concatenate the old translation with the new one.

=back

=back

=head1 AUTHOR

Rudolf Rosa <rosa@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2013 by Institute of Formal and Applied Linguistics,
Charles University in Prague

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

