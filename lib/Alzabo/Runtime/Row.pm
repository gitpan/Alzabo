package Alzabo::Runtime::Row;

use strict;
use vars qw($VERSION);

use Alzabo::Runtime;

use Params::Validate qw( :all );
Params::Validate::set_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.52 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    validate( @_, { table => { isa => 'Alzabo::Runtime::Table' },
		    id => { type => SCALAR | HASHREF,
			    optional => 1 },
		    prefetch => { type => UNDEF | HASHREF,
				  optional => 1 },
		    time => { type => UNDEF | SCALAR,
			      optional => 1 },
		    no_cache => { optional => 1 },
		    insert => { optional => 1 } } );
    my %p = @_;

    unless ( ref $p{prefetch} && $p{time} )
    {
	delete $p{prefetch};
	delete $p{time};
    }

    my $self;
    if ( $Alzabo::ObjectCache::VERSION && ! $p{no_cache} )
    {
	$self = Alzabo::Runtime::CachedRow->new(%p);
	return $self if exists $self->{data};
    }
    else
    {
	$self = bless {}, $class;
    }

    $self->{table} = $p{table};

    Alzabo::Exception::Logic->throw( error => "Can't make rows for tables without a primary key" )
	unless $self->table->primary_key;

    $self->{id} = $self->_make_id_hash(%p);

    $self->_init(%p);

    return $self;
}

sub _init
{
    my $self = shift;
    my %p = @_;

    while ( my ($k, $v) = each %{ $self->{id} } )
    {
	$self->{data}{$k} = $v;
    }

    # If there is
    unless ( keys %{ $self->{data} } > keys %{ $self->{id} } )
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

    return { ($p{table}->primary_key)[0]->name => $p{id} };
}

sub _get_data
{
    my $self = shift;
    my @cols = @_;

    my $driver = $self->table->schema->driver;

    my $sql = ( $self->table->schema->sqlmaker->
		select( $self->table->columns(@cols) )->
		from( $self->table ) );
    $self->_where($sql);

    my @row = $driver->one_row( sql => $sql->sql,
				bind => $sql->bind )
	or $self->_no_such_row_error;

    my %data;
    @data{@cols} = @row;

    return %data;
}

sub select
{
    my $self = shift;
    my @cols = @_;

    my %data = $self->_get_data(@cols);

    return wantarray ? @data{@cols} : $data{ $cols[0] };
}

sub update
{
    my $self = shift;
    my %data = @_;

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
}

sub delete
{
    my $self = shift;

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

    if (ref $self)
    {
	return $self->{id_string} if exists $self->{id_string};
	$self->{id_string} = join ';:;_;:;', ( $self->table->schema->name,
					       $self->table->name,
					       map { $_, $self->{id}{$_} } sort keys %{ $self->{id} } );
	return $self->{id_string};
    }
    else
    {
	my $id_hash = $self->_make_id_hash(%p);
	return join ';:;_;:;', ( $p{table}->schema->name,
				 $p{table}->name,
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

=head1 DESCRIPTION

These objects represent actual rows from the database containing
actual data.  They can be created via their new method or via an
Alzabo::Runtime::Table object.

=head1 CACHING

If you load the L<C<Alzabo::ObjectCache>|Alzabo::ObjectCache> module
before loading this one, then row objects will be cached, as will
database accesses.

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

If your cache class synchronizes itself across multiple processes
does), then it is highly recommended that you not do any operations
that change data in the database (delete or update) with objects that
were created with this parameter as it will probably cause problems.

=head3 Returns

A new C<Alzabo::Runtiem::Row> object.  It will attempt to retrieve the
row from the cache first unless the C<no_cache> parameter is true.  If
no object matches these values then an exception will be thrown.

=head3 Throws

L<C<Alzabo::Exception::NoSuchRow>|Alzabo::Exceptions>

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
