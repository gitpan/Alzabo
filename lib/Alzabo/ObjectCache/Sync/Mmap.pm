package Alzabo::ObjectCache::Sync::Mmap;

use strict;

use Cache::Mmap;

use vars qw($VERSION $CACHE);

use Alzabo::ObjectCache::Sync;
use base qw( Alzabo::ObjectCache::Sync );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.4 $ =~ /(\d+)\.(\d+)/;

1;

sub import
{
    my $class = shift;
    my %p = @_;

    Alzabo::Exception::Params->throw( error => "The 'sync_mmap_file' parameter is required when using the " . __PACKAGE__ . ' module' )
	unless exists $p{sync_mmap_file};

    if ( -e $p{sync_mmap_file} && $p{clear_on_startup} )
    {
	unlink $p{sync_mmap_file}
	    or Alzabo::Exception::System->throw( error => "Can't delete '$p{sync_mmap_file}': $!" );
    }

    $CACHE = Cache::Mmap->new( $p{sync_mmap_file}, { strings => 1,
						     buckets => 100,
						     writethrough => 0,
						   } );
}

sub _init
{
    my $self = shift;
    $self->{cache} = $CACHE;
}

sub update
{
    my $self = shift;
    my $id = shift;
    my $time = shift;
    my $overwrite = shift;

    my $curval = $self->{cache}->read($id);

    $self->{cache}->write( $id => $time )
	if ( $overwrite ||
	     ! defined $curval ||
	     $curval <= 0 );
}

sub sync_time
{
    my $self = shift;
    my $id = shift;

    return $self->{cache}->read($id);
}

__END__

=head1 NAME

Alzabo::ObjectCache::Sync::Mmap - Uses a Mmap file to sync object caches

=head1 SYNOPSIS

  use Alzabo::ObjectCache
      ( store => 'Alzabo::ObjectCache::Store::Memory',
        sync  => 'Alzabo::ObjectCache::Sync::Mmap',
        clear_on_startup => 1 );

=head1 DESCRIPTION

This class implements object cache syncing between multiple processes
using Mmap to handle data storage.  The C<Cache::Mmap> module handles
locking.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
