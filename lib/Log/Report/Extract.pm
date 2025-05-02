# This code is part of distribution Log-Report-Lexicon. Meta-POD processed
# with OODoc into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package Log::Report::Extract;

use warnings;
use strict;

use Log::Report 'log-report-lexicon';
use Log::Report::Lexicon::Index ();
use Log::Report::Lexicon::POT   ();

=chapter NAME
Log::Report::Extract - Collect translatable strings

=chapter SYNOPSIS
 # See the extensions

=chapter DESCRIPTION
This module helps maintaining the POT files, updating the list of
message-ids which are kept in them.  After initiation, the M<process()>
method needs to be called with all files which changed since last
processing and the existing PO files will get updated accordingly.  If no
translations exist yet, one C<textdomain/xx.po> file will be created.

=chapter METHODS

=section Constructors

=c_method new %options

=requires lexicon DIRECTORY
The place where the lexicon is kept.  When no lexicon is defined yet,
this will be the directory where an C<domain/xx.po> file will be created.

=option  charset STRING
=default charset 'utf-8'
The character-set used in the PO files.

=cut

sub new(@)
{   my $class = shift;
    (bless {}, $class)->init( {@_} );
}

sub init($)
{   my ($self, $args) = @_;
    my $lexi = $args->{lexicon} || $args->{lexicons}
        or error __"extractions require an explicit lexicon directory";

    -d $lexi or mkdir $lexi
        or fault __x"cannot create lexicon directory {dir}", dir => $lexi;

    $self->{LRE_index}   = Log::Report::Lexicon::Index->new($lexi);
    $self->{LRE_charset} = $args->{LRE_charset} || 'utf-8';
    $self->{LRE_domains} = {};
    $self;
}

#---------------
=section Accessors

=method index
Returns the M<Log::Report::Lexicon::Index> object, which is listing
the files in the lexicon directory tree.

=method charset
Returns the character-set used inside the POT files.

=method domains
Returns a sorted list of all known domain names.
=cut

sub index()   {shift->{LRE_index}}
sub charset() {shift->{LRE_charset}}
sub domains() {sort keys %{shift->{LRE_domains}}}

=method pots $domain
Returns the list of M<Log::Report::Lexicon::POT> objects which contain
the tables for $domain.
=cut

sub pots($)
{   my ($self, $domain) = @_;
    my $r = $self->{LRE_domains}{$domain};
    $r ? @$r : ();
}

=method addPot $domain, $pot, %options
=cut

sub addPot($$%)
{   my ($self, $domain, $pot) = @_;
    push @{$self->{LRE_domains}{$domain}}, ref $pot eq 'ARRAY' ? @$pot : $pot
        if $pot;
}

#---------------
=section Processors

=method process $filename, %options
Update the domains mentioned in the $filename.  All text-domains defined
in the file will get updated automatically, but should not written before
all files are processed.

Returned is the number of messages found in this particular file.
=cut

sub process($@)
{   my ($self, $fn, %opts) = @_;
    panic "not implemented";
}

=method cleanup %options
Remove all references.

=option keep HASH|ARRAY
=default keep []
Keep the information about these filename, either specified as ARRAY of
names, or a HASH where the keys are the named.
=cut

sub cleanup(%)
{   my ($self, %args) = @_;
    my $keep = $args{keep} || {};
    $keep    = +{ map +($_ => 1), @$keep }
        if ref $keep eq 'ARRAY';

    foreach my $domain ($self->domains)
    {   $_->keepReferencesTo($keep) for $self->pots($domain);
    }
}

=method showStats [$domains]
Show a status about the DOMAIN (by default all domains).  At least mode
verbose is required to see this.

The statistics are sent to (Log::Report) dispatchers which accept
notice and info.  This could be syslog.  When you have no explicit
dispatchers in your program, the level of detail get controlled by
the 'mode':

   use Log::Report mode => 'DEBUG';  # or 'VERBOSE'
=cut

