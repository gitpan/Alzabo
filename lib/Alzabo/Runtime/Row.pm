package Alzabo::Runtime::Row;

use strict;
use vars qw($VERSION $CACHE_CLASS);

use Alzabo::Runtime;

use fields qw( id table data cache );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.20 $ =~ /(\d+)\.(\d+)/;

1;

sub import
{
    return if defined $CACHE_CLASS;

    shift;
    my $class = shift || 'Alzabo::ObjectCache';

    eval "use $class";
    die $@ if $@;

    $CACHE_CLASS = $class;
}

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    if ($CACHE_CLASS)
    {
	my $row = $CACHE_CLASS->new->fetch_object( $class->id(@_) );
	return $row if $row;
    }

    my $self;
    {
	no strict 'refs';
	$self = bless [ \%{"${class}::FIELDS"} ], $class;
    }
    $self->_init(@_);

    $self->{cache}->store_object($self)
	if $self->{cache};

    return $self;
}

sub _init
{
    my Alzabo::Runtime::Row $self = shift;
    my %p = @_;

    $self->{table} = $p{table};
    $self->{id} = $self->_make_id_hash(%p);
    $self->{cache} = $CACHE_CLASS->new if defined $CACHE_CLASS && (! $p{no_cache});

    while (my ($k, $v) = each %{ $self->{id} })
    {
	$self->{data}{$k} = $v;
    }

    if (my @pre = $self->{table}->prefetch)
    {
	$self->get_data(@pre);
    }
    else
    {
	# Need to try to fetch something to confirm that this row exists!
	my @pk = $self->{table}->primary_key;
	my $sql = 'SELECT 1 FROM ' . $self->{table}->name . ' WHERE ';
	$sql .= join ' AND ', map { $_->name . ' = ?' } @pk;

	$self->_no_such_row_error unless
	    $self->table->schema->driver->one_row( sql => $sql,
						   bind => [ map { $self->{id}{ $_->name } } @pk ] );
    }
}

sub _make_id_hash
{
    my Alzabo::Runtime::Row $self = shift;
    my %p = @_;

    return $p{id} if ref $p{id};

    my ($pk) = exists $p{table} ? $p{table}->primary_key : $self->{table}->primary_key;

    AlzaboException( error => "Can't make rows for tables without a primary key" )
	unless $pk;

    return { $pk->name => $p{id} };
}

sub get_data
{
    my Alzabo::Runtime::Row $self = shift;
    my @cols = @_;

    my %select;
    foreach my $c (@cols)
    {
	foreach my $s ( $self->{table}->group_by_column($c) )
	{
	    $select{$s} = 1 if ! exists $self->{data}{$s};
	}
    }

    my $driver = $self->table->schema->driver;

    my @pk = $self->{table}->primary_key;

    my $sql = 'SELECT ';
    $sql .= join ', ', keys %select;
    $sql .= ' FROM ' . $self->{table}->name . ' WHERE ';
    $sql .= join ' AND ', map { $_->name . ' = ?' } @pk;

    my %hash = $driver->one_row_hash( sql => $sql,
				      bind => [ map { $self->{id}{ $_->name } } @pk ] );

    $self->_no_such_row_error
	unless keys %hash;

    $self->{cache}->register_refresh($self) if $self->{cache};

    while (my ($k, $v) = each %hash)
    {
	$self->{data}{$k} = $v;
    }
}

sub select
{
    my Alzabo::Runtime::Row $self = shift;
    my @cols = @_;

    $self->check_cache if $self->{cache};

    my @needed = grep { ! exists $self->{data}{$_} } @cols;
    $self->get_data(@needed) if @needed;

    return wantarray ? @{ $self->{data} }{@cols} : $self->{data}{ $cols[0] };
}

