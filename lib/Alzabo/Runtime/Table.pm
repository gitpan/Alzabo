package Alzabo::Runtime::Table;

use strict;
use vars qw($VERSION);

use Alzabo::Runtime;

use base qw(Alzabo::Table);
use fields qw(prefetch groups);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.16 $ =~ /(\d+)\.(\d+)/;

1;

sub insert
{
    my Alzabo::Runtime::Table $self = shift;
    my %p = @_;

    my $vals = $p{values};

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
		AlzaboException->throw( error => "No value provided for primary key (" . $pk->name . ") and no sequence is available." );
	    }
	}
    }

    my @fk;
    foreach my $c ($self->columns)
    {
	push @fk, $self->foreign_keys_by_column($c);

	next if $self->column_is_primary_key($c);

	AlzaboException->throw( error => "Column " . $c->name . " cannot be null." )
            unless defined $vals->{ $c->name } || $c->null;
    }

    $driver->start_transaction( table => $self,
				id => 'insert' ) if @fk;

    my $sql = 'INSERT INTO ' . $self->name . ' (';
    $sql .= join ', ', sort keys %$vals;
    $sql .= ') VALUES (';
    $sql .= join ', ', ('?') x scalar keys %$vals;
    $sql .= ')';

    my %id;
    eval
    {
	foreach my $fk (@fk)
	{
	    $fk->register_update( $vals->{ $fk->column_from->name } );
	}

	$self->schema->driver->do( sql => $sql,
				   bind => [ map { $vals->{$_} } sort keys %$vals ] );

	foreach my $pk (@pk)
	{
	    # special case for MySQL.  Sequenced columns will be undef
	    # (to use AUTO_INCREMENT feature in MySQL)
	    $id{ $pk->name } = defined $vals->{ $pk->name } ? $vals->{ $pk->name } : $driver->get_last_id($self);
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

    return $self->row_by_pk( id => \%id );
}

sub row_by_pk
{
    my Alzabo::Runtime::Table $self = shift;
    my %p = @_;

    my $pk_val = $p{id} || $p{pk};

    my @pk = $self->primary_key;

    AlzaboException->throw( error => 'Incorrect number of id values provided.  ' . scalar @pk . ' are needed.')
	if ref $pk_val && @pk != scalar keys %$pk_val;

    if (@pk > 1)
    {
	AlzaboException->throw( error => 'Primary key for ' . $self->name . ' is more than one column.  Please provide multiple key values as an hashref.' )
	    if ! ref $pk_val;

	foreach my $pk (@pk)
	{
	    AlzaboException->throw( error => 'No value provided for primary key ' . $pk->name . '.' )
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

    return $self->row_by_pk( %p, id => \%pk );
}

sub rows_where
{
    my Alzabo::Runtime::Table $self = shift;
    my %p = @_;

    my $sql = $self->_sql_base(%p);

    $sql .= ' WHERE ';
    my %where = %{ $p{where} };
    $sql .= join ' AND ', map { defined $where{$_} ? "$_ = ?" : "$_ IS NULL" } sort keys %where;
    my $bind = [ map { $where{$_} } grep { defined $where{$_} } sort keys %where ];

    return $self->_cursor_by_sql( %p, sql => $sql, bind => $bind );
}

sub rows_by_where_clause
{
    my Alzabo::Runtime::Table $self = shift;
    my %p = @_;

    my $sql = $self->_sql_base(%p);

    $sql .= ' WHERE ' . $p{where};

    return $self->_cursor_by_sql( %p, sql => $sql );
}

sub all_rows
{
    my Alzabo::Runtime::Table $self = shift;

    my $sql = $self->_sql_base;
    return $self->_cursor_by_sql( @_, sql => $sql );
}

sub _sql_base
{
    my Alzabo::Runtime::Table $self = shift;
    my %p = @_;

    my $sql = 'SELECT ';
    # Include table name in case of joins!
    $sql .= join ', ', map {$self->name . '.' . $_->name} $self->primary_key;
    $sql .= ' FROM ';

    if ($p{from})
    {
	$sql .= join ', ', $p{from};
    }
    else
    {
	$sql .= $self->name;
    }

    return $sql;
}

sub _cursor_by_sql
{
    my Alzabo::Runtime::Table $self = shift;
    my %p = @_;

    my @pk_names = map {$_->name} $self->primary_key;

    my @h;
    my %driver_p = ( sql => $p{sql} );
    $driver_p{bind} = $p{bind} if exists $p{bind};

    my $statement = $self->schema->driver->statement( %driver_p );

    return Alzabo::Runtime::RowCursor->new( statement => $statement,
					    table => $self,
					    no_cache => $p{no_cache} );
}

sub row_count
{
    my Alzabo::Runtime::Table $self = shift;

    return $self->schema->driver->one_row( sql => 'SELECT COUNT(*) FROM ' . $self->name );
}

sub set_prefetch
{
    my Alzabo::Runtime::Table $self = shift;
    $self->{prefetch} = $self->_canonize_prefetch;
}

sub _canonize_prefetch
{
    my Alzabo::Runtime::Table $self = shift;

    foreach my $c (@_)
    {
	AlzaboException->throw( error => "Column " . $c->name . " doesn't exist in $self->{name}" )
	    unless exists $self->{columns}{ $c->name };
    }

    return [ map {$_->name} grep { ! $self->column_is_primary_key($_) } @_ ]
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
	next if $self->column_is_primary_key($col);
	$self->{groups}{ $col->name } = \@names;
    }
}

sub group_by_column
{
    my Alzabo::Runtime::Table $self = shift;
    my $col = shift;

    return ref $self->{groups}{$col} ? @{ $self->{groups}{$col} } : $col;
}

__END__

=head1 NAME

Alzabo::Runtime::Table - Table objects

=head1 SYNOPSIS

  use Alzabo::Runtime::Table;

=head1 DESCRIPTION

This object is able to create rows, either by making objects based on
existing data or inserting new data to make new rows.

This object also implements a method of lazy column evaluation that
can be used to save memory and database wear and tear, though it needs
to be used carefully.  Please see the C<set_prefetch> and C<add_group>
methods as well as L<LAZY COLUMN LOADING> for details.

=head1 METHODS

=over 4

=item * insert

Takes the following parameters:

=item -- values => $hashref

This hashref should be a hash of column names to values.

Inserts the given values into the table and returns a new row object
if it is successful.  If no values are given for a primary key column
and the column is sequenced then the values will be generated from the
sequence.

All other parameters given will be passed directly to the
Alzabo::Runtime::Row C<new> method (such as the 'no_cache' parameter).

Exceptions:

 AlzaboException - no value provided for unsequenced foreign key.
 AlzaboException - attempt to set non-NULL column to NULL
 AlzaboReferentialIntegrityException - insert violates referential
 integrity.

=item * row_by_pk

Takes the following parameters:

=item -- pk => $pk_val or \%pk_val

DEPRECATED:

=item -- id => $pk_val or \%pk_val

These parameters are the same.  The 'id' parameter will be removed in
a future version.

Given a primary key value, this method will return a new
Alzabo::Runtime::Row object matching this key.  The primary key can be
either a simple scalar, when the column is a single primary key, or a
hash reference of column names to primary key when the primary key is
more than one column.

All other parameters given will be passed directly to the
Alzabo::Runtime::Row C<new> method (such as the 'no_cache' parameter).

If no rows in the database match the id value given then an empty list
or undef will be returned (for list or scalar context).

Exceptions:

 AlzaboException - values provided are not enough or do not match
 primary key.

=item * row_by_id

Takes the following parameters:

=item -- row_id => $row_id

Given a string representation of a row's id (as returned by the
Alzabo::Runtime::Row C<id> method), returns a new Alzabo::Runtime::Row
object matching that id.

All other parameters given will be passed directly to the
Alzabo::Runtime::Row C<new> method (such as the 'no_cache' parameter).

Returns a new Alzabo::Runtime::RowCursor object representing the
query.

Exceptions:

 AlzaboException - no row matches the id.

=item * rows_where

Takes the following parameters:

=item -- where => { column_name => $column_value }

A hash reference of column names to column values that will be
SELECTed for.

=item -- from => $from

A FROM clause for a SQL statement.  This can be omitted, in which case
only the current table is used.

This is a simpler version of the rows_by_where_clause method that does
a better job of abstracting SQL, at the expense of some flexibility.

Given these items this method generates SQL that will retrieve a set
of primary keys for the table and return an array of rows based on
that information.

Returns a new Alzabo::Runtime::RowCursor object representing the
query.

=item * rows_by_where_clause

Takes the following parameters:

=item -- where => $from

A WHERE clause for a SQL statement.  This parameter is required.

=item -- from => $from

A FROM clause for a SQL statement.  This can be omitted, in which case
only the current table is used.

=item -- bind => $one_value or \@values

An optional list of values to be bound to the statement execution.

Given these items this method generates SQL that will retrieve a set
of primary keys for the table and return an array of rows based on
that information.  If you want the rows to come back in a specific
order you'll probably have to use an 'ORDER BY' clause in your 'where'
parameter.

All other parameters given will be passed directly to the
Alzabo::Runtime::Row C<new> method (such as the 'no_cache' parameter).


Returns a new Alzabo::Runtime::RowCursor object representing the
query.

WARNING: This method may be deprecated in the future in favor of
something that abstracts SQL even more.

=item * all_rows

Simply returns all the rows in the table.

All other parameters given will be passed directly to the
Alzabo::Runtime::Row C<new> method (such as the 'no_cache' parameter).

Returns a new Alzabo::Runtime::RowCursor object representing the
query.

=item * row_count

Returns a scalar indicating how many rows the table has.

=item * set_prefetch (Alzabo::Column objects)

Given a list of column objects, this makes sure that all
Alzabo::Runtime::Row objects fetch this data as soon as they are
created, as well as immediately after they know they have been expired
in the cache.

NOTE: It is pointless (though not an error) to give primary key column
here as these are always prefetched (in a sense).

=item * prefetch

Returns a list of column names (not objects) that should be
prefetched.  Used by Alzabo::Runtime::Row.

=item * add_group (Alzabo::Column objects)

Given a list of column objects, this method creates a group containing
these columns.  This means that if any column in the group is fetched
from the database, they will all be fetched.  Otherwise column are
always fetched singly.  Currently, a column cannot be part of more
than one group.

NOTE: It is pointless to include a column that was given to the
C<set_prefetch> method in a group here, as it always fetched as soon
as possible.

=item * group_by_column ($column_name)

Given a column name, this returns a list of column names representing
the group that this column is part of.  If it is not part of a group,
only the name passed in is returned.  Used by Alzabo::Runtime::Row.

=head1 LAZY COLUMN LOADING

I stole this concept directly from Michael Schwern's Class::DBI module
(credit where its due).

By default, row objects only load data from the database as it is
requested via the select method.  This is stored internally in the
object after being fetched.  If the object is expired in the cache, it
will erase this information.

This is good because it saves on memory and make object creation but
it is bad because you could potentially end up with one SQL call per
column (excluding primary key columns, which are never fetched from
the database).

The Alzabo::Runtime::Table class provides two method to help you
handle this potential problem.  Basically these methods allow you to
declare usage patterns for the table.

The first method, C<set_prefetch>, allows you to specify a list of
columns to be fetched immediately after object creation or after an
object discovers it is expired in the cache.  These should be columns
that you expect to use extremely frequently.

The second method, C<add_group>, allows you to group columns together.
If you attempt to fetch one of these columns, then all the columns in
the group will be fetched.  This is useful in cases where you don't
often want certain data, but when you do you need several related
pieces.

=back

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
