use strict;

use Alzabo::Config;

use lib '.', './t';

require 'base.pl';

1;
sub mysql_make_schema
{
    my %p = @_;
    my $s = Alzabo::Create::Schema->new( name => $p{db_name},
					 rdbms => 'MySQL',
				       );

    $s->make_table( name => 'employee' );
    my $emp_t = $s->table('employee');
    $emp_t->make_column( name => 'employee_id',
			 type => 'int',
			 sequenced => 1,
			 primary_key => 1,
		       );
    $emp_t->make_column( name => 'name',
			 type => 'varchar',
			 length => 200,
		       );
    $emp_t->make_column( name => 'smell',
			 type => 'varchar',
			 length => 200,
			 nullable => 0,
			 default => 'grotesque',
		       );
    $emp_t->make_column( name => 'cash',
			 type => 'float',
			 length => 6,
			 precision => 2,
			 nullable => 1,
		       );
    $emp_t->make_index( columns => [ { column => $emp_t->column('name'),
				       prefix => 10 },
				     { column => $emp_t->column('smell') },
				   ] );

    $s->make_table( name => 'department');
    my $dep_t = $s->table('department');
    $dep_t->make_column( name => 'department_id',
			 type => 'int',
			 sequenced => 1,
			 primary_key => 1,
		       );
    $dep_t->make_column( name => 'name',
			 type => 'varchar',
			 length => 200,
		       );
    $dep_t->make_column( name => 'manager_id',
			 type => 'int',
			 length => 200,
			 nullable => 1,
		       );

    $s->add_relation( table_from => $dep_t,
		      table_to => $emp_t,
		      columns_from => $dep_t->column('manager_id'),
		      columns_to => $emp_t->column('employee_id'),
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
			  type => 'varchar',
			  length => 200,
			);
    $proj_t->make_index( columns => [ { column => $proj_t->column('name'),
					prefix => 20 } ] );
    $s->add_relation( table_from => $proj_t,
		      table_to   => $dep_t,
		      min_max_from => [ '1', '1' ],
		      min_max_to => [ '0', 'n' ],
		    );

    $emp_t->column('department_id')->set_name('dep_id');

    $s->add_relation( table_from => $emp_t,
		      table_to   => $proj_t,
		      min_max_from => [ '0', 'n' ],
		      min_max_to   => [ '0', 'n' ],
		    );

    my $char_pk_t = $s->make_table( name => 'char_pk' );
    $char_pk_t->make_column( name => 'char_col',
			     type => 'varchar',
			     length => 20,
			     primary_key => 1 );

    $s->save_to_file;

    delete $p{rdbms};
    $s->create(%p);

    $s->driver->disconnect;

    return $s;
}

# make sure to use native types or Postgres converts them and then the
# reverse engineering tests fail.
sub pg_make_schema
{
    my %p = @_;
    my $s = Alzabo::Create::Schema->new( name => $p{db_name},
					 rdbms => 'PostgreSQL',
				       );

    $s->make_table( name => 'employee' );
    my $emp_t = $s->table('employee');
    $emp_t->make_column( name => 'employee_id',
			 type => 'int4',
			 sequenced => 1,
			 primary_key => 1,
		       );
    $emp_t->make_column( name => 'name',
			 type => 'varchar',
			 length => 200,
		       );
    $emp_t->make_column( name => 'smell',
			 type => 'varchar',
			 length => 200,
			 nullable => 1,
			 default => 'grotesque',
		       );
    $emp_t->make_column( name => 'cash',
			 type => 'numeric',
			 length => 6,
			 precision => 2,
			 nullable => 1,
		       );
    $emp_t->make_index( columns => [ { column => $emp_t->column('name') } ] );

    $s->make_table( name => 'department');
    my $dep_t = $s->table('department');
    $dep_t->make_column( name => 'department_id',
			 type => 'int4',
			 sequenced => 1,
			 primary_key => 1,
		       );
    $dep_t->make_column( name => 'name',
			 type => 'varchar',
			 length => 200,
		       );
    $dep_t->make_column( name => 'manager_id',
			 type => 'int4',
			 nullable => 1,
		       );

    $s->add_relation( table_from => $dep_t,
		      table_to => $emp_t,
		      columns_from => $dep_t->column('manager_id'),
		      columns_to => $emp_t->column('employee_id'),
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
			  type => 'int4',
			  sequenced => 1,
			  primary_key => 1,
			);
    $proj_t->make_column( name => 'name',
			  type => 'varchar',
			  length => 200,
			);

    $s->add_relation( table_from => $proj_t,
		      table_to   => $dep_t,
		      min_max_from => [ '1', '1' ],
		      min_max_to => [ '0', 'n' ],
		    );
    $proj_t->make_index( columns => [ { column => $proj_t->column('name') } ] );

    $emp_t->column('department_id')->set_name('dep_id');

    $s->add_relation( table_from => $emp_t,
		      table_to   => $proj_t,
		      min_max_from => [ '0', 'n' ],
		      min_max_to   => [ '0', 'n' ],
		    );

    my $char_pk_t = $s->make_table( name => 'char_pk' );
    $char_pk_t->make_column( name => 'char_col',
			     type => 'varchar',
			     length => 20,
			     primary_key => 1 );
    $char_pk_t->make_column( name => 'fixed_char',
			     type => 'char',
			     nullable => 1,
			     length => 5 );

    $s->save_to_file;

    delete $p{rdbms};
    $s->create(%p);

    $s->driver->disconnect;

    return $s;
}
