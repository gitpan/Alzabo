package Alzabo::ObjectCache::DBMSync;

use strict;

use vars qw($SELF $VERSION $FILE);

use base qw( Alzabo::ObjectCache::Sync );

use Alzabo::Exceptions;
use DB_File;
use Fcntl qw( :flock O_RDONLY O_RDWR O_CREAT );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.4 $ =~ /(\d+)\.(\d+)/;

1;

sub import
{
    my $class = shift;
    my %p = @_;

    Alzabo::Exception::Params->throw( error => "The 'dbm_file' parameter is required when using the " . __PACKAGE__ . ' module' )
	unless exists $p{dbm_file};

    $FILE = $p{dbm_file};

    if ( ( ! -e $FILE) || $p{clear_on_startup} )
    {
	if (-e $FILE)
	{
	    unlink $FILE or Alzabo::Exception::System->throw( error => "Can't delete '$FILE': $!" );
	}

	my %db;
	my $db = tie %db, 'DB_File', $FILE, O_RDWR | O_CREAT, 0644
	    or Alzabo::Exception::System->throw( error => "Can't create '$FILE': $!" );
	if ( $p{clear_on_startup} )
	{
	    %db = ();
	    $db->sync;
	}
    }
}

sub _init
{
    my $self = shift;
    $self->{dbm_file} = $FILE;
}

sub update
{
    my $self = shift;
    my $id = shift;
    my $time = shift;
    my $overwrite = shift;

    $self->_dbm( write => $id, $time, ! $overwrite );
}

sub sync_time
{
    my $self = shift;
    my $id = shift;

    return $self->_dbm( read => $id );
}

sub clear
{
    return unless $SELF;
    %{ $SELF->{times} } = ();
}

sub _dbm
{
    my $self = shift;
    my $mode = shift;
    my $id = shift;
    my $val = shift;
    my $preserve = shift;

    # The DB should already exist (see import method) so O_CREAT
    # should never be needed.  If the DB file disappears from under us
    # I think its better to fail than to simply ignore that.
    my ($lock_mode, $open_mode) = $mode eq 'write' ? ( LOCK_EX, O_RDWR ) : ( LOCK_SH, O_RDONLY );

    my %orig_db;
    # This code largely ripped off from Tie::DB_FileLock
    my $db = tie %orig_db, 'DB_File', $self->{dbm_file}, $open_mode, 0644
	or Alzabo::Exception::System->throw( error => "Can't tie '$self->{dbm_file}' ($mode mode): $!" );

    $db->sync;

    my $fh = do { local *FH; *FH; };
    open $fh, '<&=' . $db->fd
	or Alzabo::Exception::System->throw( error =>
					     "Can't dup file descriptor for '$self->{dbm_file}': $!" );

    flock( $fh, $lock_mode )
	or Alzabo::Exception::System->throw( error =>
					     "Unable to place a $mode lock on '$self->{dbm_file}': $!" );

    my %db;
    $db = tie %db, 'DB_File', $self->{dbm_file}, $open_mode, 0644
	or Alzabo::Exception::System->throw( error => "Can't tie '$self->{dbm_file}' ($mode mode): $!" );

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
	or Alzabo::Exception::System->throw( error => "Unable to unlock '$self->{dbm_file}': $!" );

    # This is crucial for some reason I can't figure out!
    close $fh;

    return $return;
}

__END__

=head1 NAME

Alzabo::ObjectCache::DBMSync - Uses a DBM file to sync object caches

=head1 SYNOPSIS

  use Alzabo::ObjectCache( store => 'Alzabo::ObjectCache::MemoryStore',
                           sync  => 'Alzabo::ObjectCache::DBMSync',
                           dbm_file => 'somefilename.db',
                           clear_on_startup => 1 );

=head1 DESCRIPTION

This class implements object cache syncing between multiple processes
using a Berkeley DB file to handle data storage.  It implements
locking to make sure that there are no race conditions with
reading/writing data.

=head1 IMPORT PARAMETERS

=over 4

=item * dbm_file => $filename

This parameter is required.  It is the parameter of the file which
will be used to store the syncing data.  If the file does not exist,
it will be created.  If it does exist it will not be overwritten.

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
