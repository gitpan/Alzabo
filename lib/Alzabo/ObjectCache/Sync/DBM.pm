package Alzabo::ObjectCache::Sync::DBM;

use strict;

use vars qw($SELF $VERSION);

use Alzabo::ObjectCache::Sync;
use base qw( Alzabo::ObjectCache::Sync );

use Alzabo::Exceptions;

$VERSION = sprintf '%2d.%02d', q$Revision: 1.5 $ =~ /(\d+)\.(\d+)/;

1;

sub update
{
    my $self = shift;
    my $id = shift;
    my $time = shift;
    my $overwrite = shift;

    $self->dbm( write => $id, $time, ! $overwrite );
}

sub sync_time
{
    my $self = shift;
    my $id = shift;

    return $self->dbm( read => $id );
}

__END__

=head1 NAME

Alzabo::ObjectCache::Sync::DBM - Base class for syncing modules that use DBM files

=head1 SYNOPSIS

  package Alzabo::ObjectCache::Sync::SomeDBMImplementation;

  use base qw( Alzabo::ObjectCache::Sync::DBM );

=head1 DESCRIPTION

All that a module that subclasses this module needs to do is implement
a C<dbm> method and an optional C<import> method.

=head1 INTERFACE

=head2 import

This method is where the subclass should do whatever setup it needs to
do.  This could mean creating a new DBM file if needed and perhaps
opening it.  It is desirable to do this here if the objects can be
shared across multiple processes.

=head2 dbm ( $mode, $id, $value, $preserve )

The first argument will be either 'read' or 'write'.  The second is
the object id.  The last two arguments are only relevant when the mode
is 'write'.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
