package Alzabo::Table;

use strict;
use vars qw($VERSION);

use Alzabo;

use Tie::IxHash;

use fields qw( schema name columns indexes pk fk );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.21 $ =~ /(\d+)\.(\d+)/;

1;

sub schema
{
    my Alzabo::Table $self = shift;

    return $self->{schema};
}

sub name
{
    my Alzabo::Table $self = shift;

    return $self->{name};
}

sub column
{
    my Alzabo::Table $self = shift;
    my $name = shift;

    AlzaboException->throw( error => "Column $name doesn't exist in $self->{name}" )
	unless $self->{columns}->EXISTS($name);

    return $self->{columns}->FETCH($name);
}

sub columns
{
    my Alzabo::Table $self = shift;

    return $self->{columns}->Values;
}

sub primary_key
{
    my Alzabo::Table $self = shift;

    return $self->{pk}->Values;
}

sub column_is_primary_key
{
    my Alzabo::Table $self = shift;
    my $col = shift;

    my $name = $col->name;
    AlzaboException->throw( error => "Column $name doesn't exist in $self->{name}" )
	unless $self->{columns}->EXISTS($name);

    return $self->{pk}->EXISTS($name);
}

sub foreign_keys
{
    my Alzabo::Table $self = shift;
    my %p = @_;

    my $c_name = $p{column}->name;
    my $t_name = $p{table}->name;

    AlzaboException->throw( error => "Column $c_name doesn't exist in $self->{name}" )
	unless $self->{columns}->EXISTS($c_name);

    AlzaboException->throw( error => "No foreign keys to $t_name exist in $self->{name}" )
	unless exists $self->{fk}{$t_name};

    AlzaboException->throw( error => "Column $c_name is not a foreign key to $t_name in $self->{name}" )
	unless exists $self->{fk}{$t_name}{$c_name};

    return wantarray ? @{ $self->{fk}{$t_name}{$c_name} } : $self->{fk}{$t_name}{$c_name}[0];
}

sub foreign_keys_by_table
{
    my Alzabo::Table $self = shift;
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
    my Alzabo::Table $self = shift;
    my $col = shift;

    AlzaboException->throw( error => "Column " . $col->name . " doesn't exist in $self->{name}" )
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
    my Alzabo::Table $self = shift;

    my @fk;
    my $fk = $self->{fk};
    foreach my $t (keys %$fk)
    {
	foreach my $c ( keys %{ $fk->{$t} } )
	{
	    push @fk, @{ $fk->{$t}{$c} };
	}
    }

    return wantarray ? @fk : $fk[0];
}

sub index
{
    my Alzabo::Table $self = shift;
    my $id = shift;

    AlzaboException->throw( error => "Index $id doesn't exist in $self->{name}" )
	unless $self->{indexes}->EXISTS($id);

    return $self->{indexes}->FETCH($id);
}

sub indexes
{
    my Alzabo::Table $self = shift;

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

=over 4

=item * schema

Returns the schema object that this table belong to.

=item * name

Returns the name of the table.

=item * column ($name)

Returns an Alzabo::Column object that matches the name given.

=item * columns

Returns all column objects for the table.

=item * primary_key

Returns a list of column objects that make up the primary key for the
table.

=item * column_is_primary_key (Alzabo::Column object)

Returns a boolean value indicating whether or not the column given is
part of the table's primary key.

=item * foreign_keys

Takes the following parameters:

=item -- column => Alzabo::Column object

=item -- table  => Alzabo::Table object

Returns a list of foreign key objects from the given column to the
given table, if they exist.  In scalar context, returns the first item
in the list.  There is no guarantee as to what the first item will be.

Exceptions:

 AlzaboException - Column doesn't exist in table
 AlzaboException - No foreign keys to the given table exist.
 AlzaboException - The given column is not a foreign key to the given table.

=item * foreign_keys_by_table (Alzabo::Table object)

Returns a list of all the foreign key objects to the given table.  In
scalar context, returns the first item in the list.  There is no
guarantee as to what the first item will be.

=item * foreign_keys_by_column (Alzabo::Column object)

Returns a list of all the foreign key objects that the given column is
a part of, if there are any.  In scalar context, returns the first
item in the list.  There is no guarantee as to what the first item
will be.

Exceptions:

 AlzaboException - Column doesn't exist in table

=item * all_foreign_keys

Returns a list of all the foreign key objects for this table.  In
scalar context, returns the first item in the list.  There is no
guarantee as to what the first item will be.

=item * index ($index_id)

Given an index id (as returned from the Alzabo::Index C<id> method),
returns the index matching this id, if it exists in the table.

Exceptions:

 AlzaboException - Index doesn't exist in table

=item * indexes

Returns all index objects for the table.

=back

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
