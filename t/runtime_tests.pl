use strict;

use Alzabo::Create;
use Alzabo::Runtime;

my $p;
BEGIN
{
    use lib '.', './t';
    require 'base.pl';

    if ($ENV{OBJECTCACHE_PARAMS} && (my $c_params = eval $ENV{OBJECTCACHE_PARAMS}))
    {
	require Alzabo::ObjectCache;
	Alzabo::ObjectCache->import( %$c_params );
    }

    $p = eval $ENV{CURRENT_TEST};
    if ( $p->{rdbms} eq 'mysql' )
    {
	eval 'use Alzabo::SQLMaker::MySQL qw(:all)';
    }
    elsif ( $p->{rdbms} eq 'pg' )
    {
	eval 'use Alzabo::SQLMaker::PostgreSQL qw(:all)';
    }
}

use Test::More qw(no_header);
use Test::Builder;

# we want to use Test::More but start at a number > 1
my $test = Test::Builder->new;
$test->current_test( $ENV{TEST_START_NUM} );
$test->no_plan;
$test->no_header(1);
$test->no_ending(1);

my $s = Alzabo::Runtime::Schema->load_from_file( name => $p->{db_name} );

eval { run_tests($s, %$p); };
warn "Error running tests: $@" if $@;

if ( $ENV{SYNC_TESTS} )
{
    print "  Running sync tests (same caching modules)\n";
    eval { run_sync_tests($s, %$p); };
    warn "Error running multi process tests: $@" if $@;
}

