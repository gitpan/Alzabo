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
print "1..$test_count\n";

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

    my $s2 = eval { Alzabo::Create::Schema->reverse_engineer(%p); };
    ok( ! $@,
	"Error reverse engineering schema: $@" );

    my @diff = $s1->rules->schema_sql_diff( old => $s1,
					    new => $s2 );

    my $sql = join "\n", @diff;
    ok ( ! $sql,
	 "Reverse engineered schema's SQL differed from original's SQL:\n$sql\n" );

    $s1->delete;
}
