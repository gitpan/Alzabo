use strict;

use Alzabo::Create;
use Alzabo::Runtime;

use lib '.', './t';

require 'base.pl';

BEGIN
{
    if (my $c_params = eval $ENV{OBJECTCACHE_PARAMS})
    {
	require Alzabo::ObjectCache;
	Alzabo::ObjectCache->import( %$c_params );
    }
}

my $p = eval $ENV{CURRENT_TEST};

my $s = Alzabo::Runtime::Schema->load_from_file( name => $p->{db_name} );

$main::COUNT = $ENV{TEST_START_NUM};
$main::COUNT = $ENV{TEST_START_NUM};

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

    eval { $s->set_user('foo') };
    ok( ! $@,
	"Unable to set user to 'foo': $@" );

    eval { $s->set_password('foo'); };
    ok( ! $@,
	"Unable to set password to 'foo': $@" );

    eval { $s->set_host('foo'); };
    ok( ! $@,
	"Unable to set host to 'foo': $@" );

    $s->$_(undef) foreach qw( set_user set_password set_host );

    $s->set_user($p{user}) if $p{user};
    $s->set_password($p{password}) if $p{password};
    $s->set_host($p{host}) if $p{host};
    $s->set_referential_integrity(1);
    $s->connect;

    my $emp_t = $s->table('employee');
    my $dep_t = $s->table('department');
    my $proj_t = $s->table('project');
    my $emp_proj_t = $s->table('employee_project');

    my %dep;
    eval { $dep{borg} = $dep_t->insert( values => { name => 'borging' } ); };
    ok( ! $@,
	"Unable to insert row into department table: $@" );
    ok( $dep{borg}->select('name') eq 'borging',
	"The borg department name should be 'borging' but it's", $dep{borg}->select('name') );

    $dep{lying} = $dep_t->insert( values => { name => 'lying to the public' } );

    my $borg_id = $dep{borg}->select('department_id');
    delete $dep{borg};
    eval { $dep{borg} = $dep_t->row_by_pk( pk => $borg_id ); };

    ok( $dep{borg} && $dep{borg}->select('name') eq 'borging',
	"Department's name should be 'borging' but it's '" . $dep{borg}->select('name') . "'" );

    eval { $dep_t->insert( values => { name => 'will break',
				       manager_id => 1 } ); };

    ok( $@ && $@->isa('Alzabo::Exception::ReferentialIntegrity'),
	"Attempt to insert a non-existent manager_id into department should have caused a referential integrity exception but we got '$@' instead" );

    my %emp;
    eval { $emp{bill} = $emp_t->insert( values => { name => 'Big Bill',
						    department_id => $borg_id,
						    smell => 'robotic',
						    cash => 20.2,
						  } ); };
    ok( ! $@,
	"Unable to insert row into employee table: $@" );

    eval { $emp_t->insert( values => { name => undef,
				       department_id => $borg_id,
				       smell => 'robotic',
				       cash => 20.2,
				     } )->delete; };
    ok( $@ && $@->isa('Alzabo::Exception::Params'),
	"Inserting a non-nullable column as NULL should have produced an Alzabo::Exception::Params exception: $@" );

    eval { $emp_t->insert( values => { name => 'asfalksf',
				       department_id => $borg_id,
				       smell => undef,
				       cash => 20.2,
				     } )->delete; };
    ok( ! $@,
	"Inserting a non-nullable column with a default as NULL should not have produced an exception: $@" );

    $emp{bill}->update( cash => undef, smell => 'hello!' );
    ok( ! defined $emp{bill}->select('cash'),
	"cash for bill should be NULL but it's", $emp{bill}->select('cash') );

    ok( $emp{bill}->select('smell') eq 'hello!',
	"smell for bill should be 'hello!' but it's", $emp{bill}->select('smell') );

    eval { $emp{bill}->update( name => undef ) };
    ok( $@ && $@->isa('Alzabo::Exception::Params'),
	 "Attempt to update a non-nullable column to NULL should have produced an Alzabo::Exception::Params exception: $@" );

    eval { $dep{borg}->update( manager_id => $emp{bill}->select('employee_id') ); };
    ok( ! $@,
	"Unable to set manager_id column for borg department: $@" );

    eval { $emp{2} = $emp_t->insert( values => { name => 'unit 2',
						 smell => 'good',
						 department_id => $dep{lying}->select('department_id') } ); };
    ok( ! $@,
	"Unable to create employee 'unit 2': $@" );

    my $emp2_id = $emp{2}->select('employee_id');
    delete $emp{2};

    my $cursor;
    my $x = 0;
    eval { $cursor = $emp_t->rows_where( where => [ $emp_t->column('employee_id'), '=', $emp2_id ] );
	   while ( my $row = $cursor->next_row )
	   {
	       $x++;
	       $emp{2} = $row;
	   } };

    ok( ! $@,
	"Unable to retrieve 'unit 2' employee via rows_where method and cursor: $@" );

    ok( ! $cursor->errors,
	"Unable to retrieve 'unit 2' employee via rows_where method and cursor: ", join ' ', $cursor->errors );
    ok( $x == 1,
	"More than one row was found where employee_id == $emp2_id (found $x)" );

    ok( $emp{2}->select('name') eq 'unit 2',
	"An employee row was found but its name is ", $emp{2}->select('name'), ", not 'unit 2'");


    my %proj;
    $proj{extend} = $proj_t->insert( values => { name => 'Extend',
						 department_id => $dep{borg}->select('department_id') } );
    $proj{embrace} = $proj_t->insert( values => { name => 'Embrace',
						  department_id => $dep{borg}->select('department_id')  } );

    $emp_proj_t->insert( values => { employee_id => $emp{bill}->select('employee_id'),
				     project_id  => $proj{extend}->select('project_id') } );

    my $fk = $emp_t->foreign_keys_by_table($emp_proj_t);
    $x = 0;
    my @emp_proj;
    eval { $cursor = $emp{bill}->rows_by_foreign_key( foreign_key => $fk );
	   while ( my $row = $cursor->next_row )
	   {
	       $x++;
	       push @emp_proj, $row;
	   } };
    ok( ! $@ && ! $cursor->errors && $x == 1 && @emp_proj == 1 &&
	$emp_proj[0]->select('employee_id') == $emp{bill}->select('employee_id') &&
	$emp_proj[0]->select('project_id') == $proj{extend}->select('project_id'),
	"Attempt to fetch rows by foreign key failed: $@" );

    $x = 0;
    my @rows;
    eval { $cursor = $emp_t->all_rows;
	   while ( my $row = $cursor->next_row )
	   {
	       $x++;
	   } };
    ok( ! $@ && ! $cursor->errors && $x == 2,
	"The employee table had $x rows but should have had 2" );

    $cursor->reset;
    my $count = $cursor->all_rows;
    ok( $count == 2 && ! $cursor->errors,
	"Cursor's all_rows method returned $count rows but should have returned 2" );

    $cursor = eval { $s->join( tables => [ $emp_t, $emp_proj_t, $proj_t ],
			       where =>  [ [ $emp_t->column('employee_id'), '=', 1 ] ] ) };
    ok( ! $@,
	"Join threw an exception: $@" );

    @rows = $cursor->next_rows;
    ok( scalar @rows == 3 &&
	$rows[0]->table->name eq 'employee' &&
	$rows[1]->table->name eq 'employee_project' &&
	$rows[2]->table->name eq 'project',
	"Join cursor did not return rows in expected order or did not return 3 rows" );

    my $id = $emp{bill}->select('employee_id');
    $emp{bill}->delete;

    eval { my $c = $emp_t->row_by_pk( pk => $id ) };
    ok( $@ && $@->isa('Alzabo::Exception::NoSuchRow' ),
	 "There should be no bill row in the employee table" );

    eval { $emp{bill}->select('name'); };
    my $expect = $Alzabo::ObjectCache::VERSION ? 'Alzabo::Exception::Cache::Deleted' : 'Alzabo::Exception::NoSuchRow';
    ok( $@ && $@->isa($expect),
        "Attempt to select from deleted row object should have thrown a $expect exception but threw: $@" );

    eval { $emp_proj_t->row_by_pk( pk => { employee_id => $id,
					   project_id => $proj{extend}->select('project_id') } ); };
    # 5.6.0 is broken and gives a wack error here
    ok( $@ && ( $@->isa('Alzabo::Exception::NoSuchRow') || $] == 5.006 ),
	 "There should be no bill/extend row in the employee_project table: $@" );

    ok( ! defined $dep{borg}->select('manager_id'),
	"The manager_id for the borg department should be NULL but it's", $dep{borg}->select('manager_id') );

    my $dep_id = $dep{borg}->select('department_id');

    $emp_t->insert( values => { name => 'bob', smell => 'awful', department_id => $dep_id } );
    $emp_t->insert( values => { name => 'rachel', smell => 'horrid', department_id => $dep_id } );
    $emp_t->insert( values => { name => 'al', smell => 'bad', department_id => $dep_id } );

    my @emps = eval { $emp_t->all_rows( order_by => { columns => $emp_t->column('name') } )->all_rows };
    ok( ! $@, "Error attempting to select all rows with ORDER BY: $@" );
    ok( scalar @emps == 4,
	"There are ", scalar @emps, " employee table rows rather than 4" );
    ok( $emps[0]->select('name') eq 'al' &&
	 $emps[1]->select('name') eq 'bob' &&
	 $emps[2]->select('name') eq 'rachel' &&
	 $emps[3]->select('name') eq 'unit 2',
	 "The rows returned from the ORDER BY query do not appear to be ordered alphabetically by name" );

    @emps = eval { $emp_t->all_rows( order_by => $emp_t->column('name') )->all_rows };
    ok( ! $@, "Error attempting to select all rows with ORDER BY: $@" );
    ok( scalar @emps == 4,
	"There are ", scalar @emps, " employee table rows rather than 4" );
    ok( $emps[0]->select('name') eq 'al' &&
	 $emps[1]->select('name') eq 'bob' &&
	 $emps[2]->select('name') eq 'rachel' &&
	 $emps[3]->select('name') eq 'unit 2',
	 "The rows returned from the ORDER BY query do not appear to be ordered alphabetically by name" );

    @emps = eval { $emp_t->all_rows( order_by => [ $emp_t->column('name') ] )->all_rows };
    ok( ! $@, "Error attempting to select all rows with ORDER BY: $@" );
    ok( scalar @emps == 4,
	"There are ", scalar @emps, " employee table rows rather than 4" );
    ok( $emps[0]->select('name') eq 'al' &&
	 $emps[1]->select('name') eq 'bob' &&
	 $emps[2]->select('name') eq 'rachel' &&
	 $emps[3]->select('name') eq 'unit 2',
	 "The rows returned from the ORDER BY query do not appear to be ordered alphabetically by name" );

    @emps = eval { $emp_t->all_rows( order_by => { columns => $emp_t->column('smell') } )->all_rows };
    ok( ! $@, "Error attempting to select all rows with ORDER BY (2): $@" );
    ok( scalar @emps == 4,
	"There are", scalar @emps, "employee table rows rather than 4" );
    ok( $emps[0]->select('name') eq 'bob' &&
	 $emps[1]->select('name') eq 'al' &&
	 $emps[2]->select('name') eq 'unit 2' &&
	 $emps[3]->select('name') eq 'rachel',
	 "The rows returned from the ORDER BY query do not appear to be ordered alphabetically by smell" );

    @emps = eval { $emp_t->all_rows( order_by => { columns => $emp_t->column('smell'),
						   sort => 'desc' } )->all_rows };
    ok( ! $@, "Error attempting to select all rows with ORDER BY (3): $@" );
    ok( scalar @emps == 4,
	"There are", scalar @emps, "employee table rows rather than 4" );
    ok( $emps[0]->select('name') eq 'rachel' &&
	 $emps[1]->select('name') eq 'unit 2' &&
	 $emps[2]->select('name') eq 'al' &&
	 $emps[3]->select('name') eq 'bob',
	 "The rows returned from the ORDER BY query do not appear to be reverse ordered alphabetically by smell" );

    $count = eval { $emp_t->row_count; };

    ok( ! $@, "Error attempting to get row count: $@" );
    ok( $count == 4,
	"There are $count employee table rows rather than 4" );

    $count = eval { $emp_t->func( func => 'COUNT', args => $emp_t->column('employee_id') ); };

    ok( ! $@, "Error attempting to get row count via func method: $@" );
    ok( $count == 4,
	"There are $count employee table rows rather than 4" );

    @emps = eval { $emp_t->all_rows( order_by => { columns => $emp_t->column('smell'),
						   sort => 'desc' },
				     limit => 2 )->all_rows };

    ok( ! $@, "Error attempting to select all rows with ORDER BY & LIMIT: $@" );
    ok( scalar @emps == 2,
	"There are", scalar @emps, "employee table rows rather than 2" );
    ok( $emps[0] && $emps[0]->select('name') eq 'rachel' &&
	 $emps[1] && $emps[1]->select('name') eq 'unit 2',
	 "The rows returned from the ORDER BY & LIMIT query do not appear to be reverse ordered alphabetically by smell" );

    @emps = eval { $emp_t->all_rows( order_by => { columns => $emp_t->column('smell'),
						   sort => 'desc' },
				     limit => [2, 2] )->all_rows };
    ok( ! $@, "Error attempting to select all rows with ORDER BY & LIMIT: $@" );
    ok( scalar @emps == 2,
	"There are", scalar @emps, "employee table rows rather than 2" );
    ok( $emps[0] && $emps[0]->select('name') eq 'al' &&
	 $emps[1] && $emps[1]->select('name') eq 'bob',
	 "The rows returned from the ORDER BY & LIMIT query do not appear to be reverse ordered alphabetically by smell (or the offset is not being respected)" );

    my $char_row = eval { $s->table('char_pk')->insert( values => { char_col => 'pk value' } ); };
    ok( ! $@,
	"Insert into char_pk table threw exception: $@" );

    $char_row->delete;
    eval { $s->table('char_pk')->row_by_pk( pk => 'pk value' ); };
    # 5.6.0 is broken and gives a wack error here
    ok( $@ && ( $@->isa('Alzabo::Exception::NoSuchRow') || $] == 5.006 ),
	 "Attempt to fetch deleted row should have thrown an Alzabo::Exception::NoSuchRow exception but threw: $@" );

    my $val;
    eval { $char_row->select('char_col'); };
    my $expect = $Alzabo::ObjectCache::VERSION ? 'Alzabo::Exception::Cache::Deleted' : 'Alzabo::Exception::NoSuchRow';
    ok( $@ && $@->isa($expect),
	"Attempt to select from deleted row should have thrown an $expect exception but threw: $@" );

    $char_row = eval { $s->table('char_pk')->insert( values => { char_col => 'pk value' } ); };
    ok( ! $@,
	"Insert into char_pk table threw exception: $@" );

    eval { $s->table('char_pk')->row_by_pk( pk => 'pk value' ); };
    ok( ! $@,
	 "Attempt to fetch char_pk row where char => 'pk value' threw an exception: $@" );

    my $val;
    eval { $val = $char_row->select('char_col'); };
    ok( ! $@,
	 "Attempt to select from char_pk row threw an exception: $@" );
    ok( defined $val && $val eq 'pk value',
	"char column in char_pk should be 'pk value' but it is '$val'" );

    $emp_t->set_prefetch( $emp_t->columns( qw( name smell ) ) );
    my @p = $emp_t->prefetch;
    ok( ( @p == 2 && grep { $_ eq 'name' } @p && grep { $_ eq 'smell' } @p ),
	"Prefetch should have returned two columns, 'name' and 'smell'.  But it returned @p" );

    ok( $emp_t->row_count == 4,
	"emp_t table should have 4 rows but it reports it has ", $emp_t->row_count );

    my $smell = $emps[0]->select('smell');
    ok( $emp_t->row_count( where => [ $emp_t->column('smell'), '=', $smell ] ) == 1,
	"emp_t table should have 1 row where smell is '$smell' but it reports it has ",
	$emp_t->row_count( where => [ $emp_t->column('smell'), '=', $smell ] ) );

    $emps[0]->delete;
    eval { $emps[0]->update( smell => 'kaboom' ); };
    $expect = $Alzabo::ObjectCache::VERSION ? 'Alzabo::Exception::Cache::Deleted' : 'Alzabo::Exception::NoSuchRow';
    ok( $@ && $@->isa($expect),
	"Attempt to update a deleted row should have throw a $expect exception but threw: $@" );

    my $row_id = $emps[1]->id;
    my $row = eval { $emp_t->row_by_id( row_id => $row_id ) };
    ok( ! $@,
	"Attempting to fetch a row via the ->row_by_id method failed: $@" );
    ok( $row->id eq $emps[1]->id,
	"Row retrieved via the ->row_by_id method should be the same as the row whose id was used" );
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

    waitpid($pid, 0);
}

