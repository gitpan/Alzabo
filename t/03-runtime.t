use strict;

BEGIN
{
    unless (defined $ENV{ALZABO_RDBMS_TESTS})
    {
	print "1..0\n";
	exit;
    }
}

use Alzabo::Create;
use Alzabo::Config;

use Data::Dumper;

use File::Spec;

use lib '.', './t';

require 'base.pl';

require 'make_schemas.pl';
require 'drop_schemas.pl';

# squash dumb warnings
$DB_File::VERSION = $IPC::Shareable::VERSION = $BerkeleyDB::VERSION = 0;

$Data::Dumper::Indent = 0;

my $tests = eval $ENV{ALZABO_RDBMS_TESTS};
die $@ if $@;

# re-order the tests to prevent test failures with multi-process tests
# & Pg.
my @t;
foreach my $db ( qw( mysql pg oracle sybase ) )
{
    push @t, grep { $_->{rdbms} eq $db } @$tests;
}

my @cache =
    ( [
       { store => 'Alzabo::ObjectCache::Store::Memory',
	 sync  => 'Alzabo::ObjectCache::Sync::Null' },
       0,
      ],
      [
       { store => 'Alzabo::ObjectCache::Store::Memory',
	 sync  => 'Alzabo::ObjectCache::Sync::Null',
	 lru_size => 2 },
       0,
      ],
      [
       # no caching at all
       { store => 0,
	 sync  => 0 },
       0,
      ],
    );

my $sync = 0;

my %has;
$has{DB_File} = eval { require DB_File } && $DB_File::VERSION >= 1.76 && ! $@;
$has{IPC} = eval { require IPC::Shareable } && $IPC::Shareable::VERSION >= 0.54 && ! $@;
$has{BerkeleyDB} = eval { require BerkeleyDB } && $BerkeleyDB::VERSION >= 0.15 && ! $@;
$has{SDBM_File} = eval { require SDBM_File } && ! $@;
$has{'Cache::Mmap'} = eval { require Cache::Mmap } && ! $@;

if ($has{DB_File})
{
    unshift @cache,
	[ { store => 'Alzabo::ObjectCache::Store::Memory',
	    sync  => 'Alzabo::ObjectCache::Sync::DB_File',
	    sync_dbm_file => File::Spec->catfile( 't', 'objectcache', 'db_filesynctest.dbm' ),
	    clear_on_startup => 1,
	  },
	  1
	];

    $sync++;
}
if ($has{IPC})
{
    unshift @cache,
	[ { store => 'Alzabo::ObjectCache::Store::Memory',
	    sync  => 'Alzabo::ObjectCache::Sync::IPC' },
	  1
	];

    $sync++;
}
if ($has{BerkeleyDB})
{
    unshift @cache,
	[ { store => 'Alzabo::ObjectCache::Store::Memory',
	    sync  => 'Alzabo::ObjectCache::Sync::BerkeleyDB',
	    sync_dbm_file => File::Spec->catfile( 't', 'objectcache', 'bdb_sync_1.dbm' ),
	    clear_on_startup => 1,
	  },
	  1
	];

    $sync++;

    unshift @cache,
	[ { store => 'Alzabo::ObjectCache::Store::BerkeleyDB',
	    sync  => 'Alzabo::ObjectCache::Sync::BerkeleyDB',
	    store_dbm_file => File::Spec->catfile( 't', 'objectcache', 'bdb_store.dbm' ),
	    sync_dbm_file => File::Spec->catfile( 't', 'objectcache', 'bdb_sync_2.dbm' ),
	    clear_on_startup => 1,
	  },
	  1
	];

    $sync++;

    unshift @cache,
	[ { store => 'Alzabo::ObjectCache::Store::BerkeleyDB',
	    sync  => 'Alzabo::ObjectCache::Sync::Null',
	    store_dbm_file => File::Spec->catfile( 't', 'objectcache', 'bdb_store_lru.dbm' ),
	    lru_size => 2 },
	  0,
	],

}
if ($has{SDBM_FILE})
{
    unshift @cache,
	[ { store => 'Alzabo::ObjectCache::Store::Memory',
	    sync  => 'Alzabo::ObjectCache::Sync::SDBM_File',
	    sync_dbm_file => File::Spec->catfile( 't', 'objectcache', 'sdbmsynctest.dbm' ),
	    clear_on_startup => 1,
	  },
	  1
	];

    $sync++;
}
if ($has{'Cache::Mmap'})
{
    unshift @cache,
	[ { store => 'Alzabo::ObjectCache::Store::Memory',
	    sync  => 'Alzabo::ObjectCache::Sync::Mmap',
	    sync_mmap_file => File::Spec->catfile( 't', 'objectcache', 'mmap' ),
	    clear_on_startup => 1,
	  },
	  1
	];

    $sync++;
}

