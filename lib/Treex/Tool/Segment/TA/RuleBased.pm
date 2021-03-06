package Treex::Tool::Segment::TA::RuleBased;
use utf8;
use Moose;
use Treex::Core::Common;
extends 'Treex::Tool::Segment::RuleBased';

# In Tamil, there are places where terminal punctuation '.'
# occur but that is not a sentence boundary. The "Name intials"
# are the most likely places of occurrence.
 
# for ex: The name "Palaniappan Chidambaram" is written in 
# Tamil as "P. Chidambaram" where the sentence segmentation 
# program shouldn't treat the "." as sentence boundary.

# The following regex lists all possible "Name initials"

#my $UNBREAKERS = qr{
#    tapiLyU|TirumaTi|Tiru|celvi|ngai|njai|shai|shau|ngau|njau|nge|nau|vau|Rau|nai|shi|shu|she|
#jau|hai|hau|rau|wau|zau|shO|Nau|rai|Lai|Lau|lau|vai|Rai|tai|xau|ngA|shI|shA|
#pau|njO|wai|ngo|njU|ngu|Sai|Sau|nga|shE|sho|ngU|jai|zai|mau|yau|kau|sha|yai|
#nje|kai|nju|njE|xai|tau|sri|njo|ngE|ngO|ngI|pai|nji|njI|cai|cau|mai|nja|ngi|
#Tau|Tai|lai|njA|shU|Nai|ep|ec|el|em|en|Ar|eS|LU|Ri|Ru|LE|rA|LA|ne|ri|RO|Re|rI|Ro|RU|Le|nO|zA|cE|
#le|yI|lO|SU|lu|lU|vI|vU|ca|vO|yU|Ni|ze|rE|zu|re|zo|zE|rO|nA|lA|jI|zI|pE|To|
#ya|va|pa|yA|la|ra|wa|au|ta|hA|wE|ve|ka|RI|wu|li|xa|na|NA|yu|hI|te|Ra|La|Li|
#Sa|ha|ju|ro|ji|jo|jE|je|kI|LI|nu|nI|ru|ti|nE|SO|lI|SI|wI|So|SE|Ti|SA|me|Si|
#hi|sh|hE|he|xE|ko|xU|Ta|ng|jU|xO|xo|vu|lo|ma|xu|xI|wA|xA|cA|kO|Lo|ki|cU|cu|
#Nu|ci|kA|RE|nj|kE|ke|kU|jA|NU|Na|Su|TA|vo|xe|nU|LO|jO|pU|co|zO|RA|ku|pI|Lu|
#ni|TU|ho|No|Tu|zU|wo|TI|Se|TO|za|TE|zi|pe|pu|ai|vA|mA|pO|po|we|wU|vE|pi|pA|
#wO|hO|lE|yi|mU|ce|yo|yE|ye|mu|mI|Te|mO|mo|mE|vi|ja|tU|tu|tO|to|tE|tI|rU|yO|
#mi|no|tA|cO|xi|NE|Ne|hU|hu|wi|NI|cI|NO|i|a|T|S|n|c|h|p|O|o|q|u|y|e|t|v|m|k|
#a|I|E|U|z|R|l|r|L|j|w|N|A|x
#}x; 

