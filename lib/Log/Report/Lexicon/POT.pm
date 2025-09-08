#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!
#oorestyle: old style disclaimer to be removed.
#oorestyle: not found P for method filename($filename)

# This code is part of distribution Log-Report-Lexicon. Meta-POD processed
# with OODoc into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package Log::Report::Lexicon::POT;
use base 'Log::Report::Lexicon::Table';

use warnings;
use strict;

use Log::Report 'log-report-lexicon';
use Log::Report::Lexicon::PO  ();

use POSIX        qw/strftime/;
use List::Util   qw/sum/;
use Scalar::Util qw/blessed/;
use Encode       qw/decode/;

use constant     MSGID_HEADER => '';

#--------------------
=chapter NAME
Log::Report::Lexicon::POT - manage PO files

=chapter SYNOPSIS
  # this is usually not for end-users, See ::Extract::PerlPPI
  # using a PO table

  my $pot = Log::Report::Lexicon::POT->read('po/nl.po', charset => 'utf-8')
     or die;

  my $po = $pot->msgid('msgid');
  my $po = $pot->msgid($msgid, $msgctxt);
  print $pot->nrPlurals;
  print $pot->msgstr('msgid', 3);
  print $pot->msgstr($msgid, 3, $msgctxt);
  $pot->write;  # update the file

  # fill the table, by calling the next a lot
  my $po  = Log::Report::Lexicon::PO->new(...);
  $pot->add($po);

  # creating a PO table
  $pot->write('po/nl.po')
      or die;

=chapter DESCRIPTION
This module is reading, extending, and writing POT files.  POT files
are used to store translations in humanly readable format for most of
existing translation frameworks, like GNU gettext and Perl's Maketext.
If you only wish to access the translation, then you may use the much
more efficient Log::Report::Lexicon::POTcompact.

The code is loosely based on Locale::PO, by Alan Schwartz.  The coding
style is a bit off the rest of C<Log::Report>, and there was a need to
sincere simplification.  Each PO record will be represented by a
Log::Report::Lexicon::PO.

=chapter METHODS

=section Constructors

=c_method new %options
Create a new POT file.  The initial header is generated for you, but
it can be changed using the M<header()> method.

=option  charset STRING
=default charset 'UTF-8'
The charset to be used for the createed file.  It is unwise to use anything
else than 'UTF-8', but allowed.  Before [1.09] this option was required.

=requires textdomain STRING
The package name, used in the directory structure to store the
PO files.

=option  version STRING
=default version undef

=option  nr_plurals INTEGER
=default nr_plurals 2
The number of translations each of the translation with plural form
need to have.

=option  plural_alg EXPRESSION
=default plural_alg C<n!=1>
The algorithm to be used to calculate which translated msgstr to use.

=option  plural_forms RULE
=default plural_forms <constructed from nr_plurals and plural_alg>
[0.992] When this option is used, it overrules P<nr_plurals> and
P<plural_alg>.  The RULE should be a full "Plural-Forms" field.

=option  index HASH
=default index {}
A set of translations (Log::Report::Lexicon::PO objects),
with msgid as key.

=option  date STRING
=default date now
Overrule the date which is included in the generated header.

=option  filename STRING
=default filename undef
Specify an output filename.  The name can also be specified when
M<write()> is called.

=error textdomain parameter is required
=cut

sub init($)
{	my ($self, $args) = @_;

	$self->{LRLP_fn}      = $args->{filename};
	$self->{LRLP_index}   = $args->{index}   || {};
	$self->{LRLP_charset} = $args->{charset} || 'UTF-8';

	my $version    = $args->{version};
	my $domain     = $args->{textdomain}
		or error __"textdomain parameter is required";

	my $forms      = $args->{plural_forms};
	unless($forms)
	{	my $nrplurals = $args->{nr_plurals} || 2;
		my $algo      = $args->{plural_alg} || 'n!=1';
		$forms        = "nplurals=$nrplurals; plural=($algo);";
	}

	$self->_createHeader(
		project => $domain . (defined $version ? " $version" : ''),
		forms   => $forms,
		charset => $args->{charset},
		date    => $args->{date}
	);

	$self->setupPluralAlgorithm;
	$self;
}

=c_method read $filename, %options
Read the POT information from $filename.

=requires charset STRING
The character-set which is used for the file.  You must specify
this explicitly.

=fault cannot read in $cs from file $fn: $!
=fault cannot read from file $fn (unknown charset): $!
=error cannot detect charset in $fn
=error unsupported charset $charset in $fn
=fault failed reading from file $fn: $!
=cut

