package Alzabo::ObjectCache::Store::Memory;

use vars qw($SELF $VERSION);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.5 $ =~ /(\d+)\.(\d+)/;

1;

sub import {}

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
    my $self = shift;

    %{ $self->{cache} } = ();
}

sub fetch_object
{
    my $self = shift;
    my $id = shift;

    # avoid auto-viv
    return $self->{cache}{$id} if exists $self->{cache}{$id};
}

sub store_object
{
    my $self = shift;
    my $obj = shift;

    my $id = $obj->id;

    return if exists $self->{cache}{$id};

    $self->{cache}{$id} = $obj;
}

sub delete_from_cache
{
    my $self = shift;

    delete $self->{cache}{ shift() };
}

__END__

=head1 NAME

Alzabo::ObjectCache::Store::Memory - Cache objects in memory

=head1 SYNOPSIS

  use Alzabo::ObjectCache( store => 'Alzabo::ObjectCache::Store::Memory',
                           sync  => 'Alzabo::ObjectCache::Sync::Null' );

=head1 DESCRIPTION

This class simply stores cached objects in memory.  This means that a
given object should never have to be created twice.

=head1 CAVEATS

This module has no upper limit on how many objects it will store.  If
you are operating in a persistent environment such as mod_perl, these
will have a tendency to eat up memory over time.  Use the lru_size
parameter to Alzabo::ObjectCache to make this module act as an LRU.

=head1 METHODS

Note that pretty much all the methods that take an object as an
argument will silently do nothing if the object is not already in the
cache.  The obvious exception is the
L<C<store_object>|Alzabo::ObjectCache::Store::Memory/store_object
($object)> method.

=head2 new

=head3 Returns

A new C<Alzabo::ObjectCache::Store::Memory> object.

=head2 fetch_object ($id)

=head3 Returns

The specified object if it is in the cache.  Otherwise it returns
undef.

=head2 store_object ($object)

Stores an object in the cache.  This will not overwrite an existing
object in the cache.  To do that you must first call the
L<C<delete_from_cache>|Alzabo::ObjectCache::Store::Memory/delete_from_cache
($object)> method.

=head2 delete_from_cache ($id)

This method allows you to remove an object from the cache.  This does
not register the object as deleted.  It is provided solely so that you
can call L<C<store_object>|Alzabo::ObjectCache/store_object ($object)>
after calling this method and have
L<C<store_object>|Alzabo::ObjectCache/store_object ($object)> actually
store the new object.

=head1 CLASS METHOD

=head2 clear

Call this method to completely clear the cache.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
