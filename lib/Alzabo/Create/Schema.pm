package Alzabo::Create::Schema;

use strict;
use vars qw($VERSION);

use Alzabo::ChangeTracker;
use Alzabo::Config;
use Alzabo::Create;
use Alzabo::Driver;
use Alzabo::RDBMSRules;
use Alzabo::Runtime;

use Class::Fields ();
use Class::Fields::Fuxor ();
use Storable ();

use Tie::IxHash;

use base qw( Alzabo::Schema );

use fields qw( driver_name instantiated original rules );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.37 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;
    my %p = @_;

    my $self;
    {
	no strict 'refs';
	$self = bless [ \%{"${class}::FIELDS"} ], $class;
    }

    $self->{rules} = Alzabo::RDBMSRules->new($p{rules});
    $self->{driver_name} = $p{driver};
    $self->{driver} = Alzabo::Driver->new( driver => $p{driver},
					   schema => $self );

    AlzaboException->throw( error => "Alzabo::Create::Schema->new requires a name parameter\n" )
	unless exists $p{name};

    $self->set_name($p{name});

    $self->{tables} = Tie::IxHash->new;

    $self->_save_to_cache;

    return $self;
}

sub load_from_file
{
    my $class = shift;
    my %p = @_;

    my $schema = $class->_load_from_file(%p);

    my $name = $p{name};

    my $schema_dir = Alzabo::Config::schema_dir;

    my $fh = do { local *FH; };
    open $fh, "$schema_dir/$name/$name.rules"
	or FileSystemException->throw( error => "Unable to open $schema_dir/$name/$name.rules: $!\n" );
    my $rules = join '', <$fh>;
    close $fh
	or FileSystemException->throw( error => "Unable to close $schema_dir/$name/$name.rules: $!" );

    $rules =~ s/use (.*);/$1/;
    $schema->{rules} = Alzabo::RDBMSRules->new($rules);

    return $schema;
}

sub reverse_engineer
{
    my $proto = shift;
    my $class = ref $proto || $proto;
    my %p = @_;

    my $self = $class->new(%p);

    $self->{driver}->connect( user => $p{user},
			      password => $p{password} );

    $self->{rules}->reverse_engineer($self);

    $self->set_instantiated(1);
    $self->{original} = Storable::dclone($self);
    return $self;
}

sub set_name
{
    my Alzabo::Create::Schema $self = shift;
    my $name = shift;
    return if $self->{name} && $name eq $self->{name};

    my $old_name = $self->{name};
    $self->{name} = $name;

    eval { $self->rules->validate_schema_name($self); };
    if ($@)
    {
	$self->{name} = $old_name;
	$@->rethrow;
    }

    # Gotta clean up old files or we have a mess!
    $self->delete( name => $old_name ) if $old_name;
    $self->set_instantiated(0);
    undef $self->{original};
}

sub set_instantiated
{
    my Alzabo::Create::Schema $self = shift;

    $self->{instantiated} = shift;
}

sub make_table
{
    my Alzabo::Create::Schema $self = shift;
    my %p = @_;

    $self->add_table( table => Alzabo::Create::Table->new( schema => $self,
							   driver => $self->{driver},
							   rules => $self->{rules},
							   %p ),
		      %p );

    return $self->table( $p{name} );
}

sub add_table
{
    my Alzabo::Create::Schema $self = shift;
    my %p = @_;

    my $table = $p{table};

    AlzaboException->throw( error => "Table " . $table->name . " already exists in schema" )
	if $self->{tables}->EXISTS( $table->name );

    $self->{tables}->STORE( $table->name, $table );

    if ( exists $p{after} )
    {
	$self->move_table( after => $p{after},
			   table => $self->table( $p{name} ) );
    }
}

sub delete_table
{
    my Alzabo::Create::Schema $self = shift;
    my $table = shift;

    AlzaboException->throw( error => "Table " . $table->name ." doesn't exist in schema" )
	unless $self->{tables}->EXISTS( $table->name );

    foreach my $fk ($table->all_foreign_keys)
    {
	foreach my $other_fk ( $fk->table_to->foreign_keys_by_table($table) )
	{
	    $fk->table_to->delete_foreign_key($other_fk);
	}
    }

    $self->{tables}->DELETE( $table->name );
}

