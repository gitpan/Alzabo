package Alzabo::ObjectCache;

use vars qw($SELF $VERSION %ARGS);

use strict;

$VERSION = sprintf '%2d.%02d', q$Revision: 1.13 $ =~ /(\d+)\.(\d+)/;

1;

sub import
{
    my $class = shift;
    %ARGS = @_;

    $ARGS{store} ||= 'Alzabo::ObjectCache::MemoryStore';
    $ARGS{sync}  ||= 'Alzabo::ObjectCache::NullSync';

    # Don't want to repeat myself.
    # Don't want to repeat myself.
    foreach ( $ARGS{store}, ( $ARGS{store} eq $ARGS{sync} ? () : $ARGS{sync} ) )
    {
	eval "require $_" or die $@;
	eval { $_->import(%ARGS) };
	die $@ if $@;
    }
}

sub new
{
    return $SELF if $SELF;

    my $proto = shift;
    my $class = ref $proto || $proto;
    my %p = @_;

    $SELF = bless { store => $ARGS{store}->new(%ARGS),
		    sync  => $ARGS{sync}->new(%ARGS),
		  }, $class;

    return $SELF;
}

sub clear
{
    return unless $SELF;
    $SELF->{store}->clear;
    $SELF->{sync}->clear;
}

sub fetch_object
{
    shift->{store}->fetch_object(@_);
}

sub store_object
{
    my $self = shift;
    $self->{sync}->register_store(@_);
    $self->{store}->store_object(@_);
}

sub is_expired
{
    shift->{sync}->is_expired(@_);
}

sub register_refresh
{
    shift->{sync}->register_refresh(@_);
}

sub register_change
{
    shift->{sync}->register_change(@_);
}

sub register_delete
{
    my $self = shift;
    $self->{store}->delete_from_cache(@_);
    $self->{sync}->register_delete(@_);
}

sub is_deleted
{
    shift->{sync}->is_deleted(@_);
}

sub delete_from_cache
{
    my $self = shift;
    $self->{sync}->delete_from_cache(@_);
    $self->{store}->delete_from_cache(@_);
}

__END__

=head1 NAME

Alzabo::ObjectCache - A simple in-memory cache for row objects.

=head1 SYNOPSIS

  use Alzabo::ObjectCache( store => 'Alzabo::ObjectCache::MemoryStore',
                           sync  => 'Alzabo::ObjectCache::DBMSync',
                           dbm_file => 'somefile.db' );

=head1 DESCRIPTION

This class exists primarily to delegate necessary caching operations
to other objects.

It always contains two objects.  One is responsible for storing the
objects to be cached.  This can be done in any way that the storing
object sees fit.

The syncing object is responsible for making sure that objects in
multiple processes stay in sync with each other, as well as within a
single process.  For example, if an object in process 1 is deleted and
then process 2 attempts to retrieve the same object from the database,
process 2 needs to be told (in this case via an exception) that this
object is no longer available.  Similarly if process 1 updates the
database then if there is a cached object in process 2, it needs to
know that it should fetch its data again.

=head1 CACHING SCENARIOS

The easiest way to understand how the Alzabo caching system works is
to outline different scenarios and show the results based on different
caching configurations.

=head2 Scenario 1 - Single process - delete followed by select/update

In a single process, the following sequence occurs:

- A row object is retrieved.

- The row object's C<delete> method is called, removing the data it
represents from the database.

- The program attempts to call the row object's C<select> or C<update>
method.

=head3 Results

=over 4

=item * No caching

An C<Alzabo::Exception::NoSuchRow> exception is thrown.

=item * Any syncing module

An C<Alzabo::Exception::Cache::Deleted> exception is thrown.

=back

=head2 Scenario 2 - Multiple processes - delete followed by select

Assume two process, ids 1 and 2.

- Process 1 retrieves a row object.

- Process 2 retrieves a row object for the same database row.

- Process 1 calls that object's C<delete> method.

- Process 2 calls that object's C<select> method.

=head3 Results

=over 4

=item * No caching

An C<Alzabo::Exception::NoSuchRow> exception is thrown.

=item * Alzabo::ObjectCache::NullSync module is in use

If the column(s) have been previously retrieved in process 2, then
that data will be returned.  Otherwise, an
C<Alzabo::Exception::NoSuchRow> exception is thrown.

=item * Any other syncing module is in use

An C<Alzabo::Exception::Cache::Deleted> exception is thrown.

=back

=head2 Scenario 3 - Multiple processes - delete followed by update

Assume two process, ids 1 and 2.

- Process 1 retrieves a row object.

- Process 2 retrieves a row object for the same database row.

- Process 1 calls that object's C<delete> method.

- Process 2 calls that object's C<update> method.

=head3 Results

=over 4

=item * No caching

