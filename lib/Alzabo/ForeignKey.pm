package Alzabo::ForeignKey;

use strict;
use vars qw($VERSION);

use Alzabo;

#use fields qw( table_from table_to column_from column_to min_max_from min_max_to cardinality );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.14 $ =~ /(\d+)\.(\d+)/;

1;

sub table_from
{
    my Alzabo::ForeignKey $self = shift;

    return $self->column_from->table;
}

sub table_to
{
    my Alzabo::ForeignKey $self = shift;

    return $self->column_to->table;
}

sub column_from
{
    my Alzabo::ForeignKey $self = shift;

    return $self->{column_from};
}

sub column_to
{
    my Alzabo::ForeignKey $self = shift;

    return $self->{column_to};
}

sub column_links
{
    my Alzabo::ForeignKey $self = shift;

    return [ $self->{column_from} => $self->{column_to} ];
}

sub min_max_from
{
    my Alzabo::ForeignKey $self = shift;

    return @{ $self->{min_max_from} };
}

sub min_max_to
{
    my Alzabo::ForeignKey $self = shift;

    return @{ $self->{min_max_to} };
}

sub cardinality
{
    my Alzabo::ForeignKey $self = shift;

    return ( $self->{min_max_from}->[1], $self->{min_max_to}->[1] );
}

__END__

=head1 NAME

Alzabo::ForeignKey - Foreign key (relation) objects

=head1 SYNOPSIS

  use Alzabo::ForeignKey;

  foreach my $fk ($table->foreign_keys)
  {
      print $fk->cardinality;
  }

=head1 DESCRIPTION

A foreign key is an object defined by several properties.  It
represents a relationship from a column in one table to a column in
another table.  This relationship can be described in this manner:

There is a relationship from column BAZ in table foo to column BOZ in
table bar.  For every entry in column BAZ, there must X..Y
corresponding entries in column BOZ.  For every entry in column BOZ,
there must be Y..Z corresponding entries in column BAZ.  X, Y, and Z
are 0, 1, or n, and must form one of these pairs: 0..1, 0..n, 1..1,
1..n.

The properties that make up a foreign key are:

=over 4

=item * column_from

The column in the owning table that corresponds to some column in
'table_to'.

=item * column_to

The column to which there is a correspondence.

=item * min_max(_to, _from)

Legal values for this are 0..1, 0..n, 1..1, and 1..n (n..n
relationships are handled specially).  For the above mentioned
relationship from foo.baz to bar.boz, if the min_max_to were 0..1, we
could say, "For every entry in foo.baz, there may be 0 or 1
corresponding entries in bar.boz."  If the min_max_from value were
1..n we would say that "for every entry in bar.boz, there must be 1 or
more corresponding entries in foo.baz."

=back

Cardinality is generated from the two min_max values.  This is the max
from to the max to.  If min_max_from was 0..1 and min_max_to was 1..n
then the cardinality of the relationship would be 1..n.

=head1 METHODS

=head2 table_from

=head2 table_to

=head2 column_from

=head2 column_to

=head3 Returns

The relevant L<C<Alzabo::Table>|Alzabo::Table> or
L<C<Alzabo::Column>|Alzabo::Column> object for the property.

=head2 min_max_from

=head2 min_max_to

=head3 Returns

A two element array containing the two portions of the min_max value.

Examples: (0, 1) -- (1, 'n')

=head2 cardinality

This will be either 1..1 or 1..n.

=head3 Returns

A two element array containing the two portions of the cardinality of
the relationship.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