sub move_table
{
    my Alzabo::Create::Schema $self = shift;
    my %p = @_;

    if ( exists $p{before} && exists $p{after} )
    {
	AlzaboException->throw( error => "move_table method cannot be called with both 'before' and 'after parameters'" );
    }

    if ( $p{before} )
    {
	AlzaboException->throw( error => "Table " . $p{before}->name . " doesn't exist in schema" )
	    unless $self->{tables}->EXISTS( $p{before}->name );
    }
    else
    {
	AlzaboException->throw( error => "Table " . $p{after}->name . " doesn't exist in schema" )
	    unless $self->{tables}->EXISTS( $p{after}->name );
    }

    AlzaboException->throw( error => "Table " . $p{table}->name . " doesn't exist in schema" )
	unless $self->{tables}->EXISTS( $p{table}->name );

    $self->{tables}->DELETE( $p{table}->name );

    my $index;
    if ( $p{before} )
    {
	$index = $self->{tables}->Indices( $p{before}->name );
    }
    else
    {
	$index = $self->{tables}->Indices( $p{after}->name ) + 1;
    }

    $self->{tables}->Splice( $index, 0, $p{table}->name => $p{table} );
}

sub register_table_name_change
{
    my Alzabo::Create::Schema $self = shift;
    my %p = @_;

    AlzaboException->throw( error => "Table $p{old_name} doesn't exist in schema" )
	unless $self->{tables}->EXISTS( $p{old_name} );

    my $index = $self->{tables}->Indices( $p{old_name} );
    $self->{tables}->Replace( $index, $p{table}, $p{table}->name );
}

sub add_relation
{
    my Alzabo::Create::Schema $self = shift;
    my %p = @_;

    my $tracker = Alzabo::ChangeTracker->new;

    $self->_check_add_relation_args(%p);

    # This requires an entirely new table.
    if ($p{min_max_from}->[1] eq 'n' && $p{min_max_to}->[1] eq 'n')
    {
	$self->_create_linking_table(%p);
	return;
    }

    my $f_table = $p{table_from};
    my $t_table = $p{table_to};

    # Determined later.  This is the column that the relationship is
    # to.  As in table A/column B maps _to_ table X/column Y
    my ($col_from, $col_to);

    my $method;
    if ($p{min_max_from}->[1] ne 'n')
    {
	$method = '_create_to_1_relationship';
    }
    else
    {
	$method = '_create_to_n_relationship';
    }

    ($col_from, $col_to) = $self->$method( table_from   => $f_table,
					   table_to     => $t_table,
					   column_from  => $p{column_from},
					   column_to    => $p{column_to},
					   min_max_from => $p{min_max_from},
					   min_max_to   => $p{min_max_to},
					 );

    eval
    {
	$f_table->make_foreign_key( table_to    => $t_table,
				    column_from => $col_from,
				    column_to   => $col_to,
				    min_max_from => $p{min_max_from},
				    min_max_to   => $p{min_max_to} );
    };
    if ($@)
    {
	$tracker->backout;
	$@->rethrow;
    }

    my $fk;
    eval
    {
	$fk = $f_table->foreign_keys( table => $t_table,
				      column => $col_from );
    };
    if ($@)
    {
	$tracker->backout;
	$@->rethrow;
    }

    $tracker->add( sub { $f_table->delete_foreign_key($fk) } );

    if ($p{min_max_to}->[1] ne 'n')
    {
	$method = '_create_to_1_relationship';
    }
    else
    {
	$method = '_create_to_n_relationship';
    }

    ($col_from, $col_to) = $self->$method( table_from => $t_table,
					   table_to   => $f_table,
					   column_from => $col_to,
					   column_to   => $col_from,
					   min_max_from => $p{min_max_to},
					   min_max_to   => $p{min_max_from},
					 );

    if ($p{min_max_from}->[0] eq '1')
    {
	$col_from->null(0);
    }

    if ($p{min_max_to}->[0] eq '1')
    {
	$col_to->null(0);
    }

    eval
    {
	$t_table->make_foreign_key( table_to    => $f_table,
				    column_from => $col_from,
				    column_to   => $col_to,
				    min_max_from => $p{min_max_to},
				    min_max_to   => $p{min_max_from} );
    };
    if ($@)
    {
	$tracker->backout;
	$@->rethrow;
    }
}

