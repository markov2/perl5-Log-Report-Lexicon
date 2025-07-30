#!/usr/bin/env perl
# A cut down version of 40ppi.t that just checks that we can specify a version number
# and a text domain.

use warnings;
use strict;

use File::Temp   qw/tempdir/;
use Test::More;

BEGIN
{   eval "require PPI";
    plan skip_all => 'PPI not installed'
        if $@;

    use_ok('Log::Report::Extract::PerlPPI');
}

my $lexicon    = tempdir CLEANUP => 1;

my $ppi = Log::Report::Extract::PerlPPI->new(lexicon => $lexicon);
$ppi->process( __FILE__ );   # yes, this file!
$ppi->write;

my @potfns = $ppi->index->list('not-a-version-number');
cmp_ok(scalar @potfns, '==', 1, "one file created");
my $potfn = shift @potfns;
ok(defined $potfn);
ok(-s $potfn, "produced file $potfn has size");

done_testing();

use Log::Report 1.00 'not-a-version-number';
