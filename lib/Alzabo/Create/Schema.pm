package Alzabo::Create::Schema;

use strict;
use vars qw($VERSION);

use Alzabo::ChangeTracker;
use Alzabo::Config;
use Alzabo::Create;
use Alzabo::Driver;
use Alzabo::RDBMSRules;
use Alzabo::Runtime;
use Alzabo::SQLMaker;

use Params::Validate qw( :all );
Params::Validate::set_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

use Storable ();
use Tie::IxHash;

use base qw( Alzabo::Schema );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.58 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    validate( @_, { rdbms => { type => SCALAR },
		    name  => { type => SCALAR } } );
    my %p = @_;

    my $self = bless {}, $class;

    Alzabo::Exception::Params->throw( error => "Alzabo does not support the '$p{rdbms}' RDBMS" )
	unless ( grep { $p{rdbms} eq $_ } Alzabo::Driver->available &&
		 grep { $p{rdbms} eq $_ } Alzabo::RDBMSRules->available );

    $self->{driver} = Alzabo::Driver->new( rdbms => $p{rdbms},
					   schema => $self );
    $self->{rules} = Alzabo::RDBMSRules->new( rdbms => $p{rdbms} );

    $self->{sql} = Alzabo::SQLMaker->load( rdbms => $p{rdbms} );

    Alzabo::Exception::Params->throw( error => "Alzabo::Create::Schema->new requires a name parameter\n" )
	unless exists $p{name};

    $self->set_name($p{name});

    $self->{tables} = Tie::IxHash->new;

    $self->_save_to_cache;

    return $self;
}

sub load_from_file
{
    return shift->_load_from_file(@_);
}

sub reverse_engineer
{
    my $proto = shift;
    my $class = ref $proto || $proto;
    my %p = @_;

    my $self = $class->new( name => $p{name},
			    rdbms => $p{rdbms} );

    $self->{driver}->connect(%p);

    $self->{rules}->reverse_engineer($self);

    $self->set_instantiated(1);
    my $driver = delete $self->{driver};
    $self->{original} = Storable::dclone($self);
    $self->{driver} = $driver;
    delete $self->{original}{original};
    return $self;
}

sub set_name
{
    my $self = shift;

    validate_pos( @_, { type => SCALAR } );
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
    my $self = shift;

    validate_pos( @_, 1 );
    $self->{instantiated} = shift;
}

sub make_table
{
    my $self = shift;
    my %p = @_;

    my %p2;
    foreach ( qw( before after ) )
    {
	$p2{$_} = delete $p{$_} if exists $p{$_};
    }
    $self->add_table( table => Alzabo::Create::Table->new( schema => $self,
							   %p ),
		      %p2 );

    return $self->table( $p{name} );
}

sub add_table
{
    my $self = shift;

    validate( @_, { table  => { isa => 'Alzabo::Create::Table' },
		    before => { optional => 1 },
		    after  => { optional => 1 } } );
    my %p = @_;

    my $table = $p{table};

    Alzabo::Exception::Params->throw( error => "Table " . $table->name . " already exists in schema" )
	if $self->{tables}->EXISTS( $table->name );

    $self->{tables}->STORE( $table->name, $table );

    foreach ( qw( before after ) )
    {
	if ( exists $p{$_} )
	{
	    $self->move_table( $_ => $p{$_},
			       table => $table );
	    last;
	}
    }
}

