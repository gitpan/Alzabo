package Alzabo::ObjectCache::Sync::SDBM_File;

use strict;

use vars qw($VERSION $DB $FILE $LOCK_FILE);

use Alzabo::ObjectCache::Sync::DBM;
use base qw( Alzabo::ObjectCache::Sync::DBM );

use Alzabo::Config;
use Alzabo::Exceptions;
use Fcntl qw( :flock O_RDONLY O_RDWR O_CREAT );
use SDBM_File;

$VERSION = 2.0;

1;

sub import
{
    my $class = shift;
    my %p = @_;

    Alzabo::Exception::Params->throw( error => "The 'sync_dbm_file' parameter is required when using the " . __PACKAGE__ . ' module' )
	unless exists $p{sync_dbm_file};

    $FILE = $p{sync_dbm_file};
    $LOCK_FILE = $p{lock_file} || Alzabo::Config::root_dir() . '/SDBM_File.lock';

    if ( ( ! -e $p{sync_dbm_file}) || $p{clear_on_startup} )
    {
	if (-e $p{sync_dbm_file})
	{
	    unlink $p{sync_dbm_file} or Alzabo::Exception::System->throw( error => "Can't delete '$p{sync_dbm_file}': $!" );
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

    my $return;

    my ($lock_mode, $open_mode) = $mode eq 'write' ? ( LOCK_EX, O_RDWR | O_CREAT ) : ( LOCK_SH, O_RDONLY | O_CREAT );

    local *FH;
    open FH, "+>$LOCK_FILE"
	or Alzabo::Exception::System->throw( error => "Unable to open $LOCK_FILE: $!" );
    flock( FH, $lock_mode );

    my $db = tie my %db, 'SDBM_File', $FILE, $open_mode, 0644
	or Alzabo::Exception::System->throw( error => "Can't tie '$FILE' ($mode mode): $!" );

    if ($mode eq 'read' || $preserve)
    {
	$return = $db->FETCH($id);
    }

    if ($mode eq 'write')
    {
	unless ($preserve && defined $return && $return > 0)
	{
	    $db->STORE( $id => $val );
	    $return = $val;
	}
    }

    flock( FH, LOCK_UN );

    return $return;
}

__END__

=head1 NAME

Alzabo::ObjectCache::SDBM_File - Uses an SDBM file to sync object caches

=head1 SYNOPSIS

  use Alzabo::ObjectCache
      ( store => 'Alzabo::ObjectCache::Store::Memory',
        sync  => 'Alzabo::ObjectCache::Sync::SDBM_File',
        sync_dbm_file => 'somefilename.db',
        clear_on_startup => 1 );

=head1 DESCRIPTION

This class implements object cache syncing between multiple processes
using an SDBM_File.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
