package Alzabo::ObjectCache::Sync::BerkeleyDB;

use strict;

use vars qw($VERSION $DB $ENV);

use base qw( Alzabo::ObjectCache::Sync::DBM );

use Alzabo::Exceptions;
use BerkeleyDB qw( DB_CREATE DB_INIT_MPOOL DB_INIT_CDB DB_NOTFOUND DB_NOOVERWRITE DB_KEYEXIST );

use File::Basename ();

$VERSION = sprintf '%2d.%02d', q$Revision: 1.6 $ =~ /(\d+)\.(\d+)/;

1;

sub import
{
    my $class = shift;
    my %p = @_;

    Alzabo::Exception::Params->throw( error => "The 'sync_dbm_file' parameter is required when using the " . __PACKAGE__ . ' module' )
	unless exists $p{sync_dbm_file};

    if ( -e $p{sync_dbm_file} && $p{clear_on_startup} )
    {
	unlink $p{sync_dbm_file}
	    or Alzabo::Exception::System->throw( error => "Can't delete '$p{sync_dbm_file}': $!" );
    }

    my ($filename, $dir, $suffix) = File::Basename::fileparse( $p{sync_dbm_file} );
    $ENV = BerkeleyDB::Env->new( -Flags => DB_CREATE | DB_INIT_MPOOL | DB_INIT_CDB,
				 -Home => $dir,
			       )
	or Alzabo::Exception->throw( error => "Can't create environment: $BerkeleyDB::Error\n" );

    $DB = BerkeleyDB::Hash->new( -Filename => $filename . $suffix,
				 -Mode => 0644,
				 -Env => $ENV,
				 -Flags => DB_CREATE,
			       )
	or Alzabo::Exception::System->throw( error => "Can't create '$p{sync_dbm_file}': $! $BerkeleyDB::Error" );
}

sub dbm
{
    my $self = shift;
    my $mode = shift;
    my $id = shift;
    my $val = shift;
    my $preserve = shift;

    my $return;
    if ($mode eq 'read')
    {
	my $status = $DB->db_get($id, $return);
	Alzabo::Exception::System->throw( error => "Error retrieving sync time for id $id from Berkeley DB: $BerkeleyDB::Error" )
	    unless $status == 0 || $status == DB_NOTFOUND;
    }

    if ($mode eq 'write')
    {
	my $status = $DB->db_put( $id => $val, $preserve ? DB_NOOVERWRITE : () );

	if ( $status != 0 )
	{
	    unless ( $preserve && $status == DB_KEYEXIST )
	    {
		Alzabo::Exception::System->throw( error => "Error storing object id $id from Berkeley DB: $BerkeleyDB::Error" );
	    }
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
                           sync_dbm_file => 'somefilename.db',
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
DB library at a much lower level than would be possible with a
different DBM implementation.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
