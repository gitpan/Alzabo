package Alzabo::Index;

use strict;
use vars qw($VERSION);

use Alzabo;

use Tie::IxHash;

use fields qw( columns table unique );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.7 $ =~ /(\d+)\.(\d+)/;

1;

sub columns
{
    my Alzabo::Index $self = shift;

    my @c;
    foreach my $c ($self->{columns}->Keys)
    {
	push @c, ($self->{columns}->FETCH($c))->{column};
    }

    return @c;
}

sub prefix
{
    my Alzabo::Index $self = shift;
    my $c = shift;

    AlzaboException->throw( error => "Column " . $c->name . " is not part of index." )
	unless $self->{columns}->EXISTS( $c->name );

    return ($self->{columns}->FETCH( $c->name ))->{prefix};
}

sub unique
{
    my Alzabo::Index $self = shift;

    return $self->{unique};
}

sub id
{
    my Alzabo::Index $self = shift;

    return join '___', ( $self->{table}->name,
			 map { $_->name, $self->prefix($_) || () }
			 $self->columns );
}

sub table
{
    my Alzabo::Index $self = shift;

    return $self->{table};
}

__END__

=head1 NAME

Alzabo::Index - Index objects

=head1 SYNOPSIS

  foreach my $i ($table->indexes)
  {
     foreach my $c ($i->columns)
     {
        print $c->name;
        print '(' . $i->prefix($c) . ')' if $i->prefix($c);
    }
 }

=head1 DESCRIPTION

This object represents an index on a table.  Indexes consist of
columns and optional prefixes for each column.  The prefix specifies
how many characters of the columns should be indexes (the first X
chars).  Not all column types are likely to allow prefixes though this
depends on the RDBMS.  The order of the columns is significant.

=head1 METHODS

=over 4

=item * columns

Returns an ordered list of columns that are part of the index.

=item * prefix ($column)

Given a column object that is part of the index, this method returns
the prefix of the index.  If there is no prefix for this column in the
index, then it returns undef.

Exceptions:

 AlzaboException - The given column is not part of the index.

=item * unique

Returns a boolean value indicating whether or not the index is a
unique index.

=item * id

Returns an id for the index, which is generated from the tasble,
column and prefix information for the index.  This is useful as a
cardinal name for hashing.

=item * table

Returns the table object that the index belongs to.

=back

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