sub _check_add_relation_args
{
    my $self = shift;
    my %p = @_;

    foreach my $t ( $p{table_from}, $p{table_to} )
    {
	AlzaboException->throw( error => "Table " . $t->name . " doesn't exist in schema" )
	    unless $self->{tables}->EXISTS( $t->name );
    }

    foreach my $mm ( $p{min_max_from}, $p{min_max_to} )
    {
	AlzaboException->throw( error => "Incorrect number of min/max elements" )
	    unless scalar @$mm == 2;

	foreach my $c ( @$mm )
	{
	    AlzaboException->throw( error => "Invalid min/max: $c" )
		unless $c =~ /^[01n]$/i;
	}
    }

    # No such thing as 1..0, n..0, or n..1!
    foreach my $k ( qw( min_max_from min_max_to ) )
    {
	AlzaboException->throw( error => "Invalid min/max: $p{$k}->[0]..$p{$k}->[1]" )
	    if  $p{$k}->[1] eq '0' || ( $p{$k}->[0] eq 'n' && $p{$k}->[1] ne 'n' );
    }
}

sub _create_to_1_relationship
{
    my Alzabo::Create::Schema $self = shift;
    my %p = @_;

    return @p{ 'column_from', 'column_to' }
	if $p{column_from} && $p{column_to};

    # Add this column to the table which _must_ participate in the
    # relationship, if there is one.  This reduces NULL values.
    # Otherwise, just add to the first table specified in the
    # relation.
    my @order;

    if ( $p{min_max_from}->[0] eq '1' ||
	 ( $p{min_max_from}->[0] eq '0' &&
	   $p{min_max_to}->[0] eq '0' ) )
    {
	@order = ( 'from', 'to' );
    }
    else
    {
	@order = ( 'to', 'from' );
    }

    # Determine which table we are linking from.  This gets a new
    # column or has its column adjusted) ...
    my $f_table = $p{"table_$order[0]"};

    # And which table we are linking to.  We use the primary key from
    # this table if no column has been provided.
    my $t_table = $p{"table_$order[1]"};

    # Determine whether there is a column in 'to' table we can use.
    my $col_to;
    if ( $p{"column_$order[1]"} )
    {
	$col_to = $p{"column_$order[1]"};
    }
    else
    {
	my @c = $t_table->primary_key;

	# Is there a way to handle this properly?
	AlzaboException->throw( error => $t_table->name . " has a multiple column primary key." )
	    if @c > 1;
	AlzaboException->throw( error => $t_table->name . " has no primary key." )
	    if @c == 0;

	$col_to = $c[0];
    }

    my ($col_from);
    if ($p{"column_$order[0]"})
    {
	$col_from = $p{"column_$order[0]"};
    }
    else
    {
	my $new_col = $self->_add_foreign_key_column( table_from => $f_table,
						      table_to   => $t_table,
						      column     => $col_to );

	$col_from = $new_col;
    }

    return ($col_from, $col_to);
}

# This one's simple.  We always add/adjust the column in the table on
# the 'to' side of the relationship.  This table only relates to one
# row in the 'from' table, but a row in the 'from' table can relate to
# 'n' rows in the 'to' table.
sub _create_to_n_relationship
{
    my Alzabo::Create::Schema $self = shift;
    my %p = @_;

    my $f_table = $p{table_from};
    my $t_table = $p{table_to};

    my $col_from;
    if ( $p{column_from} )
    {
	$col_from = $p{column_from};
    }
    else
    {
	my @c = $f_table->primary_key;

	# Is there a way to handle this properly?
	AlzaboException->throw( error => $f_table->name . " has a multiple column primary key." )
	    if @c > 1;
	AlzaboException->throw( error => $f_table->name . " has no primary key." )
	    if @c == 0;

	$col_from = $c[0];
    }

    # If the column this links to in the 'to' table is not specified
    # explicitly we assume that the user wants to have this coumn
    # created/adjusted in the 'to' table.
    my $col_to;
    if ($p{column_to})
    {
	$col_to = $p{column_to};
    }
    else
    {
	$col_to = $self->_add_foreign_key_column( table_from => $t_table,
						  table_to   => $f_table,
						  column     => $col_from );
    }

    return ($col_from, $col_to);
}

# Given two tables and a column, it will add the column to the table
# if it doesn't exist.  Otherwise, it adjusts the column in the table
# to match the given column.  In either case, the two columns (the one
# passed to the method and the one altered/created) will share a
# ColumnDefinition object.