sub run_tests
{
    my $s = shift;
    my %p = @_;

    eval_ok( sub { $s->set_user('foo') },
	     "Set user for schema to foo" );

    eval_ok( sub { $s->set_password('foo') },
	     "Set password for schema to foo" );

    eval_ok( sub { $s->set_host('foo') },
	     "Set host for schema to foo" );

    $s->$_(undef) foreach qw( set_user set_password set_host );

    $s->set_user($p{user}) if $p{user};
    $s->set_password($p{password}) if $p{password};
    $s->set_host($p{host}) if $p{host};
    $s->set_referential_integrity(1);
    $s->connect;

    my $dbh = $s->driver->handle;
    my_isa_ok( $dbh, ref $s->driver->{dbh},
	    "Object returned by \$s->driver->handle method should be a database handle" );

    eval_ok( sub { $s->driver->handle($dbh) },
	     "Set \$s->driver->handle" );

    my $emp_t = $s->table('employee');
    my $dep_t = $s->table('department');
    my $proj_t = $s->table('project');
    my $emp_proj_t = $s->table('employee_project');

    my %dep;
    eval_ok( sub { $dep{borg} = $dep_t->insert( values => { name => 'borging' } ) },
	     "Insert borging row into department table" );

    is( $dep{borg}->select('name'), 'borging',
	"The borg department name should be 'borging'" );

    $dep{lying} = $dep_t->insert( values => { name => 'lying to the public' } );

    my $borg_id = $dep{borg}->select('department_id');
    delete $dep{borg};

    eval_ok( sub { $dep{borg} = $dep_t->row_by_pk( pk => $borg_id ) },
	     "Retrieve borg department row via row_by_pk method" );

    my_isa_ok( $dep{borg}, 'Alzabo::Runtime::Row',
	    "Borg department should be an Alzabo::Runtime::Row object" );

    is( $dep{borg}->select('name'), 'borging',
	"Department's name should be 'borging'" );

    eval { $dep_t->insert( values => { name => 'will break',
				       manager_id => 1 } ); };

    my_isa_ok( $@, 'Alzabo::Exception::ReferentialIntegrity',
	    "Attempt to insert a non-existent manager_id into department should have cause a referential integrity exception" );

    my %emp;
    eval_ok( sub { $emp{bill} = $emp_t->insert( values => { name => 'Big Bill',
							    dep_id => $borg_id,
							    smell => 'robotic',
							    cash => 20.2,
							  } ) },
	     "Insert Big Bill into employee table" );

    my %data = $emp{bill}->select_hash( 'name', 'smell' );
    is( $data{name}, 'Big Bill',
	"select_hash - check name key" );
    is( $data{smell}, 'robotic',
	"select_hash - check smell key" );

    eval { $emp_t->insert( values => { name => undef,
				       dep_id => $borg_id,
				       smell => 'robotic',
				       cash => 20.2,
				     } ); };

    my_isa_ok( $@, 'Alzabo::Exception::Params',
	    "Inserting a non-nullable column as NULL should produce an Alzabo::Exception::Params exception" );

    eval_ok( sub { $emp_t->insert( values => { name => 'asfalksf',
					       dep_id => $borg_id,
					       smell => undef,
					       cash => 20.2,
					     } )->delete },
	     "Inserting a NULL into a non-nullable column that has a default should produce an exception" );

    eval { $emp_t->insert( values => { name => 'YetAnotherTest',
				       dep_id => undef,
				       cash => 1.1,
				     } ) };

    my_isa_ok( $@, 'Alzabo::Exception::Params',
	    "Attempt to insert a NULL into dep_id for an employee should cause an Alzabo::Exception::Params exception" );

    eval { $emp{bill}->update( dep_id => undef ) };

    my_isa_ok( $@, 'Alzabo::Exception::Params',
	    "Attempt to update dep_id to NULL for an employee should cause  an Alzabo::Exception::Params exception" );

    $emp{bill}->update( cash => undef, smell => 'hello!' );
    ok( ! defined $emp{bill}->select('cash'),
	"Bill has no cash" );

    ok( $emp{bill}->select('smell') eq 'hello!',
	"smell for bill should be 'hello!'" );

    eval { $emp{bill}->update( name => undef ) };
    my_isa_ok( $@, 'Alzabo::Exception::Params',
	    "Attempt to update a non-nullable column to NULL should produce an Alzabo::Exception::Params exception" );

    eval_ok( sub { $dep{borg}->update( manager_id => $emp{bill}->select('employee_id') ) },
	     "Set manager_id column for borg department" );

    eval_ok( sub { $emp{2} = $emp_t->insert( values =>
					     { name => 'unit 2',
					       smell => 'good',
					       dep_id => $dep{lying}->select('department_id') } ) },
	     "Create employee 'unit 2'" );

    my $emp2_id = $emp{2}->select('employee_id');
    delete $emp{2};

    my $cursor;
    my $x = 0;
    eval_ok( sub { $cursor = $emp_t->rows_where( where => [ $emp_t->column('employee_id'), '=', $emp2_id ] );
		   while ( my $row = $cursor->next )
		   {
		       $x++;
		       $emp{2} = $row;
		   } },
	     "Retrieve 'unit 2' employee via rows_where method and cursor" );

    ok( ! $cursor->errors,
	"Check cursor errors from trying to retrieve 'unit 2' employee via rows_where method" );
    is( $x, 1,
	"Check count of rows found where employee_id == $emp2_id" );

    is( $emp{2}->select('name'), 'unit 2',
	"Check that row found has name of 'unit 2'" );


    my %proj;
    $proj{extend} = $proj_t->insert( values => { name => 'Extend',
						 department_id => $dep{borg}->select('department_id') } );
    $proj{embrace} = $proj_t->insert( values => { name => 'Embrace',
						  department_id => $dep{borg}->select('department_id')  } );

    $emp_proj_t->insert( values => { employee_id => $emp{bill}->select('employee_id'),
				     project_id  => $proj{extend}->select('project_id') } );

    $emp_proj_t->insert( values => { employee_id => $emp{bill}->select('employee_id'),
				     project_id  => $proj{embrace}->select('project_id') } );

    my $fk = $emp_t->foreign_keys_by_table($emp_proj_t);
    my @emp_proj;
    eval_ok( sub { $cursor = $emp{bill}->rows_by_foreign_key( foreign_key => $fk );
		   while ( my $row = $cursor->next )
		   {
		       push @emp_proj, $row;
		   } },
	     "Fetch rows via ->rows_by_foreign_key method" );
    is( scalar @emp_proj, 2,
	"Check that only two rows were returned" );
    is( $emp_proj[0]->select('employee_id'), $emp{bill}->select('employee_id'),
	"Check that employee_id in employee_project is same as bill's" );
    is( $emp_proj[0]->select('project_id'), $proj{extend}->select('project_id'),
	"Check that project_id in employee_project is same as extend project" );

    $x = 0;
    my @rows;

    eval_ok( sub { $cursor = $emp_t->all_rows;
		   $x++ while $cursor->next
	         },
	     "Fetch all rows from employee table" );
    ok( ! $cursor->errors,
	"Check that cursor has no errors from previous fethc" );
    is( $x, 2,
	"Only 2 rows should be found" );

    $cursor->reset;
    my $count = $cursor->all_rows;

    ok( ! $cursor->errors,
	"Check that cursor has no errors from previous fetch after reset and calling all_rows" );
    is( $x, 2,
	"Only 2 rows should be found after cursor reset" );

    eval_ok( sub { $cursor = $s->join( tables   => [ $emp_t, $emp_proj_t, $proj_t ],
				       where    => [ $emp_t->column('employee_id'), '=', 1 ],
				       order_by => $proj_t->column('project_id') ) },
	     "Join employee, employee_project, and project tables where employee_id = 1" );

    @rows = $cursor->next;

    is( scalar @rows, 3,
	"3 rows per cursor ->next call" );
    is( $rows[0]->table->name, 'employee',
	"First row is from employee table" );
    is( $rows[1]->table->name, 'employee_project',
	"Second row is from employee_project table" );
    is( $rows[2]->table->name, 'project',
	"Third row is from project table" );

    my $first_proj_id = $rows[2]->select('project_id');
    @rows = $cursor->next;
    my $second_proj_id = $rows[2]->select('project_id');

    ok( $first_proj_id < $second_proj_id,
	"Order by clause should cause project rows to come back in ascending order of project id" );

    $cursor = $s->join( tables   => [ $emp_t, $emp_proj_t, $proj_t ],
			where    => [ $emp_t->column('employee_id'), '=', 1 ],
			order_by => { columns => $proj_t->column('project_id'),
				      sort => 'desc' } );
    @rows = $cursor->next;
    $first_proj_id = $rows[2]->select('project_id');
    @rows = $cursor->next;
    $second_proj_id = $rows[2]->select('project_id');

    ok( $first_proj_id > $second_proj_id,
	"Order by clause should cause project rows to come back in descending order of project id" );

    eval_ok( sub { $cursor = $s->join( select => [ $emp_t, $emp_proj_t, $proj_t ],
				       tables => [ [ $emp_t, $emp_proj_t ],
						   [ $emp_proj_t, $proj_t ] ],
				       where =>  [ $emp_t->column('employee_id'), '=', 1 ] ) },
	     "Join with table as tables parameter" );

    @rows = $cursor->next;

    is( scalar @rows, 3,
	"3 rows per cursor ->next call" );
    is( $rows[0]->table->name, 'employee',
	"First row is from employee table" );
    is( $rows[1]->table->name, 'employee_project',
	"Second row is from employee_project table" );
    is( $rows[2]->table->name, 'project',
	"Third row is from project table" );

    eval { $s->join( select => [ $emp_t, $emp_proj_t, $proj_t ],
		     tables => [ [ $emp_t, $emp_proj_t ],
				 [ $emp_proj_t, $proj_t ],
				 [ $s->tables( 'outer_1', 'outer_2' ) ] ],
		     where =>  [ $emp_t->column('employee_id'), '=', 1 ] ) };

    my_isa_ok( $@, 'Alzabo::Exception::Logic',
	    "Join with table map that does not connect should throw an Alzabo::Exception::Logic exception" );

    {

	$s->table('outer_2')->insert( values => { outer_2_name => 'will match something',
						  outer_2_key => 1 },
				      no_cache => 1 );

	$s->table('outer_2')->insert( values => { outer_2_name => 'will match nothing',
						  outer_2_key => 99 },
				      no_cache => 1 );


	$s->table('outer_1')->insert( values => { outer_1_name => 'test1 (has matching join row)',
						  outer_2_key => 1 },
				      no_cache => 1 );

	$s->table('outer_1')->insert( values => { outer_1_name => 'test2 (has no matching join row)',
						  outer_2_key => undef },
				      no_cache => 1 );

	# doubled array reference is intentional
	my $cursor;
	eval_ok( sub { $cursor = $s->left_outer_join( tables =>
						      [ [ $s->tables( 'outer_1', 'outer_2' ) ] ] ) },
		 "Do a left outer join" );

	my @sets = $cursor->all_rows;

	is( scalar @sets, 2,
	    "Left outer join should return 2 sets of rows" );

	# re-order so that the set with 2 valid rows is always first
	unless ( defined $sets[0]->[0]->select('outer_2_key') )
	{
	    my $set = shift @sets;
	    push @sets, $set;
	}

	is( $sets[0]->[0]->select('outer_1_name'), 'test1 (has matching join row)',
	    "The first row in the first set should have the name 'test1 (has matching join row)'" );

	is( $sets[0]->[1]->select('outer_2_name'), 'will match something',
	    "The second row in the first set should have the name 'will match something'" );

	is( $sets[1]->[0]->select('outer_1_name'), 'test2 (has no matching join row)',
	    "The first row in the second set should have the name 'test12 (has no matching join row)'" );

	ok( ! defined $sets[1]->[1],
	    "The second row in the second set should not be defined\n" );

	eval_ok( sub { $cursor = $s->right_outer_join( tables =>
						       [ $s->tables( 'outer_1', 'outer_2' ) ] ) },
		 "Attempt a right outer join" );

	@sets = $cursor->all_rows;

	is( scalar @sets, 2,
	    "Right outer join should return 2 sets of rows" );

	# re-order so that the set with 2 valid rows is always first
	unless ( defined $sets[0]->[1]->select('outer_2_key') )
	{
	    my $set = shift @sets;
	    push @sets, $set;
	}

	is( $sets[0]->[0]->select('outer_1_name'), 'test1 (has matching join row)',
	    "The first row in the first set should have the name 'test1 (has matching join row)'" );

	is( $sets[0]->[1]->select('outer_2_name'), 'will match something',
	    "The second row in the first set should have the name 'will match something'" );

	ok( ! defined $sets[1]->[0],
	    "The first row in the second set should not be defined\n" );

	is( $sets[1]->[1]->select('outer_2_name'), 'will match nothing',
	    "The second row in the second set should have the name 'test12 (has no matching join row)'" );
    }

    my $id = $emp{bill}->select('employee_id');

    $emp{bill}->delete;

    eval { my $c = $emp_t->row_by_pk( pk => $id ) };
    my_isa_ok( $@, 'Alzabo::Exception::NoSuchRow',
	    "Selecting a deleted row should throw an Alzabo::Exception::NoSuchRow exception" );

    eval { $emp{bill}->select('name'); };
    my $expect = $Alzabo::ObjectCache::VERSION ? 'Alzabo::Exception::Cache::Deleted' : 'Alzabo::Exception::NoSuchRow';
    my_isa_ok( $@, $expect,
        "Attempt to select from deleted row object should throw an $expect exception" );

    eval { $emp_proj_t->row_by_pk( pk => { employee_id => $id,
					   project_id => $proj{extend}->select('project_id') } ); };
    # 5.6.0 is broken and gives a wack error here
    if ( $] == 5.006 )
    {
	ok(1, "I hate Perl 5.6.0!");
    }
    else
    {
	my_isa_ok( $@, 'Alzabo::Exception::NoSuchRow',
		"Checking cascading deletes should throw an Alzabo::Exception::NoSuchRow exception" );
    }

    ok( ! defined $dep{borg}->select('manager_id'),
	"The manager_id for the borg department should be NULL" );

    my $dep_id = $dep{borg}->select('department_id');

    $emp_t->insert( values => { name => 'bob', smell => 'awful', dep_id => $dep_id } );
    $emp_t->insert( values => { name => 'rachel', smell => 'horrid', dep_id => $dep_id } );
    $emp_t->insert( values => { name => 'al', smell => 'bad', dep_id => $dep_id } );

    my @emps;
    eval_ok ( sub { @emps = $emp_t->all_rows( order_by =>
					      { columns => $emp_t->column('name') } )->all_rows },
	      "Select all employee rows with hashref to order_by" );

    is( scalar @emps, 4,
	"There should be 4 rows in the employee table" );
    is( $emps[0]->select('name'), 'al',
	"First row name should be al" );
    is( $emps[1]->select('name'), 'bob',
	"Second row name should be bob" );
    is( $emps[2]->select('name'), 'rachel',
	"Third row name should be rachel" );
    is( $emps[3]->select('name'), 'unit 2',
	"Fourth row name should be 'unit 2'" );

    eval_ok( sub { @emps = $emp_t->all_rows( order_by => $emp_t->column('name') )->all_rows },
	     "Select all employee rows with column obj to order_by" );

    is( scalar @emps, 4,
	"There should be 4 rows in the employee table" );
    is( $emps[0]->select('name'), 'al',
	"First row name should be al" );
    is( $emps[1]->select('name'), 'bob',
	"Second row name should be bob" );
    is( $emps[2]->select('name'), 'rachel',
	"Third row name should be rachel" );
    is( $emps[3]->select('name'), 'unit 2',
	"Fourth row name should be 'unit 2'" );

    eval_ok( sub { @emps = $emp_t->all_rows( order_by => [ $emp_t->column('name') ] )->all_rows },
	     "Select all employee rows with arrayref to order_by" );

    is( scalar @emps, 4,
	"There should be 4 rows in the employee table" );
    is( $emps[0]->select('name'), 'al',
	"First row name should be al" );
    is( $emps[1]->select('name'), 'bob',
	"Second row name should be bob" );
    is( $emps[2]->select('name'), 'rachel',
	"Third row name should be rachel" );
    is( $emps[3]->select('name'), 'unit 2',
	"Fourth row name should be 'unit 2'" );

    eval_ok( sub { @emps = $emp_t->all_rows( order_by =>
					     { columns => $emp_t->column('smell') } )->all_rows },
	     "Select all employee rows with hashref to order_by (by smell)" );

    is( scalar @emps, 4,
	"There should be 4 rows in the employee table" );
    is( $emps[0]->select('name'), 'bob',
	"First row name should be bob" );
    is( $emps[1]->select('name'), 'al',
	"Second row name should be al" );
    is( $emps[2]->select('name'), 'unit 2',
	"Third row name should be 'unit 2'" );
    is( $emps[3]->select('name'), 'rachel',
	"Fourth row name should be rachel" );

    eval_ok( sub { @emps = $emp_t->all_rows( order_by => { columns => $emp_t->column('smell'),
							   sort => 'desc' } )->all_rows },
	     "Select all employee rows order by smell (descending)" );

    is( $emps[0]->select('name'), 'rachel',
	"First row name should be rachel" );
    is( $emps[1]->select('name'), 'unit 2',
	"Second row name should be 'unit 2'" );
    is( $emps[2]->select('name'), 'al',
	"Third row name should be al" );
    is( $emps[3]->select('name'), 'bob',
	"Fourth row name should be bob" );

    eval_ok( sub { $count = $emp_t->row_count },
	     "Call row_count for employee table" );

    is( $count, 4,
	"The count should be 4" );

    # this is deprecated but test it til it goes away
    eval_ok( sub { $count = $emp_t->func( func => 'COUNT', args => $emp_t->column('employee_id') ) },
	     "Get row count via deprecated ->func method" );

    is( $count, 4,
	"It should return that there are 4 rows" );

    eval_ok( sub { $count = $emp_t->function( select => COUNT( $emp_t->column('employee_id') ) ) },
	     "Get row count via spiffy new ->function method" );

    is( $count, 4,
	"There should still be just 4 rows" );

    eval_ok( sub { @emps = $emp_t->all_rows( order_by => { columns => $emp_t->column('smell'),
							   sort => 'desc' },
					     limit => 2 )->all_rows },
	     "Get all employee rows with ORDER BY and LIMIT" );

    is( scalar @emps, 2,
	"This should only return 2 rows" );

    is( $emps[0]->select('name'), 'rachel',
	"First row should be rachel" );
    is( $emps[1]->select('name'), 'unit 2',
	"Second row is 'unit 2'" );

    eval_ok( sub { @emps = $emp_t->all_rows( order_by => { columns => $emp_t->column('smell'),
							   sort => 'desc' },
					     limit => [2, 2] )->all_rows },
	     "Get all employee rows with ORDER BY and LIMIT (with offset)" );

    is( scalar @emps, 2,
	"This should only return 2 rows" );

    is( $emps[0]->select('name'), 'al',
	"First row should be al" );
    is( $emps[1]->select('name'), 'bob',
	"Second row is bob" );

    # All this stuff with this 'char_pk' table is about making sure
    # that the caching system is ok when we insert a row into a table,
    # delete it, and then insert a new row with _the same primary key_
    my $char_row;
    eval_ok( sub { $char_row = $s->table('char_pk')->insert( values => { char_col => 'pk value' } ) },
	     "Insert into char_pk table" );

    $char_row->delete;
    eval { $s->table('char_pk')->row_by_pk( pk => 'pk value' ); };
    # 5.6.0 is broken and gives a wack error here
    if ( $] == 5.006 )
    {
	ok(1, "I _still_ hate Perl 5.6.0!");
    }
    else
    {
	my_isa_ok( $@, 'Alzabo::Exception::NoSuchRow',
		"Attempt to fetch deleted row should throw an Alzabo::Exception::NoSuchRow exception" );
    }

    eval { $char_row->select('char_col'); };
    $expect = $Alzabo::ObjectCache::VERSION ? 'Alzabo::Exception::Cache::Deleted' : 'Alzabo::Exception::NoSuchRow';
    my_isa_ok( $@, $expect,
	    "Attempt to select from deleted row should throw an $expect exception" );

    eval_ok( sub { $char_row = $s->table('char_pk')->insert( values => { char_col => 'pk value' } ) },
	     "Insert into char_pk table again with same pk" );

    eval_ok( sub { $s->table('char_pk')->row_by_pk( pk => 'pk value' ) },
	     "Fetch the same just inserted row" );

    my $val;
    eval_ok( sub { $val = $char_row->select('char_col') },
	     "Get the char_col value from the newly made row" );

    is( $val, 'pk value',
	"char_col column in char_pk should be 'pk value'" );

    $emp_t->set_prefetch( $emp_t->columns( qw( name smell ) ) );
    my @p = $emp_t->prefetch;
    is( scalar @p, 2,
	"Prefetch method should return 2 column names" );
    is( scalar ( grep { $_ eq 'name' } @p ), 1,
	"One column should be 'name'" );
    is( scalar ( grep { $_ eq 'smell' } @p ), 1,
	"And the other should be 'smell'" );

    is( $emp_t->row_count, 4,
	"employee table should have 4 rows" );

    my $smell = $emps[0]->select('smell');
    is( $emp_t->row_count( where => [ $emp_t->column('smell'), '=', $smell ] ), 1,
	"Call row_count method with where parameter." );

    $emps[0]->delete;
    eval { $emps[0]->update( smell => 'kaboom' ); };
    $expect = $Alzabo::ObjectCache::VERSION ? 'Alzabo::Exception::Cache::Deleted' : 'Alzabo::Exception::NoSuchRow';
    my_isa_ok( $@, $expect,
	"Attempt to update a deleted row should throw an $expect exception" );

    my $row_id = $emps[1]->id;
    my $row;
    eval_ok( sub { $row = $emp_t->row_by_id( row_id => $row_id ) },
	     "Fetch a row via the ->row_by_id method" );
    is( $row->id, $emps[1]->id,
	"Row retrieved via the ->row_by_id method should be the same as the row whose id was used" );

    $emp_t->insert( values => { employee_id => 9000,
				name => 'bob9000',
				smell => 'a',
				dep_id => $dep_id } );
    $emp_t->insert( values => { employee_id => 9001,
				name => 'bob9001',
				smell => 'b',
				dep_id => $dep_id } );
    $emp_t->insert( values => { employee_id => 9002,
				name => 'bob9002',
				smell => 'c',
				dep_id => $dep_id } );

    my $eid_c = $emp_t->column('employee_id');
    @emps = $emp_t->rows_where( where => [ [ $eid_c, '=', 9000 ],
					   'or',
					   [ $eid_c, '=', 9002 ] ] )->all_rows;
    @emps = sort { $a->select('employee_id') <=> $b->select('employee_id') } @emps;

    is( @emps, 2,
	"Do a query with 'or' and count the rows" );
    is( $emps[0]->select('employee_id'), 9000,
	"First row returned should be employee id 9000" );

    is( $emps[1]->select('employee_id'), 9002,
	"Second row returned should be employee id 9002" );

    @emps = $emp_t->rows_where( where => [ [ $emp_t->column('smell'), '!=', 'c' ],
					   (
					    '(',
					    [ $eid_c, '=', 9000 ],
					    'or',
					    [ $eid_c, '=', 9002, ')' ],
					    ')',
					   ),
					 ] )->all_rows;
    is( @emps, 1,
	"Do another complex query with 'or' and subgroups" );
    is( $emps[0]->select('employee_id'), 9000,
	"The row returned should be employee id 9000" );

    $emp_t->insert( values => { name => 'Smelly',
				smell => 'a',
				dep_id => $dep_id,
			      } );

    @emps = eval { $emp_t->rows_where( where => [ LENGTH( $emp_t->column('smell') ), '=', 1 ] )->all_rows };

    is( @emps, 4,
	"There should be only 4 employees where the length of the smell column is 1" );

    eval_ok( sub { @emps = $emp_t->rows_where( where => [ LENGTH( $emp_t->column('smell') ), '=', 1 ],
					       limit => 2 )->all_rows },
	     "Select all employee rows with WHERE and LIMIT" );

    is( scalar @emps, 2,
       "Limit should cause only two employee rows to be returned" );

    eval_ok( sub { @emps = $emp_t->rows_where( where => [ LENGTH( $emp_t->column('smell') ), '=', 1 ],
					       order_by => { columns => $emp_t->column('smell') },
					       limit => 2 )->all_rows },
	     "Select all employee rows with WHERE, ORDER BY, and LIMIT" );

    is( scalar @emps, 2,
       "Limit should cause only two employee rows to be returned (again)" );

    my @smells = $emp_t->function( select => [ $emp_t->column('smell'), COUNT( $emp_t->column('smell') ) ],
				   group_by => $emp_t->column('smell') );
    # map smell to count
    my %smells = map { $_->[0] => $_->[1] } @smells;
    is( @smells, 6,
	"Query with group by should return 6 values" );
    is( $smells{a}, 2,
	"Check count of smell = 'a'" );
    is( $smells{b}, 1,
	"Check count of smell = 'b'" );
    is( $smells{c}, 1,
	"Check count of smell = 'c'" );
    is( $smells{awful}, 1,
	"Check count of smell = 'awful'" );
    is( $smells{good}, 1,
	"Check count of smell = 'good'" );
    is( $smells{horrid}, 1,
	"Check count of smell = 'horrid'" );

    my $p1 = $proj_t->insert( values => { name => 'P1',
					       department_id => $dep_id,
					} );
    my $p2 = $proj_t->insert( values => { name => 'P2',
					  department_id => $dep_id,
					} );

    eval_ok( sub { $cursor = $s->join( select => $dep_t,
				       distinct => $dep_t,
				       tables => [ $dep_t, $proj_t ],
				       where => [ $proj_t->column('project_id'), 'in',
						  map { $_->select('project_id') } $p1, $p2 ],
				     ) },
	     "Do a join with distinct parameter set" );

    @rows = $cursor->all_rows;

    is( scalar @rows, 1,
	"Setting distinct should cause only a single row to be returned" );

    is( $rows[0]->select('department_id'), $dep_id,
	"Returned row's department_id should be $dep_id" );

    if ( $p{rdbms} eq 'mysql' )
    {
	my $emp;
	eval_ok( sub { $emp = $emp_t->insert( values => { name => UNIX_TIMESTAMP(),
							  dep_id => $dep_id } ) },
		 "Insert using SQL function UNIX_TIMESTAMP()" );

	like( $emp->select('name'), qr/\d+/,
	      "Name should be all digits (unix timestamp)" );

	eval_ok( sub { $emp->update( name => LOWER('FOO') ) },
		 "Do update using SQL function LOWER()" );

	is( $emp->select('name'), 'foo',
	    "Name should be 'foo'" );

	eval_ok( sub { $emp->update( name => REPEAT('Foo', 3) ) },
		 "Do update using SQL function REPEAT()" );

	is( $emp->select('name'), 'FooFooFoo',
	    "Name should be 'FooFooFoo'" );

	eval_ok( sub { $emp->update( name => UPPER( REPEAT('Foo', 3) ) ) },
		 "Do update using nested SQL functions UPPER(REPEAT())" );

	is( $emp->select('name'), 'FOOFOOFOO',
	    "Name should be 'FOOFOOFOO'" );

	$emp_t->insert( values => { name => 'Timestamp',
				    dep_id => $dep_id,
				    tstamp => time - 100_000 } );

	my $cursor;
	eval_ok( sub { $cursor =
			   $emp_t->rows_where( where =>
					       [ [ $emp_t->column('tstamp'), '!=', undef ],
						 [ $emp_t->column('tstamp'), '<', UNIX_TIMESTAMP() ] ] ) },
		 "Do select with where condition that uses SQL function UNIX_TIMESTAMP()" );

	my @rows = $cursor->all_rows;
	is( scalar @rows, 1,
	    "Only one row should have a timestamp value that is not null and that is less than the current time" );
	is( $rows[0]->select('name'), 'Timestamp',
	    "That row should be named Timestamp" );
    }
    elsif ( $p{rdbms} eq 'pg' )
    {
	my $emp;
	eval_ok( sub { $emp = $emp_t->insert( values => { name => NOW(),
							  dep_id => $dep_id } ) },
		 "Do insert using SQL function NOW()" );

	like( $emp->select('name'), qr/\d+/,
	      "Name should be all digits (Postgres timestamp)" );

	eval_ok( sub { $emp->update( name => LOWER('FOO') ) },
		 "Do update using SQL function LOWER()" );

	is( $emp->select('name'), 'foo',
	    "Name should be 'foo'" );

	eval_ok( sub { $emp->update( name => REPEAT('Foo', 3) ) },
		 "Do update using SQL function REPEAT()" );

	is( $emp->select('name'), 'FooFooFoo',
	    "Name should be 'FooFooFoo'" );

	eval_ok( sub { $emp->update( name => UPPER( REPEAT('Foo', 3) ) ) },
		 "Do update using nested SQL functions UPPER(REPEAT())" );

	is( $emp->select('name'), 'FOOFOOFOO',
	    "Name should be 'FOOFOOFOO'" );

	$emp_t->insert( values => { name => 'Timestamp',
				    dep_id => $dep_id,
				    tstamp => time - 100_000 } );

	my $cursor;
	eval_ok( sub { $cursor =
			   $emp_t->rows_where( where =>
					       [ [ $emp_t->column('tstamp'), '!=', undef ],
						 [ $emp_t->column('tstamp'), '<', NOW() ] ] ) },
		 "Do select with where condition that uses SQL function NOW()" );

	my @rows = $cursor->all_rows;
	is( scalar @rows, 1,
	    "Only one row should have a timestamp value that is not null and that is less than the current time" );
	is( $rows[0]->select('name'), 'Timestamp',
	    "That row should be named Timestamp" );
    }
}

