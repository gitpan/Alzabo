package Alzabo::ObjectCache::Sync::DB_File;

use strict;

use vars qw($VERSION $FILE);

use base qw( Alzabo::ObjectCache::Sync::DBM );

use Alzabo::Exceptions;
use DB_File;
use Fcntl qw( :flock O_RDONLY O_RDWR O_CREAT );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.5 $ =~ /(\d+)\.(\d+)/;

1;

sub import
{
    my $class = shift;
    my %p = @_;

    Alzabo::Exception::Params->throw( error => "The 'sync_dbm_file' parameter is required when using the " . __PACKAGE__ . ' module' )
	unless exists $p{sync_dbm_file};

    $FILE = $p{sync_dbm_file};

    if ( ( ! -e $FILE) || $p{clear_on_startup} )
    {
	if (-e $FILE)
	{
	    unlink $FILE or Alzabo::Exception::System->throw( error => "Can't delete '$FILE': $!" );
	}
    }
}

sub dbm
{
    my $self = shift;
    my $mode = shift;
    my $id = shift;
    my $val = shift;
    my $preserve = shift;

    my ($lock_mode, $open_mode) = $mode eq 'write' ? ( LOCK_EX, O_RDWR | O_CREAT ) : ( LOCK_SH, O_RDONLY | O_CREAT );

    my %orig_db;
    # This code largely ripped off from Tie::DB_FileLock
    my $db = tie %orig_db, 'DB_File', $FILE, $open_mode, 0644
	or Alzabo::Exception::System->throw( error => "Can't tie '$FILE' ($mode mode): $!" );

    $db->sync;

    my $fh = do { local *FH; *FH; };
    open $fh, '<&=' . $db->fd
	or Alzabo::Exception::System->throw( error =>
					     "Can't dup file descriptor for '$FILE': $!" );

    flock( $fh, $lock_mode )
	or Alzabo::Exception::System->throw( error =>
					     "Unable to place a $mode lock on '$FILE': $!" );

    my %db;
    $db = tie %db, 'DB_File', $FILE, $open_mode, 0644
	or Alzabo::Exception::System->throw( error => "Can't tie '$FILE' ($mode mode): $!" );

    my $return;
    if ($mode eq 'read' || $preserve)
    {
	$db->get($id, $return);
    }

    if ($mode eq 'write')
    {
	unless ($preserve && defined $return && $return > 0)
	{
	    $db->put( $id => $val );
	    $db->sync;
	    $return = $val;
	}
    }

    flock( $fh, LOCK_UN )
	or Alzabo::Exception::System->throw( error => "Unable to unlock '$FILE': $!" );

    # This is crucial for some reason I can't figure out!
    close $fh;

    return $return;
}

__END__

=head1 NAME

Alzabo::ObjectCache::Sync::DB_File - Uses a Berkeley DB file to sync object caches

=head1 SYNOPSIS

  use Alzabo::ObjectCache( store => 'Alzabo::ObjectCache::Store::Memory',
                           sync  => 'Alzabo::ObjectCache::Sync::DB_File',
                           sync_dbm_file => 'somefilename.db',
                           clear_on_startup => 1 );

=head1 DESCRIPTION

This class implements object cache syncing between multiple processes
using a Berkeley DB file to handle data storage.  It implements
locking to make sure that there are no race conditions when
reading/writing data.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
