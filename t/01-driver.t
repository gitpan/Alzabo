use strict;

use Test::More;

use Alzabo::Driver;

use Cwd;
use File::Spec;

use lib '.', File::Spec->catdir( File::Spec->curdir, 't' );

require 'base.pl';

unless ( @$Alzabo::Build::Tests )
{
    plan skip_all => 'no test config provided';
    exit;
}

my @db;
my $test_count = 1;

my $tests = $Alzabo::Build::Tests;

plan tests => $test_count * @$tests;

my %rdbms = ( mysql => 'MySQL',
              pg    => 'PostgreSQL' );

foreach my $test (@$tests)
{
    my $driver = Alzabo::Driver->new( rdbms => $rdbms{ $test->{rdbms} } );

    my @p = ( 'user', 'password', 'host', 'port' );

    my %connect = map { $_ => $test->{$_} } grep { exists $rdbms{$_} } @p;
    eval_ok( sub { $driver->schemas(%connect) },
             "Schema method for $rdbms{ $test->{rdbms} }" );
}
