use strict;

BEGIN
{
    unless (defined $ENV{ALZABO_RDBMS_TESTS})
    {
	print "1..0\n";
#	exit;
    }
}

use Alzabo::Create;
use Alzabo::Config;

use Data::Dumper;

use File::Spec;

use lib '.', './t';

require 'base.pl';

require 'make_schemas.pl';

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

my @cache = ( [
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
	       { store => 'Alzabo::ObjectCache::Store::RDBMS',
		 sync  => 'Alzabo::ObjectCache::Sync::RDBMS',
		 ( map { 'store_' . $_ => $t[0]->{$_},
			 'sync_' . $_  => $t[0]->{$_} }
		   keys %{ $t[0] } )
	       },
	       1,
	      ],
	      [
	       # no caching at all
	       { store => 0,
		 sync  => 0 },
	       0,
	      ],
	    );

my $sync = 1;

my %has;
$has{DB_File} = eval { require DB_File } && $DB_File::VERSION >= 1.76 && ! $@;
$has{IPC} = eval { require IPC::Shareable } && $IPC::Shareable::VERSION >= 0.54 && ! $@;
$has{BekeleyDB} = eval { require BerkeleyDB } && $BerkeleyDB::VERSION >= 0.15 && ! $@;
$has{SDBM_File} = eval { require SDBM_File } && ! $@;

if ($has{DB_File})
{
    unshift @cache, [ { store => 'Alzabo::ObjectCache::Store::Memory',
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
    unshift @cache, [ { store => 'Alzabo::ObjectCache::Store::Memory',
			sync  => 'Alzabo::ObjectCache::Sync::IPC' },
		      1
		    ];
    $sync++;
}
if ($has{BekeleyDB})
{
    unshift @cache, [ { store => 'Alzabo::ObjectCache::Store::Memory',
			sync  => 'Alzabo::ObjectCache::Sync::BerkeleyDB',
			sync_dbm_file => File::Spec->catfile( 't', 'objectcache', 'bdb_sync_1.dbm' ),
			clear_on_startup => 1,
		      },
		      1
		    ];
    $sync++;

    unshift @cache, [ { store => 'Alzabo::ObjectCache::Store::BerkeleyDB',
			sync  => 'Alzabo::ObjectCache::Sync::BerkeleyDB',
			store_dbm_file => File::Spec->catfile( 't', 'objectcache', 'bdb_store.dbm' ),
			sync_dbm_file => File::Spec->catfile( 't', 'objectcache', 'bdb_sync_2.dbm' ),
			clear_on_startup => 1,
		      },
		      1
		    ];
    $sync++;

    unshift @cache, [ { store => 'Alzabo::ObjectCache::Store::BerkeleyDB',
			sync  => 'Alzabo::ObjectCache::Sync::Null',
			store_dbm_file => File::Spec->catfile( 't', 'objectcache', 'bdb_store_lru.dbm' ),
			lru_size => 2 },
		      0,
		    ],

}
if ($has{SDBM_FILE})
{
    unshift @cache, [ { store => 'Alzabo::ObjectCache::Store::Memory',
			sync  => 'Alzabo::ObjectCache::Sync::SDBM_File',
			sync_dbm_file => File::Spec->catfile( 't', 'objectcache', 'sdbmsynctest.dbm' ),
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
	unshift @cache, [ { store => 'Alzabo::ObjectCache::Store::Null',
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

my $TESTS_PER_RUN = 146;
my $SYNC_TESTS_PER_RUN = 19;

#
# For each test in @$tests, the non-sync tests will be run once.  For
# each set of modules in @cache the non-sync tests will be run once
# but there is an overlap because the first test is the one used
# repeatedly for the cache tests.
#
# For each count of $sync the sync tests will be run once.
#
my $test_count = ( ( $TESTS_PER_RUN * (@t + @cache - 1) ) +
		   ( $SYNC_TESTS_PER_RUN * $sync ) );

my %SINGLE_RDBMS_TESTS = ( mysql => 11,
			   pg => 11,
			 );

my $test = shift @t;
my $last_test_num;

#
# Now add in RDBMS specific test counts
#
foreach my $rdbms (keys %SINGLE_RDBMS_TESTS)
{
    next unless grep { $_->{rdbms} eq $rdbms } $test, @t;

    if ( $test->{rdbms} eq $rdbms )
    {
	$test_count += $SINGLE_RDBMS_TESTS{$rdbms} * @cache;
    }
    else
    {
	$test_count += $SINGLE_RDBMS_TESTS{$rdbms};
    }
}

print "1..$test_count\n";

foreach my $c (@cache)
{
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

    system( "$^X t/runtime_tests.pl" )
	and die "Can't run '$^X runtime_tests.pl: $!";

    my $cs = Alzabo::Create::Schema->load_from_file( name => $test->{schema_name} );
    $cs->delete;
    eval { $cs->drop(%$test); };
    warn $@ if $@;
    $cs->driver->disconnect;
}

if (@t)
{
    my $c_params = Data::Dumper->Dump( [ { store => 'Alzabo::ObjectCache::Store::Memory',
					   sync  => 'Alzabo::ObjectCache::Sync::Null' } ],
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

	print "\nRunning $test->{rdbms} runtime tests with\n\tstore => Alzabo::ObjectCache::Store::Memory,\n\tsync  => Alzabo::ObjectCache::Sync::Null\n";
	print "\tlru_size => $test->{lru_size}\n" if $test->{lru_size};
	print "\n";

	my $t = Data::Dumper->Dump( [$test], [''] );
	$t =~ s/\$ = //;
	$t =~ s/'/"/g;
	$ENV{CURRENT_TEST} = $t;
	$ENV{TEST_START_NUM} = $last_test_num;
	$last_test_num += $TESTS_PER_RUN;

	system( "$^X t/runtime_tests.pl" )
	    and die "Can't run '$^X runtime_tests.pl: $!";

	my $cs = Alzabo::Create::Schema->load_from_file( name => $test->{schema_name} );
	$cs->delete;
	eval { $cs->drop(%$test); };
    }
}
