package Alzabo::Column;

use strict;
use vars qw($VERSION);

use Alzabo;

use Tie::IxHash;

$VERSION = sprintf '%2d.%02d', q$Revision: 1.23 $ =~ /(\d+)\.(\d+)/;

1;

sub table
{
    my $self = shift;

    return $self->{table};
}

sub name
{
    my $self = shift;

    return $self->{name};
}

*null = \&nullable;
sub nullable
{
    my $self = shift;

    return $self->{nullable};
}

sub attributes
{
    my $self = shift;

    return keys %{ $self->{attributes} };
}

sub has_attribute
{
    my $self = shift;
    my %p = @_;

    my $att = $p{case_sensitive} ? $p{attribute} : lc $p{attribute};

    return exists $self->{attributes}{$att};
}

sub type
{
    my $self = shift;

    return $self->definition->type;
}

sub sequenced
{
    my $self = shift;

    return $self->{sequenced};
}

sub default
{
    my $self = shift;

    return $self->{default};
}

sub length
{
    my $self = shift;

    return $self->definition->length;
}

sub precision
{
    my $self = shift;

    return $self->definition->precision;
}

sub definition
{
    my $self = shift;

    return $self->{definition};
}

sub is_primary_key
{
    my $self = shift;

    return $self->table->column_is_primary_key($self);
}

sub is_numeric
{
    my $self = shift;

    return $self->table->schema->rules->type_is_numeric( $self->type );
}

sub is_character
{
    my $self = shift;

    return $self->table->schema->rules->type_is_char( $self->type );
}

sub is_blob
{
    my $self = shift;

    return $self->table->schema->rules->type_is_blob( $self->type );
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

=head1 METHODS

=head2 table

=head3 Returns

The table object in which this column is located.

=head2 name

=head3 Returns

The column's name as a string.

=head2 nullable

=head3 Returns

A boolean value indicating whether or not NULLs are allowed in this
column.

=head2 attributes

A column's attributes are strings describing the column (for example,
valid attributes in MySQL are 'UNSIGNED' or 'ZEROFILL'.

=head3 Returns

A list of strings.

=head2 has_attribute

=head3 Parameters:

This method can be used to test whether or not a column has a
particular attribute.  By default, the check is case-insensitive.

=over 4

=item * attribute => $attribute

=item * case_sensitive => 0 or 1 (defaults to 0)

=back

=head3 Returns

A boolean value indicating whether or not the column has this
particular attribute.

=head2 type

=head3 Returns

The column's type as a string.

=head2 sequenced

The meaning of a sequenced column varies from one RDBMS to another.
In those with sequences, it means that a sequence is created and that
values for this column will be drawn from it for inserts into this
table.  In databases without sequences, the nearest analog for a
sequence is used (in MySQL the column is given the AUTO_INCREMENT
attribute, in Sybase the identity attribute).

In general, this only has meaning for the primary key column of a
table with a single column primary key.  Setting the column as
sequenced means its value never has to be provided to when calling
C<Alzabo::Runtime::Table-E<gt>insert>.

=head3 Returns

A boolean value indicating whether or not this column is sequenced.

=head2 default

=head3 Returns

The default value of the column as a string, or undef if there is
no default.

=head2 length

=head3 Returns

The length attribute of the column, or undef if there is none.

=head2 precision

=head3 Returns

The precision attribute of the column, or undef if there is none.

=head2 is_primary_key

=head3 Returns

A boolean value indicating whether or not this column is part of its
table's primary key.

=head2 is_numeric

=head3 Returns

A boolean value indicating whether the column is a numeric type
column.

=head2 is_character

=head3 Returns

A boolean value indicating whether the column is a character type
column.

=head2 is_blob

=head3 Returns

A boolean value indicating whether the column is a blob column.

=head2 definition

The definition object is very rarely of interest.  Use the
L<C<type>|type> method if you are only interested in the column's
type.

=head3 Returns

The L<C<Alzabo::ColumnDefinition>|Alzabo::ColumnDefinition> object
which holds this column's type information.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