# This is called when a relationship is created and the columns aren't
# specified.  This means that changes to the column in one table are
# automatically reflected in the other table, which is generally a
# good thing.
sub _add_foreign_key_column
{
    my Alzabo::Create::Schema $self = shift;
    my %p = @_;

    my $tracker = Alzabo::ChangeTracker->new;

    # This is the table that to which we are adding the foreign key.
    my $table = $p{table_from};

    # This is the column from the _other_ table that is the key
    # column.
    my $col = $p{column};

    # Note: This code _does_ explicitly want to compare the string
    # representation of the $col reference.
    my $new_col;
    if ( eval { $table->column( $col->name ) } &&
	 ( $col->definition ne $table->column( $col->name )->definition ) )
    {
	# This will make the two column share a single definition
	# object.
	my $old_def = $table->column( $col->name )->definition;
	$table->column( $col->name )->change_definition($col->definition);

	$tracker->add( sub { $table->column( $col->name )->change_definition($old_def) } );
    }
    else
    {
	# Just add the new column, but use the existing definition
	# object.
	$table->make_column( name => $col->name,
			     definition => $col->definition );

	my $del_col = $table->column( $col->name );
	$tracker->add( sub { $table->delete_column($del_col) } );
    }

    # Return the new column we just made.
    return $table->column( $col->name );
}

sub _create_linking_table
{
    my Alzabo::Create::Schema $self = shift;
    my %p = @_;

    my $tracker = Alzabo::ChangeTracker->new;

    my $t1 = $p{table_from};
    my $t2 = $p{table_to};

    my $t1_col;
    if ($p{column_from})
    {
	$t1_col = $p{column_from};
    }
    else
    {
	my @c = $t1->primary_key;

	# Is there a way to handle this properly?
	AlzaboException->throw( error => $t1->name . " has a multiple column primary key." )
	    if @c > 1;
	AlzaboException->throw( error => $t1->name . " has no primary key." )
	    if @c == 0;

	$t1_col = $c[0];
    }

    my $t2_col;
    if ($p{column_to})
    {
	$t2_col = $p{column_to};
    }
    else
    {
	my @c = $t2->primary_key;

	# Is qthere a way to handle this properly?
	AlzaboException->throw( error => $t2->name . " has a multiple column primary key." )
	    if @c > 1;
	AlzaboException->throw( error => $t2->name . " has no primary key." )
	    if @c == 0;

	$t2_col = $c[0];
    }

    # First we create the table.
    my $linking;
    $linking = $self->make_table( name => $p{name} || $p{table_from}->name . '_' . $p{table_to}->name );
    $tracker->add( sub { $self->delete_table($linking) } );

    eval
    {
	$linking->make_column( name => $t1_col->name,
			       definition => $t1_col->definition );
    };
    if ($@)
    {
	$tracker->backout;
	$@->rethrow;
    }

    eval
    {

	$linking->make_column( name => $t2_col->name,
			       definition => $t2_col->definition );
    };
    if ($@)
    {
	$tracker->backout;
	$@->rethrow;
    }

    eval
    {
	foreach my $c ( $t1_col, $t2_col )
	{
	    $linking->add_primary_key( $linking->column( $c->name ) );
	}
    };
    if ($@)
    {
	$tracker->backout;
	$@->rethrow;
    }

    eval
    {
	$self->add_relation( table_from => $t1,
			     table_to   => $linking,
			     min_max_from => [ $p{min_max_from}->[0], 'n' ],
			     min_max_to   => [ '1', '1' ],
			     column_from => $t1_col,
			     column_to   => $linking->column( $t1_col->name ) );
    };
    if ($@)
    {
	$tracker->backout;
	$@->rethrow;
    }

    eval
    {
	$self->add_relation( table_from => $t2,
			     table_to   => $linking,
			     min_max_from => [ $p{min_max_to}->[0], 'n' ],
			     min_max_to   => [ '1', '1' ],
			     column_from => $t2_col,
			     column_to   => $linking->column( $t2_col->name ) );
    };

    if ($@)
    {
	$tracker->backout;
	$@->rethrow;
    }
}

sub instantiated
{
    my Alzabo::Create::Schema $self = shift;

    return $self->{instantiated};
}

sub rules
{
    my Alzabo::Create::Schema $self = shift;

    return $self->{rules};
}

