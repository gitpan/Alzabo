use strict;

use Alzabo::Create;
use Alzabo::Config;

use Data::Dumper;

use lib '.', './t';

require 'base.pl';

unless (defined $ENV{ALZABO_RDBMS_TESTS})
{
    print "1..0\n";
    exit;
}

require 'make_schemas.pl';

$Data::Dumper::Indent = 0;

my $tests = eval $ENV{ALZABO_RDBMS_TESTS};

my $TESTS_PER_RUN = 64;
my $SYNC_TESTS_PER_RUN = 15;
my $test_count = ($TESTS_PER_RUN * (@$tests + 3)) + ($SYNC_TESTS_PER_RUN * 2);

print "1..$test_count\n";

# re-order the tests to prevent test failures with multi-process tests
# & Pg.
my @t;
foreach my $db ( qw( mysql pg oracle sybase ) )
{
    push @t, grep { $_->{rdbms} eq $db } @$tests;
}

my $test = shift @t;
my $last_test_num;
foreach my $c ( [ { store => 'Alzabo::ObjectCache::MemoryStore',
		    sync  => 'Alzabo::ObjectCache::DBMSync',
		    dbm_file => 't/dbmsynctest.dbm',
		    clear_on_startup => 1,
		  },
		  1
		],
		[ { store => 'Alzabo::ObjectCache::MemoryStore',
		    sync  => 'Alzabo::ObjectCache::IPCSync' },
		  1
		],
		[
		 { store => 'Alzabo::ObjectCache::MemoryStore',
		   sync  => 'Alzabo::ObjectCache::NullSync' },
		 0,
		],
		[
		 # no caching at all
		 { store => 0,
		   sync  => 0 },
		 0,
		],
	      )
{
    my $s;
    {
	no strict 'refs';
	&{ "$test->{rdbms}_make_schema" }(%$test);
    }

    my $store_mod = $c->[0]->{store} || 'Nothing';
    my $sync_mod  = $c->[0]->{sync} || 'Nothing';
    print "Running $test->{rdbms} runtime tests with\n\tstore => $store_mod,\n\tsync  => $sync_mod\n";

    my $t = Data::Dumper->Dump( [$test], [''] );
    $t =~ s/\$ = //;
    $t =~ s/'/"/g;
    $ENV{CURRENT_TEST} = $t;

    delete $ENV{OBJECTCACHE_PARAMS};
    if ($c->[0]->{store})
    {
	my $c_params = Data::Dumper->Dump( [ $c->[0] ], [''] );

	$c_params =~ s/\$ = //;
	$c_params =~ s/'/"/g;
	$ENV{OBJECTCACHE_PARAMS} = $c_params;
    }

    $ENV{SYNC_TESTS} = $c->[1] ? 1 : 0;
    $ENV{TEST_START_NUM} = $last_test_num ? $last_test_num : 0;

    $last_test_num += $TESTS_PER_RUN;
    $last_test_num += $SYNC_TESTS_PER_RUN if $c->[1];

    system( "$^X t/runtime_tests.pl" )
	and die "Can't run '$^X runtime_tests.pl: $!";

    my $cs = Alzabo::Create::Schema->load_from_file( name => $test->{db_name} );
    $cs->delete;
    eval { $cs->drop(%$test); };
    warn $@ if $@;
    $cs->driver->disconnect;
}

if (@t)
{
    my $c_params = Data::Dumper->Dump( [ { store => 'Alzabo::ObjectCache::MemoryStore',
					   sync  => 'Alzabo::ObjectCache::NullSync' } ],
				       [''] );
    $c_params =~ s/\$ = //;
    $c_params =~ s/'/"/g;
    $ENV{OBJECTCACHE_PARAMS} = $c_params;
    $ENV{SYNC_TESTS} = 0;

    foreach my $test (@t)
    {
	{
	    no strict 'refs';
	    &{ "$test->{rdbms}_make_schema" }(%$test);
	}

	print "Running $test->{rdbms} runtime tests with\n\tstore => Alzabo::ObjectCache::MemoryStore,\n\tsync  => Alzabo::ObjectCache::NullSync\n";

	my $t = Data::Dumper->Dump( [$test], [''] );
	$t =~ s/\$ = //;
	$t =~ s/'/"/g;
	$ENV{CURRENT_TEST} = $t;
	$ENV{TEST_START_NUM} = $last_test_num;
	$last_test_num += $TESTS_PER_RUN;

	system( "$^X t/runtime_tests.pl" )
	    and die "Can't run '$^X runtime_tests.pl: $!";

	my $cs = Alzabo::Create::Schema->load_from_file( name => $test->{db_name} );
	$cs->delete;
	eval { $cs->drop(%$test); };
    }
}
