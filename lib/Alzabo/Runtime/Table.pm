package Alzabo::Runtime::Table;

use strict;
use vars qw($VERSION);

use Alzabo::Runtime;

use base qw(Alzabo::Table);

#use fields qw(prefetch groups);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.32 $ =~ /(\d+)\.(\d+)/;

1;

sub insert
{
    my Alzabo::Runtime::Table $self = shift;
    my %p = @_;

    my $vals = delete $p{values};

    my $driver = $self->schema->driver;

    my @pk = $self->primary_key;
    foreach my $pk (@pk)
    {
	unless (exists $vals->{ $pk->name })
	{
	    if ($pk->sequenced)
	    {
		$vals->{ $pk->name } = $driver->next_sequence_number($pk);
	    }
	    else
	    {
		Alzabo::Exception::Params->throw( error => "No value provided for primary key (" . $pk->name . ") and no sequence is available." );
	    }
	}
    }

    my @fk;
    foreach my $c ($self->columns)
    {
	push @fk, $self->foreign_keys_by_column($c);

	next if $c->is_primary_key;

	Alzabo::Exception::Params->throw( error => "Column " . $c->name . " cannot be null." )
            unless defined $vals->{ $c->name } || $c->null;
    }

    $driver->start_transaction( table => $self,
				id => 'insert' ) if @fk;


    my $sql = ( $self->schema->sqlmaker->
		insert->
		into($self, $self->columns( sort keys %$vals ) )->
		values( map { $self->column($_) => $vals->{$_} } sort keys %$vals ) );

    my %id;
    eval
    {
	foreach my $fk (@fk)
	{
	    $fk->register_insert( $vals->{ $fk->column_from->name } );
	}

	$self->schema->driver->do( sql => $sql->sql,
				   bind => $sql->bind );

	foreach my $pk (@pk)
	{
	    $id{ $pk->name } = ( defined $vals->{ $pk->name } ?
				 $vals->{ $pk->name } :
				 $driver->get_last_id($self) );
	}
    };
    if ($@)
    {
	$driver->rollback;
	$@->rethrow;
    }
    else
    {
	$driver->finish_transaction( table => $self,
				     id => 'insert' ) if @fk;
    }

    return $self->row_by_pk( pk => \%id, %p );
}

sub row_by_pk
{
    my Alzabo::Runtime::Table $self = shift;
    my %p = @_;

    my $pk_val = exists $p{pk} ? $p{pk} : $p{id};

    my @pk = $self->primary_key;

    Alzabo::Exception::Params->throw( error => 'Incorrect number of pk values provided.  ' . scalar @pk . ' are needed.')
	if ref $pk_val && @pk != scalar keys %$pk_val;

    if (@pk > 1)
    {
	Alzabo::Exception::Params->throw( error => 'Primary key for ' . $self->name . ' is more than one column.  Please provide multiple key values as a hashref.' )
	    unless ref $pk_val;

	foreach my $pk (@pk)
	{
	    Alzabo::Exception::Params->throw( error => 'No value provided for primary key ' . $pk->name . '.' )
		unless defined $pk_val->{ $pk->name };
	}
    }

    return Alzabo::Runtime::Row->new( %p,
				      table => $self,
				      id => $pk_val );
}

sub row_by_id
{
    my Alzabo::Runtime::Table $self = shift;
    my %p = @_;

    my (undef, undef, %pk) = split ';:;_;:;', $p{row_id};

    return $self->row_by_pk( %p, pk => \%pk );
}

sub rows_where
{
    my Alzabo::Runtime::Table $self = shift;
    my %p = @_;

    my $sql = $self->_make_sql;

    if ( $p{where} )
    {
	$p{where} = [ $p{where} ] unless UNIVERSAL::isa( $p{where}[0], 'ARRAY' );
	my $x = 0;
	foreach ( @{ $p{where} } )
	{
	    my $op = $x++ ? 'and' : 'where';
	    $sql->$op(@$_);
	}
    }

    return $self->_cursor_by_sql( %p, sql => $sql );
}

sub all_rows
{
    my Alzabo::Runtime::Table $self = shift;

    my $sql = $self->_make_sql(@_);

    return $self->_cursor_by_sql( @_, sql => $sql );
}

sub _make_sql
{
    my Alzabo::Runtime::Table $self = shift;
    my %p = @_;

    my $sql = ( $self->schema->sqlmaker->
		select( $self->primary_key )->
		from( $self ) );

    return $sql;
}

sub _cursor_by_sql
{
    my Alzabo::Runtime::Table $self = shift;
    my %p = @_;

    if ( exists $p{order_by} )
    {
	Alzabo::Exception::Params->throw( error => "No columns provided for order by" )
	    unless $p{order_by}{columns};

	my @c = ( UNIVERSAL::isa( $p{order_by}{columns}, 'ARRAY' ) ?
		  @{ $p{order_by}{columns} } :
		  $p{order_by}{columns} );

	$p{sql}->order_by( @c );

	if ( defined $p{order_by}{sort} )
	{
	    my $s = lc $p{order_by}{sort};
	    $p{sql}->$s();
	}
    }

    if ( exists $p{limit} )
    {
	$p{sql}->limit( ref $p{limit} ? @{ $p{limit} } : $p{limit} );
    }

    my $statement = $self->schema->driver->statement( sql => $p{sql}->sql,
						      bind => $p{sql}->bind,
						      limit => $p{sql}->get_limit );

    return Alzabo::Runtime::RowCursor->new( statement => $statement,
					    table => $self,
					    no_cache => $p{no_cache} );
}