sub update
{
    my Alzabo::Runtime::Row $self = shift;
    my %data = @_;

    if ($self->{cache})
    {
	AlzaboCacheException->throw( error => "Cannot update expired object" )
	    unless $self->check_cache;
    }

    my $driver = $self->table->schema->driver;

    my @fk;
    foreach my $k (keys %data)
    {
	# This will throw an exception if the column doesn't exist.
	my $c = $self->{table}->column($k);

	AlzaboException->throw( error => 'Cannot change the value of primary key columns.  Delete the row object and create a new one instead.' )
	    if $self->{table}->column_is_primary_key($c);

	# Only make the change if the two values are different.  The
	# convolutions are necessary to avoid a warning.
	unless ( ! exists $self->{data}{$k} ||
		 ( defined $data{$k} && ! defined $self->{data}{$k} ) ||
		 ( ! defined $data{$k} && defined $self->{data}{$k} ) ||
		 ( $data{$k} ne $self->{data}{$k} )
	       )
	{
	    delete $data{$k};
	    next;
	}

	AlzaboException->throw( error => "Column " . $c->name . " cannot be null." )
	    unless defined $data{$k} || $c->null;

	push @fk, $self->{table}->foreign_keys_by_column($c)
	    if $self->table->schema->referential_integrity;
    }

    return unless keys %data;

    # If we have foreign keys we'd like all the fiddling to be atomic.
    $driver->start_transaction( table => $self->table,
				id => [ values %{ $self->{id} } ],
				fk => \@fk ) if @fk && $self->table->schema->referential_integrity;

    my @pk = $self->{table}->primary_key;
    my $sql = 'UPDATE ' . $self->{table}->name;
    $sql .= ' SET ';
    $sql .= join ', ', map {"$_ = ?"} sort keys %data;
    $sql .= ' WHERE ';
    $sql .= join ' AND ', map {$_->name . ' = ?'} @pk;

    eval
    {
	my @bind = @data{ sort keys %data };
	push @bind, map { $self->{id}{ $_->name } } @pk;
	$driver->do( sql => $sql,
		     bind => \@bind );

	if ($self->table->schema->referential_integrity)
	{
	    foreach my $fk (@fk)
	    {
		$fk->register_update( $data{ $fk->column_from->name } );
	    }
	}
    };
    if ($@)
    {
	$driver->rollback;
	$@->rethrow;
    }
    else
    {
	$driver->finish_transaction( table => $self->table,
				     id => [ values %{ $self->{id} } ],
				     fk => \@fk ) if @fk && $self->table->schema->referential_integrity;
    }
    $self->{cache}->register_change($self) if $self->{cache};

    while (my ($k, $v) = each %data)
    {
	$self->{data}{$k} = $v;
    }
}

sub delete
{
    my Alzabo::Runtime::Row $self = shift;

    if ($self->{cache})
    {
	AlzaboCacheException->throw( 'Cannot delete an expired object' )
	    unless $self->check_cache;
    }

    my $driver = $self->table->schema->driver;

    my @fk;
    if ($self->table->schema->referential_integrity)
    {
	@fk = $self->{table}->all_foreign_keys;

	$driver->start_transaction( table => $self->table,
				    id => $self->id,
				    fk => \@fk ) if @fk;
    }

    my @pk = $self->{table}->primary_key;
    my $sql = 'DELETE FROM ' . $self->{table}->name;
    $sql .= ' WHERE ';
    $sql .= join ' AND ', map {$_->name . ' = ?'} @pk;

    eval
    {
	$driver->do( sql => $sql,
		     bind => [ map { $self->{id}{ $_->name } } @pk ] );

	if ($self->table->schema->referential_integrity)
	{
	    foreach my $fk (@fk)
	    {
		$fk->register_delete($self);
	    }
	}
    };
    if ($@)
    {
	$driver->rollback;
	$@->rethrow;
    }
    else
    {
	$driver->finish_transaction( table => $self->table,
				     id => $self->id,
				     fk => \@fk ) if @fk && $self->table->schema->referential_integrity;
    }

    $self->{cache}->register_delete($self) if $self->{cache};
}

sub check_cache
{
    my Alzabo::Runtime::Row $self = shift;

    AlzaboCacheException->throw( error => "Object has been deleted" )
	if $self->{cache}->is_deleted($self);

    if ( $self->{cache}->is_expired($self) )
    {
	$self->{data} = {};

	while (my ($k, $v) = each %{ $self->{id} })
	{
	    $self->{data}{$k} = $v;
	}

	my @pre = $self->{table}->prefetch;
	$self->get_data(@pre) if @pre;

	return 0;
    }

    return 1;
}

sub table
{
    my Alzabo::Runtime::Row $self = shift;

    return $self->{table};
}

sub rows_by_foreign_key
{
    my Alzabo::Runtime::Row $self = shift;
    my %p = @_;

    my $fk = $p{foreign_key};

    my $where = $fk->column_to->name . ' = ?';
    return $fk->table_to->rows_by_where_clause( where => $where,
						bind => $self->select( $fk->column_from->name ),
						%p );
}

# Class or object method
sub id
{
    my Alzabo::Runtime::Row $self = shift;
    my %p = @_;

    my $table = ref $self ? $self->{table} : $p{table};

    if (ref $self)
    {
	return join ';:;_;:;', ( $table->schema->name,
				 $table->name,
				 map { $_, $self->{id}{$_} } sort keys %{ $self->{id} } );
    }
    else
    {
	my $id_hash = $self->_make_id_hash(%p);
	return join ';:;_;:;', ( $table->schema->name,
				 $table->name,
				 map { $_, $id_hash->{$_} } sort keys %$id_hash );
    }
}

