package Alzabo::Runtime::Row;

use strict;
use vars qw($VERSION $CACHE_CLASS);

use Alzabo::Runtime;

#use fields qw( id table data cache );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.33 $ =~ /(\d+)\.(\d+)/;

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

    my $self = bless {}, $class;
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
    my Alzabo::Runtime::Row $self = shift;
    my %p = @_;

    return $p{id} if ref $p{id};

    my ($pk) = exists $p{table} ? $p{table}->primary_key : $self->table->primary_key;

    Alzabo::Exception::Logic( error => "Can't make rows for tables without a primary key" )
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
	foreach my $s ( $self->table->group_by_column($c) )
	{
	    $select{$s} = 1 unless exists $self->{data}{$s};
	}
    }

    my $driver = $self->table->schema->driver;

    my ($pk1, @pk) = $self->table->primary_key;

    my $sql = ( $self->table->schema->sqlmaker->
		select( $self->table->columns( sort keys %select ) )->
		from( $self->table ) );
    $self->_where($sql);

    my @row = $driver->one_row( sql => $sql->sql,
				bind => $sql->bind )
	or $self->_no_such_row_error;

    my %hash;
    @hash{ sort keys %select } = @row;

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
	Alzabo::Exception::Cache::Expired->throw( error => "Cannot update expired object" )
	    unless $self->check_cache;
    }

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
	    unless defined $data{$k} || $c->null;

	push @fk, $self->table->foreign_keys_by_column($c)
	    if $self->table->schema->referential_integrity;
    }

    return unless keys %data;

    # If we have foreign keys we'd like all the fiddling to be atomic.
    $driver->start_transaction( table => $self->table,
				id => [ values %{ $self->{id} } ],
				fk => \@fk ) if @fk && $self->table->schema->referential_integrity;

    my $sql = ( $self->table->schema->sqlmaker->
		update( $self->table ) );
    $sql->set( $self->table->column($_), $data{$_} ) foreach sort keys %data;

    $self->_where($sql);

    eval
    {
	$driver->do( sql => $sql->sql,
		     bind => $sql->bind );

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
	Alzabo::Exception::Cache::Expired->throw( 'Cannot delete an expired object' )
	    unless $self->check_cache;
    }

    my $driver = $self->table->schema->driver;

    my @fk;
    if ($self->table->schema->referential_integrity)
    {
	@fk = $self->table->all_foreign_keys;

	$driver->start_transaction( table => $self->table,
				    id => $self->id,
				    fk => \@fk ) if @fk;
    }

    my $sql = ( $self->table->schema->sqlmaker->
		delete->from( $self->table ) );
    $self->_where( $sql );

    eval
    {
	$driver->do( sql => $sql->sql,
		     bind => $sql->bind );

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
    my Alzabo::Runtime::Row $self = shift;

    Alzabo::Exception::Cache::Deleted->throw( error => "Object has been deleted" )
	if $self->{cache}->is_deleted($self);

    if ( $self->{cache}->is_expired($self) )
    {
	$self->{data} = {};

	while (my ($k, $v) = each %{ $self->{id} })
	{
	    $self->{data}{$k} = $v;
	}

	$self->get_data( $self->table->prefetch ) if $self->table->prefetch;

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

    my $fk = delete $p{foreign_key};

    my $fk_val = $self->select( $fk->column_from->name );

    if ( $fk->column_to->is_primary_key && scalar $fk->table_to->primary_key == 1 )
    {
	return $fk->table_to->row_by_pk( pk => $fk_val, %p );
    }
    else
    {
	if ($p{where})
	{
	    $p{where} = [ $p{where} ] unless UNIVERSAL::isa( $p{where}[0], 'ARRAY' );
	}

	push @{ $p{where} }, [ $fk->column_to, '=', $fk_val ];
	return $fk->table_to->rows_where(%p);
    }
}

# Class or object method
sub id
{
    my Alzabo::Runtime::Row $self = shift;
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
    my Alzabo::Runtime::Row $self = shift;

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

=head1 import METHOD

This method is called when you C<use> this class.  You can pass a
string to the module via the C<use> function.  This string is assumed
to be the name of a class which does caching and that has a specific
interface that C<Alzabo::Runtime::Row> expects (see the CACHING
CLASSES section for more details).  The C<Alzabo::Runtime::Row> class
will attempt to load the class you have specified and will then use it
for all future caching operations.

The default is to use the
L<C<Alzabo::ObjectCache>|Alzabo::ObjectCache> class.  If you are
programming in a persistent environment it is highly recommended that
you read L<C<Alzabo::ObjectCache> CAVEATS
section|Alzabo::ObjectCache/CAVEATS> for more information on how that
class works.

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

Given a foreign key object, this method returns a
L<C<Alzabo::Runtime::RowCursor>|Alzabo::Runtime::RowCursor> object for
the rows in the table that the relationship is _to_, based on the
value of the relevant column in the current row.

All other parameters given will be passed directly to the
L<C<new>|new> method (such as the C<no_cache>
paremeter).

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
