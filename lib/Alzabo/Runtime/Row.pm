package Alzabo::Runtime::Row;

use strict;
use vars qw($VERSION $CACHE);

use Alzabo::Runtime;

use Params::Validate qw( :all );
Params::Validate::set_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.45 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    validate( @_, { table => { isa => 'Alzabo::Runtime::Table' },
		    id => { type => SCALAR | HASHREF },
		    no_cache => { optional => 1 },
		    insert => { optional => 1 } } );
    my %p = @_;

    if ( defined $CACHE && $CACHE && ! $p{insert} )
    {
	my $row = $CACHE->fetch_object( $class->id(@_) );
	if ($row)
	{
	    $row->check_cache;
	    return $row;
	}
    }
    elsif (! defined $CACHE)
    {
	# If the module isn't loaded we assume the user doesn't want
	# caching done we stick a 0 in $CACHE to prevent going through
	# this code again
	$CACHE = $Alzabo::ObjectCache::VERSION ? Alzabo::ObjectCache->new : 0;
    }

    my $self = bless {}, $class;

    $self->{table} = $p{table};
    $self->{id} = $self->_make_id_hash(%p);
    $self->{cache} = $CACHE if $CACHE && (! $p{no_cache});

    $self->{cache}->delete_from_cache($self)
	if $p{insert} && $self->{cache};

    $self->_init;

    $self->{cache}->store_object($self)
	if $self->{cache};
    $self->{cache}->register_change($self) if $self->{cache} && $p{insert};

    return $self;
}

sub _init
{
    my $self = shift;

    while (my ($k, $v) = each %{ $self->{id} })
    {
	$self->{data}{$k} = $v;
    }

    if (my @pre = $self->table->prefetch)
    {
	$self->get_data(@pre);
    }
    else
    {
	# Need to try to fetch something to confirm that this row exists!
	my $sql = ( $self->table->schema->sqlmaker->
		    select( ($self->table->primary_key)[0] )->
		    from( $self->table ) );

	$self->_where($sql);

	$self->_no_such_row_error
	    unless defined $self->table->schema->driver->one_row( sql => $sql->sql,
								  bind => $sql->bind );
    }
}

sub _make_id_hash
{
    my $self = shift;
    my %p = @_;

    return $p{id} if ref $p{id};

    my ($pk) = exists $p{table} ? $p{table}->primary_key : $self->table->primary_key;

    Alzabo::Exception::Logic( error => "Can't make rows for tables without a primary key" )
	unless $pk;

    return { $pk->name => $p{id} };
}

sub get_data
{
    my $self = shift;
    my @cols = @_;

    my %select;
    my %data;
    foreach my $c (@cols)
    {
	if ($self->{cache})
	{
	    foreach my $s ( $self->table->group_by_column($c) )
	    {
		if ( exists $self->{data}{$s} )
		{
		    $data{$s} = $self->{data}{$s};
		}
		else
		{
		    $select{$s} = 1;
		}
	    }
	}
	else
	{
	    $select{$c} = 1;
	}
    }

    if (keys %select)
    {
	my $driver = $self->table->schema->driver;

	my $sql = ( $self->table->schema->sqlmaker->
		    select( $self->table->columns( sort keys %select ) )->
		    from( $self->table ) );
	$self->_where($sql);

	my @row = $driver->one_row( sql => $sql->sql,
				    bind => $sql->bind )
	    or $self->_no_such_row_error;

	@data{ sort keys %select } = @row;

	$self->{cache}->register_refresh($self) if $self->{cache};

	if ($self->{cache})
	{
	    while (my ($k, $v) = each %data)
	    {
		$self->{data}{$k} = $v;
	    }
	}
    }

    return \%data;
}

sub select
{
    my $self = shift;
    my @cols = @_;

    $self->check_cache if $self->{cache};

    my $data = $self->get_data(@cols);

    return wantarray ? @{ $data }{@cols} : $data->{ $cols[0] };
}

