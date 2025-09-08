#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Log::Report::Translator::Context;

use warnings;
use strict;

use Log::Report 'log-report-lexicon';

#--------------------
=chapter NAME
Log::Report::Translator::Context - handle translation contexts

=chapter SYNOPSIS

  # usually, the context information is in a separate file
  textdomain 'my-domain',
    config => $filename;

=chapter DESCRIPTION

[Added in Log::Report v1.00]
The "contexts" concept in (GNU's version of) gettext, has a
very restricted purpose: to separate two (accidental) uses of the
same message-id, under different circumstances.  The same msgid may
translated diffently in one file or the other.

For instance, two libraries used in the same application, or two
componentent within a single library both want to used the same
default text (which usually is very short)

  char * t1 = pgettext('interface', 'None');
  char * t2 = pgettext('selections', 'None');

Some translation setups use the library name consequently as msgctxt.
But, the name "context" is pretending much more power than the gettext
libraries are capable of: it usually only behaves like a namespace.

For Log::Report, the power of "context" is extended with selecting
between alternatives for the use of a msgid B<on the same spot>.

For instance, the gender of the user of the website determines whether
`he' or `she' needs to be used in the translation.  In this example,
the gender is set as context keyword in the message:

  my ($name, $sex) = ('Jack', 'male');
  print __x"{name<gender} found his key", name => $name,
    _context => "gender=$sex";

=chapter METHODS

=section Constructors

=c_method new %options

=option  rules HASH
=default rules {}
=cut

sub new(@)  { my $class = shift; (bless {}, $class)->init({@_}) }
sub init($)
{	my ($self, $args) = @_;
	$self->{LRTC_rules} = $self->_context_table($args->{rules} || {});
	$self;
}

#--------------------
=section Attributes

=method rules
Returns a HASH to the simplified context maps.
=cut

sub rules() { $_[0]->{LRTC_rules} }

#--------------------
=section Action

=method ctxtFor $message, $lang, [$context]
Returns a pair of the MSGID stripped from context markup, and the
context evaluated into the msgctxt string.  The $message is a
Log::Report::Message object.  The $context is the default context
for a certain textdomain.

  my ($msgid, $msgctxt) = $context->ctxtFor($msg, $lang, $context);

=cut

=error no context definition for `$tag' in `$msgid'
=warning no value for tag `$tag' in the context
=warning unknown alternative `$alt' for tag `$tag' in context of `$msgid'
=cut

sub _strip_ctxt_spec($)
{	my $msgid = shift;
	my @tags;
	while($msgid =~ s/\{ ([^<}]*) \<(\w+) ([^}]*) \}/ length "$1$3" ? "{$1$3}" : ''/xe)
	{	push @tags, $2;
	}
	($msgid, [sort @tags]);
}

sub ctxtFor($$;$)
{	my ($self, $msg, $lang, $def_context) = @_;
	my $rawid = $msg->msgid;
	my ($msgid, $tags) = _strip_ctxt_spec $rawid;
	@$tags or return ($msgid, undef);

	my $maps = $self->rules;
	$lang    =~ s/_.*//;

	my $msg_context = $self->needDecode($rawid, $msg->context || {});
	$def_context  ||= {};
#use Data::Dumper;
#warn "context = ", Dumper $msg, $msg_context, $def_context;

	my @c;
	foreach my $tag (@$tags)
	{	my $map = $maps->{$tag}
			or error __x"no context definition for `{tag}' in `{msgid}'", tag => $tag, msgid => $rawid;

		my $set = $map->{$lang} || $map->{default};
		next if $set eq 'IGNORE';

		my $v   = $msg_context->{$tag} || $def_context->{$tag};
		unless($v)
		{	warning __x"no value for tag `{tag}' in the context", tag => $tag;
			($v) = keys %$set;
		}
		unless($set->{$v})
		{	warning __x"unknown alternative `{alt}' for tag `{tag}' in context of `{msgid}'", alt => $v, tag => $tag, msgid => $rawid;
			($v) = keys %$set;
		}

		push @c, "$tag=$set->{$v}";
	}

	my $msgctxt = join ' ', sort @c;
	($msgid, $msgctxt);
}

