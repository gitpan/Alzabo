use strict;

BEGIN
{
    unless (defined $ENV{ALZABO_RDBMS_TESTS})
    {
	print "1..0\n";
	exit;
    }
}

use Alzabo::Driver;

use Cwd;
use File::Spec;

use lib '.', './t';

require 'base.pl';

my @db;
my $test_count = 1;

my $tests = eval $ENV{ALZABO_RDBMS_TESTS};

Test::More->import( tests => $test_count * @$tests );

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