sub create
{
    my Alzabo::Create::Schema $self = shift;
    my %p = @_;

    my @sql = $self->make_sql;

    $self->{driver}->create_database(%p)
	unless $self->{instantiated};

    $self->{driver}->connect(%p);

    foreach my $statement (@sql)
    {
	$self->{driver}->do( sql => $statement );
    }

    $self->set_instantiated(1);
    $self->{original} = Storable::dclone($self);
}

sub make_sql
{
    my Alzabo::Create::Schema $self = shift;

    if ($self->{instantiated})
    {
	return $self->rules->schema_sql_diff( old => $self->{original},
					      new => $self );
    }
    else
    {
	return $self->rules->schema_sql($self);
    }
}

sub drop
{
    my Alzabo::Create::Schema $self = shift;
    my %p = @_;

    $self->{driver}->drop_database(%p);
    $self->set_instantiated(0);
}

sub delete
{
    my Alzabo::Create::Schema $self = shift;
    my %p = @_;

    my $name = $p{name} || $self->name;
    my $schema_dir = Alzabo::Config::schema_dir;

    my $dh = do { local *DH; };
    opendir $dh, "$schema_dir/$name"
	or FileSystemException->throw( error => "Unable to open $schema_dir/$name directory: $!" );
    foreach my $f (grep {-f "$schema_dir/$name/$_"} readdir $dh)
    {
	unlink "$schema_dir/$name/$f"
	    or FileSystemException->throw( error => "Unable to delete $schema_dir/$name/$f: $!" );
    }
    closedir $dh or FileSystemException->throw( error => "Unable to close $schema_dir/$name: $!" );
    rmdir "$schema_dir/$name"
	or FileSystemException->throw( error => "Unable to delete $schema_dir/$name: $!" );
}

sub save_to_file
{
    my Alzabo::Create::Schema $self = shift;

    my $schema_dir = Alzabo::Config::schema_dir;
    unless (-e "$schema_dir/$self->{name}")
    {
	mkdir "$schema_dir/$self->{name}", 0775
	    or FileSystemException->throw( error => "Unable to make directory $schema_dir/$self->{name}: $!" );
    }

    my $fh = do { local *FH; };
    open $fh, ">$schema_dir/$self->{name}/$self->{name}.create.alz"
	or FileSystemException->throw( error => "Unable to write to $schema_dir/$self->{name}.create.alz: $!\n" );
    Storable::nstore_fd( $self, $fh )
	or StorableException->throw( error => "Can't store to filehandle" );
    close $fh
	or FileSystemException->throw( error => "Unable to close $schema_dir/$self->{name}/$self->{name}.create.alz: $!" );

    open $fh, ">$schema_dir/$self->{name}/$self->{name}.rules"
	or FileSystemException->throw( error => "Unable to write to $schema_dir/$self->{name}.alz: $!\n" );
    print $fh ref $self->{rules};
    close $fh
	or FileSystemException->throw( error => "Unable to close $schema_dir/$self->{name}/$self->{name}.rules: $!" );

    open $fh, ">$schema_dir/$self->{name}/$self->{name}.driver"
	or FileSystemException->throw( error => "Unable to write to $schema_dir/$self->{name}.alz: $!\n" );
    print $fh ref $self->{driver};
    close $fh
	or FileSystemException->throw( error => "Unable to close $schema_dir/$self->{name}/$self->{name}.driver: $!" );

    my $rt = $self->make_runtime_clone;

    open $fh, ">$schema_dir/$self->{name}/$self->{name}.runtime.alz"
	or FileSystemException->throw( error => "Unable to write to $schema_dir/$self->{name}.runtime.alz: $!\n" );
    Storable::nstore_fd( $rt, $fh )
	or StorableException->throw( error => "Can't store to filehandle" );
    close $fh
	or FileSystemException->throw( error => "Unable to close $schema_dir/$self->{name}/$self->{name}.create.alz: $!" );

    $self->_save_to_cache;
}

