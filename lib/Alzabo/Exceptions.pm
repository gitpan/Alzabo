package Alzabo::Exceptions;

use strict;
use vars qw($VERSION);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.8 $ =~ /(\d+)\.(\d+)/;

my %e;

BEGIN
{
    %e = ( 'AlzaboException' =>
	   { description => 'Generic exception within the Alzabo API.  Usually this indicates a logical failure of some sort (invalid input, reference to a non-existent table or column, etc.)' },

	   'AlzaboDriverTransactionException' =>
	   { description => 'An exception from an Alzabo::Driver related to beginning, rolling back, or commiting a transaction',
	     isa => 'AlzaboException' },

	   'AlzaboRDBMSRulesException' => { description => 'A RDBMS rule check failed',
					    isa => 'AlzaboException' },

	   'AlzaboReferentialIntegrityException' =>
	   { description => 'An operation was attempted that would violate referential integrity',
	     isa => 'AlzaboException' },

	   'AlzaboCacheException' => { isa => 'AlzaboException' },

	   'AlzaboNoSuchRowException' => { isa => 'AlzaboException',
					   description => 'An attempt to fetch data from the database for a primary key that did not exist in the specified table' },

	   'DBIException' =>
	   { description => 'An exception from an Alzabo::Driver class caused by a DBI error' },

	   'EvalException' =>
	   { description => 'An attempt to eval a string failed' },

	   'FileSystemException' =>
	   { description => 'An attempt to interact with the file system failed' },

	   'StorableException' =>
	   { description => 'A function in the Storable library failed' },

	   'VirtualMethodException' =>
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

package Alzabo::Driver::Exception;

use strict;
use vars qw($VERSION);

use Exception::Class;

use base qw( Exception::Class::Base );
use fields qw( sql bind );

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
(via the Exception class).  If the environment variable 'ALZABO_DEBUG'
is true, then it will turn on stacktrace generation for all the
exception classes.

See Exception::Class for more information on how this is done.

=cut