sub delete_table
{
    my $self = shift;

    validate_pos( @_, { isa => 'Alzabo::Create::Table' } );
    my $table = shift;

    Alzabo::Exception::Params->throw( error => "Table " . $table->name ." doesn't exist in schema" )
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
    my $self = shift;

    validate( @_, { table  => { isa => 'Alzabo::Create::Table' },
		    before => { isa => 'Alzabo::Create::Table',
				optional => 1 },
		    after  => { isa => 'Alzabo::Create::Table',
				optional => 1 } } );
    my %p = @_;

    if ( exists $p{before} && exists $p{after} )
    {
	Alzabo::Exception::Params->throw( error => "move_table method cannot be called with both 'before' and 'after parameters'" );
    }

    if ( $p{before} )
    {
	Alzabo::Exception::Params->throw( error => "Table " . $p{before}->name . " doesn't exist in schema" )
	    unless $self->{tables}->EXISTS( $p{before}->name );
    }
    else
    {
	Alzabo::Exception::Params->throw( error => "Table " . $p{after}->name . " doesn't exist in schema" )
	    unless $self->{tables}->EXISTS( $p{after}->name );
    }

    Alzabo::Exception::Params->throw( error => "Table " . $p{table}->name . " doesn't exist in schema" )
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
    my $self = shift;

    validate( @_, { table => { isa => 'Alzabo::Create::Table' },
		    old_name => { type => SCALAR } } );
    my %p = @_;

    Alzabo::Exception::Params->throw( error => "Table $p{old_name} doesn't exist in schema" )
	unless $self->{tables}->EXISTS( $p{old_name} );

    my $index = $self->{tables}->Indices( $p{old_name} );
    $self->{tables}->Replace( $index, $p{table}, $p{table}->name );
}

sub add_relation
{
    my $self = shift;

    my %p = @_;

    my $tracker = Alzabo::ChangeTracker->new;

    $self->_check_add_relation_args(%p);

    # This requires an entirely new table.
    if ($p{min_max_from}->[1] eq 'n' && $p{min_max_to}->[1] eq 'n')
    {
	$self->_create_linking_table(%p);
	return;
    }

    Alzabo::Exception::Params->throw( error => "Must provide 'table_from' or 'columns_from' parameter" )
	unless $p{table_from} || $p{columns_from};

    Alzabo::Exception::Params->throw( error => "Must provide 'table_to' or 'columns_to' parameter" )
	unless $p{table_to} || $p{columns_to};

    $p{columns_from} = ( defined $p{columns_from} ? ( UNIVERSAL::isa( $p{columns_from}, 'ARRAY') ?
						      $p{columns_from} :
						      [ $p{columns_from} ] ) :
			 undef );

    $p{columns_to} = ( defined $p{columns_to} ? ( UNIVERSAL::isa( $p{columns_to}, 'ARRAY') ?
						  $p{columns_to} :
						  [ $p{columns_to} ] ) :
		       undef );

    my $f_table = $p{table_from} || $p{columns_from}->[0]->table;
    my $t_table = $p{table_to} || $p{columns_to}->[0]->table;

    if ( $p{columns_from} && $p{columns_to} )
    {
	Alzabo::Exception::Params->throw( error => "Cannot create a relationship with differing numbers of columns on either side of the relation" )
	    unless @{ $p{columns_from} } == @{ $p{columns_to} };
    }

    foreach ( [ columns_from => $f_table ], [ columns_to => $t_table ] )
    {
	my ($key, $table) = @$_;
	if ( defined $p{$key} )
	{
	    Alzabo::Exception::Params->throw( error => "All the columns in a given side of the relationship must be from the same table" )
		if grep { $_->table ne $table } @{ $p{$key} };
	}
    }

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
					   columns_from => $p{columns_from},
					   columns_to   => $p{columns_to},
					   min_max_from => $p{min_max_from},
					   min_max_to   => $p{min_max_to},
					 );

    eval
    {
	$f_table->make_foreign_key( columns_from => $col_from,
				    columns_to   => $col_to,
				    min_max_from => $p{min_max_from},
				    min_max_to   => $p{min_max_to} );
    };
    if ($@)
    {
	$tracker->backout;
	$@->rethrow;
    }

    my @fk;
    eval
    {
	foreach my $c ( @$col_from )
	{
	    push @fk, $f_table->foreign_keys( table => $t_table,
					      column => $c );
	}
    };
    if ($@)
    {
	$tracker->backout;
	$@->rethrow;
    }

    $tracker->add( sub { $f_table->delete_foreign_key($_) foreach @fk } );

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
					   columns_from => $col_to,
					   columns_to   => $col_from,
					   min_max_from => $p{min_max_to},
					   min_max_to   => $p{min_max_from},
					 );

    if ($p{min_max_from}->[0] eq '1')
    {
	$_->nullable(0) foreach @{ $p{columns_from} };
    }

    if ($p{min_max_to}->[0] eq '1')
    {
	$_->nullable(0) foreach @{ $p{columns_to} };
    }

    eval
    {
	$t_table->make_foreign_key( columns_from => $col_from,
				    columns_to   => $col_to,
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
	next unless defined $t;
	Alzabo::Exception::Params->throw( error => "Table " . $t->name . " doesn't exist in schema" )
	    unless $self->{tables}->EXISTS( $t->name );
    }

    foreach my $mm ( $p{min_max_from}, $p{min_max_to} )
    {
	Alzabo::Exception::Params->throw( error => "Incorrect number of min/max elements" )
	    unless scalar @$mm == 2;

	foreach my $c ( @$mm )
	{
	    Alzabo::Exception::Params->throw( error => "Invalid min/max: $c" )
		unless $c =~ /^[01n]$/i;
	}
    }

    # No such thing as 1..0, n..0, or n..1!
    foreach my $k ( qw( min_max_from min_max_to ) )
    {
	Alzabo::Exception::Params->throw( error => "Invalid min/max: $p{$k}->[0]..$p{$k}->[1]" )
	    if  $p{$k}->[1] eq '0' || ( $p{$k}->[0] eq 'n' && $p{$k}->[1] ne 'n' );
    }
}

