package Alzabo::ObjectCache::Sync;

use vars qw($SELF $VERSION);

use strict;

use Alzabo::Exceptions;
use Time::HiRes qw( time );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.15 $ =~ /(\d+)\.(\d+)/;

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
    $SELF->{id_times} = {};

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
    my $id = $obj->id;
    my $time = shift;

    $time = sprintf('%11.23f', defined $time ? $time : time);

    $self->{obj_times}{$obj} = $time;

    return if
	exists $self->{id_times}{$id};

    # don't overwrite
    $self->update( $id => $time, 0 );
    $self->{id_times}{$id} = $time;
}

sub is_expired
{
    my $self = shift;
    my $obj = shift;
    my $id = $obj->id;

    my $sync_time = $self->sync_time($id);

    return 1 if exists $self->{obj_times}{$obj} && $self->{obj_times}{$obj} < $sync_time;

    return 1 if exists $self->{id_times}{$id} && $self->{id_times}{$id} < $sync_time;

    return 1 if $sync_time && ! ( exists $self->{id_times}{$id} || exists $self->{obj_times}{$obj} );

    return 0;
}

sub register_refresh
{
    my $self = shift;
    my $obj = shift;
    my $id = $obj->id;

    return unless exists $self->{obj_times}{$obj};

    my $time = sprintf( '%11.23f', time );
    $self->{obj_times}{$obj} = $time;
}

sub register_change
{
    my $self = shift;
    my $obj = shift;
    my $id = $obj->id;
    my $time = shift;

    return unless exists $self->{id_times}{$id};

    $time = sprintf('%11.23f', defined $time ? $time : time);

    $self->{id_times}{$id} = $self->{obj_times}{$obj} = $time;
    $self->update( $id => $time, 1 );
}

sub register_delete
{
    my $self = shift;
    my $obj = shift;
    my $id = $obj->id;

    return unless exists $self->{id_times}{$id};

    $self->update( $id => -1, 1 );
    delete $self->{id_times}{$id};
    delete $self->{obj_times}{$obj};
}

sub is_deleted
{
    my $self = shift;
    my $obj = shift;
    my $id = $obj->id;

    return 1 if $self->sync_time($id) == -1;
    return 0;
}

sub delete_from_cache
{
    my $self = shift;
    my $obj = shift;

    delete $self->{obj_times}{$obj};
}

sub clear
{
    my $self = shift;

    $self->{id_times} = {};
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
