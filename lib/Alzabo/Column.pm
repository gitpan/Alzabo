package Alzabo::Column;

use strict;
use vars qw($VERSION);

use Alzabo;

use Tie::IxHash;

use fields qw( name table attributes null definition sequenced );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.12 $ =~ /(\d+)\.(\d+)/;

1;

sub table
{
    my Alzabo::Column $self = shift;

    return $self->{table};
}

sub name
{
    my Alzabo::Column $self = shift;

    return $self->{name};
}

sub null
{
    my Alzabo::Column $self = shift;

    return $self->{null};
}

sub attributes
{
    my Alzabo::Column $self = shift;

    return keys %{ $self->{attributes} };
}

sub type
{
    my Alzabo::Column $self = shift;

    return $self->{definition}->type;
}

sub sequenced
{
    my Alzabo::Column $self = shift;

    return $self->{sequenced};
}

sub definition
{
    my Alzabo::Column $self = shift;

    return $self->{definition};
}

sub is_primary_key
{
    my Alzabo::Column $self = shift;

    return $self->table->column_is_primary_key($self);
}

__END__

=head1 NAME

Alzabo::Column - Column objects

=head1 SYNOPSIS

  use Alzabo::Column;

  foreach my $c ($table->columns)
  {
      print $c->name;
  }

=head1 DESCRIPTION

This object represents a column.  It holds data specific to a column.
Additional data is held in a ColumnDefinition object, which is used to
allow two columns to share a type (which is good for foreign keys and
such).

=head1 METHODS

=over 4

=item * table

Returns the table object in which this column is located.

=item * name

Returns the column's name (a string).

=item * null

Returns a boolean value indicating whether or not NULLs are allowed in
this column.

=item * attributes

Returns the column's attributes.  These are strings describing the
column (for example, valid attributes in MySQL are 'UNSIGNED' or
'ZEROFILL'.

The return value of this method is a list of strings.

=item * type

Returns the column's type.  This is just delegated to the
ColumnDefinition object contained in the Column object.

=item * sequenced

Returns a boolean value indicating whether or not this column is
sequenced (in MySQL, this uses 'AUTO_INCREMENT'.  In other RDBMS's, a
true sequence will be created for this column that will be used by the
Alzabo::Runtime::* classes).

=item * definition

Returns the Alzabo::ColumnDefinition object which holds this column's
type information.

=item * is_primary_key

Returns a boolean value indicating whether or not this column is part
of its table's primary key.

=back

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