sub update
{
    my $self = shift;
    my %data = @_;

    if ($self->{cache})
    {
	Alzabo::Exception::Cache::Expired->throw( error => "Cannot update expired object" )
	    unless $self->check_cache;
    }

    $self->_no_such_row_error if $self->{deleted};

    my $driver = $self->table->schema->driver;

    my @fk;
    foreach my $k (keys %data)
    {
	# This will throw an exception if the column doesn't exist.
	my $c = $self->table->column($k);

	Alzabo::Exception::Params->throw( error => 'Cannot change the value of primary key columns.  Delete the row object and create a new one instead.' )
	    if $c->is_primary_key;

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
	Alzabo::Exception::Params->throw( error => "Column " . $c->name . " cannot be null." )
	    unless defined $data{$k} || $c->nullable || defined $c->default;

	push @fk, $self->table->foreign_keys_by_column($c)
	    if $self->table->schema->referential_integrity;
    }

    return unless keys %data;

    # If we have foreign keys we'd like all the fiddling to be atomic.
    $driver->start_transaction;

    my $sql = ( $self->table->schema->sqlmaker->
		update( $self->table ) );
    $sql->set( map { $self->table->column($_), $data{$_} } keys %data );

    $self->_where($sql);

    eval
    {
	$driver->do( sql => $sql->sql,
		     bind => $sql->bind );

	if ($self->table->schema->referential_integrity)
	{
	    foreach my $fk (@fk)
	    {
		$fk->register_update( map { $_->name => $data{ $_->name } } $fk->columns_from );
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
	$driver->finish_transaction;
    }

    $self->{cache}->register_change($self) if $self->{cache};

    if ($self->{cache})
    {
	while (my ($k, $v) = each %data)
	{
	    $self->{data}{$k} = $v;
	}
    }
}

sub delete
{
    my $self = shift;

    if ($self->{cache})
    {
	Alzabo::Exception::Cache::Expired->throw( error => 'Cannot delete an expired object' )
	    unless $self->check_cache;
    }

    my $driver = $self->table->schema->driver;

    my @fk;
    if ($self->table->schema->referential_integrity)
    {
	@fk = $self->table->all_foreign_keys;

	$driver->start_transaction;
    }

    my $sql = ( $self->table->schema->sqlmaker->
		delete->from( $self->table ) );
    $self->_where( $sql );

    eval
    {
	if ($self->table->schema->referential_integrity)
	{
	    foreach my $fk (@fk)
	    {
		$fk->register_delete($self);
	    }
	}

	$driver->do( sql => $sql->sql,
		     bind => $sql->bind );

    };
    if ($@)
    {
	$driver->rollback;
	$@->rethrow;
    }
    else
    {
	$driver->finish_transaction;
    }

    $self->{cache}->register_delete($self) if $self->{cache};
    $self->{deleted} = 1;
}

sub _where
{
    my $self = shift;
    my $sql = shift;

    my ($pk1, @pk) = $self->table->primary_key;

    $sql->where( $pk1, '=', $self->{id}{ $pk1->name } );
    $sql->and( $_, '=', $self->{id}{ $_->name } ) foreach @pk;
}

sub check_cache
{
    my $self = shift;

    Alzabo::Exception::Cache::Deleted->throw( error => "Object has been deleted" )
	if $self->{cache}->is_deleted($self);

    if ( $self->{cache}->is_expired($self) )
    {
	$self->{data} = {};

	while (my ($k, $v) = each %{ $self->{id} })
	{
	    $self->{data}{$k} = $v;
	}

	if ($self->table->prefetch)
	{
	    $self->get_data( $self->table->prefetch );
	}
	else
	{
	    $self->{cache}->register_refresh($self) if $self->{cache};
	}

	return 0;
    }

    return 1;
}

sub table
{
    my $self = shift;

    return $self->{table};
}

sub rows_by_foreign_key
{
    my $self = shift;
    my %p = @_;

    my $fk = delete $p{foreign_key};

    my %fk_vals = map { $_->name => $self->select( $_->name ) } $fk->columns_from;

    if ( ( grep { $_->is_primary_key } $fk->columns_to ) == scalar $fk->table_to->primary_key )
    {
	return $fk->table_to->row_by_pk( pk => \%fk_vals, %p );
    }
    else
    {
	if ($p{where})
	{
	    $p{where} = [ $p{where} ] unless UNIVERSAL::isa( $p{where}[0], 'ARRAY' );
	}

	push @{ $p{where} }, map { [ $_->[1], '=', $fk_vals{ $_->[0]->name } ] } $fk->column_pairs;
	return $fk->table_to->rows_where(%p);
    }
}

# Class or object method
sub id
{
    my $self = shift;
    my %p = @_;

    my $table = ref $self ? $self->table : $p{table};

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
    my $self = shift;

    my $err = 'Unable to find a row in ' . $self->table->name . ' where ';
    my @vals;
    while ( my ($k, $v) = each %{ $self->{id} } )
    {
	my $val = "$k = $v";
	push @vals, $val;
    }
    $err .= join ', ', @vals;
    Alzabo::Exception::NoSuchRow->throw( error => $err );
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

=head1 CACHING

This module attempts to use the
L<C<Alzabo::ObjectCache>|Alzabo::ObjectCache> module if it has already
been loaded when a new row is created.  It will use the cache to store
objects after they are created as well as using it check object
expiration and deletion.

In addition, using the cache allows the object to cache the results of
column fetches.  This is an additional performance gain.

=head1 METHODS

=head2 new

=head3 Parameters

=over 4

=item * table => C<Alzabo::Runtime::Table> object

=item * id => (see below)

=item * no_cache => 0 or 1

The C<id> parameter may be one of two things.  If the table has only a
single column primary key, it can be a simple scalar with the value of
that primary key for this row.

If the primary key is more than one column than it must be a hash
reference containing column names and values such as:

  { pk_column1 => 1,
    pk_column2 => 'foo' }

=back

Setting the C<no_cache> parameter to true causes this particular row
object to not interact with the cache at all.  This can be useful if
you know you will be creating a very large number of row objects all
at once that you have no intention of re-using.

If your cache class attempts to synchronize itself across multiple
processes (such as L<C<Alzabo::ObjectCacheIPC>|Alzabo::ObjectCacheIPC>
does), then it is highly recommended that you not do any operations
that change data in the database (delete or update) with objects that
were created with this parameter as it will probably cause problems.

=head3 Returns

A new C<Alzabo::Runtiem::Row> object.  It will attempt to retrieve the
row from the cache first unless the C<no_cache> parameter is true.  If
no object matches these values then an exception will be thrown.

=head3 Throws

L<C<Alzabo::Exception::NoSuchRow>|Alzabo::Exceptions>

=head2 get_data

Tells the row object to connect to the database and fetch the data for
the row matching this row's primary key values.  If a cache class is
specified it attempts to fetch the data from the cache first.

=head2 select (@list_of_column_names)

=head3 Returns

Returns a list of values matching the specified columns in a list
context.  In scalar context it returns only a single value (the first
column specified).

=head2 update (%hash_of_columns_and_values)

Given a hash of columns and values, attempts to update the database to
and the object to represent these new values.

=head2 delete

Deletes the row from the RDBMS and the cache, if it exists.

=head2 id

Returns the row's id value as a string.  This can be passed to the
L<C<Alzabo::Runtime::Table-E<gt>row_by_id>|Alzabo::Runtime::Table/row_by_id>
method to recreate the row later.

=head2 table

Returns the L<C<Alzabo::Runtime::Table>|Alzabo::Runtime::Table> object
that this row belongs to.

=head2 rows_by_foreign_key

=head3 Parameters

=over 4

=item * foreign_key => C<Alzabo::Runtime::ForeignKey> object

=back

Given a foreign key object, this method returns either an
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> object or an
L<C<Alzabo::Runtime::RowCursor>|Alzabo::Runtime::RowCursor> object for
the row(s) in the table that to which the relationship exists, based
on the value of the relevant column(s) in the current row.

The type of object returned is based on the cardinality of the
relationship.  If the relationship says that there could only be one
matching row, then a row object is returned, otherwise it returns a
cursor.

All other parameters given will be passed directly to the
L<C<new>|new> method (such as the C<no_cache>
paremeter).

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
