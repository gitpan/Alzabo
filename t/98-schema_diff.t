use strict;

use Test::More;

use Alzabo::Create;

use lib '.', File::Spec->catdir( File::Spec->curdir, 't' );

require 'base.pl';

unless ( @$Alzabo::Build::Tests )
{
    plan skip_all => 'no test config provided';
    exit;
}

require 'make_schemas.pl';

my $tests = $Alzabo::Build::Tests;

my $test_count = 0;
foreach (@$tests)
{
    $test_count += 10;
}

plan tests => $test_count;

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
				     type => 'int',
				     primary_key => 1,
				   );

    eval_ok( sub { $s->create(%p) },
	     "Create schema (via diff) with one table added" );

    my $idx = ($s->table('project')->indexes)[0];

    $s->table('project')->delete_index($idx);

    eval_ok( sub { $s->create(%p) },
	     "Create schema (via diff) with one index deleted" );

    $s->table('cruft')->make_column( name => 'cruftiness',
				     type => 'int',
				     nullable => 1,
				     default => 10 );

    eval_ok( sub { $s->create(%p) },
	     "Create schema (via diff) with one column (null and with a default) added" );

    my $dbh = $s->driver->handle;
    $dbh->do( 'INSERT INTO cruft (cruft_id, cruftiness) VALUES (1, 2)' );
    $dbh->do( 'INSERT INTO cruft (cruft_id, cruftiness) VALUES (2, 4)' );

    $s->table('cruft')->column('cruftiness')->set_type('float');
    $s->table('cruft')->set_name('new_cruft');

    eval_ok( sub { $s->create(%p) },
	     "Create schema (via diff) with a table name change and column type change" );

    my ($val) =
        $dbh->selectrow_array( 'SELECT cruftiness FROM new_cruft WHERE cruft_id = 2' );
    is( $val, 4,
        "Data should be preserved across table name change" );

    $s->table('new_cruft')->column('cruft_id')->set_name('new_cruft_id');

    eval_ok( sub { $s->create(%p) },
	     "Create schema (via diff) with a column name change" );

    my ($val) =
        $dbh->selectrow_array( 'SELECT cruftiness FROM new_cruft WHERE new_cruft_id = 2' );
    is( $val, 4,
        "Data should be preserved across column name change" );
}