sub read($@)
{	my ($class, $fn, %args) = @_;
	my $self    = bless {LRLP_index => {}}, $class;

	my $charset = $args{charset};
	$charset    = $1
		if !$charset && $fn =~ m!\.([\w-]+)(?:\@[^/\\]+)?\.po$!i;

	my $fh;
	if(defined $charset)
	{	open $fh, "<:encoding($charset):crlf", $fn
			or fault __x"cannot read in {cs} from file {fn}", cs => $charset, fn => $fn;
	}
	else
	{	open $fh, '<:raw:crlf', $fn
			or fault __x"cannot read from file {fn} (unknown charset)", fn=>$fn;
	}

	local $/   = "\n\n";
	my $linenr = 1;  # $/ frustrates $fh->input_line_number
	while(1)
	{	my $location = "$fn line $linenr";
		my $block    = <$fh>;
		defined $block or last;

		$linenr += $block =~ tr/\n//;

		$block   =~ s/\s+\z//s;
		length $block or last;

		unless($charset)
		{	$charset = $block =~ m/\"content-type:.*?charset=["']?([\w-]+)/mi ? $1
			  : error __x"cannot detect charset in {fn}", fn => $fn;

			trace "auto-detected charset $charset for $fn";
			binmode $fh, ":encoding($charset):crlf";

			$block = decode $charset, $block
				or error __x"unsupported charset {charset} in {fn}", charset => $charset, fn => $fn;
		}

		my $po = Log::Report::Lexicon::PO->fromText($block, $location);
		$self->add($po) if $po;
	}

	close $fh
		or fault __x"failed reading from file {fn}", fn => $fn;

	$self->{LRLP_fn}      = $fn;
	$self->{LRLP_charset} = $charset;

	$self->setupPluralAlgorithm;
	$self;
}

=method write [$filename|$fh], %options
When you pass an open $fh, you are yourself responsible that
the correct character-encoding (binmode) is set.  When the write
followed a M<read()> or the filename was explicitly set with M<filename()>,
then you may omit the first parameter.

=option  only_active BOOLEAN
=default only_active false
[1.02] Do not write records which do have a translation, but where the
msgid has disappeared from the sources.  By default, these records are
commented out (marked with '#~') but left in the file.

=error no filename or file-handle specified for PO
When a PO file is written, then a filename or file-handle must be
specified explicitly, or set beforehand using the M<filename()>
method, or known because the write follows a M<read()> of the file.
=cut

=error no filename or file-handle specified for PO
=fault cannot write to file $fn with $layers: $!
=cut

sub write($@)
{	my $self = shift;
	my $file = @_%2 ? shift : $self->filename;
	my %args = @_;

	defined $file
		or error __"no filename or file-handle specified for PO";

	my $need_refs = $args{only_active};
	my @opt       = (nr_plurals => $self->nrPlurals);

	my $fh;
	if(ref $file) { $fh = $file }
	else
	{	my $layers = '>:encoding('.$self->charset.')';
		open $fh, $layers, $file
			or fault __x"cannot write to file {fn} with {layers}", fn => $file, layers => $layers;
	}

	$fh->print($self->msgid(MSGID_HEADER)->toString(@opt));
	my $index = $self->index;
	foreach my $msgid (sort keys %$index)
	{	next if $msgid eq MSGID_HEADER;

		my $rec  = $index->{$msgid};
		my @recs = blessed $rec ? $rec   # one record with $msgid
		  : @{$rec}{sort keys %$rec};    # multiple records, msgctxt

		foreach my $po (@recs)
		{	next if $po->useless;
			next if $need_refs && !$po->references;
			$fh->print("\n", $po->toString(@opt));
		}
	}

	$fh->close
		or failure __x"write errors for file {fn}", fn => $file;

	$self;
}

#--------------------
=section Attributes

=method charset
The character-set to be used for reading and writing.  You do not need
to be aware of Perl's internal encoding for the characters.

=method index
Returns a HASH of all defined PO objects, organized by msgid.  Please try
to avoid using this: use M<msgid()> for lookup and M<add()> for adding
translations.

=method filename
Returns the $filename, as derived from M<read()> or specified during
initiation with M<new(filename)>.
=cut

sub charset()  { $_[0]->{LRLP_charset} }
sub index()    { $_[0]->{LRLP_index} }
sub filename() { $_[0]->{LRLP_fn} }

=method language
Returns the language code, which is derived from the filename.
=cut

sub language() { $_[0]->filename =~ m![/\\](\w+)[^/\\]*$! ? $1 : undef }

#--------------------
=section Managing PO's

=method msgid STRING, [$msgctxt]
Lookup the Log::Report::Lexicon::PO with the STRING.  If you
want to add a new translation, use M<add()>.  Returns undef
when not defined.
=cut

sub msgid($;$)
{	my ($self, $msgid, $msgctxt) = @_;
	my $msgs = $self->index->{$msgid} or return;

	return $msgs
		if blessed $msgs
		&& (!$msgctxt || $msgctxt eq $msgs->msgctxt);

	$msgs->{$msgctxt};
}

=method msgstr $msgid, [$count, [$msgctxt]]
Returns the translated string for $msgid.  When $count is not specified or
undef, the translation string related to "1" is returned.
=cut

