package Alzabo::Exceptions;

use strict;
use vars qw($VERSION);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.27 $ =~ /(\d+)\.(\d+)/;

my %e;

BEGIN
{
    %e = ( 'Alzabo::Exception' =>
	   { description => 'Generic exception within the Alzabo API.  Should only be used as a base class.' },

	   'Alzabo::Exception::Cache' =>
	   { description => 'An operation was attempted on a row that is either deleted or expired in the cache.',
	     isa => 'Alzabo::Exception' },

	   'Alzabo::Exception::Cache::Deleted' =>
	   { description => 'An operation was attempted on a row that is deleted in the cache.',
	     isa => 'Alzabo::Exception::Cache' },

	   'Alzabo::Exception::Cache::Expired' =>
	   { description => 'An operation was attempted on a row that is expired in the cache.',
	     isa => 'Alzabo::Exception::Cache' },

	   'Alzabo::Exception::Driver' =>
	   { description => 'An attempt to eval a string failed',
	     fields => [ 'sql', 'bind' ],
	     isa => 'Alzabo::Exception' },

	   'Alzabo::Exception::Eval' =>
	   { description => 'An attempt to eval a string failed',
	     isa => 'Alzabo::Exception::Cache' },

	   'Alzabo::Exception::Logic' =>
	   { description => 'An internal logic error occurred (presumably, Alzabo was asked to do something that cannot be done)',
	     isa => 'Alzabo::Exception' },

	   'Alzabo::Exception::NoSuchRow' =>
	   { description => 'An attempt to fetch data from the database for a primary key that did not exist in the specified table',
	     isa => 'Alzabo::Exception' },

	   'Alzabo::Exception::Params' =>
	   { description => 'An exception generated when there is an error in the parameters passed in a method of function call',
	     isa => 'Alzabo::Exception' },

	   'Alzabo::Exception::NotNullable' =>
	   { description => 'An exception generated when there is an attempt is made to set a non-nullable column to NULL',
	     isa => 'Alzabo::Exception::Params',
             fields => [ 'column_name' ],
           },

	   'Alzabo::Exception::Panic' =>
	   { description => 'An exception generated when something totally unexpected happens',
	     isa => 'Alzabo::Exception' },

	   'Alzabo::Exception::RDBMSRules' =>
	   { description => 'An RDBMS rule check failed',
	     isa => 'Alzabo::Exception' },

	   'Alzabo::Exception::ReferentialIntegrity' =>
	   { description => 'An operation was attempted that would violate referential integrity',
	     isa => 'Alzabo::Exception' },

	   'Alzabo::Exception::SQL' =>
	   { description => 'An exception generated when there a logical error in a set of operation on an Alzabo::SQLMaker object',
	     isa => 'Alzabo::Exception' },

	   'Alzabo::Exception::Storable' =>
	   { description => 'An attempt to call a function from the Storable module failed',
	     isa => 'Alzabo::Exception' },

	   'Alzabo::Exception::System' =>
	   { description => 'An attempt to interact with the system failed',
	     isa => 'Alzabo::Exception' },

	   'Alzabo::Exception::VirtualMethod' =>
	   { description => 'Indicates that the method called must be subclassed in the appropriate class',
	     isa => 'Alzabo::Exception' },

	 );
}

use Exception::Class (%e);

Alzabo::Exception->Trace(1);

package Alzabo::Exception;

sub format
{
    my $self = shift;

    if (@_)
    {
        $self->{format} = shift eq 'html' ? 'html' : 'text';
    }

    return $self->{format} || 'text';
}

sub as_string
{
    my $self = shift;

    my $stringify_function = "as_" . $self->format;

    return $self->$stringify_function();
}

sub as_text
{
    return $_[0]->full_message;
}

sub as_html
{
    my $self = shift;

    my $msg = $self->full_message;

    require HTML::Entities;
    $msg = HTML::Entities::encode_entities($msg);
    $msg =~ s/\n/<br>/;

    my $html = <<"EOF";
<html><body>
<p align="center"><font face="Verdana, Arial, Helvetica, sans-serif"><b>System error</b></font></p>
<table border="0" cellspacing="0" cellpadding="1">
 <tr>
  <td nowrap align="left" valign="top"><b>error:</b>&nbsp;</td>
  <td align="left" valign="top" nowrap>$msg</td>
 </tr>
 <tr>
  <td align="left" valign="top" nowrap><b>code stack:</b>&nbsp;</td>
  <td align="left" valign="top" nowrap>
EOF

    foreach my $frame ( $self->trace->frames )
    {
        my $filename = HTML::Entities::encode_entities( $frame->filename );
        my $line = $frame->line;

        $html .= "$filename: $line<br>\n";
    }

    $html .= <<'EOF';
  </td>
 </tr>
</table>

</body></html>
EOF

    return $html;
}

package Alzabo::Exception::Driver;

sub full_message
{
    my $self = shift;

    my $msg = $self->error;
    $msg .= "\nSQL: " . $self->sql if $self->sql;

    if ( $self->bind )
    {
	my @bind = map { defined $_ ? $_ : '<undef>' } @{ $self->bind };
	$msg .= "\nBIND: @bind" if @bind;
    }

    return $msg;
}

1;

=head1 NAME

Alzabo::Exceptions - Creates all exception subclasses used in Alzabo.

=head1 SYNOPSIS

  use Alzabo::Exceptions;

=head1 DESCRIPTION

Using this class creates all the exceptions classes used by Alzabo
(via the L<C<Exception::Class>|Exception::Class> class).

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

=item * Alzabo::Exception::Panic

This exception is thrown when something completely unexpected happens
(think Monty Python).

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

=item * Alzabo::Exception::Storable

A error when trying to freeze, thaw, or clone an object using
Storable.

=item * Alzabo::Exception::System

Some sort of system call (file read/write, stat, etc.) failed.

=item * Alzabo::Exception::VirtualMethod

A virtual method was called.  This indicates that this method should
be subclassed.

=back

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