sub row_count
{
    my Alzabo::Runtime::Table $self = shift;

    my $sql = $self->schema->sqlmaker->select->count('*')->from($self);
    return $self->schema->driver->one_row( sql => $sql->sql );
}

sub set_prefetch
{
    my Alzabo::Runtime::Table $self = shift;
    $self->{prefetch} = $self->_canonize_prefetch(@_);
}

sub _canonize_prefetch
{
    my Alzabo::Runtime::Table $self = shift;

    foreach my $c (@_)
    {
	Alzabo::Exception::Params->throw( error => "Column " . $c->name . " doesn't exist in $self->{name}" )
	    unless exists $self->{columns}{ $c->name };
    }

    return [ map {$_->name} grep { ! $_->is_primary_key($_) } @_ ]
}

sub prefetch
{
    my Alzabo::Runtime::Table $self = shift;

    return ref $self->{prefetch} ? @{ $self->{prefetch} } : ();
}

sub add_group
{
    my Alzabo::Runtime::Table $self = shift;

    my @names = map { $_->name } @_;
    foreach my $col (@_)
    {
	Alzabo::Exception::Params->throw( error => "Column " . $col->name . " doesn't exist in $self->{name}" )
		unless $self->{columns}->EXISTS( $col->name );

	next if $col->is_primary_key;
	$self->{groups}{ $col->name } = \@names;
    }
}

sub group_by_column
{
    my Alzabo::Runtime::Table $self = shift;
    my $col = shift;

    return exists $self->{groups}{$col} ? @{ $self->{groups}{$col} } : $col;
}

__END__

=head1 NAME

Alzabo::Runtime::Table - Table objects

=head1 SYNOPSIS

  my $table = $schema->table('foo');

  my $row = $table->row_by_pk( pk => 1 );

  my $row_cursor = $table->rows_where( where => [ C<Alzabo::Column> object, '=', 5 } );

=head1 DESCRIPTION

This object is able to create rows, either by making objects based on
existing data or inserting new data to make new rows.

This object also implements a method of lazy column evaluation that
can be used to save memory and database wear and tear, though it needs
to be used carefully.  Please see methods as well as L<LAZY COLUMN
LOADING> for details.

=head1 INHERITS FROM

C<Alzabo::Table>

=for pod_merge merged

=head1 METHODS

=head2 Methods that return an C<Alzabo::Runtime::Row> object

=head2 insert

Inserts the given values into the table.  If no values are given for a
primary key column and the column is
L<sequenced|Alzabo::Column/sequenced> then the values will be
generated from the sequence.

=head3 Parameters

=over 4

=item * values => $hashref

The hashref contains column names and values for the new row.

=back

All other parameters given will be passed directly to the
L<C<Alzabo::Runtime::Row-E<gt>new>|Alzabo::Runtime::Row/new> method
(such as the C<no_cache> parameter).

=head3 Returns

A new L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> object.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=head2 row_by_pk

The primary key can be either a simple scalar, as when the table has a
single primary key, or a hash reference of column names to primary key
values when the primary key is more than one column.

=head3 Parameters

=over 4

=item * pk => $pk_val or \%pk_val

=back

All other parameters given will be passed directly to the
L<C<Alzabo::Runtime::Row-E<gt>new>|Alzabo::Runtime::Row/new>
method (such as the C<no_cache> parameter).

=head3 Returns

A new L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> object.  If no
rows in the database match the value(s) given then an empty list or
undef will be returned (for list or scalar context).

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=head2 row_by_id

This method is useful for regenerating a row that has been saved by
reference to its id (returned by the
L<C<Alzabo::Runtime::Row-E<gt>id>|Alzabo::Runtime::Row/id> method).
This may be more convenient than saving a multi-column primary key
when trying to maintain state in a wbe app, for example.

=head3 Parameters

=over 4

=item * row_id => $row_id

=back

A string representation of a row's id (as returned by the
L<C<Alzabo::Runtime::Row-E<gt>id>|Alzabo::Runtime::Row/id> method).

All other parameters given will be passed directly to the
L<C<Alzabo::Runtime::Row-E<gt>new>|Alzabo::Runtime::Row/new>
method (such as the C<no_cache> parameter).

=head3 Returns

A new L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> object.  If no
rows in the database match the value(s) given then an empty list or
undef will be returned (for list or scalar context).

=head2 Methods that return C<Alzabo::Runtime::RowCursor> object

The following methods, L<C<rows_where>|rows_where> and
L<C<all_rows>|all_rows>, all return an
L<C<Alzabo::Runtime::RowCursor>|Alzabo::Runtime::RowCursor> object
representing the results of the query.  This is the case even for
queries that end up returning one or zero rows.