sub msgstr($;$$)
{	my ($self, $msgid, $count, $msgctxt) = @_;
	my $po   = $self->msgid($msgid, $msgctxt)
		or return undef;

	$count //= 1;
	$po->msgstr($self->pluralIndex($count));
}

=method add $po
Add the information from a $po into this POT.  If the msgid of the $po
is already known, that is an error.

=error translation already exists for '$msgid' with '$ctxt
=cut

sub add($)
{	my ($self, $po) = @_;
	my $msgid = $po->msgid;
	my $index = $self->index;

	my $h = $index->{$msgid};
	$h or return $index->{$msgid} = $po;

	$h = $index->{$msgid} = +{ ($h->msgctxt // '') => $h }
		if blessed $h;

	my $ctxt = $po->msgctxt // '';
	error __x"translation already exists for '{msgid}' with '{ctxt}", msgid => $msgid, ctxt => $ctxt
		if $h->{$ctxt};

	$h->{$ctxt} = $po;
}

=method translations [$active]
Returns a list with all defined Log::Report::Lexicon::PO objects. When
the string $active is given as parameter, only objects which have
references are returned.

=error the only acceptable parameter is 'ACTIVE', not '$p'
=cut

sub translations(;$)
{	my $self = shift;
	@_ or return map +(blessed $_ ? $_ : values %$_), values %{$self->index};

	error __x"the only acceptable parameter is 'ACTIVE', not '{p}'", p => $_[0]
		if $_[0] ne 'ACTIVE';

	grep $_->isActive, $self->translations;
}

=method header [$field, [$content]]
The translation of a blank MSGID is used to store a MIME header, which
contains some meta-data.  When only a $field is specified, that content is
looked-up (case-insensitive) and returned.  When a $content is specified,
the knowledge will be stored.  In latter case, the header structure
may get created.  When the $content is set to undef, the field will
be removed.

=error no header defined in POT for file $fn
=cut

sub _now() { strftime "%Y-%m-%d %H:%M%z", localtime }

sub header($;$)
{	my ($self, $field) = (shift, shift);
	my $header = $self->msgid(MSGID_HEADER)
		or error __x"no header defined in POT for file {fn}", fn => $self->filename;

	if(!@_)
	{	my $text = $header->msgstr(0) || '';
		return $text =~ m/^\Q$field\E\:\s*([^\n]*?)\;?\s*$/im ? $1 : undef;
	}

	my $content = shift;
	my $text    = $header->msgstr(0);

	for($text)
	{	if(defined $content)
		{	s/^\Q$field\E\:([^\n]*)/$field: $content/im  # change
			|| s/\z/$field: $content\n/;   # new
		}
		else
		{	s/^\Q$field\E\:[^\n]*\n?//im;  # remove
		}
	}

	$header->msgstr(0, $text);
	$content;
}

=method updated [$date]
Replace the "PO-Revision-Date" with the specified $date, or the current
moment.
=cut

sub updated(;$)
{	my $self = shift;
	my $date = shift || _now;
	$self->header('PO-Revision-Date', $date);
	$date;
}

### internal
sub _createHeader(%)
{	my ($self, %args) = @_;
	my $date   = $args{date} || _now;

	my $header = Log::Report::Lexicon::PO->new(msgid => MSGID_HEADER, msgstr => <<__CONFIG);
Project-Id-Version: $args{project}
Report-Msgid-Bugs-To:
POT-Creation-Date: $date
PO-Revision-Date: $date
Last-Translator:
Language-Team:
MIME-Version: 1.0
Content-Type: text/plain; charset=$args{charset}
Content-Transfer-Encoding: 8bit
Plural-Forms: $args{forms}
__CONFIG

	my $version = $Log::Report::VERSION || '0.0';
	$header->addAutomatic("Header generated with ".__PACKAGE__." $version\n");

	$self->index->{&MSGID_HEADER} = $header
		if $header;

	$header;
}

=method removeReferencesTo $filename
Remove all the references to the indicate $filename from all defined
translations.  Returns the number of refs left.
=cut

sub removeReferencesTo($)
{	my ($self, $filename) = @_;
	sum map $_->removeReferencesTo($filename), $self->translations;
}

=method keepReferencesTo $table
Remove all references which are not found as key in the hash $table.
Returns the number of references left.
=cut

sub keepReferencesTo($)
{	my ($self, $keep) = @_;
	sum map $_->keepReferencesTo($keep), $self->translations;
}

=method stats
Returns a HASH with some statistics about this POT table.
=cut

sub stats()
{	my $self  = shift;
	my %stats = (msgids => 0, fuzzy => 0, inactive => 0);
	foreach my $po ($self->translations)
	{	next if $po->msgid eq MSGID_HEADER;
		$stats{msgids}++;
		$stats{fuzzy}++    if $po->fuzzy;
		$stats{inactive}++ if !$po->isActive && !$po->useless;
	}
	\%stats;
}

1;
