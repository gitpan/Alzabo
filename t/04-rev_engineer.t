# This is just to test whether this stuff compiles.

use strict;

use Alzabo::Create;
use Cwd;

use lib '.', './t';

require 'base.pl';

unless (defined $ENV{ALZABO_RDBMS_TESTS})
{
    print "1..0\n";
    exit;
}

require 'make_schemas.pl';

my $tests = eval $ENV{ALZABO_RDBMS_TESTS};

my $TESTS_PER_RUN = 2;
my $test_count = $TESTS_PER_RUN * @$tests;

eval "use Test::More ( tests => $test_count )";
die $@ if $@;

foreach my $test (@$tests)
{
    print "Running $test->{rdbms} reverse engineering tests\n";
    my $s1;
    {
	no strict 'refs';
	$s1 = &{ "$test->{rdbms}_make_schema" }(%$test);
    }

    my %p = ( name => $s1->name,
	      rdbms => $s1->driver->driver_id,
	      user => $test->{user},
	      password => $test->{password},
	      host => $test->{host},
	    );

    my $s2;
    eval_ok( sub { $s2 = Alzabo::Create::Schema->reverse_engineer(%p) },,
	     "Reverse engineer the @{[$s1->name]} schema with @{[$s1->driver->driver_id]}" );

    my @diff = $s1->rules->schema_sql_diff( old => $s1,
					    new => $s2 );

    my $sql = join "\n", @diff;
    ok ( ! $sql,
	 "Reverse engineered schema's SQL should be the same as the original's" );

    $s1->delete;
}
