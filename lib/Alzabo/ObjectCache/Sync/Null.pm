package Alzabo::ObjectCache::Sync::Null;

use strict;

use vars qw($VERSION);

use Alzabo::ObjectCache::Sync;
use base qw( Alzabo::ObjectCache::Sync );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.5 $ =~ /(\d+)\.(\d+)/;

1;

sub _init
{
    my $self = shift;
    $self->{times} = {};
}

sub clear
{
    my $self = shift;

    %{ $self->{times} } = ();
}

sub sync_time
{
    my $self = shift;
    my $id = shift;

    return $self->{times}{$id}
}

sub update
{
    my $self = shift;
    my $id = shift;
    my $time = shift;
    my $overwrite = shift;

    $self->{times}{$id} = $time
	if ( $overwrite ||
	     ! exists $self->{times}{$id} ||
	     $self->{times}{$id} <= 0 );
}

__END__

=head1 NAME

Alzabo::ObjectCache::Sync::Null - No inter-process cache syncing

=head1 SYNOPSIS

  use Alzabo::ObjectCache( store => 'Alzabo::ObjectCache::Store::Memory',
                           sync  => 'Alzabo::ObjectCache::Sync::Null' );

=head1 DESCRIPTION

This class does not do any actual inter-process syncing.  It does,
however, keep track of deleted objects.  This is needed in the case
where one part of a program deletes an object to which another part of
the program has a refence.  If the other part attempts to use the
object an exception will be thrown.

If you are running Alzabo as part of a single-process application,
using this syncing module along with one of the storage modules will
probably increase the speed of your application.  Using it in a
multi-process situation is likely to cause data corruption unless your
application is entirely read-only.

L<CACHING SCENARIOS|Alzabo::ObjectCache/CACHING SCENARIOS>.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
