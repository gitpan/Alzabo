package Alzabo::ObjectCache::Sync::Null;

use strict;

use vars qw($SELF $VERSION);

use base qw( Alzabo::ObjectCache::Sync );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.2 $ =~ /(\d+)\.(\d+)/;

1;

sub _init
{
    my $self = shift;
    $self->{times} = {};
}

sub clear
{
    return unless $SELF;
    %{ $SELF->{times} } = ();
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
using this syncing module along with one of the caching modules will
increase the speed of your application.  Using it in a multi-process
situation is likely to cause data corruption unless your application
is entirely read-only.

L<CACHING SCENARIOS|Alzabo::ObjectCache/CACHING SCENARIOS>.

=head1 METHODS

=head2 new

=head3 Returns

A new C<Alzabo::ObjectCache> object.

=head2 fetch_object ($id)

=head3 Returns

The specified object if it is in the cache.  Otherwise it returns
undef.

=head2 store_object ($object)

Stores an object in the cache.  This will not overwrite an existing
object in the cache.  To do that you must first call the
L<C<delete_from_cache>|Alzabo::ObjectCache/delete_from_cache
($object)> method.

=head2 is_expired ($object)

Objects cached in this class are never expired.

=head3 Returns

This always false for this class because there is no notion of
expiration for this cache.

=head2 is_deleted ($object)

=head3 Returns

A boolean value indicating whether or not an object has been deleted
from the cache.

=head2 register_refresh ($object)

This does nothing in this class.

=head2 register_change ($object)

This does nothing in this class.

=head2 register_delete ($object)

This tells the cache that the object has been removed from its
external data source.  This causes the cache to remove the object
internally.  Future calls to
L<C<is_deleted>|Alzabo::ObjectCache/is_deleted ($object)> for this
object will now return true.

=head2 delete_from_cache ($object)

This method allows you to remove an object from the cache.  This does
not register the object as deleted.  It is provided solely so that you
can call L<C<store_object>|Alzabo::ObjectCache/store_object ($object)>
after calling this method and have
L<C<store_object>|Alzabo::ObjectCache/store_object ($object)> actually
store the new object.

=head1 CLASS METHOD

=head2 clear

Call this method to completely clear the cache.

=head1 CAVEATS

This module has no upper limit on how many objects it will store.  If
you are operating in a persistent environment such as mod_perl, these
will have a tendency to eat up memory over time.

In order to prevent processes from growing without stop, it is
recommended that you call the L<C<clear>|clear> method at the entry
point(s) for your persistent application.  This will flush the cache
completely.  You can also call this method whenever you know you are
done using any row objects you've created up to a certain point in
your application.  However, if you plan on creating them again later
it would probably be a performance win to not do this.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