=ci_method needDecode $source, STRING|ARRAY|HASH|PAIRS
Converts the context settings passed with the MSGID, into a HASH which will
be matched to the context providers.
=cut

=error tags value must have form `a=b', found `$this' in `$source'
=cut

sub needDecode($@)
{	my ($thing,  $source) = (shift, shift);
	return +{@_} if @_ > 1;
	my $c = shift;
	return $c if !defined $c || ref $c eq 'HASH';

	my %c;
	foreach (ref $c eq 'ARRAY' ? @$c : (split /[\s,]+/, $c))
	{	my ($kw, $val) = split /\=/, $_, 2;
		defined $val
			or error __x"tags value must have form `a=b', found `{this}' in `{source}'", this => $_, source => $source;
		$c{$kw} = $val;
	}
	\%c;
}

=method expand $msgid, $language, %options
Expand the context settings into all possible combinations which need
translations in the PO file.  This may depend on the $language.
The $msgid is used in error messages.

=error unknown context tag '$tag' used in '$msgid'
=cut

sub expand($$@)
{	my ($self, $raw, $lang) = @_;
	my ($msgid, $tags) = _strip_ctxt_spec $raw;

	$lang =~ s/_.*//;

	my $maps    = $self->rules;
	my @options = [];

	foreach my $tag (@$tags)
	{	my $map = $maps->{$tag}
			or error __x"unknown context tag '{tag}' used in '{msgid}'", tag => $tag, msgid => $msgid;
		my $set = $map->{$lang} || $map->{default};

		my %uniq   = map +("$tag=$_" => 1), values %$set;
		my @oldopt = @options;
		@options   = ();

		foreach my $alt (keys %uniq)
		{	push @options, map +[ @$_, $alt ], @oldopt;
		}
	}

	($msgid, [sort map join(' ', @$_), @options]);
}

sub _context_table($)
{	my ($self, $rules) = @_;
	my %rules;
	foreach my $tag (keys %$rules)
	{	my $d = $rules->{$tag};
		$d = +{ alternatives => $d } if ref $d eq 'ARRAY';

		my %simple;
		my $default  = $d->{default} || {};           # default map
		if(my $alt   = $d->{alternatives})            # simpelest map
		{	$default = +{ map +($_ => $_), @$alt };
		}

		$simple{default} = $default;
		foreach my $set (keys %$d)
		{	next if $set eq 'default' || $set eq 'alternatives';
			my %set = (%$default, %{$d->{$set}});
			$simple{$_} = \%set for split /\,/, $set;  # table per lang
		}
		$rules{$tag} = \%simple;
	}

	\%rules;
}

#--------------------
=chapter DETAILS