foreach ( qw( BerkeleyDB SDBM_File DB_File IPC ) )
{
    if ($has{$_})
    {
	unshift @cache,
	    [ { store => 'Alzabo::ObjectCache::Store::Null',
		sync => "Alzabo::ObjectCache::Sync::$_",
		sync_dbm_file => File::Spec->catfile( 't', 'objectcache', 'sync_test_null_store.dbm' ),
		clear_on_startup => 1,
	      },
	      1
	    ];

	$sync++;
	last;
    }
}

my $TESTS_PER_RUN = 317;
my $SYNC_TESTS_PER_RUN = 20;

#
# For each test in @cache, the tests will be run once.
#
# For each test in @$tests, the tests (using RDBMS caching) will be
# run once.
#
# Then any remaining tests in @$tests will be run.
#
# For each count of $sync the sync tests will be run once.
#
# For each test in @$tests, the sync tests will be run once (using
# RDBMS caching).
#
my $test_count = ( ( $TESTS_PER_RUN * @cache ) +
		   ( $TESTS_PER_RUN * @t ) +
		   ( $TESTS_PER_RUN * (@t - 1) ) +
		   ( $SYNC_TESTS_PER_RUN * $sync ) +
		   ( $SYNC_TESTS_PER_RUN * @t )
		 );

my %SINGLE_RDBMS_TESTS = ( mysql => 23,
			   pg => 11,
			 );

my $test = shift @t;
my $last_test_num;

foreach my $rdbms (keys %SINGLE_RDBMS_TESTS)
{
    next unless grep { $_->{rdbms} eq $rdbms } $test, @t;

    if ( $test->{rdbms} eq $rdbms )
    {
	$test_count += $SINGLE_RDBMS_TESTS{$rdbms} * @cache;

	# Once for RDBMS caching
	$test_count += $SINGLE_RDBMS_TESTS{$rdbms};
    }
    else
    {
	# once normally and once for RDBMS caching
	$test_count += $SINGLE_RDBMS_TESTS{$rdbms} * 2;
    }
}

print "1..$test_count\n";

foreach my $c (@cache)
{
    run_tests($test, $c);
}

# test all RDBMS's with RDBMS caching
foreach my $t ( $test, @t )
{
    run_tests( $t, [
		    { store => 'Alzabo::ObjectCache::Store::RDBMS',
		      sync  => 'Alzabo::ObjectCache::Sync::RDBMS',
		      store_schema_name => $t->{schema},
		      sync_schema_name  => $t->{schema},
		      ( map { ( "store_$_" => $t->{$_},
				"sync_$_"  => $t->{$_} ) }
			keys %$t ),
		    },
		    1,
		   ],
	     );
}

# run remaining tests (other RDBMS with basic caching)
foreach my $test (@t)
{
    run_tests($test, [
		      { store => 'Alzabo::ObjectCache::Store::Memory',
			sync  => 'Alzabo::ObjectCache::Sync::Null',
		      },
		      0,
		     ],
	     );
}

sub run_tests
{
    my ($test, $c) = @_;

    my $s;
    {
	no strict 'refs';
	&{ "$test->{rdbms}_make_schema" }(%$test);
    }

    my $store_mod = $c->[0]->{store} || 'Nothing';
    my $sync_mod  = $c->[0]->{sync} || 'Nothing';
    print "\nRunning $test->{rdbms} runtime tests with\n\tstore => $store_mod,\n\tsync  => $sync_mod\n";
    print "\tlru_size: $c->[0]->{lru_size}\n" if $c->[0]->{lru_size};
    print "\n";

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

    foreach (keys %SINGLE_RDBMS_TESTS)
    {
	$last_test_num += $SINGLE_RDBMS_TESTS{$_} if $_ eq $test->{rdbms};
    }

    my $tests_pl = File::Spec->catfile( 't', 'runtime_tests.pl' );
    system( "$^X $tests_pl" )
	and die "Can't run '$^X $tests_pl: $!";

    {
	no strict 'refs';
	&{ "$test->{rdbms}_drop_schema" }(%$test);
    }
}
