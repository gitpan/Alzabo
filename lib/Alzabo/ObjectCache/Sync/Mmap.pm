package Alzabo::ObjectCache::Sync::Mmap;

use strict;

use Cache::Mmap;

use vars qw($VERSION $CACHE);

use Alzabo::ObjectCache::Sync;
use base qw( Alzabo::ObjectCache::Sync );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.3 $ =~ /(\d+)\.(\d+)/;

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

Alzabo::ObjectCache::Sync::IPC - Uses a IPC file to sync object caches

=head1 SYNOPSIS

  use Alzabo::ObjectCache
      ( store => 'Alzabo::ObjectCache::Store::Memory',
        sync  => 'Alzabo::ObjectCache::Sync::IPC',
        clear_on_startup => 1 );

=head1 DESCRIPTION

This class implements object cache syncing between multiple processes
using IPC to handle data storage.  The C<IPC::Shareable> module which
it uses handles locking issues.

In normal circumstances, the IPC segment used by this module is
deleted when the process that first loaded the module ends.  If the
program is aborted abnormally (via certain signals, for example) then
this cleanup will probably not occur.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
