package Alzabo::Exceptions;

use strict;
use vars qw($VERSION);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.14 $ =~ /(\d+)\.(\d+)/;

my %e;

BEGIN
{
    %e = ( 'Alzabo::Exception' =>
	   { description => 'Generic exception within the Alzabo API.  Should only be used as a base class.' },

	   'Alzabo::Exception::Cache' =>
	   { isa => 'Alzabo::Exception',
	     description => 'An operation was attempted on a row that is either deleted or expired in the cache.'},

	   'Alzabo::Exception::Cache::Deleted' =>
	   { isa => 'Alzabo::Exception::Cache',
	     description => 'An operation was attempted on a row that is deleted in the cache.'},

	   'Alzabo::Exception::Cache::Expired' =>
	   { isa => 'Alzabo::Exception::Cache',
	     description => 'An operation was attempted on a row that is expired in the cache.'},

	   'Alzabo::Exception::Eval' =>
	   { description => 'An attempt to eval a string failed' },

	   'Alzabo::Exception::Logic' =>
	   { description => 'An internal logic error occurred (presumably, Alzabo was asked to do something that cannot be done)',
	     isa => 'Alzabo::Exception' },

	   'Alzabo::Exception::NoSuchRow' =>
	   { isa => 'Alzabo::Exception',
	     description => 'An attempt to fetch data from the database for a primary key that did not exist in the specified table' },

	   'Alzabo::Exception::Params' =>
	   { description => 'An exception generated when there is an error in the parameters passed in a method of function call',
	     isa => 'Alzabo::Exception' },

	   'Alzabo::Exception::RDBMSRules' =>
	   { isa => 'Alzabo::Exception',
	     description => 'An RDBMS rule check failed' },

	   'Alzabo::Exception::ReferentialIntegrity' =>
	   { isa => 'Alzabo::Exception',
	     description => 'An operation was attempted that would violate referential integrity' },

	   'Alzabo::Exception::SQL' =>
	   { description => 'An exception generated when there a logical error in a set of operation on an ALzabo::SQLMaker object',
	     isa => 'Alzabo::Exception' },

	   'Alzabo::Exception::System' =>
	   { description => 'An attempt to interact with the file system failed' },

	   'Alzabo::Exception::VirtualMethod' =>
	   { description => 'Indicates that the method called must be subclassed in the appropriate class' },

	 );
}

use Exception::Class (%e);
$ENV{ALZABO_DEBUG} = 1;
if ($ENV{ALZABO_DEBUG})
{
    Exception::Class::Base->do_trace(1);
    foreach my $class (keys %e)
    {
	$class->do_trace(1);
    }
}

package Alzabo::Exception::Driver;

use strict;
use vars qw($VERSION);

use Exception::Class;

use base qw( Exception::Class::Base );

$VERSION = '0.1';

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;
    my %p = @_;

    my $self = $class->SUPER::new(%p);

    $self->{sql} = $p{sql},
    $self->{bind} = $p{bind} || [];

    return $self;
}

sub description
{
    return 'an error related to database communications through DBI';
}

sub sql
{
    my $self = shift;

    return $self->{sql};
}

sub bind
{
    my $self = shift;

    return @{ $self->{bind} };
}


1;

=head1 NAME

Alzabo::Exceptions - Creates all exception subclasses used in Alzabo.

=head1 SYNOPSIS

  use Alzabo::Exceptions;

=head1 DESCRIPTION

Using this class creates all the exceptions classes used by Alzabo
(via the L<C<Exception::Class>|Exception::Class> class).  If the
environment variable 'ALZABO_DEBUG' is true, then it will turn on
stacktrace generation for all the exception classes.

See L<C<Exception::Class>|Exception::Class> for more information on
how this is done.

=head1 EXCEPTION CLASSES

=over 4

=item * Alzabo::Exception

This is the base class for all exceptions generated within Alzabo (all
exceptions should return true for C<$@-E<gt>isa('Alzabo::Exception')>
except those that are generated via internal Perl errors).

=item * Alzabo::Exception::Cache

Base class for cache-related exceptions.

=item * Alzabo::Exception::Cache::Deleted

An attempt was made to operate on a row that had been deleted in the
cache.  In this case there is no point in attempting further
operations on the row, as it is no longer in the database.

=item * Alzabo::Exception::Cache::Expired

An attempt was made to operate on a row that had been expired in the
cache.  The row will refresh itself before returning this exception so
it may be desirable to attempt the operation that caused this error
again.

=item * Alzabo::Exception::Driver

An error occured while accessing a database.  See
L<C<Alzabo::Driver>|Alzabo::Driver> for more details.

=item * Alzabo::Exception::Eval

An attempt to eval something returned an error.

=item * Alzabo::Exception::Logic

Alzabo was asked to do something logically impossible, like retrieve
rows for a table without a primary key.

=item * Alzabo::Exception::NoSuchRow

An attempt was made to fetch data from the database with a primary key
that does not actually exist in the specified table.

=item * Alzabo::Exception::Params

This exception is thrown when there is a problem with the parameters
passed to a method or function.  These problems can include missing
parameters, invalid values, etc.

=item * Alzabo::Exception::RDBMSRules

A rule for the relevant RDBMS was violated (bad schema name, table
name, column attribute, etc.)

=item * Alzabo::Exception::ReferentialIntegrity

An insert/update/delete was attempted that would violate referential
integrity constraints.

=item * Alzabo::Exception::SQL

An error thrown when there is an attempt to generate invalid SQL via
the Alzabo::SQLMaker module.

=item * Alzabo::Exception::System

Some sort of system call (file read/write, stat, etc.) failed.

=item * Alzabo::Exception::VirtualMethod

A virtual method was called.  This indicates that this method should
be subclassed.

=back

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
