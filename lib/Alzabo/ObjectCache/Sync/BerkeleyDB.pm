package Alzabo::ObjectCache::Sync::BerkeleyDB;

use strict;

use vars qw($SELF $VERSION $DB $ENV);

use base qw( Alzabo::ObjectCache::Sync::DBM );

use Alzabo::Exceptions;
use BerkeleyDB qw( DB_CREATE DB_INIT_MPOOL DB_INIT_LOCK DB_INIT_CDB DB_INIT_TXN );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.1 $ =~ /(\d+)\.(\d+)/;

1;

sub import
{
    my $class = shift;
    my %p = @_;

    Alzabo::Exception::Params->throw( error => "The 'dbm_file' parameter is required when using the " . __PACKAGE__ . ' module' )
	unless exists $p{dbm_file};

    if ( ( ! -e $p{dbm_file}) || $p{clear_on_startup} )
    {
	if (-e $p{dbm_file})
	{
	    unlink $p{dbm_file} or Alzabo::Exception::System->throw( error => "Can't delete '$p{dbm_file}': $!" );
	}

    }

    $ENV = BerkeleyDB::Env->new( -Flags => DB_CREATE | DB_INIT_MPOOL | DB_INIT_CDB )
	or Alzabo::Exception->throw( error => "Can't create environment: $BerkeleyDB::Error\n" );
    $DB = BerkeleyDB::Hash->new( -Filename => $p{dbm_file},
				 -Mode => 0644,
				 -Env => $ENV,
				 -Flags => DB_CREATE,
			       )
	or Alzabo::Exception::System->throw( error => "Can't create '$p{dbm_file}': $! $BerkeleyDB::Error" );
}

sub dbm
{
    my $self = shift;
    my $mode = shift;
    my $id = shift;
    my $val = shift;
    my $preserve = shift;

    my $return;
    if ($mode eq 'read' || $preserve)
    {
	$DB->db_get($id, $return);
    }

    if ($mode eq 'write')
    {
	unless ($preserve && defined $return && $return > 0)
	{
	    $DB->db_put( $id => $val );
	    $return = $val;
	}
    }

    return $return;
}

__END__

=head1 NAME

Alzabo::ObjectCache::Sync::BerkeleyDB - Uses a DBM file to sync object caches

=head1 SYNOPSIS

  use Alzabo::ObjectCache( store => 'Alzabo::ObjectCache::Store::Memory',
                           sync  => 'Alzabo::ObjectCache::Sync::BerkeleyDB',
                           dbm_file => 'somefilename.db',
                           clear_on_startup => 1 );

=head1 DESCRIPTION

This class implements object cache syncing between multiple processes
using a Berkeley DB file to handle data storage.  It implements
locking to make sure that there are no race conditions with
reading/writing data.

The difference between this module and the
C<Alzabo::ObjectCache::Sync::DB_File> module is that module uses the
BerkeleyDB Perl module, which can take advantage of the new features
available in versions 2 and 3 of the Berkeley DB library.  These
features allow this module to avoid having to constantly open and
close the DBM file.  In addition, locking is handled by the Berkeley
DB library at a much lower level than would be possible from this
module.

=head1 IMPORT PARAMETERS

=over 4

=item * dbm_file => $filename

This parameter is required.  It is the name of the file which will be
used to store the syncing data.  If the file does not exist, it will
be created.  If it does exist it will not be overwritten.

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