sub parent
{
    my $s = shift;

    close $p_read;
    close $p_write;

    $s->driver->disconnect;
    $s->connect;

    my $emp = eval { $s->table('employee')->insert( values => { name => 'parent',
								department_id => 1,
							      } ); };
    ok( ! $@,
	"Unable to insert new row into employee table: $@" );

    # A.
    print $c_write $emp->select('employee_id'), "\n";

    # B.
    my $res = get_pipe_data($c_read);
    ok( ! $res, $res );

    # C.
    $res = get_pipe_data($c_read);
    ok( ! $res, $res );

    $emp->update( name => 'parent2' );
    ok( $emp->select('name'),
	"Employee row's name in parent should be 'parent2' but it is '" . $emp->select('name') . "'" );

    # D.
    print $c_write "1\n";

    # E.
    $res = get_pipe_data($c_read);
    ok( ! $res, $res );

    $emp->delete;
    eval { $emp->select('name') };
    ok( $@ && $@->isa('Alzabo::Exception::Cache::Deleted'),
	"Attempt to select from deleted row should have caused an Alzabo::Exception::Cache::Deleted exception but we got: $@" );

    # F.
    print $c_write "1\n";

    # G.
    $res = get_pipe_data($c_read);
    ok( ! $res, $res );

    # H.
    my $emp2_id = get_pipe_data($c_read);
    my $emp2 = eval { $s->table('employee')->row_by_pk( pk => $emp2_id ); };
    ok( ! $@,
	"Unable to fetch employee row where employee_id = $emp2_id" );

    # I.
    print $c_write "1\n";

    # J.
    get_pipe_data($c_read);

    undef $emp2;

    # This should come from the cache.
    $emp2 = $s->table('employee')->row_by_pk( pk => $emp2_id );
    eval { $emp2->update( name => 'newname3' ); };
    ok( ! $@,
	"Attempt to update row immediate after update in child failed: $@" );

    # K.
    print $c_write "1\n";

    # L.
    $res = get_pipe_data($c_read);
    ok( ! $res, $res );

    # M.
    print $c_write "1\n";

    # N.
    $res = get_pipe_data($c_read);
    ok( ! $res, $res );

    my $emp3 = eval { $s->table('employee')->insert( values => { name => 'parent',
								 department_id => 1,
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
    $res = get_pipe_data($c_read);
    ok( ! $res, $res );

    # Q.
    print $c_write "1\n";

    # R.
    $res = get_pipe_data($c_read);
    ok( ! $res, $res );

    my $name = eval { $emp3->select('name') };
    ok( ! $@,
	"Attempt to get name from created/deleted/created row caused an error: $@" );

    ok( $name eq 'lazarus',
	"Employee3's name should be 'lazarus' but it is '$name'" );

    my $e1000 = eval { $s->table('employee')->insert( values => { employee_id => 1000,
								  name => 'alive1',
								  department_id => 1,
								} ); };
    $e1000->delete;

    # S.
    print $c_write "1\n";

    # T.
    get_pipe_data($c_read);

    my $new_name = eval { $e1000->select('name') };
    ok( ! $@,
	"Attempt to retrieve employee_id 1000 caused an error: $@" );

    ok( $new_name eq 'alive2',
	"Employee 1000's name should be 'alive2' but it is $new_name" );

    close $c_read;
    close $c_write;
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
    print $p_write ( $@ ?
		    "Unable to fetch row from employee table where employee_id = $pk: $@" :
		     0 );
    print $p_write "\n";

    # C.
    print $p_write ( $emp->select('name') eq 'parent' ?
		     0 :
		    "Employee row's name for pk $pk should be 'parent' but it is '" . $emp->select('name') . "'"
		   );
    print $p_write "\n";

    # D.
    get_pipe_data($p_read);

    # Cache sync should find that this process's object is expired and
    # refresh.

    # E.
    print $p_write ( $emp->select('name') eq 'parent2' ?
		     0 :
		    "Employee row's name for pk $pk should be 'parent2' but it is '" . $emp->select('name') . "'"
		   );
    print $p_write "\n";

    # F.
    get_pipe_data($p_read);

    eval { $emp->select('name') };

    # G.
    print $p_write ( $@ && $@->isa('Alzabo::Exception::Cache::Deleted') ?
		     0 :
		     "Attempt to select from deleted row should have caused an Alzabo::Exception::Cache::Deleted exception but we got: $@" );
    print $p_write "\n";

    my $emp2 = eval { $s->table('employee')->insert( values => { name => 'newname', department_id => 1 } ); };

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
    print $p_write( $@ ?
		    0 :
		    "Expected Alzabo::Exception::Cache::Expired exception but got: $@" );
    print $p_write "\n";

    # M.
    get_pipe_data($p_read);

    # N.
    print $p_write( eval { $emp2->select('name') eq 'newname3' } ?
		    0 :
		    ( $@ ?
		      "Attempt to select name threw exception: $@" :
		      "Name should be 'newname3' but it is " . $emp2->select('name') ) );
    print $p_write "\n";

    # O.
    my $emp3_id = get_pipe_data($p_read);

    my $emp3 = eval { $s->table('employee')->insert( values => { employee_id => $emp3_id,
								 name => 'lazarus',
								 department_id => 1,
							       } ); };

    # P.
    print $p_write( $@ ?
		    "Unable to insert another row with employee_id $emp3_id: $@" :
		    0 );
    print $p_write "\n";

    # Q.
    get_pipe_data($p_read);

    my $name = $emp3->select('name');

    # R.
    print $p_write( $name eq 'lazarus' ?
		    0 :
		    "emp3 name should be 'lazarus' but it is '$name'" );
    print $p_write "\n";

    # S.
    get_pipe_data($p_read);

    eval { $s->table('employee')->insert( values => { employee_id => 1000,
						      name => 'alive2',
						      department_id => 1,
						    } ); };

    # T.
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
    return $data;
}
