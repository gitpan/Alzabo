package Alzabo::Runtime::Cursor;

use strict;
use vars qw($VERSION);

use Alzabo::Runtime;

$VERSION = 2.0;

1;

sub new
{
    shift->_virtual;
}

sub next
{
    shift->_virtual;
}

sub all_rows
{
    shift->_virtual;
}

sub _virtual
{
    my $self = shift;

    my $sub = (caller(1))[3];
    Alzabo::Exception::VirtualMethod->throw
            ( error =>
              "$sub is a virtual method and must be subclassed in " . ref $self );
}

sub reset
{
    my $self = shift;

    $self->{statement}->execute( $self->{statement}->bind );

    $self->{seen} = {};
    $self->{count} = 0;
}

sub count
{
    my $self = shift;

    return $self->{count};
}

sub next_as_hash
{
    my $self = shift;

    my @next = $self->next or return;

    return map { defined $_ ? ( $_->table->name => $_ ) : () } @next;
}

__END__

=head1 NAME

Alzabo::Runtime::Cursor - Base class for Alzabo cursors

=head1 SYNOPSIS

  use Alzabo::Runtime::Cursor;

=head1 DESCRIPTION

This is the base class for cursors.

=head1 METHODS

=head2 new

Virtual method.

=head2 all_rows

Virtual method.

=head2 reset

Resets the cursor so that the next C<next> call will return the first
row of the set.

=head2 count

=head3 Returns

The number of rows returned by the cursor so far.

=head2 next_as_hash

=head3 Returns

The next row or rows in a hash, where the hash key is the table name
and the hash value is the row object.

=head1 RATIONALE FOR CURSORS

Using cursors is definitely more complicated.  However, there are two
excellent reasons for using them: speed and memory savings.  As an
example, I did a test with the old code (which returned all its
objects at once) against a table with about 8,000 rows using the
L<C<Alzabo::Runtime::Table-E<gt>all_rows>
method|Alzabo::Runtime::Table/all_rows>.  Under the old
implementation, it took significantly longer to return the first row.
Even more importantly than that, the old implementation used up about
10MB of memory versus about 4MB!  Now imagine that with a 1,000,000
row table.

Thus Alzabo uses cursors so it can scale better.  This is a
particularly big win in the case where you are working through a long
list of rows and may stop before the end is reached.  With cursors,
Alzabo creates only as many rows as you need.  Plus the start up time
on your loop is much, much quicker.  In the end, your program is
quicker and less of a memory hog.  This is good.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
