package Alzabo::ObjectCache::Sync::SDBM_File;

use strict;

use vars qw($SELF $VERSION $DB $FILE $LOCK_FILE);

use base qw( Alzabo::ObjectCache::Sync::DBM );

use Alzabo::Config;
use Alzabo::Exceptions;
use Fcntl qw( :flock O_RDONLY O_RDWR O_CREAT );
use SDBM_File;

$VERSION = sprintf '%2d.%02d', q$Revision: 1.3 $ =~ /(\d+)\.(\d+)/;

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

  use Alzabo::ObjectCache( store => 'Alzabo::ObjectCache::Store::Memory',
                           sync  => 'Alzabo::ObjectCache::Sync::SDBM_File',
                           sync_dbm_file => 'somefilename.db',
                           clear_on_startup => 1 );

=head1 DESCRIPTION

This class implements object cache syncing between multiple processes
using an SDBM_File.

=head1 IMPORT PARAMETERS

=over 4

=item * sync_dbm_file => $filename

This parameter is required.  It is the name of the file which will be
used to store the syncing data.  If the file does not exist, it will
be created.  If it does exist it will not be overwritten.

=item * lock_file => $filename

This parameter is optional.  It defaults to a file named
"SDBM_File.lock" in your Alzabo installation's top level directory.

=item * clear_on_startup => $boolean

If this is true, then a new file is B<always> created on when the
module is loaded, overwriting any existing file.  This is generally
desirable as an existing file may contain spurious entries from
previous executions of the program.  However, in the interests of
safety, this parameter defaults to false.

=back

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
