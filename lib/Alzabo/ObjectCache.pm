package Alzabo::ObjectCache;

use vars qw($SELF $VERSION);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.9 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    return $SELF if $SELF;

    my $proto = shift;
    my $class = ref $proto || $proto;
    my %p = @_;

    $SELF = bless {}, $class;
    return $SELF;
}

sub clear
{
    return unless $SELF;
    %{ $SELF->{cache} } = ();
}

sub fetch_object
{
    my $self = shift;
    my $id = shift;

    if ( exists $self->{cache}{$id} && $self->{cache}{$id} != 0 )
    {
	return $self->{cache}{$id};
    }
}

sub store_object
{
    my $self = shift;
    my $obj = shift;

    my $id = $obj->id;
    return if exists $self->{cache}{$id};

    $self->{cache}{$id} = $obj;
}

sub is_expired
{
    return;
}

sub register_refresh
{
    return;
}

sub register_change
{
    return;
}

sub register_delete
{
    my $self = shift;
    my $obj = shift;

    my $id = $obj->id;

    return unless exists $self->{cache}{$id};

    $self->{cache}{$id} = 0;
}

sub is_deleted
{
    my $self = shift;
    my $obj = shift;

    my $id = $obj->id;

    return unless exists $self->{cache}{$id};

    return $self->{cache}{$id} == 0;
}

sub delete_from_cache
{
    my $self = shift;
    my $obj = shift;

    my $id = $obj->id;

    return unless exists $self->{cache}{$id};

    delete $self->{cache}{$id};
}

__END__

=head1 NAME

Alzabo::ObjectCache - A simple in-memory cache for row objects.

=head1 SYNOPSIS

  use Alzabo::Runtime::Row qw(Alzabo::ObjectCache);

=head1 DESCRIPTION

This class is a very simple caching class.  It's main purpose is to
ensure that any given row is only created once.  This means that when
some sort of action at a distance on a row happens, any other
references to it stay up to date.  For example, if your application
triggers an update for referential integrity reasons and you have a
reference to the same object in your code, this makes sure that the
update will be seen in your code.

=head1 METHODS

Note that pretty much all the methods that take an object as an
argument will silently do nothing if the object is not already in the
cache.  The obvious exception is the
L<C<store_object>|Alzabo::ObjectCache/store_object ($object)> method.

Many of the methods in this class really don't do anything and are
here merely to support the interface that
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> expects.

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
