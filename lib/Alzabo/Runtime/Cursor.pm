package Alzabo::Runtime::Cursor;

use strict;
use vars qw($VERSION);

use Alzabo::Runtime;

use fields qw( errors no_cache statement );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.1 $ =~ /(\d+)\.(\d+)/;

1;

sub new
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
    VirtualMethodException->throw( error =>
				   "$sub is a virtual method and must be subclassed in " . ref $self );
}

sub reset
{
    my $self = shift;

    $self->{statement}->execute( $self->{statement}->bind );

    $self->{errors} = [];
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

This is the base class for cursors

=head1 METHODS

=over 4

=item * new

Virtual method.

=item * all_rows

Virtual method.

=item * errors

If the last C<next_row> or C<next_rows> call encountered a situation
where the SQL query returned primary keys not actually in the target
table, then this method will return a list of AlzaboNoSuchRowException
objects detailing this.  This allows you to ignore these errors if you
so desire without having to do explicit exception handling.  For more
information on what you can do with this method see L<the HANDLING
ERRORS section|HANDLING ERRORS>.

=item * reset

Resets the cursor so that the next C<next_row> or C<next_rows> call
will return the first row of the set.

=back

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

 my $cursor = $schema->table('movie')->rows_where( from => [ 'movie', 'movie_alias' ],
                                                   where => 'movie_alias.alias like ?',
                                                   bind => 'Foo%' );

The cursor returned is relying on the movie_id column in the
movie_alias table.  It's possible that there are values in this column
that are not actually in the movie table.  The cursor object will
gloss over this fact.  The C<next_row> method will not return a false
value until its underlying DBI statement handle stops returning data.
The reasoning behind this is that otherwise there would be no way to
distinguish between: A) a false value caused by there being no more
data coming back from the query on the movie_alias table and B) a
false value caused by there being no row in the movie column matching
a given movie_id value.

It is certainly possible that there are situations when you don't care
about referential integrity and you want to simply get all the rows
you can.  In other cases, you will want to handle errors.  I would
have used exceptions for this purpose except the following code would
then not function properly.

 while ( my $row = eval { $cursor->next_row } )
 {
     do_something if $@;  # or alternately just ignore $@

     ... do something with $row ...
 }

The reason is that throwing an exception in the eval block would cause
the eval to return an undef.  This means that the 'do_something if
$@;' clause would _never_ get executed.  Even worse, if you wanted to
ignore the exeception you wouldn't be able to!  The workaround would
be:

 do
 {
     my $row = eval { $cursor->next_row };
     # either do something with $@ or ignore it.
 } while ( $row || ( $@ && $@->isa('AlzaboNoSuchRowException') );

Even worse, if the exception handling involved an eval, then you'd
have to copy $@ to a temporary value.

So, while throwing an exception is probably the most correct way to do
it, I've instead created the C<errors> method.

This means that the idiom for checking errors from the next_row method
is as follows:

 while ( my $row = $cursor->next_row )
 {
     do_something if $cursor->errors;

     ... do something with $row ...
 }

The advantage here is that ignoring the exception is easy.  If you
want to check them then just remember that the C<errors> method will
return a list of AlzaboNoSuchRowException objects that occurred during
the previous C<next_row> call.

Also note that other types of exceptions are rethrown from the
C<next_row> method.

=head1 RATIONALE FOR CURSORS

Using cursors is definitely more complicated.  However, there is are
two excellent rationales: speed and memory savings.  As an example, I
did a test with the old code (which returned all its objects at once)
against a table with about 8,000 rows using the
L<Alzabo::Runtime::Table all_rows
method|Alzabo::Runtime::Table/all_rows>.  Under the old
implementation, it took significantly longer to return the first row.
Even more importantly than that, the old implementation used up about
10MB of memory versus about 4MB!  Now imagine that with a 1,000,000
row table.

For those curious to know why, here's the reason.  Under perl, the
following code:

 foreach (1..1_000_000)
 {
     print "$_\n";
 }

first constructs a temporary array with _all_ the values (that's an
array one million scalars long!) and then returns it one by one.  It
takes a nontrivial amount of time to construct that array, meaning
that the first print statement is delayed.  Even worse, the array uses
up memory.

Thus Alzabo now uses cursors, meaning it scales way better.  This is a
particularly big win in the case where you are working through a long
list of rows but you may stop before the end is reached.  With
cursors, Alzabo creates only as many rows as you need.  Plus the start
up time on your loop is much, much quicker.  In the end, your program
is quicker and less of a memory hog.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