my $pid;
my ($c_read, $c_write, $p_read, $p_write);

sub run_sync_tests
{
    my $s = shift;
    my %p = @_;

    $c_read  = do { local *FH; };
    $c_write = do { local *FH; };
    $p_read  = do { local *FH; };
    $p_write = do { local *FH; };

    pipe( $p_read, $c_write );
    pipe( $c_read, $p_write );

    select( ( select($c_write), $| = 1 )[0] );
    select( ( select($p_write), $| = 1 )[0] );

    local $SIG{ALRM} = sub { die "sync tests were taking way too long (" . ($pid ? 'parent' : 'child') . ')' };
    alarm(60);

    if ( $pid = fork() )
    {
	parent($s);
    }
    else
    {
	child($s);
    }

    alarm(0);

    waitpid($pid, 0);
}

sub parent
{
    my $s = shift;

    close $p_read;
    close $p_write;

    $s->driver->disconnect;
    $s->connect;

    my $emp;
    eval_ok( sub { $emp = $s->table('employee')->insert( values => { name => 'parent',
								     dep_id => 1,
								   } ) },
	     "Insert new row into employee table" );

    # A.
    print $c_write $emp->select('employee_id'), "\n";

    # B.
    my ($ok, $name) = parse_child_response( get_pipe_data($c_read) );
    ok($ok, $name);

    # C.
    ($ok, $name) = parse_child_response( get_pipe_data($c_read) );
    ok($ok, $name);

    $emp->update( name => 'parent2' );
    is( $emp->select('name'), 'parent2',
	"Employee row's name in parent should be 'parent2'" );

    # D.
    print $c_write "1\n";

    # E.
    ($ok, $name) = parse_child_response( get_pipe_data($c_read) );
    ok($ok, $name);

    $emp->delete;
    eval { $emp->select('name') };
    my_isa_ok( $@, 'Alzabo::Exception::Cache::Deleted',
	    "Attempt to select from deleted row should have caused an Alzabo::Exception::Cache::Deleted exception" );

    # F.
    print $c_write "1\n";

    # G.
    ($ok, $name) = parse_child_response( get_pipe_data($c_read) );
    ok($ok, $name);

    # H.
    my $emp2_id = get_pipe_data($c_read);
    my $emp2;
    eval_ok( sub { $emp2 = $s->table('employee')->row_by_pk( pk => $emp2_id ) },
	     "Fetch employee row where employee_id = $emp2_id" );

    # I.
    print $c_write "1\n";

    # J.
    get_pipe_data($c_read);

    undef $emp2;

    # This should come from the cache.
    $emp2 = $s->table('employee')->row_by_pk( pk => $emp2_id );
    eval { $emp2->update( name => 'newname3' ); };
    my_isa_ok( $@, 'Alzabo::Exception::Cache::Expired',
	    "Attempt to update row immediately should throw an Alzabo::Exception::Cache::Expired exception" );

    # K.
    print $c_write "1\n";

    # L.
    ($ok, $name) = parse_child_response( get_pipe_data($c_read) );
    ok($ok, $name);

    # M.
    print $c_write "1\n";

    # N.
    ($ok, $name) = parse_child_response( get_pipe_data($c_read) );
    ok($ok, $name);

    my $emp3 = eval { $s->table('employee')->insert( values => { name => 'parent',
								 dep_id => 1,
							       } ); };
    my $emp3_id = $emp3->select('employee_id');

    my $pid2;
    if ( $pid2 = fork )
    {
	$s->driver->disconnect;
	$s->connect;
	waitpid($pid2, 0);
    }
    else
    {
	$s->driver->disconnect;
	$s->connect;
	# circumvent caching
	$s->driver->do( sql => 'DELETE FROM employee WHERE employee_id = ?',
			bind => $emp3_id );
	exit 0;
    }

    # O.
    print $c_write "$emp3_id\n";

    # P.
    ($ok, $name) = parse_child_response( get_pipe_data($c_read) );
    ok($ok, $name);

    # Q.
    print $c_write "1\n";

    # R.
    ($ok, $name) = parse_child_response( get_pipe_data($c_read) );
    ok($ok, $name);

    my $emp_name;
    eval_ok( sub { $emp_name = $emp3->select('name') },
	     "Attempt to get name from created/deleted/created row" );

    is( $emp_name, 'lazarus',
	"Employee3's name should be 'lazarus'" );

    my $e1000 = eval { $s->table('employee')->insert( values => { employee_id => 1000,
								  name => 'alive1',
								  dep_id => 1,
								} ); };
    $e1000->delete;

    # S.
    print $c_write "1\n";

    # T.
    get_pipe_data($c_read);

    my $new_name;
    eval_ok( sub { $new_name = $e1000->select('name') },
	     "Attempt to retrieve name for employee_id 1000" );

    is( $new_name, 'alive2',
	"Employee 1000's name should be 'alive2'" );

    $s->table('employee')->set_prefetch( $s->table('employee')->column('name') );
    Alzabo::ObjectCache->clear;

    my $cursor = $s->table('employee')->rows_where( where => [ $s->table('employee')->column('employee_id'), '=', 1000 ] );

    # U.
    print $c_write "1\n";

    # V.
    get_pipe_data($c_read);

    # This is basically a test that the ->clear method for the cache
    # actually worked.
    my $rocko = $cursor->next;
    is( $rocko->select('name'), 'Rocko',
	"The name of employee 1000 should now be 'Rocko'" );

    close $c_read;
    close $c_write;
}

