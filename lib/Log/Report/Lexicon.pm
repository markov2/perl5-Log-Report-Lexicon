use warnings;
use strict;

package Log::Report::Lexicon;

use Log::Report 'log-report-lexicon';

=chapter NAME
Log::Report::Lexicon - translations

=chapter SYNOPSIS

=chapter DESCRIPTION
This module is the main extry point for the distribution, but has
currently no further use.  This distribution contains all components
of M<Log::Report> which handle translations.

If you do not need translations, you do not need to install this module.
When you use M<Log::Report> and need to add translations, it may be
very little work: when you nicely wrote texts in the advised message
format like

   print __x"Greetings to you, {name}", name => $name;
   fault __x"cannot open file {filename}", filename => $fn;

then all is in perfect condition to introduce translations: it requires
very little to no additions to the existing code!

In this distribution:

=over 4

=item * M<Log::Report::Extract>
Logic used by the F<xgettext-perl> binary (also included here) to
extract msgid's from perl scripts and (website) templates.

=item * M<Log::Report::Lexicon::Table>
Translation table administration, in PO or MO format.

=item * M<Log::Report::Lexicon::Index>
Translation table file file administration, understanding locales,
domains, and attributes in the filenames.

=item * M<Log::Report::Translator>
The run-time component of translations.
=back

=chapter METHODS

=section Constructors

=c_method new %options
=cut

sub new(@)
{   my $class = shift;
    (bless {}, $class)->init( {@_} );
}

sub init($)
{   my ($self, $args) = @_;
    $self;
}

#--------------
=section Accessors

=cut

#--------------

1;
