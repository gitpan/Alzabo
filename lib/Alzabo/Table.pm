package Alzabo::Table;

use strict;
use vars qw($VERSION);

use Alzabo;

use Tie::IxHash;

$VERSION = sprintf '%2d.%02d', q$Revision: 1.32 $ =~ /(\d+)\.(\d+)/;

1;

sub schema
{
    my $self = shift;

    return $self->{schema};
}

sub name
{
    my $self = shift;

    return $self->{name};
}

sub column
{
    my $self = shift;
    my $name = shift;

    Alzabo::Exception::Params->throw( error => "Column $name doesn't exist in $self->{name}" )
	unless $self->{columns}->EXISTS($name);

    return $self->{columns}->FETCH($name);
}

sub columns
{
    my $self = shift;

    if (@_)
    {
	return map { $self->column($_) } @_;
    }

    return $self->{columns}->Values;
}

sub primary_key
{
    my $self = shift;

    return $self->{pk}->Values;
}

sub column_is_primary_key
{
    my $self = shift;
    my $col = shift;

    my $name = $col->name;
    Alzabo::Exception::Params->throw( error => "Column $name doesn't exist in $self->{name}" )
	unless $self->{columns}->EXISTS($name);

    return $self->{pk}->EXISTS($name);
}

sub foreign_keys
{
    my $self = shift;
    my %p = @_;

    my $c_name = $p{column}->name;
    my $t_name = $p{table}->name;

    Alzabo::Exception::Params->throw( error => "Column $c_name doesn't exist in $self->{name}" )
	unless $self->{columns}->EXISTS($c_name);

    Alzabo::Exception::Params->throw( error => "No foreign keys to $t_name exist in $self->{name}" )
	unless exists $self->{fk}{$t_name};

    Alzabo::Exception::Params->throw( error => "Column $c_name is not a foreign key to $t_name in $self->{name}" )
	unless exists $self->{fk}{$t_name}{$c_name};

    return wantarray ? @{ $self->{fk}{$t_name}{$c_name} } : $self->{fk}{$t_name}{$c_name}[0];
}

sub foreign_keys_by_table
{
    my $self = shift;
    my $name = shift->name;

    my $fk = $self->{fk};
    my @fk;
    if ( exists $fk->{$name} )
    {
	foreach my $c ( keys %{ $fk->{$name} } )
	{
	    push @fk, @{ $fk->{$name}{$c} };
	}
    }

    return wantarray ? @fk : $fk[0];
}

sub foreign_keys_by_column
{
    my $self = shift;
    my $col = shift;

    Alzabo::Exception::Params->throw( error => "Column " . $col->name . " doesn't exist in $self->{name}" )
	unless $self->{columns}->EXISTS( $col->name );

    my @fk;
    my $fk = $self->{fk};
    foreach my $t (keys %$fk)
    {
	if ( exists $fk->{$t}{ $col->name } )
	{
	    push @fk, @{ $fk->{$t}{ $col->name } };
	}
    }

    return wantarray ? @fk : $fk[0];
}

sub all_foreign_keys
{
    my $self = shift;

    my %seen;
    my @fk;
    my $fk = $self->{fk};
    foreach my $t (keys %$fk)
    {
	foreach my $c ( keys %{ $fk->{$t} } )
	{
	    foreach my $key ( @{ $fk->{$t}{$c} } )
	    {
		next if $seen{$key};
		push @fk, $key;
		$seen{$key} = 1;
	    }
	}
    }

    return wantarray ? @fk : $fk[0];
}

sub index
{
    my $self = shift;
    my $id = shift;

    Alzabo::Exception::Params->throw( error => "Index $id doesn't exist in $self->{name}" )
	unless $self->{indexes}->EXISTS($id);

    return $self->{indexes}->FETCH($id);
}

sub indexes
{
    my $self = shift;

    return $self->{indexes}->Values;
}

__END__

=head1 NAME

Alzabo::Table - Table objects

=head1 SYNOPSIS

  use Alzabo::Table;

  my $t = $schema->table('foo');

  foreach $pk ($t->primary_keys)
  {
     print $pk->name;
  }

=head1 DESCRIPTION

Objects in this class represent tables.  They contain foreign key,
index, and column objects.

=head1 METHODS

=head2 schema

=head3 Returns

The L<C<Alzabo::Schema>|Alzabo::Schema> object to which this table
belongs.

=head2 name

=head3 Returns

The name of the table.

=head2 column ($name)

=head3 Returns

The L<C<Alzabo::Column>|Alzabo::Column> object that matches the name
given.

=head2 columns (@optional_list_of_column_names)

=head3 Returns

A list of L<C<Alzabo::Column>|Alzabo::Column> objects that match the
list of names given.  If no list is provided, then it returns all
column objects for the table.

=head2 primary_key

A primary key is one or more columns which must be unique in each row
of the table.  For a multi-column primary key, than the values of the
columns taken in order must be unique.  The order of a multi-column
key is significant as most RDBMS's will create an index on the primary
key using the same column order as is specified and column order
usually matters in indexes.

=head3 Returns

An ordered list of column objects that make up the primary key for the
table.

=head2 column_is_primary_key (C<Alzabo::Column> object)

This method is really only needed if you're not sure that column
belongs to the table.  Otherwise just call the
L<C<Alzabo::Column-E<gt>is_primary_key>|Alzabo::Column/is_primary_key>
method on the column object.

=head3 Returns

A boolean value indicating whether or not the column given is part of
the table's primary key.

=head2 foreign_keys

=head3 Parameters

=over 4

=item * column => C<Alzabo::Column> object

=item * table  => C<Alzabo::Table> object

=back

=head3 Returns

A list of L<C<Alzabo::ForeignKey>|Alzabo::ForeignKey> objects from the
given column to the given table, if they exist.  In scalar context,
returns the first item in the list.  There is no guarantee as to what
the first item will be.

=head2 foreign_keys_by_table (C<Alzabo::Table> object)

=head3 Returns

A list of all the L<C<Alzabo::ForeignKey>|Alzabo::ForeignKey> objects
to the given table.  In scalar context, returns the first item in the
list.  There is no guarantee as to what the first item will be.

=head2 foreign_keys_by_column (C<Alzabo::Column> object)

Returns a list of all the L<C<Alzabo::ForeignKey>|Alzabo::ForeignKey>
objects that the given column is a part of, if any.  In scalar
context, returns the first item in the list.  There is no guarantee as
to what the first item will be.

=head2 all_foreign_keys

=head3 Returns

A list of all the L<C<Alzabo::ForeignKey>|Alzabo::ForeignKey> objects
for this table.  In scalar context, returns the first item in the
list.  There is no guarantee as to what the first item will be.

=head2 index ($index_id)

This method expect an index id as returned by the
L<C<Alzabo::Index-E<gt>id>|Alzabo::Index/id> method.

=head3 Returns

The L<C<Alzabo::Index>|Alzabo::Index> object matching this id, if it
exists in the table.

=head2 indexes

=head3 Returns

All the L<C<Alzabo::Index>|Alzabo::Index> objects for the table.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
