package Alzabo::ObjectCache;

use vars qw($SELF $VERSION);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.4 $ =~ /(\d+)\.(\d+)/;

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

Alzabo::ObjectCache - A simple cache for row objects.

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
cache.  The obvious exception is the C<store_object> method.

Many of the methods in this class really don't do anything and are
here merely to support the interface that Alzabo::Runtime::Row
expects.

=over 4

=item * new

Takes the following parameters:

=item -- cache_size => $size

Maximum number of objects that can be cached at once.

Returns the caching object.

=item * fetch_object ($id)

Given an object id, returns the object if it is in the cache.
Otherwise it returns undef.

=item * store_object ($object)

Stores an object in the cache.  This will not overwrite an existing
object in the cache.  To do that you must first call the
C<delete_from_cache> method.

=item * is_expired ($object)

Always returns false.

=item * is_deleted ($object)

Returns a boolean value indicating whether or not an object has been
deleted from the cache.

=item * register_refresh ($object)

No op.

=item * register_change ($object)

No op.

=item * register_delete ($object)

This tells the cache that the object has been removed from its
external data source.  This causes the cache to remove the object
internally.  Future calls to C<is_deleted> for this object will now
return true.

=item * delete_from_cache ($object)

This method allows you to remove an object from the cache.  This does
not register the object as deleted.  It is provided solely so that you
can call C<store_object> after calling this method and have
C<store_object> actually store the new object.

=back

=head1 CLASS METHOD

=over 4

=item * clear

Call this method to completely clear the cache.

=back

=head1 CAVEATS

This module has no upper limit on how many objects it will store.  If
you are operating in a persistent environment such as mod_perl, these
will have a tendency to eat up memory over time.

In order to prevent processes from growing without stop, it is
recommended that you call the C<clear> method at the entry point(s)
for your persistent application.  This will flush the cache
completely.  You can also call this method whenever you know you are
done using any row objects you've created up to a certain point in
your application.  However, if you plan on creating them later it
would probably be a performance win to not do this.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
