package Alzabo::ObjectCache::Sync;

use vars qw($SELF $VERSION);

use strict;

use Alzabo::Exceptions;
use Time::HiRes qw( time );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.5 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    return $SELF if $SELF;

    my $proto = shift;
    my $class = ref $proto || $proto;

    $SELF = bless {}, $class;
    $SELF->_init(@_);
    $SELF->{times} = {};

    return $SELF;
}

sub _init
{
    return;
}

sub clear
{
    return unless $SELF;
    %{ $SELF->{times} } = ();
}

sub register_store
{
    my $self = shift;
    my $obj = shift;
    my $id = $obj->id;

    return if
	exists $self->{times}{$id} && defined $self->{times}{$id} && $self->{times}{$id} > 0;

    my $time = time;
    # don't overwrite
    $self->update( $id => $time, 0 );

    $self->{times}{$id} = $time;
}

sub is_expired
{
    my $self = shift;
    my $obj = shift;
    my $id = $obj->id;

    return unless exists $self->{times}{$id};

    return $self->{times}{$id} < $self->sync_time($id);
}

sub register_refresh
{
    my $self = shift;
    my $obj = shift;
    my $id = $obj->id;

    return unless exists $self->{times}{$id};

    $self->{times}{$id} = time;
}

sub register_change
{
    my $self = shift;
    my $obj = shift;
    my $id = $obj->id;

    return unless exists $self->{times}{$id};

    my $time = time;
    $self->{times}{$id} = $time;
    $self->update( $id => $time, 1 );
}

sub register_delete
{
    my $self = shift;
    my $obj = shift;
    my $id = $obj->id;

    return unless exists $self->{times}{$id};

    $self->{times}{$id} = -1;
    $self->update( $id => -1, 1 );
}

sub is_deleted
{
    my $self = shift;
    my $obj = shift;
    my $id = $obj->id;

    return 1 if $self->sync_time($id) == -1;
    return 0;
}

sub delete_from_cache
{
    my $self = shift;

    delete $self->{times}{ shift->id };
}

sub update
{
    shift()->_virtual;
}

sub sync_time
{
    shift()->_virtual;
}

sub _virtual
{
    my $self = shift;

    my $sub = (caller(1))[3];
    Alzabo::Exception::VirtualMethod->throw( error =>
					     "$sub is a virtual method and must be subclassed in " . ref $self );
}

__END__

=head1 NAME

Alzabo::ObjectCache::Sync - Base class for syncing classes

=head1 SYNOPSIS

  package Alzabo::ObjectCache::TelepathySync;
  use base qw( Alzabo::ObjectCache::Sync );

=head1 DESCRIPTION

This class implements most of the logic needed for syncing operations.
Subclasses only need to implement methods for actually storing and
retrieving the refresh times for an object.

=head1 METHODS

=head2 new

=head3 Returns

A new cache object.

=head2 fetch_object ($id)

=head3 Returns

The object if it is in the cache.  Otherwise it returns undef.

=head2 store_object ($object)

Stores an object in the cache.  This will not overwrite an existing
object in the cache.  To do that you must first call the
L<C<delete_from_cache>|Alzabo::ObjectCache::Sync/delete_from_cache
($object)> method.

=head2 is_expired ($object)

An object is expired when the local copy's last retrieval of its data
occurred before another copy (in another process, presumably) updated
the external data source containing the object's data (such as an
RDBMS).  Note that a deleted object will not be reported as expired.
Instead, call the L<C<is_deleted>|Alzabo::ObjectCache::Sync/is_deleted
($object)> method.

=head3 Returns

A boolean value indicating whether or not the object is expired.

=head2 is_deleted ($object)

=head3 Returns

A boolean value indicating whether or not an object has been deleted
from the cache.

=head2 register_refresh ($object)

This tells the cache that an object considers its internal data to be
up to date with whatever external source it needs to be up to date
with.

=head2 register_change ($object)

This tells the cache that an object has updated its external data
source.  This means that objects in other processes now become
expired.

=head2 register_delete ($object)

This tells the cache that the object has been removed from its
external data source.  This causes the cache to remove the object
internally.  Future calls to
L<C<is_deleted>|Alzabo::ObjectCache::Sync/is_deleted ($object)> in any
process for this object will now return true.

=head2 delete_from_cache ($object)

This method allows you to remove an object from the cache.  This does
not register the object as deleted.  It is provided solely so that you
can call L<C<store_object>|Alzabo::ObjectCache::Sync/store_object
($object)> after calling this method and have
L<C<store_object>|Alzabo::ObjectCache::Sync/store_object ($object)>
actually store the new object.

=head1 VIRTUAL METHODS

The following methods should be implemented in a subclass.

=head2 _init

This method will be called when the object is first created.  If not
implemented then it will be a noop.

=head2 sync_time ($id)

=head3 Returns

Returns the time that the object matching the given id was last
refreshed.

=head2 update ($id, $time, $overwrite)

This is called to update the state of the syncing object in regards to
a particularl object.  The first parameter is the object's id.  The
second is the time that the object was last refreshed.  The third
parameter, which is optional, tells the syncing object whether or not
to preserve an existing time for the object if it already has one.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