sub parse_child_response
{
    my $res = shift;

    my ($ok, $name) = split /:/, $res, 2;
    unless (defined $ok && defined $name)
    {
	return 0, "incomprehensible child response: $res";
    }

    return $ok, $name;
}

sub child
{
    my $s = shift;

    close $c_read;
    close $c_write;

    $s->driver->disconnect;
    $s->connect;

    # A.
    my $pk = get_pipe_data($p_read);

    my $emp = eval { $s->table('employee')->row_by_pk( pk => $pk ); };

    # B.
    my $tag = "Fetch row from employee table where employee_id = $pk";
    print $p_write ( $@ ? "0:$tag" : "1:$tag" );
    print $p_write "\n";

    # C.
    $tag = "Employee row's name for pk $pk should be 'parent'.  It is '" . $emp->select('name') . "'";
    print $p_write ( $emp->select('name') eq 'parent' ? "1:$tag" : "0:$tag" );
    print $p_write "\n";

    # D.
    get_pipe_data($p_read);

    # Cache sync should find that this process's object is expired and
    # refresh.

    # E.
    $tag = "Employee row's name for pk $pk should be 'parent2'.  It is '" . $emp->select('name') . "'";
    print $p_write ( $emp->select('name') eq 'parent2' ? "1:$tag" : "0:$tag" );
    print $p_write "\n";

    # F.
    get_pipe_data($p_read);

    eval { $emp->select('name') };

    # G.
    $tag = "Attempt to select from deleted row should have caused an Alzabo::Exception::Cache::Deleted exception";
    print $p_write ( $@ && $@->isa('Alzabo::Exception::Cache::Deleted') ? "1:$tag" : "0:$tag: $@" );
    print $p_write "\n";

    my $emp2 = eval { $s->table('employee')->insert( values => { name => 'newname', dep_id => 1 } ); };

    # H.
    print $p_write $emp2->select('employee_id'), "\n";

    # I.
    get_pipe_data($p_read);

    $emp2->update( name => 'newname2' );

    # J.
    print $p_write "1\n";

    # K.
    get_pipe_data($p_read);

    eval { $emp2->update( name => 'newname4' ); };

    # L.
    $tag = "Got exception attempting to update emp2 row";
    print $p_write( $@ ? "0:$tag: $@" : "1:$tag" );
    print $p_write "\n";

    # M.
    get_pipe_data($p_read);

    # N.
    $tag = "Name should be 'newname4'. It is " . eval { $emp2->select('name') };
    print $p_write( eval { $emp2->select('name') eq 'newname4' } ?
		    "1:$tag" : "0:$tag: $@" );
    print $p_write "\n";

    # O.
    my $emp3_id = get_pipe_data($p_read);

    my $emp3 = eval { $s->table('employee')->insert( values => { employee_id => $emp3_id,
								 name => 'lazarus',
								 dep_id => 1,
							       } ); };

    # P.
    $tag = "insert another row with employee_id $emp3_id";
    print $p_write( $@ ? "0:tag: $@" : "1:$tag" );
    print $p_write "\n";

    # Q.
    get_pipe_data($p_read);

    my $name = $emp3->select('name');

    # R.
    $tag = "emp3 name should be 'lazarus'.  It is '$name'";
    print $p_write( $name eq 'lazarus' ? "1:$tag" : "0:$tag" );
    print $p_write "\n";

    # S.
    get_pipe_data($p_read);

    my $e1000 = eval { $s->table('employee')->insert( values => { employee_id => 1000,
								  name => 'alive2',
								  dep_id => 1,
								} ); };

    # T.
    print $p_write "1\n";

    # U.
    get_pipe_data($p_read);

    $e1000->update( name => 'Rocko' );

    # V.
    print $p_write "1\n";

    close $p_write;
    close $p_read;

    $s->driver->disconnect;
    exit;
}

sub get_pipe_data
{
    my $fh = shift;

    local $SIG{ALRM} = sub { die "sync test pipe read was taking way too long (" . ($pid ? 'parent' : 'child') . ')' }; 
    alarm(7);

    my $data = <$fh>;
    local $SIG{ALRM};

    chomp $data;

    alarm(0);

    return $data;
}