sub showStats(;$)
{   my $self    = shift;
    my @domains = @_ ? @_ : $self->domains;

    dispatcher needs => 'INFO'
        or return;

    foreach my $domain (@domains)
    {   my $pots = $self->{LRE_domains}{$domain} or next;
        my ($msgids, $fuzzy, $inactive) = (0, 0, 0);

        foreach my $pot (@$pots)
        {   my $stats = $pot->stats;
            next unless $stats->{fuzzy} || $stats->{inactive};

            $msgids   = $stats->{msgids};
            next if $msgids == $stats->{fuzzy};   # ignore the template

            notice __x
                "{domain}: {fuzzy%3d} fuzzy, {inact%3d} inactive in {filename}"
              , domain => $domain, fuzzy => $stats->{fuzzy}
              , inact => $stats->{inactive}, filename => $pot->filename;

            $fuzzy    += $stats->{fuzzy};
            $inactive += $stats->{inactive};
        }

        if($fuzzy || $inactive)
        {   info __xn
"{domain}: one file with {ids} msgids, {f} fuzzy and {i} inactive translations"
, "{domain}: {_count} files each {ids} msgids, {f} fuzzy and {i} inactive translations in total"
              , scalar(@$pots), domain => $domain
              , f => $fuzzy, ids => $msgids, i => $inactive
        }
        else
        {   info __xn
                "{domain}: one file with {ids} msgids"
              , "{domain}: {_count} files with each {ids} msgids"
              , scalar(@$pots), domain => $domain, ids => $msgids;
        }
    }
}

=method write [$domain]
Update the information of the files related to $domain, by default all
processed DOMAINS.

All information known about the written $domain is removed from the cache.
=cut

sub write(;$)
{   my ($self, $domain) = @_;
    unless(defined $domain)  # write all
    {   $self->write($_) for $self->domains;
        return;
    }

    my $pots = delete $self->{LRE_domains}{$domain}
        or return;  # nothing found

    for my $pot (@$pots)
    {   $pot->updated;
        $pot->write;
    }

    $self;
}

sub DESTROY() {shift->write}

sub _reset($$)
{   my ($self, $domain, $fn) = @_;

    my $pots = $self->{LRE_domains}{$domain}
           ||= $self->_read_pots($domain);

    $_->removeReferencesTo($fn) for @$pots;
}

sub _read_pots($)
{   my ($self, $domain) = @_;

    my $index   = $self->index;
    my $charset = $self->charset;

    my @pots    = map Log::Report::Lexicon::POT->read($_, charset=> $charset),
        $index->list($domain);

    trace __xn "found one pot file for domain {domain}"
             , "found {_count} pot files for domain {domain}"
             , @pots, domain => $domain;

    return \@pots
        if @pots;

    # new text-domain found, start template
    my $fn = $index->addFile("$domain.$charset.po");
    info __x"starting new textdomain {domain}, template in {filename}"
      , domain => $domain, filename => $fn;

    my $pot = Log::Report::Lexicon::POT->new
      ( textdomain => $domain
      , filename   => $fn
      , charset    => $charset
      , version    => 0.01
      );

    [ $pot ];
}

=method store $domain, $filename, $linenr, $context, $msg, [$msg_plural]
Register the existence of a ($msg, $msg_plural) in all POTs of
the $domain.
=cut

sub store($$$$;$)
{   my ($self, $domain, $fn, $linenr, $msgid, $plural) = @_;

    my $textdomain = textdomain $domain;
    my $context    = $textdomain->contextRules;

    foreach my $pot ($self->pots($domain))
    {   my ($stripped, $msgctxts);
        if($context)
        {   my $lang = $pot->language || 'en';
            ($stripped, $msgctxts) = $context->expand($msgid, $lang);

            if($plural && $plural =~ m/\{[^}]*\<\w+/)
            {   error __x"no context tags allowed in plural `{msgid}'"
                  , msgid => $plural;
            }
        }
        else
        {   $stripped = $msgid;
        }

        $msgctxts && @$msgctxts
            or $msgctxts = [undef];

    MSGCTXT:
        foreach my $msgctxt (@$msgctxts)
        {
            if(my $po = $pot->msgid($stripped, $msgctxt))
            {   $po->addReferences( ["$fn:$linenr"]);
                $po->plural($plural) if $plural;
                next MSGCTXT;
            }

            my $format = $stripped =~ m/\{/ ? 'perl-brace' : 'perl';
            my $po = Log::Report::Lexicon::PO->new
              ( msgid        => $stripped
              , msgid_plural => $plural
              , msgctxt      => $msgctxt
              , fuzzy        => 1
              , format       => $format
              , references   => [ "$fn:$linenr" ]
              );

            $pot->add($po);
        }
    }
}

1;