sub _no_such_row_error
{
    my Alzabo::Runtime::Row $self = shift;

    my $err = 'Unable to find a row in ' . $self->{table}->name . ' where ';
    my @vals;
    while ( my ($k, $v) = each %{ $self->{id} } )
    {
	my $val = "$k = $v";
	push @vals, $val;
    }
    $err .= join ', ', @vals;
    AlzaboNoSuchRowException->throw( error => $err );
}

__END__

=head1 NAME

Alzabo::Runtime::Row - Row objects

=head1 SYNOPSIS

  use Alzabo::Runtime::Row;

  ... or ...

  use Alzabo::Runtime::Row qw(MyCaching::Class);

=head1 DESCRIPTION

These objects represent actual rows from the database containing
actual data.  They can be created via their new method or via an
Alzabo::Runtime::Table object.

=head1 Alzabo::Runtime::Row import METHOD

This method is called when you C<use> this class.  You can pass a
string to the module via the C<use> function.  This string is assumed
to be the name of a class which does caching and that has a specific
interface that Alzabo::Runtime::Row expects (see the CACHING CLASSES
section for more details).  The Alzabo::Runtime::Row class will
attempt to load the class you have specified and will then use it for
all future caching operations.

The default is to use the Alzabo::ObjectCache class.  If you are
programming in a persistent environment it is highly recommended that
you read L<Alzabo::ObjectCache/"CAVEATS"> for more information on how
that class works.

=head1 METHODS

=item * new

Takes the following parameters:

=item -- table => Alzabo::Runtime::Row object

=item -- id => (see below)

=item -- no_cache => 0 or 1

The 'id' parameter may be one of two things.  If the table has only a
single column primary key, it can be a simple scalar with the value of
that primary key for this row.

If the primary key is more than one column than it must be a hash
reference containing column names and values such as:

  { pk_column1 => 1,
    pk_column2 => 'foo' }

Returns a new row object.  If you specified a caching class it will
attempt to retrieve the row from the cache first unless the 'no_cache'
parameter is true.  If no object matches these values then an
exception _will_ be thrown.

Setting the 'no_cache' parameter to true causes this particular row
object to not interact with the caching class at all.  This can be
useful if you know you will be creating a very large number of row
objects all at once that you have no intention of re-using any time
soon and your cache class uses an LRU type of cache or something
similar.

If your cache class attempts to synchronize itself across multiple
processes, then it is highly recommended that you not do any
operations that change data in the database with objects that were
created with this parameter as it will probably cause a big nasty
mess.  Don't say I didn't warn you.

Exceptions:

 AlzaboException - attempt to create a row for a table without a
 primary key.
 AlzaboNoSuchRowException - no row matched the primary key values
 given

item * get_data

Tells the row object to connect to the database and fetch the data for
the row matching this row's primary key values.  If a cache class is
specified it attempts to fetch the data from the cache first.

Exceptions:

 AlzaboNoSuchRowException - no row in the RDBMS matches this object's
 primary key value(s).

=item * select (@list_of_column_names)

In list context, returns a list of values matching the specified
columns.  In scalar context it returns only a single value (the first
column specified).

Exceptions:

 AlzaboCacheException - the row this object represents has been
 deleted from the database.

item * update (%hash_of_columns_and_values)

Given a hash of columns and values, attempts to update the database to
and the object to represent these new values.

Exceptions:

 AlzaboCacheException - the row this object represents has been
 deleted from the database.
 AlzaboCacheException - the row has expired in the cache (something
 else updated the object before you did).
 AlzaboException - attempt to change the value of a primary key
 column. Instead, delete the row object and create a new one.
 AlzaboException - attempt to set a column to NULL which cannot be NULL.
 AlzaboReferentialIntegrity - something you tried to do violates
 referential integrity.

=item * delete

Deletes the row from the RDBMS and the cache, if it exists.

Exceptions:

 AlzaboCacheException - the row this object represents has been
 deleted from the database.
 AlzaboCacheException - the row has expired in the cache (something
 else updated the object before you did).

=item * id

Returns the row's id value as a string.  This can be passed to the
Alzabo::Runtime::Table C<row_by_id> method to recreate the row later.

=item * table

Returns the table object that this row belongs to.

=item * rows_by_foreign_key

Takes the following parameters:

=item -- foreign_key => Alzabo::ForeignKey object

Given a foreign key object, this method returns a
Alzabo::Runtime::RowCursor object for the rows in the table that the
relationship is _to_, based on the value of the relevant column in the
current row.

All other parameters given will be passed directly to the
Alzabo::Runtime::Row C<new> method (such as the 'no_cache' paremeter).

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
