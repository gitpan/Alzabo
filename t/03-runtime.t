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

# squash dumb warnings
$DB_File::VERSION = $IPC::Shareable::VERSION = $BerkeleyDB::VERSION = 0;

$Data::Dumper::Indent = 0;

my $tests = eval $ENV{ALZABO_RDBMS_TESTS};

my @cache = ( [
	       { store => 'Alzabo::ObjectCache::Store::Memory',
		 sync  => 'Alzabo::ObjectCache::Sync::Null' },
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
if ( eval { require DB_File } && $DB_File::VERSION >= 1.76 && ! $@ )
{
    unshift @cache, [ { store => 'Alzabo::ObjectCache::Store::Memory',
			sync  => 'Alzabo::ObjectCache::Sync::DB_File',
			dbm_file => 't/db_filesynctest.dbm',
			clear_on_startup => 1,
		      },
		      1
		    ];
    $sync++;
}
if ( eval { require IPC::Shareable } && $IPC::Shareable::VERSION >= 0.54 && ! $@ )
{
    unshift @cache, [ { store => 'Alzabo::ObjectCache::Store::Memory',
			sync  => 'Alzabo::ObjectCache::Sync::IPC' },
		      1
		    ];
    $sync++;
}
if ( eval { require BerkeleyDB } && $BerkeleyDB::VERSION >= 0.15 && ! $@ )
{
    unshift @cache, [ { store => 'Alzabo::ObjectCache::Store::Memory',
			sync  => 'Alzabo::ObjectCache::Sync::BerkeleyDB',
			dbm_file => 't/berkeleydbsynctest.dbm',
			clear_on_startup => 1,
		      },
		      1
		    ];
    $sync++;
}
if ( eval { require SDBM_File } && ! $@ )
{
    unshift @cache, [ { store => 'Alzabo::ObjectCache::Store::Memory',
			sync  => 'Alzabo::ObjectCache::Sync::SDBM_File',
			dbm_file => 't/sdbmsynctest.dbm',
			clear_on_startup => 1,
		      },
		      1
		    ];
    $sync++;
}

my $TESTS_PER_RUN = 70;
my $SYNC_TESTS_PER_RUN = 18;
my $test_count = ( ( $TESTS_PER_RUN * (@$tests + $#cache) ) +
		   ( $SYNC_TESTS_PER_RUN * $sync ) );

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

foreach my $c (@cache)
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

	print "Running $test->{rdbms} runtime tests with\n\tstore => Alzabo::ObjectCache::Store::Memory,\n\tsync  => Alzabo::ObjectCache::Sync::Null\n";

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
