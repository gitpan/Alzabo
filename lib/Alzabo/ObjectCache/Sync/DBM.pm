package Alzabo::ObjectCache::Sync::DBM;

use strict;

use vars qw($SELF $VERSION);

use base qw( Alzabo::ObjectCache::Sync );

use Alzabo::Exceptions;

$VERSION = sprintf '%2d.%02d', q$Revision: 1.2 $ =~ /(\d+)\.(\d+)/;

1;

sub update
{
    my $self = shift;
    my $id = shift;
    my $time = shift;
    my $overwrite = shift;

    $self->dbm( write => $id, $time, ! $overwrite );
}

sub sync_time
{
    my $self = shift;
    my $id = shift;

    return $self->dbm( read => $id );
}

sub clear
{
    return unless $SELF;
    %{ $SELF->{times} } = ();
}

__END__

=head1 NAME

Alzabo::ObjectCache::Sync::DBM - Base class for syncing modules that use DBM files

=head1 SYNOPSIS

  use base qw( Alzabo::ObjectCache::Sync::DBM );

=head1 DESCRIPTION

All that a module that subclasses this module needs to do is implement
a C<dbm> method and an optional C<import> method.

=head1 INTERFACE

todo

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
