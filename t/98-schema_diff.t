#!/usr/bin/perl -w

use strict;

use File::Spec;

use lib '.', File::Spec->catdir( File::Spec->curdir, 't', 'lib' );

use Alzabo::Test::Utils;

use Test::More;


my @rdbms_names = Alzabo::Test::Utils->rdbms_names;

unless (@rdbms_names)
{
    plan skip_all => 'no test config provided';
    exit;
}

my $tests_per_run = 10;

plan tests => $tests_per_run * @rdbms_names;


Alzabo::Test::Utils->remove_all_schemas;


foreach my $rdbms (@rdbms_names)
{
    my $s = Alzabo::Test::Utils->make_schema($rdbms);

    my %connect = Alzabo::Test::Utils->connect_params_for($rdbms);

    $s->table('employee')->delete_column( $s->table('employee')->column('name') );

    eval_ok( sub { $s->create(%connect) },
	     "Create schema (via diff) with one column deleted" );

    $s->table('department')->make_column( name => 'foo',
					  type => 'int',
					  nullable => 1 );

    eval_ok( sub { $s->create(%connect) },
	     "Create schema (via diff) with one column added" );

    $s->delete_table( $s->table('department') );

    eval_ok( sub { $s->create(%connect) },
	     "Create schema (via diff) with one table deleted" );

    $s->make_table( name => 'cruft' );
    $s->table('cruft')->make_column( name => 'cruft_id',
				     type => 'int',
				     primary_key => 1,
				   );

    eval_ok( sub { $s->create(%connect) },
	     "Create schema (via diff) with one table added" );

    my $idx = ($s->table('project')->indexes)[0];

    $s->table('project')->delete_index($idx);

    eval_ok( sub { $s->create(%connect) },
	     "Create schema (via diff) with one index deleted" );

    $s->table('cruft')->make_column( name => 'cruftiness',
				     type => 'int',
				     nullable => 1,
				     default => 10 );

    eval_ok( sub { $s->create(%connect) },
	     "Create schema (via diff) with one column (null and with a default) added" );

    my $dbh = $s->driver->handle;
    $dbh->do( 'INSERT INTO cruft (cruft_id, cruftiness) VALUES (1, 2)' );
    $dbh->do( 'INSERT INTO cruft (cruft_id, cruftiness) VALUES (2, 4)' );

    $s->table('cruft')->column('cruftiness')->set_type('float');
    $s->table('cruft')->set_name('new_cruft');

    eval_ok( sub { $s->create(%connect) },
	     "Create schema (via diff) with a table name change and column type change" );

    my ($val) =
        $dbh->selectrow_array( 'SELECT cruftiness FROM new_cruft WHERE cruft_id = 2' );
    is( $val, 4,
        "Data should be preserved across table name change" );

    $s->table('new_cruft')->column('cruft_id')->set_name('new_cruft_id');

    eval_ok( sub { $s->create(%connect) },
	     "Create schema (via diff) with a column name change" );

    ($val) =
        $dbh->selectrow_array( 'SELECT cruftiness FROM new_cruft WHERE new_cruft_id = 2' );
    is( $val, 4,
        "Data should be preserved across column name change" );
}