The "contexts" concept in (GNU's version of) gettext, has a
very restricted purpose: to separate two (accidental) uses of the
same message-id, under different circumstances.  The same msgid may
translated diffently in one file or the other.

For instance, two libraries used in the same application, or two
componentent within a single library both want to used the same
default text (which usually is very short)

  char * t1 = pgettext('interface', 'None');
  char * t2 = pgettext('selections', 'None');

Some translation setups use the library name consequently as msgctxt.
But, the name "context" is pretending much more power than the gettext
libraries are capable of: it usually only behaves like a namespace.

=section Contexts in Log::Report

For Log::Report, the power of "context" is extended with selecting
between alternatives for the use of a msgid B<on the same spot>.

For instance, the gender of the user of the website determines whether
`he' or `she' needs to be used in the translation.  In this example,
the gender is set as context keyword in the message:

  my ($name, $sex) = ('Jack', 'male');
  print __x"{name<gender} found his key", name => $name,
    _context => "gender=$sex";

This would also be possible in traditional gettext, although probably
rarely used.  A complication is that the scripts to maintain the po
tables are not too smart; do not understand complex code constructs.
Probably this would beed needed:

  if(sex==MALE)
  {   printf pgettext('male', "%s found his key\n", name);
  }
  else
  {   printf pgettext('female', "%s found her key\n", name);
  }


=section Using context_rules

In Log::Report's extended concept of "contexts", you can select between
multiple translations for the same msgid, when they

=over 4
=item * appear with different purpose (like gnu's concept of contexts)
=item * need alternative translation sets B<on the same spot>
=item * interpolate global parameters in messages
=back

In the standard gettext set-up, some msgid may accidentally collide
between two different uses.  For instance, whether you translate the word
"Open" in the menu for "Files" to mean "open a file", and the word "Open"
in the status display meaning "the file is open".  In some languages,
these translations may differ.  Using a msgctxt keyword will cause the
same msgid to appear twice in the PO-file.

But, there is a much broader need for context sensitive translations,
which is not in the provided by standard gettext: environmental
information or parameters may influence the translation more than simply
solvable by inserted parameters.

For instance, the gender of the user of the website determines whether
`he' or `she' needs to be used.  In this example, the gender is set as
context keyword in the message:

  $name = 'Jack';
  print __x"{name} found her key", name => $name;

You may try to solve this via:

  my ($name, $gender) = ('Jack', 'male');
  print __x"{name} found {personal} key", name => $name,
    personal => ($gender eq 'male' ? 'his' : 'her');    # No!

This does not translate!  For one, you would need to translate C<his> and
C<her> to the language as well.  But in some languages, the differences
between addressed genders have more impact on the whole sentence.

So, Log::Report translations add extra syntax:

  my ($name, $gender) = ('Jack', 'male');
  print __x"{name<gender} found her key", name => $name,
    _context => "gender=$gender";

The C<gender> marking tells the translation table builder (xgettext-perl)
and the translation handler that there is a context active.

Now, the English PO-file has

  # gender alternatives 'male' and 'female'

  msgctxt "gender=male"
  msgid  "{name} found his key"
  msgstr "{name} found his key"

  msgctxt "gender=female"
  msgid   "{name} found his key"
  msgstr  "{name} found her key"

To make this work, both the application and the C<xgettext-perl> script
must share information to understand which genders are available.  See
the section on "Configuration" below.

Another example:

  print __x"greetings{<style}";
  # style alternatives 'formal' and 'informal'

  msgctxt "style=formal"
  msgid   "greetings"
  msgstr  "Dear Sir/Madam,"

  msgctxt "style=informal"
  msgid   "greetings"
  msgstr  "Hey buddy,"

As can be seen, the '<style' marking may be added inside the '{}' of
a filled-in parameter, or may appear on its own.  These markings are
removed from the msgid in the PO file, so that you may freely add them to
the strings used in your program without disturbing existing translations.

=subsection Specifying the context per Message

You need to specify the context at each message which is influenced by
the context.  This can be a comma separated list of words, an ARRAY, or
a HASH:

  _context => 'gender=male'
  _context => 'gender=male,agegroup=adult,married=yes'
  _context => [ 'gender=male', 'agegroup=adult', 'married=yes']
  _context => [ qw/gender=male agegroup=adult married=yes/ ]

  my @context = (qw/gender=male agegroup=adult married=yes/);
  _context => \@context;

Probably the
  my %context = (gender => 'male', agegroup => 'adult', married => 'yes');
  my %context = qw/gender male  agegroup adult  married yes/;
  _context => \%context;

Standard gettext only allows a single keyword (=string)
C<Log::Report> permits you to set-up a context for a whole
text-domain, which means that multiple context rules may be active at
any moment.

=subsection Global parameters

You can use contexts to set global interpolation parameters.  For instance,
running a pure perl webserver, you may serve multiple domains.  Some of
the log messages may need to show that domain name.  Of course, you can
collect (or pass on) the hostname when throwing the error... something
like this:

  # can I access $vhost easily?
  error __x"For {host}, login failed for {user}",
        host => $vhost->name, user => $user;

Via contexts:

  # when you know the vhost: (max once per request)
  textdomain->setContext(host => $vhost->name);  # or updateContext

  # until you reconfigure the context
  error __x"For {_context.host}, login failed for {user}", user => $user;

The context values are always available for interpolation.

=subsection Specifying the context per Domain

Above examples are to be specified per message.  You may also
set a default.  The top of your modules set the text-domain (name
of the translation table) for all strings found in those files.
In this case, for instance "webpages"

  # Log::Report::textdomain()
  (textdomain 'webpages')->setContext(%context);

This context is used as defaults, the C<_context> attribute used by
strings are overruling these.

=subsection The msgctxt

The gnutext implementation of the context is very simple.  This is to
be expected from a library written in C.  The msgctxt alternatives
are matched against the context keywords of the message.  In all or
none of the alternatives match, then just a random translation is
chosen.

In the simplest form, the msgctxt field contains a single keyword
(not containing a comma).

  msgctxt "gender=male"

But you can do more.  B<Be warned> that most (all?) existing tools
which smartly edit PO-files do not understand these constructs: they
see the msgctxt as dump string without meaning.

  msgctxt "agegroup=baby,agegroup=grandparent" # baby OR grandparent
  msgctxt "gender=male agegroup=adult"         # both male AND adult

So, a comma separated list of alternatives.  If any matches, then the
rule is selected.

=subsection Configuration

The tools which handle translations expect the msgctxt to be static.
For instance, contain a filename where the string is used to disambigue
accidental collissions of the use of the same msgid for different
purposes.

Now, we have designed far more flexible contexts.  We need to generate all
possible msgctxt values while extracting msgids to update the PO-files.
Therefore, we need a map-file.

The context maps are included in a configuration file which is passed to
xgettext-perl and to the program which uses contexts.
See M<Log::Report::Domain::readConfig()>.

Example of such configuration file: (JSON syntax and Perl syntax)

  === JSON ===                    ==== Perl ==   =
 {{
     "context_rules" : {             context_rules => {
        "gender" : [                    gender => [
           "male",                         'male',
           "female"                        'female'
        ]                               ]
     }                               }
  }                               }

or

  {                               {
     "context_rules" : {             context_rules => {
        "gender" : {                    gender => {
           "alternatives" : [              alternatives => [
              "male",                         'male',
              "female",                       'female',
              "unknown"                       'unknown'
           ]                               ]
           ... more config for 'gender'    ...
        }                                }
     }                               }
  }                               }

As "alternatives", we list the alternatives as known by the application
internals.  Each msgid which contains a C<< {<gender} >> mark will be
replicated three times, in each language table.  Each copy will be marked
with a different value from "alternatives".

However, languages differ.  For instance, in some language we may address
the C<unknown> gender as being a male person.  In other languages, the
translation can express this "unknown" personality.  To get this to work,
you can use the C<msgctxt> construct.

The default C<msgctxt>, as used in the previous example, is simply mapping
the alternatives directly on msgctxt values which are the same:

  {                                { context_rules =>
   "context_rules" : {                { gender =>
      "gender" : {                      { default => { qw/
         "default" : {                      female  female
            "female" : "female",            male    male
            "male" : "male"                 unknown male / }
            "unknown" : "male",         , 'nl,de' => { qw/
         },                                 unknown x    / }
         "nl,de" : {
            "unknown" : "x"
         }                              }
       ... more configuration ...
       }
    ... more context rules ...
    }                                 }
  }                                }

By default, there will only be two msgid copies in a language file,
because at run-time the "unknown" is mapped on "male".  An exception
for the Dutch (nl*) and German (de*) tables, which apparently support
the third gender.

If you are not interested for a certain tag, then put it on 'IGNORE'
as default or for your language.

  "default" : "IGNORE",           default => 'IGNORE'
  "nl": "IGNORE"                  nl => 'IGNORE'
=cut

1;
