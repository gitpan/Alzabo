use strict;

BEGIN
{
    unless (defined $ENV{ALZABO_RDBMS_TESTS})
    {
	print "1..0\n";
	exit;
    }
}

use Alzabo::Runtime;

use lib '.', './t';

require 'base.pl';

require 'make_schemas.pl';

eval 'use Test::More ( tests => 9 )';
die $@ if $@;

my $tests = eval $ENV{ALZABO_RDBMS_TESTS};
die $@ if $@;

my $t = pop @$tests;
{
    no strict 'refs';
    &{ "$t->{rdbms}_make_schema" }(%$t);
}

my $s = Alzabo::Runtime::Schema->load_from_file( name => $t->{schema_name} );

foreach ( qw( user password host port ) )
{
    my $m = "set_$_";
    $s->$m( $t->{$_} );
}
$s->connect;

my $emp_t = $s->table('employee');
$s->table('department')->insert( values => { department_id => 1,
					     name => 'borging' } );

$emp_t->insert( values => { employee_id => 98765,
			    name => 'bob98765',
			    smell => 'bb',
			    dep_id => 1 } );

my $ser;
eval_ok( sub { my $row = $emp_t->row_by_pk( pk => 98765 );
	       $ser = Storable::freeze($row);
	     }, "Freeze employee" );

my $eid;
eval_ok( sub { my $row = Storable::thaw($ser);
	       $eid = $row->select('employee_id');
	     }, "Thaw employee" );

is( $eid, 98765,
    "Employee survived freeze & thaw" );

eval_ok( sub { my $row = $emp_t->row_by_pk( pk => 98765 );
	       $ser = Storable::nfreeze($row);
	     }, "NFreeze employee" );

my $smell;
eval_ok( sub { my $row = Storable::thaw($ser);
	       $smell = $row->select('smell');
	     }, "Thaw employee" );

is( $smell, 'bb',
    "Employee survived nfreeze & thaw" );

eval_ok( sub { my $p_row = $emp_t->potential_row( values => { name => 'Alice' } );
	       $ser = Storable::freeze($p_row);
	     }, "Freeze potential employee" );

my $name;
eval_ok( sub { my $p_row = Storable::thaw($ser);
	       $name = $p_row->select('name');
	     }, "Thaw potential employee" );

is( $name, 'Alice',
    "Potential employee survived freeze & thaw" );