sub make_runtime_clone
{
    my Alzabo::Create::Schema $self = shift;

    my $clone = Storable::dclone($self);
    my $fields = Class::Fields::Fuxor::get_fields('Alzabo::Create::Schema');
    foreach my $f ( reverse sort { $fields->{$a} cmp $fields->{$b} } keys %$fields )
    {
	next if Class::Fields::is_inherited('Alzabo::Create::Schema', $f);
	my $idx = $clone->[0]->{$f};
	splice @$clone, $idx, 1;
    }

    foreach my $t ($clone->tables)
    {
	my $fields = Class::Fields::Fuxor::get_fields('Alzabo::Create::Table');
	foreach my $f ( reverse sort { $fields->{$a} cmp $fields->{$b} } keys %$fields )
	{
	    next if Class::Fields::is_inherited('Alzabo::Create::Table', $f);
	    my $idx = $t->[0]->{$f};
	    splice @$t, $idx, 1;
	}

	foreach my $c ($t->columns)
	{
	    my $fields = Class::Fields::Fuxor::get_fields('Alzabo::Create::Column');
	    foreach my $f ( reverse sort { $fields->{$a} cmp $fields->{$b} } keys %$fields )
	    {
		next if Class::Fields::is_inherited('Alzabo::Create::Column', $f);
		my $idx = $c->[0]->{$f};
		splice @$c, $idx, 1;
	    }

	    my $def = $c->definition;
	    $fields = Class::Fields::Fuxor::get_fields('Alzabo::Create::ColumnDefinition');
	    foreach my $f ( reverse sort { $fields->{$a} cmp $fields->{$b} } keys %$fields )
	    {
		next if Class::Fields::is_inherited('Alzabo::Create::ColumnDefinition', $f);
		my $idx = $def->[0]->{$f};
		splice @$def, $idx, 1;
	    }
	    bless $def, 'Alzabo::Runtime::ColumnDefinition';
	    $def->[0] = \%Alzabo::Runtime::ColumnDefinition::FIELDS;
	    bless $c, 'Alzabo::Runtime::Column';
	    $c->[0] = \%Alzabo::Runtime::Column::FIELDS;
	}

	foreach my $fk ($t->all_foreign_keys)
	{
	    my $fields = Class::Fields::Fuxor::get_fields('Alzabo::Create::ForeignKey');
	    foreach my $f ( reverse sort { $fields->{$a} cmp $fields->{$b} } keys %$fields )
	    {
		next if Class::Fields::is_inherited('Alzabo::Create::ForeignKey', $f);
		my $idx = $fk->[0]->{$f};
		splice @$fk, $idx, 1;
	    }
	    bless $fk, 'Alzabo::Runtime::ForeignKey';
	    $fk->[0] = \%Alzabo::Runtime::ForeignKey::FIELDS;
	}

	foreach my $i ($t->indexes)
	{
	    my $fields = Class::Fields::Fuxor::get_fields('Alzabo::Create::Index');
	    foreach my $f ( reverse sort { $fields->{$a} cmp $fields->{$b} } keys %$fields )
	    {
		next if Class::Fields::is_inherited('Alzabo::Create::Index', $f);
		my $idx = $i->[0]->{$f};
		splice @$i, $idx, 1;
	    }
	    bless $i, 'Alzabo::Runtime::Index';
	    $i->[0] = \%Alzabo::Runtime::Index::FIELDS;
	}

	bless $t, 'Alzabo::Runtime::Table';
	$t->[0] = \%Alzabo::Runtime::Table::FIELDS;
    }
    bless $clone, 'Alzabo::Runtime::Schema';
    $clone->[0] = \%Alzabo::Runtime::Schema::FIELDS;

    $clone->{driver} = Alzabo::Driver->new( driver => $self->{driver_name},
					    schema => $clone );

    return $clone;
}

# Overrides method in base to load create schema instead of runtime
# schema
sub _schema_file_type
{
    return 'create';
}

__END__

=head1 NAME

Alzabo::Create::Schema - Schema objects for schema creation

=head1 SYNOPSIS

  use Alzabo::Create::Schema;

=head1 DESCRIPTION

This class represnets the whole schema, and contains table objects.

=head1 METHODS

=over 4

=item * new

Takes the following parameters:

=item -- name => $name

=item -- rules => $rules_subclass

=item -- driver => $driver_subclass

The values given to rules and driver should be the identifying piece
of the subclass.  For example, to use the MySQL driver you'd give the
string 'MySQL' (which identifies the class Alzabo::Driver::MySQL).

Exceptions:

 AlzaboException - no name provided.

=item * load_from_file($name)

Returns a schema object previously saved to disk based on the name
given.

Exceptions:

 AlzaboException - No saved schema of the given name.
 FileSystemException - Can't open, close or stat a file.
 EvalException - Unable to evaluate the contents of a file.

=item * reverse_engineer

Takes the following parameters:

=item -- name => $name

=item -- rules => $rules_subclass