An C<Alzabo::Exception::NoSuchRow> exception is thrown.

=item * Alzabo::ObjectCache::NullSync module is in use

The object will attempt to update the database.  This is a potential
disaster if, in the meantime, another row with the same primary key
has been inserted.

=item * Any other syncing module is in use

An C<Alzabo::Exception::Cache::Deleted> exception is thrown.

=back

=head2 Scenario 4 - Multiple processes - update followed by update

Assume two process, ids 1 and 2.

- Process 1 retrieves a row object.

- Process 2 retrieves a row object for the same database row.

- Process 1 calls that object's C<update> method.

- Process 2 calls that object's C<update> method.

- Process 1 calls that object's C<select> method.

=head3 Results

=over 4

=item * No caching

The correct data (from process 2's update) is returned.

=item * Alzabo::ObjectCache::NullSync module is in use

Incorrect data (from process 1's update) is returned.

=item * Any other syncing module is in use

The correct data (from process 2's update) is returned.

=back

=head2 Scenario 4 - Multiple processes - delete followed by update

Assume two process, ids 1 and 2.

- Process 1 retrieves a row object.

- Process 2 retrieves a row object for the same database row.

- Process 1 calls that object's C<delete> method.

- Process 2 calls that object's C<update> method.

=head3 Results

=over 4

=item * No caching

An C<Alzabo::Exception::NoSuchRow> exception is thrown.

=item * Alzabo::ObjectCache::NullSync module is in use

The object will attempt to update the database.  This is a potential
disaster if, in the meantime, another row with the same primary key
has been inserted.

=item * Any other syncing module is in use

An C<Alzabo::Exception::Cache::Deleted> exception is thrown.

=back

=head2 Scenario 5 - Multiple processes - delete followed by insert (same primary key)

Assume two process, ids 1 and 2.

- Process 1 retrieves a row object.

- The row is deleted.  In this case, it does not matter whether this
happens through Alzabo or not.

- Process 2 inserts a new row, B<with the same primary key>.

- Process 1 or 2 calls that object's C<select> method.

=head3 Results

=over 4

=item * All cases.

The correct data (from process 2's insert) is returned.  This is a bit
odd if process 1 called the object's C<delete> method, but in that
case it shouldn't be reusing the same object anyway.

=back

This example may seem a bit far-fetched but is actually quite likely
when using MySQL's C<auto_increment> feature.

=head2 Summary

The most important thing to take from this is that you should B<never>
use the C<Alzabo::ObjectCache::NullSync> class in a multi-process
situation.  It is really only safe if you are sure your code will only
be running in a single process at a time.

In all other cases, either use no caching or use one of the other
syncing classes to ensure that data really is synced across multiple
processes.

=head1 METHODS

=head2 import

=head3 Parameters

=over 4

=item * store => 'Alzabo::ObjectCache::StoringClass'

This should be the name of a class that implements the
Alzabo::ObjectCache object storing interface.

Default is
L<C<Alzabo::ObjectCache::MemoryStore>|Alzabo::ObjectCache::MemoryStore>.

=item * sync => 'Alzabo::ObjectCache::SyncingClass'

This should be the name of a class that implements the
Alzabo::ObjectCache object syncing interface.

Default is
L<C<Alzabo::ObjectCache::NullSync>|Alzabo::ObjectCache::NullSync>.

=back

All parameters given will be passed to the import method of the
storing and syncing class being used.

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

Tells the cache system that an object has refreshed its data from the
database.

=head2 register_change ($object)

Tells the cache system that an object has updated its data in the
database.

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

=head2 clear

Call this method to completely clear the cache.

=head1 CAVEATS

This module has no upper limit on how many objects it will store.  If
you are operating in a persistent environment such as mod_perl, these
will have a tendency to eat up memory over time.

In order to prevent processes from growing without stop, it is
recommended that you call the L<C<clear>|clear> method at the entry
point(s) for your persistent application.  This will flush the cache
completely.

=head1 STORING INTERFACE

The interface that any object storing module needs to implement is as
follows:

=head2 new

=head3 Returns

A new object.

=head2 fetch_object ($id)

=head3 Returns

The specified object if it is in the cache.  Otherwise it returns
undef.

=head2 store_object ($object)

Stores an object in the cache but should not overwrite an existing
object.

=head2 delete_from_cache ($object)

This method deletes an object from the cache.

=head2 clear

Completely clears the cache.

=head1 SYNCING INTERFACE

Any class that implements the syncing interface should inherit from
L<C<Alzabo::ObjectCache::Sync>|Alzabo::ObjectCache::Sync>.  This class
provides most of the functionality necessary to handle syncing
operations.

The interface that any object storing module needs to implement is as
follows:

=head2 _init

This method will be called when the object is first created.

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
