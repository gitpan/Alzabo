package Alzabo::ForeignKey;

use strict;
use vars qw($VERSION);

use Alzabo;

use fields qw( table_from table_to column_from column_to min_max_from min_max_to cardinality );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.8 $ =~ /(\d+)\.(\d+)/;

1;

sub table_from
{
    my Alzabo::ForeignKey $self = shift;

    return $self->{table_from};
}

sub table_to
{
    my Alzabo::ForeignKey $self = shift;

    return $self->{table_to};
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
another table.  This relationship can be described via a sentence
"There is a relationship from column baz in table foo to column Y in
table bar.  For every entry in column baz in table foo, there must X-Y
corresponding entries in table bar.  For every entry in column boz in
table bar, there must be Y-Z corresponding entries in table foo."  X,
Y, and Z are the number 0, 1, or n.

The properties that make up a foreign key are:

table_from - The table that 'owns' the foreign key.

table_to - The table to which the relationship is made.

column_from - The column in the owning table that corresponds to some
column in 'table_to'.

column_to - The column to which there is a correspondence.

min_max(_to, _from) - Legal values for this are 0..1, 0..n, 1..1, and
1..n (n..n relationships are handled specially).  For the above
mentioned relationship from foo.baz to bar.boz, if the min_max_to were
0..1, we could say, "For every entry in foo.baz, there may be 0 or 1
corresponding entries in bar.boz."  If the min_max_from value were
1..n we would say that "for every entry in bar.boz, there must be 1 or
more corresponding entries in foo.baz."

Cardinality is generated from the two min_max values.  This is the max
from to the max to.  If min_max_from was 0..1 and min_max_to was 1..n
then the cardinality of the relationship would be 1..n.

=head1 METHODS

=over 4

=item * table_from

=item * table_to

=item * column_from

=item * column_to

Returns the relevant object for the property.

=item * min_max_from, min_max_to

Returns a two element array containing the two portions of the min_max
value.

=item * cardinality

Returns a two element array containing the two portions of the
cardinality of the relationship.

=back

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
