package Alzabo::ObjectCacheIPC;

use vars qw($SELF $VERSION %IPC);

use fields qw( cache ipc times );

use Tie::Cache;

$VERSION = sprintf '%2d.%02d', q$Revision: 1.11 $ =~ /(\d+)\.(\d+)/;

1;

BEGIN
{
    use IPC::Shareable;
    tie %IPC, 'IPC::Shareable', 'AOCI', { create => 1, destroy => 1 }
	or die "couldn't tie to IPC segment during BEGIN block";
}

sub new
{
    return $SELF if $SELF;

    my $proto = shift;
    my $class = ref $proto || $proto;
    my %p = @_;

    $SELF = bless {}, $class;

    tie %{ $SELF->{cache} }, 'Tie::Cache', { MaxCount => $p{cache_size} || 1000 };

    $SELF->{ipc} = \%IPC;
    $SELF->{times} = {};

    return $SELF;
}

sub clear
{
    return unless $SELF;
    %{ $SELF->{times} } = {};
    %{ $SELF->{cache} } = {};
}

sub fetch_object
{
    my $self = shift;
    my $id = shift;

    return $self->{cache}{$id} if exists $self->{cache}{$id};
}

sub store_object
{
    my $self = shift;
    my $obj = shift;
    my $id = $obj->id;

    return if exists $self->{cache}{$id};

    my $time = time;
    $self->{ipc}{$id} ||= $time;
    $self->{times}{$id} = $time;
    $self->{cache}{$id} = $obj;
}

sub is_expired
{
    my $self = shift;
    my $obj = shift;
    my $id = $obj->id;

    return unless $self->{cache}{$id};

    return $self->{times}{$id} < $self->{ipc}{$id};
}

sub register_refresh
{
    my $self = shift;
    my $obj = shift;
    my $id = $obj->id;

    return unless $self->{cache}{$id};

    $self->{times}{$id} = time;
}

sub register_change
{
    my $self = shift;
    my $obj = shift;
    my $id = $obj->id;

    return unless $self->{cache}{$id};

    $self->{times}{$id} = $self->{ipc}{$id} = time;
}

sub register_delete
{
    my $self = shift;
    my $obj = shift;
    my $id = $obj->id;

    return unless $self->{cache}{$id};

    $self->{times}{$id} = $self->{ipc}{$id} = -1;
    delete $self->{cache}{$id};
}

sub is_deleted
{
    my $self = shift;
    my $obj = shift;
    my $id = $obj->id;

    return 1 if $self->{times}{$id} == -1;
    return 0;
}

sub delete_from_cache
{
    my $self = shift;
    my $obj = shift;
    my $id = $obj->id;

    return unless $self->{cache}{$id};

    delete $self->{times}{$id};
    delete $self->{cache}{$id};
}

__END__

=head1 NAME

Alzabo::ObjectCacheIPC - Uses IPC to coordinate object caching between
multiple processes.

=head1 SYNOPSIS

  use Alzabo::Runtime::Row qw(Alzabo::ObjectCacheIPC);

=head1 DESCRIPTION

This class serves two functions.  First it caches objects in the memory
space local to a process.  Second, it keeps track of whether or not an
object has been updated or deleted in another process by using IPC to
keep track of the timestamps of objects.

This allows it know when another process update or deletes an object.
The cache class is then able to act appropriately and inform the
caller that the object needs to be refreshed (presumably against an
external data source such as a database).

Though this class was written specifically to work with the
Alzabo::Runtime::Row class it will work with any set of objects that
support an C<id> method.  Just make sure that the return value of this
method is really truly unique.

=head1 METHODS

Note that pretty much all the methods that take an object as an
argument will silently do nothing if the object is not already in the
cache.  The obvious exception is the C<store_object> method.

=head2 new

=head3 Parameters

=over 4

=item * cache_size => $size

Maximum number of objects that can be cached at once.

=back

=head3 Returns

A new cache object.

=head2 fetch_object ($id)

=head3 Returns

The object if it is in the cache.  Otherwise it returns undef.

=head2 store_object ($object)

Stores an object in the cache.  This will not overwrite an existing
object in the cache.  To do that you must first call the
L<C<delete_from_cache>|Alzabo::ObjectCacheIPC/delete_from_cache
($object)> method.

=head2 is_expired ($object)

An object is expired when the local copy's last retrieval of its data
occurred before another copy (in another process, presumably) updated
the external data source containing the object's data (such as an
RDBMS).  Note that a deleted object will not be reported as expired.
Instead, call the L<C<is_deleted>|Alzabo::ObjectCacheIPC/is_deleted
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
L<C<is_deleted>|Alzabo::ObjectCacheIPC/is_deleted ($object)> in any
process for this object will now return true.

=head2 delete_from_cache ($object)

This method allows you to remove an object from the cache.  This does
not register the object as deleted.  It is provided solely so that you
can call L<C<store_object>|Alzabo::ObjectCacheIPC/store_object
($object)> after calling this method and have
L<C<store_object>|Alzabo::ObjectCacheIPC/store_object ($object)>
actually store the new object.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