=item -- driver => $driver_subclass

See the new method documentation for an explanation of the 'rules' and
'driver' parameters.

=item -- user => $user (optional)

User name to use when connecting to database.

=item -- password => $password (optional)

Password to use when connecting to database.

Attempts to connect to a database and instantiate a new schema object
based on information on a given database.  The returned object will
have its instantiated value set to true so that subsequent changes
will lead to SQL diffs, as opposed to SQL to create the database from
scratch.

=item * set_name ($name)

Change the schema name.  Since the schemas are saved on disk based on
the name, this deletes the files under the old name.  Call
save_to_file immediately afterwards if you want to make sure you have
a copy of the schema saved.

Exceptions:

 AlzaboRDBMSRulesException - invalid schema name.

=item * make_table (see below)

This method makes a new table and adds it to the schema, the
parameters given are passed directly to the Alzabo::Create::Table->new
method.  In addition, the schema fills in the schema parameter for the
table.

Exceptions:

 AlzaboException - Table already exists in the table.

 See Alzabo::Create::Table docs for other exceptions

=item * add_table

Takes the following parameters:

=item -- table => Alzabo::Create::Table object

=item -- after => Alzabo::Create::Table object (optional)

Add a table to the schema.  If the 'after' parameter is given then the
C<move_table> method will be called to move the new table to the
appropriate position.

Exceptions:

 AlzaboException - Table already exists in schema.

=item * delete_table( Alzabo::Create::Table object )

Removes the given table from the schema.  Will also delete all foreign
keys in other tables that it can find a link to.

Exceptions:

AlzaboException - Table doesn't exist in schema.

=item * move_table

Takes the following parameters:

=item -- table => Alzabo::Create::Table object

The table to move.

and either ...

=item -- before => Alzabo::Create::Table object

Move the table before this table

... or ...

=item -- after => Alzabo::Create::Table object

Move the table after this table.

Exceptions:

 AlzaboException - one of the tables passed in is not part of the
 schema.
 AlzaboException - both a 'before' and 'after' parameter were
 specified.

=item * add_relation

Takes the following parameters:

=item -- table_from => Alzabo::Create::Table object

=item -- table_to => Alzabo::Create::Table object

=item -- column_from => Alzabo::Create::Column object (optional)

=item -- column_to => Alzabo::Create::Column object (optional)

=item -- min_max_from => (see below)

=item -- min_max_to => (see below)

The two min_max attributes both take the same kind of argument, an
array reference two scalars long.

The first of these scalars can be the value '0' or '1' while the
second can be '1' or 'n'.

Creates a relationship between two tables.  This involves creating
Alzabo::Create::ForeignKey objects in both tables.  If the
'column_from' and 'column_to' parameters are not specified then the
schema object attempts to calculate the proper values for these
attributes.

If both the 'min_max_from' and 'min_max_to' attributes are 0 or 1 to
'n' then a new table will be created to link the two tables together.
This table will contain the primary keys of both the tables passed
into this function.  It will contain foreign keys to both of these
tables as well and these tables will be linked to this new table.

=item * instantiated

Returns the value of the schema's instantiated attribute.  It is true
if the schema has been created in a RDBMS backend, otherwise false.

=item * set_instantiated ($bool)

Set the schema's instantiated attribute as true or false.

=item * rules

Returns the schema's Alzabo::RDBMSRules object.

=item * create

Takes the following parameters:

=item -- host => $host

=item -- user => $user

=item -- password => $user

These three are all passed the schema's Alzabo::Driver object to
connect to the database.

This method causes the schema to connect to the RDBMS, create a new
database if necessary, and then execute whatever SQL is necessary to
make the database match the schema.

=item * make_sql

Returns an array containing the SQL statements necessary to either
create the database from scratch or update the database to match the
schema object.

=item * drop

Takes the following parameters:

=item -- host => $host

=item -- user => $user

=item -- password => $user

These three are all passed the schema's Alzabo::Driver object to
connect to the database.

Drops the database/schema from the RDBMS.  It does not delete the
Alzabo files from disk.  To do this, call the C<delete> method.

=item * delete

Removes the schema object from disk.  It does not delete the database
from the RDBMS.  To do this you must call the C<drop> method first.

=item * save_to_file

Saves the schema to a file on disk.  It also saves a version of the
schema that has been re-blessed into the Alzabo::Runtime::* classes
with the creation specific attributes removed.

=back

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
