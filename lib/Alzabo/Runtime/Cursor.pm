package Alzabo::Runtime::Cursor;

use strict;
use vars qw($VERSION);

use Alzabo::Runtime;

$VERSION = sprintf '%2d.%02d', q$Revision: 1.11 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    shift->_virtual;
}

sub next
{
    shift->_virtual;
}

sub next_row
{
    shift->_virtual;
}

sub next_rows
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
    Alzabo::Exception::VirtualMethod->throw( error =>
					     "$sub is a virtual method and must be subclassed in " . ref $self );
}

sub reset
{
    my $self = shift;

    $self->{statement}->execute( $self->{statement}->bind );

    $self->{errors} = [];
    $self->{seen} = {};
}

sub errors
{
    my $self = shift;

    return @{ $self->{errors} };
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

=head2 errors

If the last C<next> call encountered a situation where the SQL query
returned primary keys not actually in the target table, then the
exception objects are stored in the cursor.  This method can be used
to retrieve these objects.  This allows you to ignore these errors if
you so desire without having to do explicit exception handling.  For
more information on what you can do with this method see L<the
HANDLING ERRORS section|HANDLING ERRORS>.

=head3 Returns

A list of L<C<Alzabo::Exception::NoSuchRow>|Alzabo::Exceptions>
objects.

=head2 reset

Resets the cursor so that the next C<next> call will return the first
row of the set.

=head1 HANDLING ERRORS

Let's assume a database in with following tables:

 TABLE NAME: movie

 movie_id          int
 title             varchar(50)

 TABLE NAME: movie_alias

 alias_id           int
 movie_id           int
 alias              varchar(50)

Now, let's assume you have a schema object C<$schema> and you execute
the following code:

 my $cursor = $schema->join( tables => [ $schema->tables( 'movie', 'movie_alias' ) ],
                             select => [ $schema->table('movie') ],
                             where  => [ $schema->table('movie_alias')->column('alias'), 'like', 'Foo%' ] );

The cursor returned is relying on the movie_id column in the
movie_alias table.  It's possible that there are values in this column
that are not actually in the movie table but the cursor object will
ignore the exceptions caused by these bad ids.  The C<next> method
will not return a false value until its underlying DBI statement
handle stops returning data.  The reasoning behind this is that
otherwise there would be no way to distinguish between: A) a false
value caused by there being no more data coming back from the query on
the movie_alias table and B) a false value caused by there being no
row in the movie column matching a given movie_id value.

It is certainly possible that there are situations when you don't care
about referential integrity and you want to simply get all the rows
you can.  In other cases, you will want to handle errors.  I would
have used exceptions for this purpose except the following code would
then not function properly.

 while ( my $row = eval { $cursor->next } )
 {
     do_something if $@;  # or alternately just ignore $@

     ... do something with $row ...
 }

The reason is that throwing an exception in the eval block would cause
the eval to return an undef.  This means that the 'do_something if
$@;' clause would _never_ get executed.  In that case, you couldn't
ignore the exception if you wanted to because it interrupts the
C<while> loop.  The workaround would be:

 do
 {
     my $row = eval { $cursor->next };
     # either do something with $@ or ignore it.
 } while ( $row || ( $@ && $@->isa('Alzabo::Exception::NoSuchRow') );

However, this is not an idiom I particularly want to encourage, as it
is counter-intuitive.

So, while throwing an exception may be the most 'correct' way to do
it, I've instead created the L<C<errors>|errors> method.

This means that the idiom for checking errors from the C<next> method
is as follows:

 while ( my $row = $cursor->next )
 {
     do_something if $cursor->errors;

     ... do something with $row ...
 }

The advantage here is that ignoring the exception is easy.  If you
want to check them then just remember that the L<C<errors>|errors>
method will return a list of
L<C<Alzabo::Exception::NoSuchRow>|Alzabo::Exceptions> objects that
occurred during the previous C<next> call.

Also note that other types of exceptions are rethrown from the C<next>
method.

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
