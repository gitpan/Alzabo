package Alzabo::ObjectCache::Sync;

use vars qw($SELF $VERSION);

use strict;

use Alzabo::Exceptions;
use Time::HiRes qw( time );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.17 $ =~ /(\d+)\.(\d+)/;

1;

sub import { 1 };

sub new
{
    return $SELF if $SELF;

    my $proto = shift;
    my $class = ref $proto || $proto;

    $SELF = bless {}, $class;
    $SELF->_init(@_);
    $SELF->{obj_times} = {};

    return $SELF;
}

sub _init
{
    return;
}

sub register_store
{
    my $self = shift;
    my $obj = shift;
    my $time = shift;

    my $id = $obj->id_as_string;
    my $cache_id = $obj->cache_id;

    $time = sprintf('%11.23f', defined $time ? $time : time);

    $self->{obj_times}{$cache_id} = $time;

    # don't overwrite
    $self->update( $id => $time, 0 );
}

sub is_expired
{
    my $self = shift;
    my $obj = shift;

    my $id = $obj->id_as_string;
    my $cache_id = $obj->cache_id;

    my $sync_time = $self->sync_time($id);

    return 0 if exists $self->{obj_times}{$cache_id} && $self->{obj_times}{$cache_id} >= $sync_time;

    return 1 if exists $self->{obj_times}{$cache_id} && $self->{obj_times}{$cache_id} < $sync_time;

    return 1 if $sync_time && ! exists $self->{obj_times}{$cache_id};

    return 0;
}

sub register_refresh
{
    my $self = shift;
    my $obj = shift;
    my $id = $obj->id_as_string;
    my $cache_id = $obj->cache_id;

    return unless exists $self->{obj_times}{$cache_id};

    my $time = sprintf( '%11.23f', time );
    $self->{obj_times}{$cache_id} = $time;
}

sub register_change
{
    my $self = shift;
    my $obj = shift;
    my $time = shift;

    my $id = $obj->id_as_string;
    my $cache_id = $obj->cache_id;

    $time = sprintf('%11.23f', defined $time ? $time : time);

    $self->{obj_times}{$cache_id} = $time;
    $self->update( $id => $time, 1 );
}

sub register_delete
{
    my $self = shift;
    my $obj = shift;
    my $id = $obj->id_as_string;
    my $cache_id = $obj->cache_id;

    $self->update( $id => -1, 1 );
    delete $self->{obj_times}{$cache_id};
}

sub is_deleted
{
    my $self = shift;
    my $obj = shift;
    my $id = $obj->id_as_string;

    return 1 if $self->sync_time($id) == -1;
    return 0;
}

sub delete_from_cache
{
    my $self = shift;
    my $obj = shift;
    my $cache_id = $obj->cache_id;

    delete $self->{obj_times}{$cache_id};
}

sub clear
{
    my $self = shift;

    $self->{obj_times} = {};
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

  use Alzabo::ObjectCache::Sync;
  use base qw( Alzabo::ObjectCache::Sync );

=head1 DESCRIPTION

This class implements most of the logic needed for syncing operations.
Subclasses only need to implement methods for actually storing and
retrieving the refresh times for an object.

=head1 SUBCLASSING

See the L<C<Alzabo::ObjectCache>|Alzabo::ObjectCache/Syncing
Interface> docs for information on what a subclass of this module
should implement.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
