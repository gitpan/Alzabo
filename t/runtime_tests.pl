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
	local $^W;  # Silence warning from Alzabo::ObjectCache::RDBMS
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

my $s = Alzabo::Runtime::Schema->load_from_file( name => $p->{schema_name} );

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

    eval_ok( sub { $s->set_port(1234) },
	     "Set port for schema to 1234" );

    $s->$_(undef) foreach qw( set_user set_password set_host set_port );

    $s->set_user($p{user}) if $p{user};
    $s->set_password($p{password}) if $p{password};
    $s->set_host($p{host}) if $p{host};
    $s->set_host($p{port}) if $p{port};
    $s->set_referential_integrity(1);
    $s->connect;

    my $dbh = $s->driver->handle;
    isa_ok( $dbh, ref $s->driver->{dbh},
	    "Object returned by \$s->driver->handle method" );

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

    {
	my @all = $dep{borg}->select;
	is( @all, 3,
	    "select with no columns should return all the values" );
	is( $all[1], 'borging',
	    "The second value should be the department name" );

	my %all = $dep{borg}->select_hash;
	is( keys %all, 3,
	    "select_hash with no columns should return two keys" );
	ok( exists $all{department_id},
	    "The returned hash should have a department_id key" );
	ok( exists $all{name},
	    "The returned hash should have a department_id key" );
	is( $all{name}, 'borging',
	    "The value of the name key be the department name" );
    }


    $dep{lying} = $dep_t->insert( values => { name => 'lying to the public' } );

    my $borg_id = $dep{borg}->select('department_id');
    delete $dep{borg};

    eval_ok( sub { $dep{borg} = $dep_t->row_by_pk( pk => $borg_id ) },
	     "Retrieve borg department row via row_by_pk method" );

    isa_ok( $dep{borg}, 'Alzabo::Runtime::Row',
	    "Borg department" );

    is( $dep{borg}->select('name'), 'borging',
	"Department's name should be 'borging'" );

    eval { $dep_t->insert( values => { name => 'will break',
				       manager_id => 1 } ); };

    my $e = $@;
    isa_ok( $e, 'Alzabo::Exception::ReferentialIntegrity',
	    "Exception thrown from attempt to insert a non-existent manager_id into department" );

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

    $e = $@;
    isa_ok( $e, 'Alzabo::Exception::Params',
	    "Exception thrown from inserting a non-nullable column as NULL" );

    {
	my $new_emp;
	eval_ok( sub { $new_emp = $emp_t->insert( values => { name => 'asfalksf',
							      dep_id => $borg_id,
							      smell => undef,
							      cash => 20.2,
							    } ) },
		 "Inserting a NULL into a non-nullable column that has a default should not produce an exception" );

	eval_ok( sub { $new_emp->delete },
		 "Delete a just-created employee" );
    }

    eval { $emp_t->insert( values => { name => 'YetAnotherTest',
				       dep_id => undef,
				       cash => 1.1,
				     } ) };

    $e = $@;
    isa_ok( $e, 'Alzabo::Exception::Params',
	    "Exception thrown from attempt to insert a NULL into dep_id for an employee" );

    eval { $emp{bill}->update( dep_id => undef ) };
    $e = $@;
    isa_ok( $e, 'Alzabo::Exception::Params',
	    "Exception thrown from attempt to update dep_id to NULL for an employee" );

    $emp{bill}->update( cash => undef, smell => 'hello!' );
    ok( ! defined $emp{bill}->select('cash'),
	"Bill has no cash" );

    ok( $emp{bill}->select('smell') eq 'hello!',
	"smell for bill should be 'hello!'" );

    eval { $emp{bill}->update( name => undef ) };
    $e = $@;
    isa_ok( $e, 'Alzabo::Exception::Params',
	    "Exception thrown from attempt to update a non-nullable column to NULL" );

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

    {
	my $row;
	eval_ok( sub { $row = $emp_t->one_row( where => [ $emp_t->column('employee_id'), '=', $emp2_id ] ) },
		 "Retrieve 'unit 2' employee via one_row method" );

	is( $row->select('name'), 'unit 2',
	    "Check that the single row returned has the name 'unit 2'" );
    }

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
	     "Fetch rows via ->rows_by_foreign_key method (expect cursor)" );
    is( scalar @emp_proj, 2,
	"Check that only two rows were returned" );
    is( $emp_proj[0]->select('employee_id'), $emp{bill}->select('employee_id'),
	"Check that employee_id in employee_project is same as bill's" );
    is( $emp_proj[0]->select('project_id'), $proj{extend}->select('project_id'),
	"Check that project_id in employee_project is same as extend project" );

    my $emp_proj = $emp_proj[0];
    $fk = $emp_proj_t->foreign_keys_by_table($emp_t);

    my $emp;
    eval_ok( sub { $emp = $emp_proj->rows_by_foreign_key( foreign_key => $fk ) },
	     "Fetch rows via ->rows_by_foreign_key method (expect row)" );
    is( $emp->select('employee_id'), $emp_proj->select('employee_id'),
	"The returned row should have bill's employee_id" );

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

    eval_ok( sub { $cursor = $s->join( join     => [ $emp_t, $emp_proj_t, $proj_t ],
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

    # Alias code
    {
	my $e_alias;
	eval_ok( sub { $e_alias = $emp_t->alias },
		 "Create an alias object for the employee table" );

	my $p_alias;
	eval_ok( sub { $p_alias = $proj_t->alias },
		 "Create an alias object for the project table" );

	eval_ok( sub { $cursor = $s->join( join     => [ $e_alias, $emp_proj_t, $p_alias ],
					   where    => [ $e_alias->column('employee_id'), '=', 1 ],
					   order_by => $p_alias->column('project_id') ) },
		 "Join employee, employee_project, and project tables where employee_id = 1 using aliases" );

	my @rows = $cursor->next;

	is( scalar @rows, 3,
	    "3 rows per cursor ->next call" );
	is( $rows[0]->table->name, 'employee',
	    "First row is from employee table" );
	is( $rows[1]->table->name, 'employee_project',
	    "Second row is from employee_project table" );
	is( $rows[2]->table->name, 'project',
	    "Third row is from project table" );
    }

    # Alias code & multiple joins to the same table
    {
	my $p_alias = $proj_t->alias;

	eval_ok( sub { $cursor = $s->join( select   => [ $p_alias, $proj_t ],
					   join     => [ $p_alias, $emp_proj_t, $proj_t ],
					   where    => [ [ $p_alias->column('project_id'), '=', 1 ],
							 [ $proj_t->column('project_id'), '=', 1 ] ],
					 ) },
		 "Join employee_project and project table (twice) using aliases" );

	my @rows = $cursor->next;

	is( scalar @rows, 2,
	    "2 rows per cursor ->next call" );
	is( $rows[0]->table->name, 'project',
	    "First row is from project table" );
	is( $rows[1]->table->name, 'project',
	    "Second row is from project table" );
	is( $rows[0]->table, $rows[1]->table,
	    "The two rows should share the same table object (the alias should be gone at this point)" );
    }

    {
	my @rows;
	eval_ok( sub { @rows = $s->one_row( tables   => [ $emp_t, $emp_proj_t, $proj_t ],
					    where    => [ $emp_t->column('employee_id'), '=', 1 ],
					    order_by => $proj_t->column('project_id') ) },
		 "Join employee, employee_project, and project tables where employee_id = 1 using one_row method" );

	is( $rows[0]->table->name, 'employee',
	    "First row is from employee table" );
	is( $rows[1]->table->name, 'employee_project',
	    "Second row is from employee_project table" );
	is( $rows[2]->table->name, 'project',
	    "Third row is from project table" );
    }

    $cursor = $s->join( join     => [ $emp_t, $emp_proj_t, $proj_t ],
			where    => [ $emp_t->column('employee_id'), '=', 1 ],
			order_by => { columns => $proj_t->column('project_id'),
				      sort => 'desc' } );
    @rows = $cursor->next;
    $first_proj_id = $rows[2]->select('project_id');
    @rows = $cursor->next;
    $second_proj_id = $rows[2]->select('project_id');

    ok( $first_proj_id > $second_proj_id,
	"Order by clause should cause project rows to come back in descending order of project id" );

    $cursor = $s->join( join     => [ $emp_t, $emp_proj_t, $proj_t ],
			where    => [ $emp_t->column('employee_id'), '=', 1 ],
			order_by => [ $proj_t->column('project_id'), 'desc' ] );

    @rows = $cursor->next;
    $first_proj_id = $rows[2]->select('project_id');
    @rows = $cursor->next;
    $second_proj_id = $rows[2]->select('project_id');

    ok( $first_proj_id > $second_proj_id,
	"Order by clause (alternate form) should cause project rows to come back in descending order of project id" );

    eval_ok( sub { $cursor = $s->join( select => [ $emp_t, $emp_proj_t, $proj_t ],
				       join   => [ [ $emp_t, $emp_proj_t ],
						   [ $emp_proj_t, $proj_t ] ],
				       where  => [ $emp_t->column('employee_id'), '=', 1 ] ) },
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
		     join   => [ [ $emp_t, $emp_proj_t ],
				 [ $emp_proj_t, $proj_t ],
				 [ $s->tables( 'outer_1', 'outer_2' ) ] ],
		     where =>  [ $emp_t->column('employee_id'), '=', 1 ] ) };

    $e = $@;
    isa_ok( $e, 'Alzabo::Exception::Logic',
	    "Exception thrown from join with table map that does not connect" );

    eval_ok( sub { @rows = $s->join( join  => $emp_t,
				     where => [ $emp_t->column('employee_id'), '=', 1 ] )->all_rows },
	     "Join with a single table" );
    is( @rows, 1,
	"Only one row should be returned" );
    is( $rows[0]->select('employee_id'), 1,
	"Returned employee should be employee number one" );

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
	eval_ok( sub { $cursor = $s->join( select => [ $s->tables( 'outer_1', 'outer_2' ) ],
					   join =>
					   [ [ left_outer_join => $s->tables( 'outer_1', 'outer_2' ) ] ] ) },
		 "Do a left outer join" );

	my @sets = $cursor->all_rows;

	is( scalar @sets, 2,
	    "Left outer join should return 2 sets of rows" );

	# re-order so that the set with 2 valid rows is always first
	unless ( defined $sets[0]->[1] )
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
	    "The second row in the second set should not be defined" );

	eval_ok( sub { $cursor = $s->join( select => [ $s->tables( 'outer_1', 'outer_2' ) ],
					   join =>
					   [ [ right_outer_join => $s->tables( 'outer_1', 'outer_2' ) ] ] ) },
		 "Attempt a right outer join" );

	@sets = $cursor->all_rows;

	is( scalar @sets, 2,
	    "Right outer join should return 2 sets of rows" );

	# re-order so that the set with 2 valid rows is always first
	unless ( defined $sets[0]->[0] )
	{
	    my $set = shift @sets;
	    push @sets, $set;
	}

	is( $sets[0]->[0]->select('outer_1_name'), 'test1 (has matching join row)',
	    "The first row in the first set should have the name 'test1 (has matching join row)'" );

	is( $sets[0]->[1]->select('outer_2_name'), 'will match something',
	    "The second row in the first set should have the name 'will match something'" );

	ok( ! defined $sets[1]->[0],
	    "The first row in the second set should not be defined" );

	is( $sets[1]->[1]->select('outer_2_name'), 'will match nothing',
	    "The second row in the second set should have the name 'test12 (has no matching join row)'" );

	# do the same join, but with specified foreign key
	my $fk = $s->table('outer_1')->foreign_keys_by_table( $s->table('outer_2') );
	eval_ok( sub { $cursor = $s->join( select => [ $s->tables( 'outer_1', 'outer_2' ) ],
					   join =>
					   [ [ right_outer_join => $s->tables( 'outer_1', 'outer_2' ), $fk ] ] ) },
		 "Attempt a right outer join, with explicit foreign key" );

	@sets = $cursor->all_rows;

	is( scalar @sets, 2,
	    "Right outer join should return 2 sets of rows" );

	# re-order so that the set with 2 valid rows is always first
	unless ( defined $sets[0]->[0] )
	{
	    my $set = shift @sets;
	    push @sets, $set;
	}

	is( $sets[0]->[0]->select('outer_1_name'), 'test1 (has matching join row)',
	    "The first row in the first set should have the name 'test1 (has matching join row)'" );

	is( $sets[0]->[1]->select('outer_2_name'), 'will match something',
	    "The second row in the first set should have the name 'will match something'" );

	ok( ! defined $sets[1]->[0],
	    "The first row in the second set should not be defined" );

	is( $sets[1]->[1]->select('outer_2_name'), 'will match nothing',
	    "The second row in the second set should have the name 'test12 (has no matching join row)'" );
    }

    my $id = $emp{bill}->select('employee_id');

    $emp{bill}->delete;

    eval { my $c = $emp_t->row_by_pk( pk => $id ) };
    $e = $@;
    isa_ok( $e, 'Alzabo::Exception::NoSuchRow',
	       "Exception thrown by selecting a deleted row" );

    eval { $emp{bill}->select('name'); };
    my $expect = $Alzabo::ObjectCache::VERSION ? 'Alzabo::Exception::Cache::Deleted' : 'Alzabo::Exception::NoSuchRow';
    $e = $@;
    isa_ok( $e, $expect,
        "Exception thrown from attempt to select from deleted row object" );

    eval { $emp_proj_t->row_by_pk( pk => { employee_id => $id,
					   project_id => $proj{extend}->select('project_id') } ); };
    # 5.6.0 is broken and gives a wack error here
    if ( $] == 5.006 )
    {
	ok(1, "I hate Perl 5.6.0!");
    }
    else
    {
	$e = $@;
	isa_ok( $e, 'Alzabo::Exception::NoSuchRow',
		"Exception thrown selecting row deleted by cascading deletes" );
    }

    ok( ! defined $dep{borg}->select('manager_id'),
	"The manager_id for the borg department should be NULL" );

    my $dep_id = $dep{borg}->select('department_id');

    $emp_t->insert( values => { name => 'bob', smell => 'awful', dep_id => $dep_id } );
    $emp_t->insert( values => { name => 'rachel', smell => 'horrid', dep_id => $dep_id } );
    $emp_t->insert( values => { name => 'al', smell => 'bad', dep_id => $dep_id } );

    {
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
    }

    {
	my @emps;
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
    }

    {
	my @emps;
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
    }

    {
	my @emps;
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
    }

    {
	my @emps;
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
    }

    eval_ok( sub { $count = $emp_t->row_count },
	     "Call row_count for employee table" );

    is( $count, 4,
	"The count should be 4" );

    eval_ok( sub { $count = $emp_t->function( select => COUNT( $emp_t->column('employee_id') ) ) },
	     "Get row count via spiffy new ->function method" );

    is( $count, 4,
	"There should still be just 4 rows" );

    my $statement;
    eval_ok( sub { $statement = $emp_t->select( select => COUNT( $emp_t->column('employee_id') ) ) },
	     "Get row count via even spiffier new ->select method" );

    isa_ok( $statement, 'Alzabo::DriverStatement',
	    "Return value from Table->select method" );

    $count = $statement->next;
    is( $count, 4,
	"There should still be just 4 rows" );

    {
	my @emps;
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
    }

    {
	my @emps;
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
    }

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
	$e = $@;
	isa_ok( $e, 'Alzabo::Exception::NoSuchRow',
		"Exception thrown trying to fetch deleted row" );
    }

    eval { $char_row->select('char_col'); };

    $expect = $Alzabo::ObjectCache::VERSION ? 'Alzabo::Exception::Cache::Deleted' : 'Alzabo::Exception::NoSuchRow';
    $e = $@;
    isa_ok( $e, $expect,
	    "Exception thrown from attempt to select from deleted row" );

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

    {
	my @emps = $emp_t->all_rows( order_by => { columns => $emp_t->column('smell'),
						   sort => 'desc' },
				     limit => [2, 2] )->all_rows;

	my $smell = $emps[0]->select('smell');
	is( $emp_t->row_count( where => [ $emp_t->column('smell'), '=', $smell ] ), 1,
	    "Call row_count method with where parameter." );

	$emps[0]->delete;
	eval { $emps[0]->update( smell => 'kaboom' ); };
	$expect = $Alzabo::ObjectCache::VERSION ? 'Alzabo::Exception::Cache::Deleted' : 'Alzabo::Exception::NoSuchRow';
	$e = $@;
	isa_ok( $e, $expect,
		"Exception thrown from attempt to update a deleted row" );

	my $row_id = $emps[1]->id_as_string;
	my $row;
	eval_ok( sub { $row = $emp_t->row_by_id( row_id => $row_id ) },
		 "Fetch a row via the ->row_by_id method" );
	is( $row->id_as_string, $emps[1]->id_as_string,
	    "Row retrieved via the ->row_by_id method should be the same as the row whose id was used" );
    }

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

    {
	my @emps = $emp_t->rows_where( where => [ [ $eid_c, '=', 9000 ],
						  'or',
						  [ $eid_c, '=', 9002 ] ] )->all_rows;

	@emps = sort { $a->select('employee_id') <=> $b->select('employee_id') } @emps;

	is( @emps, 2,
	    "Do a query with 'or' and count the rows" );
	is( $emps[0]->select('employee_id'), 9000,
	    "First row returned should be employee id 9000" );

	is( $emps[1]->select('employee_id'), 9002,
	    "Second row returned should be employee id 9002" );
    }

    {
	my @emps = $emp_t->rows_where( where => [ [ $emp_t->column('smell'), '!=', 'c' ],
						  'and',
						  (
						   '(',
						   [ $eid_c, '=', 9000 ],
						   'or',
						   [ $eid_c, '=', 9002 ],
						   ')',
						  ),
						] )->all_rows;
	is( @emps, 1,
	    "Do another complex query with 'or' and subgroups" );
	is( $emps[0]->select('employee_id'), 9000,
	    "The row returned should be employee id 9000" );
    }

    {
	my @emps = $emp_t->rows_where( where => [ (
						   '(',
						   [ $eid_c, '=', 9000 ],
						   'and',
						   [ $eid_c, '=', 9000 ],
						   ')',
						  ),
						  'or',
						  (
						   '(',
						   [ $eid_c, '=', 9000 ],
						   'and',
						   [ $eid_c, '=', 9000 ],
						   ')',
						  ),
						] )->all_rows;

	is( @emps, 1,
	    "Do another complex query with 'or', 'and' and subgroups" );
	is( $emps[0]->select('employee_id'), 9000,
	    "The row returned should be employee id 9000" );
    }

    {
	my @emps = $emp_t->rows_where( where => [ $eid_c, 'between', 9000, 9002 ] )->all_rows;
	@emps = sort { $a->select('employee_id') <=> $b->select('employee_id') } @emps;

	is( @emps, 3,
	    "Select using between should return 3 rows" );
	is( $emps[0]->select('employee_id'), 9000,
	    "First row returned should be employee id 9000" );
	is( $emps[1]->select('employee_id'), 9001,
	    "Second row returned should be employee id 9001" );
	is( $emps[2]->select('employee_id'), 9002,
	    "Third row returned should be employee id 9002" );
    }

    {
	my @emps;
	eval_ok( sub { @emps = $emp_t->rows_where( where => [ '(', '(',
							      [ $eid_c, '=', 9000 ],
							      ')', ')'
							    ] )->all_rows },
		 "Nested subgroups should be allowed" );

	is( @emps, 1,
	    "Query with nested subgroups should return 1 row" );
	is( $emps[0]->select('employee_id'), 9000,
	    "The row returned should be employee id 9000" );
    }

    $emp_t->insert( values => { name => 'Smelly',
				smell => 'a',
				dep_id => $dep_id,
			      } );

    {
	my @emps = eval { $emp_t->rows_where( where => [ LENGTH( $emp_t->column('smell') ), '=', 1 ] )->all_rows };

	is( @emps, 4,
	    "There should be only 4 employees where the length of the smell column is 1" );
    }

    {
	my @emps;
	eval_ok( sub { @emps = $emp_t->rows_where( where => [ LENGTH( $emp_t->column('smell') ), '=', 1 ],
						   limit => 2 )->all_rows },
		 "Select all employee rows with WHERE and LIMIT" );

	is( scalar @emps, 2,
	    "Limit should cause only two employee rows to be returned" );
    }

    {
	my @emps;
	eval_ok( sub { @emps = $emp_t->rows_where( where => [ LENGTH( $emp_t->column('smell') ), '=', 1 ],
						   order_by => { columns => $emp_t->column('smell') },
						   limit => 2 )->all_rows },
		 "Select all employee rows with WHERE, ORDER BY, and LIMIT" );

	is( scalar @emps, 2,
	    "Limit should cause only two employee rows to be returned (again)" );
    }

    {
	my @emps;
	eval_ok( sub { @emps = $emp_t->rows_where( where => [ '(',
							      [ $emp_t->column('employee_id'), '=', 9000 ],
							      ')',
							    ],
						   order_by => $emp_t->column('employee_id') )->all_rows },
		 "Query with subgroup followed by order by" );

	is( @emps, 1,
	    "Query with subgroup followed by order by should return 1 row" );
	is( $emps[0]->select('employee_id'), 9000,
	    "The row returned should be employee id 9000" );
    }

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

    $statement = $emp_t->select( select => [ $emp_t->column('smell'), COUNT( $emp_t->column('smell') ) ],
				 group_by => $emp_t->column('smell') );

    @smells = $statement->all_rows;

    # map smell to count
    %smells = map { $_->[0] => $_->[1] } @smells;
    is( @smells, 6,
	"Query with group by should return 6 values - via ->select" );
    is( $smells{a}, 2,
	"Check count of smell = 'a' - via ->select" );
    is( $smells{b}, 1,
	"Check count of smell = 'b' - via ->select" );
    is( $smells{c}, 1,
	"Check count of smell = 'c' - via ->select" );
    is( $smells{awful}, 1,
	"Check count of smell = 'awful' - via ->select" );
    is( $smells{good}, 1,
	"Check count of smell = 'good' - via ->select" );
    is( $smells{horrid}, 1,
	"Check count of smell = 'horrid' - via ->select" );

    @rows = $emp_t->function( select => $emp_t->column('smell'),
			      where => [ LENGTH( $emp_t->column('smell') ), '=', 1 ],
			      order_by => $emp_t->column('smell') );
    is( @rows, 4,
	"There should only be four rows which have a single character smell" );
    is( $rows[0], 'a',
	"First smell should be 'a'" );
    is( $rows[1], 'a',
	"Second smell should be 'a'" );
    is( $rows[2], 'b',
	"Third smell should be 'b'" );
    is( $rows[3], 'c',
	"Fourth smell should be 'c'" );

    $statement = $emp_t->select( select => $emp_t->column('smell'),
				 where => [ LENGTH( $emp_t->column('smell') ), '=', 1 ],
				 order_by => $emp_t->column('smell') );
    @rows = $statement->all_rows;

    is( @rows, 4,
	"There should only be four rows which have a single character smell - via ->select" );
    is( $rows[0], 'a',
	"First smell should be 'a' - via ->select" );
    is( $rows[1], 'a',
	"Second smell should be 'a' - via ->select" );
    is( $rows[2], 'b',
	"Third smell should be 'b' - via ->select" );
    is( $rows[3], 'c',
	"Fourth smell should be 'c' - via ->select" );

    @rows = $emp_t->function( select => $emp_t->column('smell'),
			      where => [ LENGTH( $emp_t->column('smell') ), '=', 1 ],
			      order_by => $emp_t->column('smell'),
			      limit => 2,
			    );
    is( @rows, 2,
	"There should only be two rows which have a single character smell - with limit" );
    is( $rows[0], 'a',
	"First smell should be 'a' - with limit" );
    is( $rows[1], 'a',
	"Second smell should be 'a' - with limit" );

    $statement = $emp_t->select( select => $emp_t->column('smell'),
				 where => [ LENGTH( $emp_t->column('smell') ), '=', 1 ],
				 order_by => $emp_t->column('smell'),
				 limit => 2,
			       );
    @rows = $statement->all_rows;

    is( @rows, 2,
	"There should only be two rows which have a single character smell -  with limit via ->select" );
    is( $rows[0], 'a',
	"First smell should be 'a' - with limit via ->select" );
    is( $rows[1], 'a',
	"Second smell should be 'a' - with limit via ->select" );

    foreach ( [ 9000, 1 ], [ 9000, 2 ], [ 9001, 1 ], [ 9002, 1 ] )
    {
	$emp_proj_t->insert( values => { employee_id => $_->[0],
					 project_id => $_->[1] } );
    }

    # find staffed projects
    @rows = $s->function( select => [ $proj_t->column('name'),
				      COUNT( $proj_t->column('name') ) ],
			  tables => [ $emp_proj_t, $proj_t ],
			  group_by => $proj_t->column('name') );
    is( @rows, 2,
	"Only two projects should be returned from schema->function" );
    is( $rows[0][0], 'Embrace',
	"First project should be Embrace" );
    is( $rows[1][0], 'Extend',
	"Second project should be Extend" );
    is( $rows[0][1], 1,
	"First project should have 1 employee" );
    is( $rows[1][1], 3,
	"Second project should have 3 employees" );

    $statement = $s->select( select => [ $proj_t->column('name'),
					 COUNT( $proj_t->column('name') ) ],
			     tables => [ $emp_proj_t, $proj_t ],
			     group_by => $proj_t->column('name') );
    @rows = $statement->all_rows;

    is( @rows, 2,
	"Only two projects should be returned from schema->select" );
    is( $rows[0][0], 'Embrace',
	"First project should be Embrace - via ->select" );
    is( $rows[1][0], 'Extend',
	"Second project should be Extend - via ->select" );
    is( $rows[0][1], 1,
	"First project should have 1 employee - via ->select" );
    is( $rows[1][1], 3,
	"Second project should have 3 employees - via ->select" );

    @rows = $s->function( select => [ $proj_t->column('name'),
				      COUNT( $proj_t->column('name') ) ],
			  tables => [ $emp_proj_t, $proj_t ],
			  group_by => $proj_t->column('name'),
			  limit => [1, 1],
			);
    is( @rows, 1,
	"Only one projects should be returned from schema->function - with limit" );
    is( $rows[0][0], 'Extend',
	"First project should be Extend - with limit" );
    is( $rows[0][1], 3,
	"First project should have 3 employees - with limit" );

    $statement = $s->select( select => [ $proj_t->column('name'),
					 COUNT( $proj_t->column('name') ) ],
			     tables => [ $emp_proj_t, $proj_t ],
			     group_by => $proj_t->column('name'),
			     limit => [1, 1],
			   );
    @rows = $statement->all_rows;

    is( @rows, 1,
	"Only one projects should be returned from schema->select - with limit via ->select" );
    is( $rows[0][0], 'Extend',
	"First project should be Extend - with limit via ->select" );
    is( $rows[0][1], 3,
	"First project should have 3 employees - with limit via ->select" );

    {
	my @rows = $s->function( select => [ $proj_t->column('name'),
					     COUNT( $proj_t->column('name') ) ],
				 tables => [ $emp_proj_t, $proj_t ],
				 group_by => $proj_t->column('name'),
				 order_by => [ COUNT( $proj_t->column('name') ), 'DESC' ] );

	is( @rows, 2,
	    "Only two projects should be returned from schema->function ordered by COUNT(*)" );
	is( $rows[0][0], 'Extend',
	    "First project should be Extend" );
	is( $rows[1][0], 'Embrace',
	    "Second project should be Embrace" );
	is( $rows[0][1], 3,
	    "First project should have 3 employee" );
	is( $rows[1][1], 1,
	    "Second project should have 1 employees" );
    }

    my $p1 = $proj_t->insert( values => { name => 'P1',
					  department_id => $dep_id,
					} );
    my $p2 = $proj_t->insert( values => { name => 'P2',
					  department_id => $dep_id,
					} );

    eval_ok( sub { $cursor = $s->join( distinct => $dep_t,
				       join     => [ $dep_t, $proj_t ],
				       where    => [ $proj_t->column('project_id'), 'in',
						     map { $_->select('project_id') } $p1, $p2 ],
				     ) },
	     "Do a join with distinct parameter set" );

    @rows = $cursor->all_rows;

    is( scalar @rows, 1,
	"Setting distinct should cause only a single row to be returned" );

    is( $rows[0]->select('department_id'), $dep_id,
	"Returned row's department_id should be $dep_id" );

    # insert rows used to test order by with multiple columns
    my $start_id = 999_990;
    foreach ( [ qw( OB1 bad ) ],
	      [ qw( OB1 worse ) ],
	      [ qw( OB2 bad ) ],
	      [ qw( OB2 worse ) ],
	      [ qw( OB3 awful ) ],
	      [ qw( OB3 bad ) ],
	    )
    {
	$emp_t->insert( values => { employee_id => $start_id++,
				    name => $_->[0],
				    smell => $_->[1],
				    dep_id => $dep_id } );
    }

    @rows = $emp_t->rows_where( where => [ $emp_t->column('employee_id'), 'BETWEEN',
					   999_990, 999_996 ],
				order_by => [ $emp_t->columns( 'name', 'smell' ) ] )->all_rows;
    is( $rows[0]->select('name'), 'OB1',
	"First row name should be OB1" );
    is( $rows[0]->select('smell'), 'bad',
	"First row smell should be bad" );
    is( $rows[1]->select('name'), 'OB1',
	"Second row name should be OB1" );
    is( $rows[1]->select('smell'), 'worse',
	"Second row smell should be bad" );
    is( $rows[2]->select('name'), 'OB2',
	"Third row name should be OB2" );
    is( $rows[2]->select('smell'), 'bad',
	"Third row smell should be bad" );
    is( $rows[3]->select('name'), 'OB2',
	"Fourth row name should be OB2" );
    is( $rows[3]->select('smell'), 'worse',
	"Fourth row smell should be worse" );
    is( $rows[4]->select('name'), 'OB3',
	"Fifth row name should be OB3" );
    is( $rows[4]->select('smell'), 'awful',
	"Fifth row smell should be awful" );
    is( $rows[5]->select('name'), 'OB3',
	"Sixth row name should be OB3" );
    is( $rows[5]->select('smell'), 'bad',
	"Sixth row smell should be bad" );

    @rows = $emp_t->rows_where( where => [ $emp_t->column('employee_id'), 'BETWEEN',
					   999_990, 999_996 ],
				order_by => [ $emp_t->column('name'), 'desc', $emp_t->column('smell'), 'asc' ] )->all_rows;
    is( $rows[0]->select('name'), 'OB3',
	"First row name should be OB3" );
    is( $rows[0]->select('smell'), 'awful',
	"First row smell should be awful" );
    is( $rows[1]->select('name'), 'OB3',
	"Second row name should be OB3" );
    is( $rows[1]->select('smell'), 'bad',
	"Second row smell should be bad" );
    is( $rows[2]->select('name'), 'OB2',
	"Third row name should be OB2" );
    is( $rows[2]->select('smell'), 'bad',
	"Third row smell should be bad" );
    is( $rows[3]->select('name'), 'OB2',
	"Fourth row name should be OB2" );
    is( $rows[3]->select('smell'), 'worse',
	"Fourth row smell should be worse" );
    is( $rows[4]->select('name'), 'OB1',
	"Fifth row name should be OB1" );
    is( $rows[4]->select('smell'), 'bad',
	"Fifth row smell should be bad" );
    is( $rows[5]->select('name'), 'OB1',
	"Sixth row name should be OB1" );
    is( $rows[5]->select('smell'), 'worse',
	"Sixth row smell should be worse" );

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

	# Fulltext support tests
	my $snuffle_id = $emp_t->insert( values => { name => 'snuffleupagus',
						     smell => 'invisible',
						     dep_id => $dep_id } )->select('employee_id');

	@rows = $emp_t->rows_where( where => [ MATCH( $emp_t->column('name') ), AGAINST('abathraspus') ] )->all_rows;
	is( @rows, 0,
	    "Make sure that fulltext search doesn't give a false positive" );

	@rows = $emp_t->rows_where( where => [ MATCH( $emp_t->column('name') ), AGAINST('snuffleupagus') ] )->all_rows;
	is( @rows, 1,
	    "Make sure that fulltext search for snuffleupagus returns 1 row" );
	is( $rows[0]->select('employee_id'), $snuffle_id,
	    "Make sure that the returned row is snuffleupagus" );

	my $rows = $emp_t->function( select => [ $emp_t->column('employee_id'), MATCH( $emp_t->column('name') ), AGAINST('snuffleupagus') ],
				     where => [ MATCH( $emp_t->column('name') ), AGAINST('snuffleupagus') ] );
	my ($id, $score) = @$rows;
	is( $id, $snuffle_id,
	    "Returned row should still be snuffleupagus" );
	like( $score, qr/\d+(?:\.\d+)?/,
	      "Returned score should be some sort of number (integer or floating point)" );
	ok( $score > 0,
	    "The score should be greater than 0 because the match was successful" );

	eval_ok( sub { @rows = $emp_t->all_rows( order_by => [ IF( 'employee_id < 100',
								   $emp_t->column('employee_id'),
								   $emp_t->column('smell'), ) ],
					       )->all_rows },
		 "Order by IF() function" );
	is( @rows, 16,
	    "Seventeen rows should have been returned" );
	is( $rows[0]->select('employee_id'), 3,
	    "First row should be id 3" );
	is( $rows[-1]->select('employee_id'), 999993,
	    "Last row should be id 999993" );

	eval_ok( sub { @rows = $emp_t->all_rows( order_by => RAND() )->all_rows },
		 "order by RAND()" );
	is ( @rows, 16,
	     "This should return 16 rows" );
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

    # Potential rows
    my $p_emp;
    eval_ok( sub { $p_emp = $emp_t->potential_row },
	     "Create potential row object");

    is( $p_emp->select('smell'), 'grotesque',
	"Potential Employee should have default smell, 'grotesque'" );

    $p_emp->update( cash => undef, smell => 'hello!' );
    ok( ! defined $p_emp->select('cash'),
	"Potential Employee cash column is not defined" );

    is( $p_emp->select('smell'), 'hello!',
	"smell for employee should be 'hello!' after update" );

    $p_emp->update( name => 'Ilya' );
    is( $p_emp->select('name'), 'Ilya',
        "New employee got a name" );

    $p_emp->update( dep_id => $dep_id );
    is( $p_emp->select('dep_id'), $dep_id,
        "New employee got a department" );

    eval { $p_emp->update( wrong => 'column' ) };
    $e = $@;
    isa_ok( $e, 'Alzabo::Exception::Params',
	    "Exception thrown from attempt to update a column which doesn't exist" );

    eval { $p_emp->update( name => undef ) };
    $e = $@;
    isa_ok( $e, 'Alzabo::Exception::Params',
	    "Exception thrown from attempt to update a non-NULLable column in a potential row to null" );

    eval { $p_emp->delete };
    $e = $@;
    isa_ok( $e, 'Alzabo::Exception::Logic',
	    "Exception thrown from attempt to delete a potential row object" );

    eval_ok( sub { $p_emp->make_live( values => { smell => 'cottony' } ) },
	     "Make potential row live");

    is( $p_emp->select('name'), 'Ilya',
        "Formerly potential employee row object should have same name as before" );

    is( $p_emp->select('smell'), 'cottony',
        "Formerly potential employee row object should have new smell of 'cottony'" );

    eval_ok ( sub { $p_emp->delete },
	      "Delete new employee" );

    eval_ok( sub { $p_emp = $emp_t->potential_row( values => { cash => 100 } ) },
	     "Create potential row object and set some fields ");

    is( $p_emp->select('cash'), 100,
	"Employee cash should be 100" );

    if ( $ENV{OBJECTCACHE_PARAMS} )
    {
	eval_ok( sub { Alzabo::ObjectCache->clear },
		 "Call ->clear on object cache" );
    }
    else
    {
	ok(1, "Dummy for ->clear without a cache");
    }

    eval { $emp_t->rows_where( where => [ $eid_c, '=', 9000,
					  $eid_c, '=', 9002 ] ) };
    $e = $@;
    isa_ok( $e, 'Alzabo::Exception::Params',
	    "Exception from where clause as single arrayref with <>3 elements" );
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
    my $e = $@;
    isa_ok( $e, 'Alzabo::Exception::Cache::Deleted',
	    "Exception thrown from attempt to select from deleted row" );

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
    is( $@ ? 1 : 0, 0,
	"No exception should be thrown from attempt to update row recently retrieved from cache" );
    is( $emp2->select('name'), 'newname3',
	"emp2 name should now be 'newname3'" );

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

    $rocko->update( name => 'Bullo' );

    # W.
    print $c_write "1\n";

    # X.
    ($ok, $name) = parse_child_response( get_pipe_data($c_read) );
    ok($ok, $name);

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

    # use select_hash to make sure it checks the cache
    $tag = "Employee row's name for pk $pk should be 'parent2'.  It is '" . {$emp->select_hash('name')}->{name} . "'";
    print $p_write ( {$emp->select_hash('name')}->{name} eq 'parent2' ? "1:$tag" : "0:$tag" );
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
    $tag = 'Attempting to update an expired row should throw an Alzabo::Exception::Cache::Expired exception';
    my $ok = ref $@ && ref $@ eq 'Alzabo::Exception::Cache::Expired';
    print $p_write( $@ ? "1:$tag" : "0:$tag: $@" );
    print $p_write "\n";

    # M.
    get_pipe_data($p_read);

    # N.
    $tag = "Name should be 'newname3'. It is " . $emp2->select('name');
    print $p_write( $emp2->select('name') eq 'newname3' ?
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

    # W.
    get_pipe_data($p_read);

    # X.
    $tag = "Rocko's name should now be 'Bullo'.  It is '" . $e1000->select('name') . "'";
    print $p_write ( $e1000->select('name') eq 'Bullo' ? "1:$tag" : "0:$tag" );
    print $p_write "\n";

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
