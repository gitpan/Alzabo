use strict;

use Alzabo::Create;
use Alzabo::Config;
use Alzabo::Runtime;

use Cwd;

my $count = 0;
$| = 1;

my $tests = eval $ENV{ALZABO_RDBMS_TESTS};
my $test_count = 20 * @$tests;
print "1..$test_count\n";

my $cwd = Cwd::cwd;
$Alzabo::Config::CONFIG{root_dir} = $cwd;

foreach (@$tests)
{
    my $s;
    {
	no strict 'refs';
	$s = &{ "$_->{rdbms}_make_schema" }(%$_);
    }

    print "Running $_->{rdbms} tests\n";
    eval { run_tests($s, %$_); };
    warn "Error running tests: $@" if $@;

    {
	no strict 'refs';
	&{ "$_->{rdbms}_clean_schema" }(%$_);
    }
}

sub run_tests
{
    my $s = shift;
    my %p = @_;

    eval { $s->set_user('foo') };
    ok ( ! $@,
	 "Unable to set user to 'foo': $@" );

    eval { $s->set_password('foo'); };
    ok ( ! $@,
	 "Unable to set password to 'foo': $@" );

    eval { $s->set_host('foo'); };
    ok ( ! $@,
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

    ok( $@ && $@->isa('AlzaboReferentialIntegrityException'),
	"Attempt to insert a non-existent manager_id into department should have caused a referential integrity exception but we got '$@' instead" );

    my %emp;
    eval { $emp{bill} = $emp_t->insert( values => { name => 'Big Bill',
						    department_id => $borg_id,
						    smell => 'robotic' } ); };
    ok( ! $@,
	"Unable to insert row into employee table: $@" );

    $emp{bill}->update( smell => undef );
    ok ( ! defined $emp{bill}->select('smell'),
	 "Smell for bill should be NULL but it's", $emp{bill}->select('smell') );

    eval { $dep{borg}->update( manager_id => $emp{bill}->select('employee_id') ); };
    ok( ! $@,
	"Unable to set employee_id column for borg department: $@" );

    eval { $emp{2} = $emp_t->insert( values => { name => 'unit 2',
						 department_id => $dep{lying}->select('department_id') } ); };
    ok( ! $@,
	"Unable to create employee 'unit 2': $@" );

    my $emp2_id = $emp{2}->select('employee_id');
    delete $emp{2};

    my $cursor;
    my $x = 0;
    eval { $cursor = $emp_t->rows_where( where => { employee_id => $emp2_id } );
	   while ( my $row = $cursor->next_row )
	   {
	       $x++;
	       $emp{2} = $row;
	   } };

    ok( ! $@ && ! $cursor->errors && $x == 1 && $emp{2}->select('name') eq 'unit 2',
	"Unable to retrieve 'unit 2' employee via rows_where method and cursor: $@" );

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

    $cursor = $s->join( tables => [ $emp_t, $emp_proj_t, $proj_t ],
			where =>  [ $emp_t->column('employee_id') => 1 ] );
    @rows = $cursor->next_rows;
    ok( scalar @rows == 3 &&
	$rows[0]->table->name eq 'employee' &&
	$rows[1]->table->name eq 'employee_project' &&
	$rows[2]->table->name eq 'project',
	"Join cursor did not return rows in expected order or did not return 3 rows" );

    my $id = $emp{bill}->select('employee_id');
    $emp{bill}->delete;
    eval { my $c = $emp_t->row_by_pk( pk => $id ) };
    ok ( $@ && $@->isa('AlzaboNoSuchRowException' ),
	 "There should be no bill row in the employee table" );

    eval { $emp{bill}->select('employee_id'); };
    ok( $@ && $@->isa('AlzaboCacheException'),,
        "Attempt to select from deleted row object produced the wrong (or no) exception: $@" );

    eval { $emp_proj_t->row_by_pk( pk => { employee_id => $id,
					   project_id => $proj{extend}->select('project_id') } ); };
    ok ( $@ && $@->isa('AlzaboNoSuchRowException' ),
	 "There should be no bill/extend row in the employee_project table" );

    ok( ! defined $dep{borg}->select('manager_id'),
	"The manager_id for the borg department should be NULL but it's", $dep{borg}->select('manager_id') );
}

sub ok
{
    my $ok = !!shift;
    print $ok ? 'ok ': 'not ok ';
    print ++$count, "\n";
    print "@_\n" if ! $ok;
}


sub mysql_make_schema
{
    my %p = @_;
    my $s = Alzabo::Create::Schema->new( name => 'alzabo_test',
				     rules => 'MySQL',
				     driver => 'MySQL' );

    $s->make_table( name => 'employee' );
    my $emp_t = $s->table('employee');
    $emp_t->make_column( name => 'employee_id',
			 type => 'int',
			 sequenced => 1,
			 primary_key => 1,
		       );
    $emp_t->make_column( name => 'name',
			 type => 'varchar(200)',
		       );
    $emp_t->make_column( name => 'smell',
			 type => 'varchar(200)',
			 null => 1,
		       );

    $s->make_table( name => 'department');
    my $dep_t = $s->table('department');
    $dep_t->make_column( name => 'department_id',
			 type => 'int',
			 sequenced => 1,
			 primary_key => 1,
		       );
    $dep_t->make_column( name => 'name',
			 type => 'varchar(200)',
		       );
    $dep_t->make_column( name => 'manager_id',
			 type => 'int',
			 null => 1,
		       );

    $s->add_relation( table_from => $dep_t,
		      table_to => $emp_t,
		      column_from => $dep_t->column('manager_id'),
		      column_to => $emp_t->column('employee_id'),
		      min_max_from => [ '0', '1' ],
		      min_max_to => [ '0', 'n' ],
		    );
    $s->add_relation( table_from => $emp_t,
		      table_to => $dep_t,
		      min_max_from => [ '1', '1' ],
		      min_max_to => [ '0', 'n' ],
		    );

    $s->make_table( name => 'project' );
    my $proj_t = $s->table('project');
    $proj_t->make_column( name => 'project_id',
			  type => 'int',
			  sequenced => 1,
			  primary_key => 1,
			);
    $proj_t->make_column( name => 'name',
			  type => 'varchar(200)',
			);

    $s->add_relation( table_from => $proj_t,
		      table_to   => $dep_t,
		      min_max_from => [ '1', '1' ],
		      min_max_to => [ '0', 'n' ],
		    );

    $s->add_relation( table_from => $emp_t,
		      table_to   => $proj_t,
		      min_max_from => [ '0', 'n' ],
		      min_max_to   => [ '0', 'n' ],
		    );

    $s->save_to_file;

    delete $p{rdbms};
    $s->create(%p);

    return Alzabo::Runtime::Schema->load_from_file( name => 'alzabo_test' );
}

sub mysql_clean_schema
{
    my %p = @_;

    my $s = Alzabo::Create::Schema->load_from_file( name => 'alzabo_test' );

    delete $p{rdbms};
    $s->drop(%p);
}
