package Alzabo::ObjectCache::Store::LRU;

use strict;

use vars qw($SELF $VERSION @ISA);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.5 $ =~ /(\d+)\.(\d+)/;

1;

sub import
{
    my $class = shift;
    my %args = @_;

    my $parent = $args{store};

    @ISA = $parent;

    eval "require $parent";
    Alzabo::Exception::Eval->throw( error => $@ ) if $@;
    $parent->import(%args);
}

sub new
{
    return $SELF if $SELF;
    my $class = shift;

    my %p = @_;
    $SELF = $class->SUPER::new(%p);

    $SELF->{lru_size} = $p{lru_size};

    $SELF->{lru} = [];
    # should pre-allocate memory for max size of array
    $#{ $SELF->{lru} } = $SELF->{lru_size};

    $SELF->{lru_index} = {};

    return $SELF;
}

sub clear
{
    my $self = shift;

    $self->{lru} = [];
    $#{ $SELF->{lru} } = $SELF->{lru_size};

    $self->{lru_index} = {};

    $self->SUPER::clear;
}

sub fetch_object
{
    my $self = shift;
    my $id = shift;

    $self->_promote($id);

    $self->SUPER::fetch_object($id);
}

sub store_object
{
    my $self = shift;
    my $obj = shift;

    $self->_promote( $obj->id_as_string );

    $self->_cull;

    $self->SUPER::store_object($obj);
}

sub delete_from_cache
{
    my $self = shift;
    my $id = shift;

    delete $self->{lru_index}{$id};

    $self->SUPER::delete_from_cache($id);
}

sub _promote
{
    my $self = shift;
    my $id = shift;

    # remove it if it exists
    if ( my $idx = delete $self->{lru_index}{$id} )
    {
	splice @{ $self->{lru} }, $idx, 1;
    }

    # put it on top
    unshift @{ $self->{lru} }, $id;
    $self->{lru_index}{$id} = 0;
}

sub _cull
{
    my $self = shift;

    if ( @{ $self->{lru} } > $self->{lru_size} )
    {
	foreach ( grep { defined } splice @{ $self->{lru} }, $self->{lru_size} )
	{
	    $self->delete_from_cache($_);
	}
    }
}


__END__

=head1 NAME

Alzabo::ObjectCache::Store::LRU - Make any storage module an LRU

=head1 SYNOPSIS

  use Alzabo::ObjectCache( store => 'Alzabo::ObjectCache::Store::Memory',
                           sync  => 'Alzabo::ObjectCache::Sync::Null',
                           lru_size => 100 );

=head1 DESCRIPTION

This class can help turn any storage module into an LRU cache fairly
easily.


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

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
