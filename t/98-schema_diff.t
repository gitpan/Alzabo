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

use lib '.', './t';

require 'base.pl';

require 'make_schemas.pl';

my $tests = eval $ENV{ALZABO_RDBMS_TESTS};
die $@ if $@;

my $test_count = 0;
foreach (@$tests)
{
    $test_count += 5;
}

eval "use Test::More ( tests => $test_count )";
die $@ if $@;

foreach my $t (@$tests)
{
    {
	no strict 'refs';
	&{ "$t->{rdbms}_make_schema" }(%$t);
    }

    my $s = Alzabo::Create::Schema->load_from_file( name => $t->{schema_name} );

    my %p = ( user => $t->{user},
	      password => $t->{password},
	      host => $t->{host},
	      port => $t->{port},
	    );

    $s->table('employee')->delete_column( $s->table('employee')->column('name') );

    eval_ok( sub { $s->create(%p) },
	     "Create schema (via diff) with one column deleted" );

    $s->table('department')->make_column( name => 'foo',
					  type => 'int',
					  nullable => 1 );

    eval_ok( sub { $s->create(%p) },
	     "Create schema (via diff) with one column added" );

    $s->delete_table( $s->table('department') );

    eval_ok( sub { $s->create(%p) },
	     "Create schema (via diff) with one table deleted" );

    $s->make_table( name => 'cruft' );
    $s->table('cruft')->make_column( name => 'cruft_id',
				     type => 'int' );

    eval_ok( sub { $s->create(%p) },
	     "Create schema (via diff) with one table added" );

    my $idx = ($s->table('project')->indexes)[0];

    $s->table('project')->delete_index($idx);

    eval_ok( sub { $s->create(%p) },
	     "Create schema (via diff) with one index deleted" );
}