# The following are Tamil "initials" in UTF8.
my $UNBREAKERS = qr {டபிள்யூ|திருமதி|திரு|செல்வி|ஙை|ஞை|ஷை|ஷௌ|ஙௌ|ஞௌ|ஙெ|னௌ|
	வௌ|றௌ|னை|ஷி|ஷு|ஷெ|ஜௌ|ஹை|ஹௌ|ரௌ|நௌ|ழௌ|ஷோ|ணௌ|ரை|ளை|ளௌ|
	லௌ|வை|றை|டை|க்ஷௌ|ஙா|ஷீ|ஷா|பௌ|ஞோ|நை|ஙொ|ஞூ|ஙு|ஸை|ஸௌ|ங|ஷே|ஷொ|ஙூ|ஜை|
	ழை|மௌ|யௌ|கௌ|ஷ|யை|ஞெ|கை|ஞு|ஞே|க்ஷை|டௌ|ஸ்ரீ|ஞொ|ஙே|ஙோ|ஙீ|பை|ஞி|ஞீ|சை|சௌ|
	மை|ஞ|ஙி|தௌ|தை|லை|ஞா|ஷூ|ணை|எப்|எச்|எல்|எம்|என்|ஆர்|எஸ்|ளூ|றி|று|ளே|ரா|ளா|னெ|ரி|றோ|
	றெ|ரீ|றொ|றூ|ளெ|னோ|ழா|சே|லெ|யீ|லோ|ஸூ|லு|லூ|வீ|வூ|ச|வோ|யூ|ணி|ழெ|ரே|ழு|ரெ|
	ழொ|ழே|ரோ|னா|லா|ஜீ|ழீ|பே|தொ|ய|வ|ப|யா|ல|ர|ந|ஔ|ட|ஹா|நே|வெ|க|றீ|நு|லி|க்ஷ|ன|
	ணா|யு|ஹீ|டெ|ற|ள|ளி|ஸ|ஹ|ஜு|ரொ|ஜி|ஜொ|ஜே|ஜெ|கீ|ளீ|னு|னீ|ரு|டி|னே|ஸோ|லீ|
	ஸீ|நீ|ஸொ|ஸே|தி|ஸா|மெ|ஸி|ஹி|ஷ்|ஹே|ஹெ|க்ஷே|கொ|க்ஷூ|த|ங்|ஜூ|க்ஷோ|க்ஷொ|
	வு|லொ|ம|க்ஷு|க்ஷீ|நா|க்ஷா|சா|கோ|ளொ|கி|சூ|சு|ணு|சி|கா|றே|ஞ்|கே|கெ|கூ|ஜா|
	ணூ|ண|ஸு|தா|வொ|க்ஷெ|னூ|ளோ|ஜோ|பூ|சொ|ழோ|றா|கு|பீ|ளு|னி|தூ|ஹொ|ணொ|து|ழூ|நொ|
	தீ|ஸெ|தோ|ழ|தே|ழி|பெ|பு|ஐ|வா|மா|போ|பொ|நெ|நூ|வே|பி|பா|நோ|ஹோ|லே|யி|மூ|செ|யொ|
	யே|யெ|மு|மீ|தெ|மோ|மொ|மே|வி|ஜ|டூ|டு|டோ|டொ|டே|டீ|ரூ|யோ|மி|னொ|டா|சோ|க்ஷி|ணே|
	ணெ|ஹூ|ஹு|நி|ணீ|சீ|ணோ|இ|அ|த்|ஸ்|ன்|ச்|ஹ்|ப்|ஓ|ஒ|ஃ|உ|ய்|எ|ட்|வ்|
	ம்|க்|அ|ஈ|ஏ|ஊ|ழ்|ற்|ல்|ர்|ள்|ஜ்|ந்|ண்|ஆ|க்ஷ்}x;

   ## no critic (RegularExpressions::ProhibitComplexRegexes) this is nothing complex, just list
   
override 'unbreakers' => sub {
    return $UNBREAKERS;
};   
   
override 'split_at_terminal_punctuation' => sub {
    my ( $self, $text ) = @_;
    my ( $openings, $closings ) = ( $self->openings, $self->closings );
    $text =~ s{
        ([.?!])                 # $1 = end-sentence punctuation
        ([$closings]?)          # $2 = optional closing quote/bracket
        \s                      #      space
        ([$openings]?\w) # $3 = any word preceded by an optional opening. Tamil does not have upper characters.
    }{$1$2\n$3}gsxm;
    return $text;
};

1;

__END__

=encoding utf-8

=head1 NAME

Treex::Tool::Segment::TA::RuleBased - rule based sentence segmenter for Tamil

=head1 DESCRIPTION

Sentence boundaries are detected based on a regex rules
that detect end-sentence punctuation ([.?!]).
This class adds a Tamil specific list of "unbreakers",
i.e. tokens that usually do not end a sentence
even if they are followed by a period. Tamil script does not have lower
case and upper case distinction, thus it may not be possible to use the 
heuristic "new sentence starts the sentence with upper case letter".

See L<Treex::Block::W2A::Segment>

=head1 AUTHOR

Martin Popel <popel@ufal.mff.cuni.cz>, Loganathan Ramasamy <ramasamy@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2011 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

