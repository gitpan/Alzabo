package Alzabo::ObjectCache;

use strict;
use vars qw($SELF $VERSION %ARGS);

# load this for use by Alzabo::Runtime::Row
use Alzabo::Runtime::CachedRow;

$VERSION = sprintf '%2d.%02d', q$Revision: 1.39 $ =~ /(\d+)\.(\d+)/;

1;

sub import
{
    my $class = shift;

    %ARGS = @_;

    $ARGS{store} ||= 'Alzabo::ObjectCache::Store::Memory';
    $ARGS{sync}  ||= 'Alzabo::ObjectCache::Sync::Null';

    # save it cause it might get mangled below
    my $store = $ARGS{store};
    if ( $ARGS{lru_size} )
    {
	require Alzabo::ObjectCache::Store::LRU;
	Alzabo::ObjectCache::Store::LRU->import(%ARGS);
	$ARGS{store} = 'Alzabo::ObjectCache::Store::LRU';
    }

    #
    # Don't want to repeat modules if store and sync were the same
    # module (before LRU tweaks).
    #
    # Also, if lru_size was set then the
    # Alzabo::ObjectCache::Store::LRU took care of importing the
    # originally specified store module so we'll leave it alone
    #
    foreach ( ( $ARGS{lru_size} ? () : $ARGS{store} ),
	      ( $store eq $ARGS{sync} ? () : $ARGS{sync} ) )
    {
	eval "require $_";
	Alzabo::Exception::Eval->throw( error => $@ ) if $@;
	$_->import(%ARGS);
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
    $self->{store}->delete_from_cache( $_[0]->id_as_string );
    $self->{sync}->register_delete(@_);
}

sub is_deleted
{
    shift->{sync}->is_deleted(@_);
}

sub delete_from_cache
{
    my $self = shift;
    $self->{sync}->delete_from_cache($_[0]);
    $self->{store}->delete_from_cache(@_);
}

sub sync_time
{
    my $self = shift;
    return $self->{sync}->sync_time( shift->id_as_string );
}

__END__

=head1 NAME

Alzabo::ObjectCache - A simple in-memory cache for row objects.

=head1 SYNOPSIS

  use Alzabo::ObjectCache
      ( store => 'Alzabo::ObjectCache::Store::Memory',
        sync  => 'Alzabo::ObjectCache::Sync::BerkeleyDB',
        sync_dbm_file => 'somefile.db' );

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

=head1 IMPORT

This module is configured entirely through the parameters passed when
it is imported.

=head2 Parameters

=over 4

=item * store => 'Alzabo::ObjectCache::Store::Foo'

This should be the name of a class that implements the
Alzabo::ObjectCache object storing interface.

The default is
L<C<Alzabo::ObjectCache::Store::Memory>|"Alzabo::ObjectCache::Store::Memory">.

=item * sync => 'Alzabo::ObjectCache::Sync::Foo'

This should be the name of a class that implements the
Alzabo::ObjectCache object syncing interface.

Default is
L<C<Alzabo::ObjectCache::Sync::Null>|"Alzabo::ObjectCache::Sync::Null">.

=item * lru_size => $size

This is the maximum number of objects you want the storing class to
store at once.  If it is 0 or undefined, the default, the storage
class will store an unlimited number of objects.

=back

All parameters given will be also be passed through to the import
method of the storing and syncing class being used.

=head1 LRU STORAGE

Any storage module can be turned into an LRU cache by passing an
lru_size parameter to this module when using it.

For example:

  use Alzabo::ObjectCache
          ( store => 'Alzabo::ObjectCache::Store::Memory',
            lru_size => 100,
            sync  => 'Alzabo::ObjectCache::Sync::BerkeleyDB',
            sync_dbm_file => 'somefile.db' );

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

=item * Alzabo::ObjectCache::Sync::Null module is in use

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

=item * Alzabo::ObjectCache::Sync::Null module is in use

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

The data from process 2's update is returned.

=item * Alzabo::ObjectCache::Sync::Null module is in use

The data from process 1's update is returned.

=item * Any other syncing module is in use

An C<Alzabo::Exception::Cache::Expired> exception is thrown when
process 2 attempts to update the row.  If process 2 were to then
attempt the update B<again> it would succeed (as the object is updated
before the exception is thrown).

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
when using MySQL's C<auto_increment> feature with older versions of
MySQL, where numbers could be re-used.

=head2 Summary

The most important thing to take from this is that you should B<never>
use the C<Alzabo::ObjectCache::Sync::Null> class in a multi-process
situation.  It is really only safe if you are sure your code will only
be running in a single process at a time.

In all other cases, either use no caching or use one of the other
syncing classes to ensure that data really is synced across multiple
processes.

=head1 RACE CONDITIONS

It is important to note that there are small race conditions in the
syncing scheme.  When data is requested from a row object, the row
object first makes sure that it is up to date with the database.  If
it is not, it refreshes itself.  Then, it returns the requested data
(whether or or not it had to refresh).  It is possible that in the
time between checking whether or not it is expired that an update
could occur.  This would not be seen by the row object.

I don't consider this a bug since it is impossible to work around and
is unlikely to be a problem.  In a single process, this is not an
issue.  In a multi-process application, this is the price that is paid
for caching.

If this is a problem for your application then you should not use
caching.

=head1 SYNCING MODULES

The following syncing modules are available with Alzabo:

=head2 Alzabo::ObjectCache::Sync::Null

This module simply emulates the syncing interface without doing any
actual syncing, though it does track deleted objects.  This module is
useful is you want to cache objects in a single process but you don't
need the overhead of real syncing.

=head2 Alzabo::ObjectCache::Sync::BerkeleyDB

=head2 Alzabo::ObjectCache::Sync::SDBM_File

=head2 Alzabo::ObjectCache::Sync::DB_File

These three modules all use DBM files, via the relevant module, to do
multi-process syncing.  They are listed in order from fastest to
slowest.  Using DB_File is significantly slower than either BerkeleyDB
or SDBM_File, which are both relatively fast.

They all take the same parameters:

=over 4

=item * sync_dbm_file => $filename

The file which should be used to store syncing data.

=item * clear_on_startup => $boolean

Indicates whether or not the file should be cleared before it is first
used.

=back

=head2 Alzabo::ObjectCache::Sync::Mmap

This module uses C<Cache::Mmap> for syncing.  It takes the following
parameters.

=over 4

=item * sync_mmap_file => $filename

The file which should be used to store syncing data.

=item * clear_on_startup => $boolean

Indicates whether or not the file should be cleared before it is first
used.

=back

=head2 Alzabo::ObjectCache::Sync::RDBMS

This module uses an RDBMS to do syncing.  This does B<not> need to be
the same database as your data is stored in, though it could be.

If the database it is told to use does not contain the table it needs,
it will use the C<Alzabo::Create> modules to create it.  If you have
warnings turned on, this will cause a warning telling you that these
modules were loaded, as having them loaded in any sort of persistent
process is probably a waste of memory.

The table it stores data in looks like this:

  AlzaboObjectCacheSync
  ----------------------
  object_id       varchar(22)   primary key
  sync_time       varchar(40)

This modules take the following parameters:

=over 4

=item * sync_schema_name => $name

This should be the name of the schema where you want syncing data to
be stored.  If it doesn't exist, this module will attempt to create
it.

=item * sync_rdbms => $name (optional)

If the schema given does not exist, then this parameter is required so
this module knows what type of database it is connecting to.

=item * sync_user => $user (optional)

A username with which to connect to the database.

=item * sync_password => $password (optional)

A password with which to connect to the database.

=item * sync_host => $host (optional)

The host where the database lives.

=item * sync_connect_params => { extra_param => 1 }

Extra connection parameters.  These will simply be passed onto the
relevant Driver module.

=back

=head2 Alzabo::ObjectCache::Sync::IPC

This module is quite slow and is included mostly for historical
reasons (it was one of the first syncing modules made).  I recommend
against using it but if you must it takes the following parameters:

=over 4

=item * clear_on_startup => $boolean

Indicates whether or not the file should be cleared before it is first
used.

=back

=head1 STORAGE MODULES

All of the storage modules may be turned into LRU caches by simply
passing the L<lru_size parameter|"LRU STORAGE">.

The following storage modules are included with Alzabo:

=head2 Alzabo::ObjectCache::Store::Null

This module mimics the storage interface without actually storing
anything.  It is useful if you want to use syncing without any
storage.

=head2 Alzabo::ObjectCache::Store::Memory

This module simply stored cached objects in memory.

=head2 Alzabo::ObjectCache::Store::BerkeleyDB

This module stores serialized cached objects in a DBM file using the
BerkeleyDB module.

It takes these parameters:

=over 4

=item * store_dbm_file => $filename

The file which should be used to store serialized objects.

=item * clear_on_startup => $boolean

Indicates whether or not the file should be cleared before it is first
used.

=back

=head2 Alzabo::ObjectCache::Store::RDBMS

This module uses an RDBMS to do store.  This does B<not> need to be
the same database as your data is stored in, though it could be.

For example, if you are using Oracle as your primary RDBMS, caching
serialized objects in a MySQL database might be a performance boost.

If the database it is told to use does not contain the table it needs,
it will use the C<Alzabo::Create> modules to create it.  If you have
warnings turned on, this will cause a warning telling you that these
modules were loaded, as having them loaded in any sort of persistent
process is probably a waste of memory.

The table it stores data in looks like this:

  AlzaboObjectCacheStore
  ----------------------
  object_id       varchar(22)   primary key
  object_data     blob

The actual type of the object_data column will vary depending on what
RDBMS you are using.

This modules take the following parameters:

=over 4

=item * store_schema_name => $name

This should be the name of the schema where you want syncing data to
be stored.  If it doesn't exist, this module will attempt to create
it.

=item * store_rdbms => $name (optional)

If the schema given does not exist, then this parameter is required so
this module knows what type of database it is connecting to.

=item * store_user => $user (optional)

A username with which to connect to the database.

=item * store_password => $password (optional)

A password with which to connect to the database.

=item * store_host => $host (optional)

The host where the database lives.

=item * store_connect_params => { extra_param => 1 }

Extra connection parameters.  These will simply be passed onto the
relevant Driver module.

=back

=head1 Alzabo::ObjectCache METHODS

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

=head3 Returns

Whether or not the given object is expired.

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

=head1 MAKING YOUR OWN SUBCLASSES

It is relatively easy to create your own storage or syncing modules by
following a fairly simple interface.

=head2 Storage Interface

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

=head2 Syncing Interface

Any class that implements the syncing interface should inherit from
L<C<Alzabo::ObjectCache::Sync>|Alzabo::ObjectCache::Sync>.  This
class provides most of the functionality necessary to handle syncing
operations.

The interface that any object storing module needs to implement is as
follows:

=head2 _init

This method will be called when the object is first created.

=head2 clear

Clears the process-local sync times (not the times shared between
processes).

=head2 sync_time ($id)

=head3 Returns

Returns the time that the object matching the given id was last
refreshed.

=head2 update ($id, $time, $overwrite)

This is called to update the state of the syncing object in regards to
a particularl object.  The first parameter is the object's id.  The
second is the time that the object was last refreshed.  The third
parameter tells the syncing object whether or not to preserve an
existing time for the object if it already has one.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