sub _create_to_1_relationship
{
    my $self = shift;
    my %p = @_;

    return @p{ 'columns_from', 'columns_to' }
	if $p{columns_from} && $p{columns_to};

    # Add these columns to the table which _must_ participate in the
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
    if ( $p{"columns_$order[1]"} )
    {
	$col_to = $p{"columns_$order[1]"};
    }
    else
    {
	my @c = $t_table->primary_key;

	Alzabo::Exception::Params->throw( error => $t_table->name . " has no primary key." )
	    unless @c;

	$col_to = \@c;
    }

    my ($col_from);
    if ($p{"columns_$order[0]"})
    {
	$col_from = $p{"columns_$order[0]"};
    }
    else
    {
	my @new_col;
	foreach my $c ( @$col_to )
	{
	    push @new_col, $self->_add_foreign_key_column( table  => $f_table,
							   column => $c );
	}

	$col_from = \@new_col;
    }

    return ($col_from, $col_to);
}

# This one's simple.  We always add/adjust the column in the table on
# the 'to' side of the relationship.  This table only relates to one
# row in the 'from' table, but a row in the 'from' table can relate to
# 'n' rows in the 'to' table.
sub _create_to_n_relationship
{
    my $self = shift;
    my %p = @_;

    my $f_table = $p{table_from};
    my $t_table = $p{table_to};

    my $col_from;
    if ( $p{columns_from} )
    {
	$col_from = $p{columns_from};
    }
    else
    {
	my @c = $f_table->primary_key;

	# Is there a way to handle this properly?
	Alzabo::Exception::Params->throw( error => $f_table->name . " has no primary key." )
	    unless @c;

	$col_from = \@c;
    }

    my $col_to;
    if ($p{columns_to})
    {
	$col_to = $p{columns_to};
    }
    else
    {
	# If the columns this links to in the 'to' table ares not specified
	# explicitly we assume that the user wants to have this coumn
	# created/adjusted in the 'to' table.
	my @new_col;
	foreach my $c ( @$col_from )
	{
	    push @new_col, $self->_add_foreign_key_column( table  => $t_table,
							   column => $c );
	}

	$col_to = \@new_col;
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
    my $self = shift;

    validate( @_, { table => { isa => 'Alzabo::Create::Table' },
		    column => { isa => 'Alzabo::Create::Column' } } );
    my %p = @_;

    my $tracker = Alzabo::ChangeTracker->new;

    # Note: This code _does_ explicitly want to compare the string
    # representation of the $p{column}->definition reference.
    my $new_col;
    if ( eval { $p{table}->column( $p{column}->name ) } &&
	 ( $p{column}->definition ne $p{table}->column( $p{column}->name )->definition ) )
    {
	# This will make the two column share a single definition
	# object.
	my $old_def = $p{table}->column( $p{column}->name )->definition;
	$p{table}->column( $p{column}->name )->change_definition($p{column}->definition);

	$tracker->add( sub { $p{table}->column( $p{column}->name )->change_definition($old_def) } );
    }
    else
    {
	# Just add the new column, but use the existing definition
	# object.
	$p{table}->make_column( name => $p{column}->name,
			     definition => $p{column}->definition );

	my $del_col = $p{table}->column( $p{column}->name );
	$tracker->add( sub { $p{table}->delete_column($del_col) } );
    }

    # Return the new column we just made.
    return $p{table}->column( $p{column}->name );
}

sub _create_linking_table
{
    my $self = shift;
    my %p = @_;

    my $tracker = Alzabo::ChangeTracker->new;

    my $t1 = $p{table_from};
    my $t2 = $p{table_to};

    my $t1_col;
    if ($p{columns_from})
    {
	$t1_col = $p{columns_from};
    }
    else
    {
	my @c = $t1->primary_key;

	Alzabo::Exception::Params->throw( error => $t1->name . " has no primary key." )
	    unless @c;

	$t1_col = \@c;
    }

    my $t2_col;
    if ($p{columns_to})
    {
	$t2_col = $p{columns_to};
    }
    else
    {
	my @c = $t2->primary_key;

	Alzabo::Exception::Params->throw( error => $t2->name . " has no primary key." )
	    unless @c;

	$t2_col = \@c;
    }

    # First we create the table.
    my $linking;
    my $name;

    if ( exists $p{name} )
    {
	$name = $p{name}
    }
    elsif ( lc $p{table_from}->name eq $p{table_from}->name )
    {
	$name = join '_', $p{table_from}->name, $p{table_to}->name;
    }
    else
    {
	$name = join '', $p{table_from}->name, $p{table_to}->name;
    }

    $linking = $self->make_table( name => $name );
    $tracker->add( sub { $self->delete_table($linking) } );

    eval
    {
	foreach my $c ( @$t1_col, @$t2_col )
	{
	    $linking->make_column( name => $c->name,
				   definition => $c->definition,
				   primary_key => 1,
				 );
	}

	$self->add_relation( table_from => $t1,
			     table_to   => $linking,
			     min_max_from => [ $p{min_max_from}->[0], 'n' ],
			     min_max_to   => [ '1', '1' ],
			     columns_from => $t1_col,
			     columns_to   => [ $linking->columns( map { $_->name } @$t1_col ) ] );

	$self->add_relation( table_from => $t2,
			     table_to   => $linking,
			     min_max_from => [ $p{min_max_to}->[0], 'n' ],
			     min_max_to   => [ '1', '1' ],
			     columns_from => $t2_col,
			     columns_to   => [ $linking->columns( map { $_->name } @$t2_col ) ] );
    };

    if ($@)
    {
	$tracker->backout;
	$@->rethrow;
    }
}

sub instantiated
{
    my $self = shift;

    return $self->{instantiated};
}

sub create
{
    my $self = shift;
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
    my $driver = delete $self->{driver};
    $self->{original} = Storable::dclone($self);
    $self->{driver} = $driver;
    delete $self->{original}{original};
}

sub make_sql
{
    my $self = shift;

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
    my $self = shift;
    my %p = @_;

    $self->{driver}->drop_database(%p);
    $self->set_instantiated(0);
}

sub delete
{
    my $self = shift;
    my %p = @_;

    my $name = $p{name} || $self->name;
    my $schema_dir = Alzabo::Config::schema_dir;

    my $dh = do { local *DH; };
    opendir $dh, "$schema_dir/$name"
	or Alzabo::Exception::System->throw( error => "Unable to open $schema_dir/$name directory: $!" );
    foreach my $f (grep {-f "$schema_dir/$name/$_"} readdir $dh)
    {
	unlink "$schema_dir/$name/$f"
	    or Alzabo::Exception::System->throw( error => "Unable to delete $schema_dir/$name/$f: $!" );
    }
    closedir $dh or Alzabo::Exception::System->throw( error => "Unable to close $schema_dir/$name: $!" );
    rmdir "$schema_dir/$name"
	or Alzabo::Exception::System->throw( error => "Unable to delete $schema_dir/$name: $!" );
}

sub save_to_file
{
    my $self = shift;

    my $schema_dir = Alzabo::Config::schema_dir;
    unless (-e "$schema_dir/$self->{name}")
    {
	mkdir "$schema_dir/$self->{name}", 0775
	    or Alzabo::Exception::System->throw( error => "Unable to make directory $schema_dir/$self->{name}: $!" );
    }

    my $fh = do { local *FH; };
    open $fh, ">$schema_dir/$self->{name}/$self->{name}.create.alz"
	or Alzabo::Exception::System->throw( error => "Unable to write to $schema_dir/$self->{name}.create.alz: $!\n" );
    Storable::nstore_fd( $self, $fh )
	or Alzabo::Exception::System->throw( error => "Can't store to filehandle" );
    close $fh
	or Alzabo::Exception::System->throw( error => "Unable to close $schema_dir/$self->{name}/$self->{name}.create.alz: $!" );

    open $fh, ">$schema_dir/$self->{name}/$self->{name}.rdbms"
	or Alzabo::Exception::System->throw( error => "Unable to write to $schema_dir/$self->{name}.rdbms: $!\n" );
    print $fh $self->{driver}->driver_id;
    close $fh
	or Alzabo::Exception::System->throw( error => "Unable to close $schema_dir/$self->{name}/$self->{name}.rdbms: $!" );

    my $rt = $self->make_runtime_clone;

    open $fh, ">$schema_dir/$self->{name}/$self->{name}.runtime.alz"
	or Alzabo::Exception::System->throw( error => "Unable to write to $schema_dir/$self->{name}.runtime.alz: $!\n" );
    Storable::nstore_fd( $rt, $fh )
	or Alzabo::Exception::System->throw( error => "Can't store to filehandle" );
    close $fh
	or Alzabo::Exception::System->throw( error => "Unable to close $schema_dir/$self->{name}/$self->{name}.create.alz: $!" );

    $self->_save_to_cache;
}

sub make_runtime_clone
{
    my $self = shift;

    my %s;
    my $clone = Storable::dclone($self);

    foreach my $f ( qw( original instantiated rules driver ) )
    {
	delete $clone->{$f};
    }

    foreach my $t ($clone->tables)
    {
	foreach my $c ($t->columns)
	{
	    my $def = $c->definition;
	    bless $def, 'Alzabo::Runtime::ColumnDefinition';
	    bless $c, 'Alzabo::Runtime::Column';
	}

	foreach my $fk ($t->all_foreign_keys)
	{
	    bless $fk, 'Alzabo::Runtime::ForeignKey';
	}

	foreach my $i ($t->indexes)
	{
	    bless $i, 'Alzabo::Runtime::Index';
	}

	bless $t, 'Alzabo::Runtime::Table';
    }
    bless $clone, 'Alzabo::Runtime::Schema';

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

This class represents the whole schema.  It contains table objects,
which in turn contain columns, indexes, etc.  It contains methods that
act globally on the schema, including methods to save it to disk,
create itself in an RDBMS, create relationships between tables, etc.

=head1 INHERITS FROM

C<Alzabo::Schema>

=for pod_merge merged

=head1 METHODS

=head2 Constructors

=head2 new

=head3 Parameters

=over 4

=item * name => $name

This is the name of the schema, and will be the name of the database
in the RDBMS.

=item * rdbms => $rdbms

The value given to RDBMS should be.

=back

=head3 Returns

A new C<Alzabo::Create::Schema> object.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>
L<C<Alzabo::Exception::System>|Alzabo::Exceptions>

=head2 load_from_file($name)

Returns a schema object previously saved to disk.

=head3 Returns

The C<Alzabo::Create::Schema> object specified by the name parameter.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=head2 reverse_engineer

Attempts to connect to a database and instantiate a new schema object
based on information in the specified database.  The returned object
will have its instantiated value set to true so that subsequent
changes will lead to SQL diffs, as opposed to SQL to create the
database from scratch.

The schema object returned by this method will have its instantiated
attribute set as true.  This means that calling the C<make_sql> method
on the object won't generate any SQL.  To do this you'd have to first
call
L<C<$schema-E<gt>set_instantiated(0)>|Alzabo::Create::Schema/set_instantiated
($bool)> and then L<C<$schema-E<gt>make_sql>|make_sql>.

=head3 Parameters

=over 4

=item * name => $name

The name of the database with which to connect.

=item * rules => $rules_subclass

=item * driver => $driver_subclass

See the L<C<new>|new> method documentation for an explanation of the
C<rules> and <driver> parameters.

=item * user => $user (optional)

User name to use when connecting to database.

=item * password => $password (optional)

Password to use when connecting to database.

=item * host => $host (optional)

The host with which to connect.

=back

=head3 Returns

A new C<Alzabo::Create::Schema> object.

=head2 Other Methods

=for pod_merge name

=head2 set_name ($name)

Change the schema name.  Since schemas are saved on disk with
filenames based on the schema name, this deletes the files for the old
name.  Call L<C<save_to_file>|save_to_file> immediately afterwards if
you want to make sure you have a copy of the schema saved.

=for pod_merge table

=for pod_merge tables

=head2 make_table

This method makes a new table and adds it to the schema, the
parameters given are passed directly to the
L<C<Alzabo::Create::Table-E<gt>new>|Alzabo::Create::Table/new> method.
The schema parameter is filled in automatically.

=head3 Returns

The L<C<Alzabo::Create::Table>|Alzabo::Create::Table> object created.

=head2 delete_table (C<Alzabo::Create::Table> object)

Removes the given table from the schema.  This method will also delete
all foreign keys in other tables that point at the given table.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=head2 add_table

Add a table to the schema.  If a before or after parameter is given
then the L<C<move_table>|move_table> method will be called to move the
new table to the appropriate position.

=head3 Parameters

=over 4

=item * table => C<Alzabo::Create::Table> object

=item * after => C<Alzabo::Create::Table> object (optional)

... or ...

=item * before => C<Alzabo::Create::Table> object (optional)

=back

=head3 Returns

The L<C<Alzabo::Create::Table>|Alzabo::Create::Table> object created.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=head2 move_table

Allows you to change the order of the tables as they are stored in the
schema.

=head3 Parameters

=over 4

=item * table => C<Alzabo::Create::Table> object

The table to move.

and either ...

=item * before => C<Alzabo::Create::Table> object

Move the table before this table

... or ...

=item * after => C<Alzabo::Create::Table> object

Move the table after this table.

=back

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=head2 add_relation

Creates a relationship between two tables.  This involves creating
L<C<Alzabo::Create::ForeignKey>|Alzabo::Create::ForeignKey> objects in
both tables.  If the C<columns_from> and C<columns_to> parameters are
not specified then the schema object attempts to calculate the proper
values for these attributes.

This is determined as follows: If the min_max_from value is 1..1 or
1..n, it assumes that the table specified as C<table_from> is dependent
on the other table, and use the other table's primary key as the
linking table.  If the C<min_max_from> and C<min_max_to> are both 0..(1
or n) then it also assumes that the C<table_from> table is dependent.
In all other cases, it uses the primary key from the C<table_from>.

If no columns with the same names exist in the other table, then
columns with that name will be created.  Otherwise, it changes the
dependent columns so that their
L<C<Alzabo::Create::ColumnDefinition>|Alzabo::Create::ColumnDefinition>
objects are the same as the columns in the table upon which it is
dependent, meaning that changes to the type of one column affects both
at the same time.

If you want to make multi-column relation, the assumption is that the
order of the columns is significant.  In other words, the first column
in the C<columns_from> parameter is assumed to correspond to the first
column in hte C<columns_to> parameter and so on.

The number of columns given in C<columns_from> and C<columns_to> must
be the same except when both C<min_max_...> parameters have are (0 or
1)..n.

If both the C<min_max_from> and C<min_max_to> parameters are (0 or
1)..n then a new table will be created to link the two tables
together.  This table will contain the primary keys of both the tables
passed into this function.  It will contain foreign keys to both of
these tables as well and these tables will be linked to this new
table.

=head3 Parameters

=over 4

=item * table_from => C<Alzabo::Create::Table> object (optional if columns_from is provided)

=item * table_to => C<Alzabo::Create::Table> object (optional if columns_to is provided)

=item * columns_from => C<Alzabo::Create::Column> object (optional if table_from is provided)

=item * columns_to => C<Alzabo::Create::Column> object (optional if table_to is provided)

=item * min_max_from => (see below)

=item * min_max_to => (see below)

The two min_max attributes both take the same kind of argument, an
array reference two scalars long.

The first of these scalars can be the value '0' or '1' while the
second can be '1' or 'n'.

=back

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=head2 create

This method causes the schema to connect to the RDBMS, create a new
database if necessary, and then execute whatever SQL is necessary to
make that database match the current state of the schema object.  If
the schema has been instantiated previously, then it will generate the
SQL necessary to change the database.  This may be destructive
(dropping tables, columns, etc) so be careful.  This will cause the
schema to be marked as instantiated.

Wherever possible, existing data will be preserved.

=head3 Parameters

=over 4

=item * host => $host

=item * user => $user

=item * password => $user

These three parameters are all passed the schema's Alzabo::Driver
object to connect to the database.

=back

=head2 instantiated

=head3 Returns

The value of the schema's instantiated attribute.  It is true if the
schema has been created in an RDBMS backend, otherwise it is false.

=head2 set_instantiated ($bool)

Set the schema's instantiated attribute as true or false.

=for pod_merge driver

=head2 rules

=head3 Returns

The schema's L<C<Alzabo::RDBMSRules>|Alzabo::RDBMSRules> object.

=head2 make_sql

=head3 Returns

An array containing the SQL statements necessary to either create the
database from scratch or update the database to match the schema
object.  See the L<C<create>|Alzabo::Create::Schema/create> method for
more details.

=head2 drop

Drops the database/schema from the RDBMS.  This will cause the schema
to be marked as not instantiated.  This method does not delete the
Alzabo files from disk.  To do this, call the C<delete> method.

=head3 Parameters

=over 4

=item * host => $host

=item * user => $user

=item * password => $user

These three parameters are all passed the schema's Alzabo::Driver
object to connect to the database.

=back

=head2 delete

Removes the schema object from disk.  It does not delete the database
from the RDBMS.  To do this you must call the L<C<drop>|drop> method
first.

=head2 save_to_file

Saves the schema to a file on disk.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
