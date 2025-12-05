#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Log::Report::Translator::POT;
use base 'Log::Report::Translator';

use warnings;
use strict;

use Log::Report 'log-report-lexicon', import => [ qw/__x error info panic/ ];

use Log::Report::Lexicon::Index;
use Log::Report::Lexicon::POTcompact;

use POSIX        qw/:locale_h/;
use Scalar::Util qw/blessed/;
use File::Spec   ();

my %lexicons;
sub _fn_to_lexdir($);

# Work-around for missing LC_MESSAGES on old Perls and Windows
{	no warnings;
	eval "&LC_MESSAGES";
	*LC_MESSAGES = sub(){5} if $@;
}

#--------------------
=chapter NAME
Log::Report::Translator::POT - translation based on POT files

=chapter SYNOPSIS
  # internal use
  my $msg = Log::Report::Message->new(
    _msgid  => "Hello World\n",
    _domain => 'my-domain',
  );

  print Log::Report::Translator::POT
     ->new(lexicons => $dir)
     ->translate($msg, 'nl-BE');

  # normal use (end-users view in the program's ::main)
  textdomain 'my-domain',
    translator =>  Log::Report::Translator::POT->new(lexicon => $dir);
  print __"Hello World\n";

=chapter DESCRIPTION

Translate a message by directly accessing POT files.  The files will load
lazily (unless forced).  This module accesses the PO's in a compact way,
using Log::Report::Lexicon::POTcompact, which is much more efficient
than Log::Report::Lexicon::PO.

=chapter METHODS

=section Constructors

=c_method new %options

=option  lexicons $directory
=default lexicons <see text>
The $directory where the translations can be found.  See
Log::Report::Lexicon::Index for the expected structure of such
directory.

The default is based on the location of the module which instantiates
this translator.  The filename of the module is stripped from its C<.pm>
extension, and used as directory name.  Within that directory, there
must be a directory named C<messages>, which will be the root directory
of a Log::Report::Lexicon::Index.

=option  charset STRING
=default charset <undef>
Enforce character set for files.  We default to reading the character-set
as defined in the header of each PO file.

=example default lexicon directory
  # file xxx/perl5.8.8/My/Module.pm
  use Log::Report 'my-domain',
    translator => Log::Report::Translator::POT->new;

  # lexicon now in xxx/perl5.8.8/My/Module/messages/

=cut

sub new(@)
{	my $class = shift;
	# Caller cannot wait until init()
	$class->SUPER::new(callerfn => (caller)[1], @_);
}

sub init($)
{	my ($self, $args) = @_;
	$self->SUPER::init($args);

	my $lex = delete $args->{lexicons} || delete $args->{lexicon} ||
		(ref $self eq __PACKAGE__ ? [] : _fn_to_lexdir $args->{callerfn});

	my @lex;
	foreach my $dir (ref $lex eq 'ARRAY' ? @$lex : $lex)
	{	# lexicon indexes are shared
		my $l = $lexicons{$dir} ||= Log::Report::Lexicon::Index->new($dir);
		$l->index;   # index the files now
		push @lex, $l;
	}
	$self->{LRTP_lexicons} = \@lex;
	$self->{LRTP_charset}  = $args->{charset};
	$self;
}

sub _fn_to_lexdir($)
{	my $fn = shift;
	$fn =~ s/\.pm$//;
	File::Spec->catdir($fn, 'messages');
}

#--------------------
=section Accessors

=method lexicons
Returns a list of Log::Report::Lexicon::Index objects, where the
translation files may be located.
=cut

sub lexicons() { @{ $_[0]->{LRTP_lexicons}} }

=method charset
Returns the default charset, which can be overrule by the locale.
=cut

sub charset() { $_[0]->{LRTP_charset} }

#--------------------
=section Translating

=method translate $msg, $lang, $context
=error unknown translation table extension '$ext' in $file.
=info read table $file as $class for $dname in $locale.
=cut

sub translate($;$$)
{	my ($self, $msg, $lang, $ctxt) = @_;
	#!!! do not debug with $msg in a print: recursion

	my $domain = $msg->{_domain};
	my $dname  = blessed $domain ? $domain->name : $domain;

	my $locale = $lang || setlocale(LC_MESSAGES)
		or return $self->SUPER::translate($msg, $lang, $ctxt);

	my $pot
	  = exists $self->{LRTP_pots}{$dname}{$locale}
	  ? $self->{LRTP_pots}{$dname}{$locale}
	  : $self->load($dname, $locale);

	   ($pot ? $pot->msgstr($msg->{_msgid}, $msg->{_count}, $ctxt) : undef)
	|| $self->SUPER::translate($msg, $lang, $ctxt);
}

sub load($$)
{	my ($self, $dname, $locale) = @_;

	foreach my $lex ($self->lexicons)
	{	my $fn = $lex->find($dname, $locale);

		!$fn && $lex->list($dname)
			and last; # there are tables for dname, but not our lang

		$fn or next;

		my ($ext) = lc($fn) =~ m/\.(\w+)$/;
		my $class
		  = $ext eq 'mo' ? 'Log::Report::Lexicon::MOTcompact'
		  : $ext eq 'po' ? 'Log::Report::Lexicon::POTcompact'
		  :     error __x"unknown translation table extension '{ext}' in {file}.", ext => $ext, file => $fn;

		info __x"read table {file} as {class} for {dname} in {locale}.", file => $fn, class => $class, dname => $dname, locale => $locale
			if $dname ne 'log-report';  # avoid recursion

		eval "require $class" or panic $@;

		return $self->{LRTP_pots}{$dname}{$locale} = $class->read($fn, charset => $self->charset);
	}

	$self->{LRTP_pots}{$dname}{$locale} = undef;
}

1;
