package Alzabo::ObjectCacheIPC;

use vars qw($SELF $VERSION %IPC);

use fields qw( cache ipc times );

use Tie::Cache;

$VERSION = sprintf '%2d.%02d', q$Revision: 1.6 $ =~ /(\d+)\.(\d+)/;

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

    return unless $self->{cache}{$id};

    return 1 if $self->{ipc}{$id} == -1;
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

=over 4

=item * new

Takes the following parameters:

=item -- cache_size => $size

Maximum number of objects that can be cached at once.

Returns the caching object (there's only ever one per process).

=item * fetch_object ($id)

Given an object id, returns the object if it is in the cache.
Otherwise it returns undef.

=item * store_object ($object)

Stores an object in the cache.  This will not overwrite an existing
object in the cache.  To do that you must first call the
C<delete_from_cache> method.

=item * is_expired ($object)

Returns a boolean value indicating whether or not the object is
expired (meaning the local copy's last update of its data occurred.
Not that a deleted object will not be reported as expired.  Instead,
call the C<is_deleted> method.

=item * is_deleted ($object)

Returns a boolean value indicating whether or not an object has been
deleted from the cache.

=item * register_refresh ($object)

This tells the cache that an object considers its internal data to be
up to date with whatever external source it needs to be up to date
with.

=item * register_change ($object)

This tells the cache that an object has updated its external data
source.  This means that objects in other processes now become
expired.

=item * register_delete ($object)

This tells the cache that the object has been removed from its
external data source.  This causes the cache to remove the object
internally.  Future calls to C<is_deleted> in any process for this
object will now return true.

=item * delete_from_cache ($object)

This method allows you to remove an object from the cache.  This does
not register the object as deleted.  It is provided solely so that you
can call C<store_object> after calling this method and have
C<store_object> actually store the new object.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
