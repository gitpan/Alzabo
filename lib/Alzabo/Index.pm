package Alzabo::Index;

use strict;
use vars qw($VERSION);

use Alzabo;

use Tie::IxHash;

#use fields qw( columns table unique );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.14 $ =~ /(\d+)\.(\d+)/;

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

    Alzabo::Exception::Params->throw( error => "Column " . $c->name . " is not part of index." )
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
chars).  Some RDBMS's do not have a concept of index prefixes.  Not
all column types are likely to allow prefixes though this depends on
the RDBMS.  The order of the columns is significant.

=head1 METHODS

=head2 columns

=head3 Returns

An ordered list of the L<C<Alzabo::Column>|Alzabo::Column> objects
that are being indexed.

=head2 prefix (C<Alzabo::Column> object)

A column prefix is, to the best of my knowledge, a MySQL specific
concept, and as such cannot be set when using an RDBMSRules module for
a different RDBMS.  However, it is important enough for MySQL to have
the functionality be present.  It allows you to specify that the index
should only look at a certain portion of a field (the first N
characters).  This prefix is required to index any sort of BLOB column
in MySQL.

=head3 Returns

This method returns the prefix for the column in the index.  If there
is no prefix for this column in the index, then it returns undef.

=head2 unique

=head3 Returns

A boolean value indicating whether or not the index is a unique index.

=head2 id

The id is generated from the table, column and prefix information for
the index.  This is useful as a canonical name for a hash key, for
example.

=head3 Returns

A string that is the id for the index.

=head2 table

=head3 Returns

The L<C<Alzabo::Table>|Alzabo::Table> object to which the index
belongs.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
