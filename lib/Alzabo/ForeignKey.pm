package Alzabo::ForeignKey;

use strict;
use vars qw($VERSION);

use Alzabo;

$VERSION = sprintf '%2d.%02d', q$Revision: 1.17 $ =~ /(\d+)\.(\d+)/;

1;

sub table_from
{
    my $self = shift;

    return ($self->columns_from)[0]->table;
}

sub table_to
{
    my $self = shift;

    return ($self->columns_to)[0]->table;
}

sub columns_from
{
    my $self = shift;

    return wantarray ? @{ $self->{columns_from} } : $self->{columns_from}[0];
}

sub columns_to
{
    my $self = shift;

    return wantarray ? @{ $self->{columns_to} } : $self->{columns_to}[0];
}

sub column_pairs
{
    my $self = shift;

    return ( map { [ $self->{columns_from}[$_] => $self->{columns_to}[$_] ] }
	     0..$#{ $self->{columns_from} } );
}

sub min_max_from
{
    my $self = shift;

    return @{ $self->{min_max_from} };
}

sub min_max_to
{
    my $self = shift;

    return @{ $self->{min_max_to} };
}

sub cardinality
{
    my $self = shift;

    return ( $self->{min_max_from}->[1], $self->{min_max_to}->[1] );
}

sub id
{
    my $self = shift;

    return join '___', ( ( map { $_->name }
			   $self->table_from,
			   $self->table_to,
			   $self->columns_from,
			   $self->columns_to,
			 ),
			 $self->min_max_from,
			 $self->min_max_to,
		       );
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

=item * columns_from

The column in the owning table that corresponds to some column in
'table_to'.

=item * columns_to

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

=head3 Returns

The relevant L<C<Alzabo::Table>|Alzabo::Table> object.

=head2 columns_from

=head2 columns_to

=head3 Returns

The relevant L<C<Alzabo::Column>|Alzabo::Column> object(s) for the
property.

=head2 column_pairs

=head3 Returns

An array of array references.  The references are to two column array
of L<C<Alzabo::Column>|Alzabo::Column> objects.  These two columns
correspond in the tables being linked together.

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