=head3 Common Parameters

These three methods all take the following parameters in addition to
whatever is described:

=over 4

=item * order_by => $group_by_clause

=item * group_by => $sort_by_clause

=back

These items should be valid SQL, though there is not need to include
the keywords 'ORDER BY' or 'GROUP BY'.

=head2 rows_where

A simple way to retrieve a row cursor based on one or more colum
values.  This does not handle any conditionals besides equality.

=head3 Parameters

=over 4

=item * where => [ C<Alzabo::Column> object, $comparison, $value or C<Alzabo::Column> object ]

This parameter can take a variety of values.  It can take a single
array reference as shown above.  The C<$comparison> should be a string
containing a SQL operator such as C<'E<gt>'> or C<'='>.

The parameter can also be an array of references to such arrays:

 [ [ C<Alzabo::Column> object, $comparison, $value or C<Alzabo::Column> object ],
   [ C<Alzabo::Column> object, $comparison, $value or C<Alzabo::Column> object ] ]

For more details on exactly what the possibilities are here, please
see the L<documentation for Alzabo::SQLMaker|Alzabo::SQLMaker/where (
(Alzabo::Column object), $comparison, (Alzabo::Column object, $value,
or Alzabo::SQLMaker statement), [ see below ] )>.  Multiple values
given to this parameter will be joined together by a logical 'AND'.

=back

All other parameters given will be passed directly to the
L<C<Alzabo::Runtime::Row-E<gt>new>|Alzabo::Runtime::Row/new>
method (such as the C<no_cache> parameter).

Given these items this method generates SQL that will retrieve a set
of primary keys for the table.

=head3 Returns

An L<C<Alzabo::Runtime::RowCursor>|Alzabo::Runtime::RowCursor> object
representing the query.

=head2 all_rows

Simply returns all the rows in the table.

=head3 Parameters

All parameters given will be passed directly to the
L<C<Alzabo::Runtime::Row-E<gt>new>|Alzabo::Runtime::Row/new> method
(such as the C<no_cache> parameter).

=head3 Returns

An L<C<Alzabo::Runtime::RowCursor>|Alzabo::Runtime::RowCursor> object
representing the query.

=head2 Other Methods

=head2 row_count

=head3 Returns

A scalar indicating how many rows the table has.

=for pod_merge schema

=for pod_merge name

=for pod_merge column

=for pod_merge columns

=for pod_merge primary_key

=for pod_merge column_is_primary_key

=for pod_merge foreign_keys

=for pod_merge foreign_keys_by_table

=for pod_merge foreign_keys_by_column

=for pod_merge all_foreign_keys

=for pod_merge index

=for pod_merge indexes

=head1 LAZY COLUMN LOADING

This concept was taken directly from Michael Schwern's Class::DBI
module (credit where it is due).

By default, L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> objects
only load data from the database as it is requested via the select
method.  This is stored internally in the object after being fetched.
If the object is expired in the cache, it will erase this information
and fetch it from the database again as needed.

This is good because it saves on memory and makes object creation
quicker, but it is bad because you could potentially end up with one
SQL call per column (excluding primary key columns, which are usually
not fetched from the database).

This class provides two method to help you handle this potential
problem.  Basically these methods allow you to declare usage patterns
for the table.

The first method,
L<C<set_prefetch>|Alzabo::Runtime::Table/set_prefetch (Alzabo::Column
objects)>, allows you to specify a list of columns to be fetched
immediately after object creation or after an object discovers it is
expired in the cache.  These should be columns that you expect to use
extremely frequently.

The second method, L<C<add_group>|Alzabo::Runtime::Table/add_group (Alzabo::Column objects)>,
allows you to group columns together.  If you attempt to fetch one of
these columns, then all the columns in the group will be fetched.
This is useful in cases where you don't often want certain data, but
when you do you need several related pieces.

=head2 Lazy column loading related methods

=head2 set_prefetch (C<Alzabo::Column> objects)

Given a list of column objects, this makes sure that all
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> objects fetch this
data as soon as they are created, as well as immediately after they
know they have been expired in the cache.

NOTE: It is pointless (though not an error) to give primary key column
here as these are always prefetched (in a sense).

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=head2 add_group (C<Alzabo::Column> objects)

Given a list of L<C<Alzabo::Column>|Alzabo::Column> objects, this
method creates a group containing these columns.  This means that if
any column in the group is fetched from the database, then they will
all be fetched.  Otherwise column are always fetched singly.
Currently, a column cannot be part of more than one group.

NOTE: It is pointless to include a column that was given to the
L<C<set_prefetch>|Alzabo::Runtime::Table/set_prefetch (Alzabo::Column
objects)> method in a group here, as it always fetched as soon as
possible.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=head2 prefetch

This method primarily exists for use by the
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> class.

=head3 Returns

A list of column names (not objects) that should be prefetched.

=head2 group_by_column ($column_name)

This method primarily exists for use by the
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> class.

=head3 Returns

A list of column names representing the group that this column is part
of.  If the column named is not part of a group, only the name passed
in is returned.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
