package Alzabo::ObjectCache::Store::BerkeleyDB;

use vars qw($SELF $VERSION);

use Alzabo::Exceptions;
use BerkeleyDB qw( DB_CREATE DB_INIT_MPOOL DB_INIT_CDB DB_NEXT DB_NOOVERWRITE DB_KEYEXIST DB_NOTFOUND DB_RMW DB_WRITECURSOR );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.10 $ =~ /(\d+)\.(\d+)/;

1;

sub import
{
    my $class = shift;
    my %p = @_;

    Alzabo::Exception::Params->throw( error => "The 'store_dbm_file' parameter is required when using the " . __PACKAGE__ . ' module' )
	unless exists $p{store_dbm_file};

    if ( -e $p{store_dbm_file} && $p{clear_on_startup} )
    {
	unlink $p{store_dbm_file}
	    or Alzabo::Exception::System->throw( error => "Can't delete '$p{store_dbm_file}': $!" );
    }

    $ENV = BerkeleyDB::Env->new( -Flags => DB_CREATE | DB_INIT_MPOOL | DB_INIT_CDB )
	or Alzabo::Exception->throw( error => "Can't create environment: $BerkeleyDB::Error\n" );
    $DB = BerkeleyDB::Hash->new( -Filename => $p{store_dbm_file},
				 -Mode => 0644,
				 -Env => $ENV,
				 -Flags => DB_CREATE,
			       )
	or Alzabo::Exception::System->throw( error => "Can't create '$p{store_dbm_file}': $! $BerkeleyDB::Error" );
}

sub new
{
    return $SELF if $SELF;

    my $proto = shift;
    my $class = ref $proto || $proto;
    my %p = @_;

    $SELF = bless { dbm => $DB }, $class;
    return $SELF;
}

sub clear
{
    return unless $SELF;

    my $cursor = $DB->db_cursor( DB_WRITECURSOR );

    my $status = 0;
    my ($t1, $t2) = (0, 0); # temp vars that hold the key/value pairs but are ignored
    while (1)
    {
	$status = $cursor->c_get( $t1, $t2, DB_NEXT | DB_RMW );

	last if $status == DB_NOTFOUND;

	Alzabo::Exception::System->throw( error => "Error retrieving next key from BerkeleyDB database: $BerkeleyDB::Error" )
	    unless $status == 0;

	$status = $cursor->c_del;

	Alzabo::Exception::System->throw( error => "Error deleting key from BerkeleyDB database: $BerkeleyDB::Error" )
	    unless $status == 0;
    }
}

sub fetch_object
{
    my $self = shift;
    my $id = shift;

    my $ser;
    my $status = $self->{dbm}->db_get( $id, $ser );

    return if $status == DB_NOTFOUND;

    Alzabo::Exception::System->throw( error => "Error retrieving object id '$id' from Berkeley DB: $BerkeleyDB::Error" )
	if $status;

    return Alzabo::Runtime::Row->thaw($ser);
}

sub store_object
{
    my $self = shift;
    my $obj = shift;

    my $id = $obj->id;

    my $ser = $obj->freeze;

    my $status = $self->{dbm}->db_put( $id => $ser, DB_NOOVERWRITE );

    Alzabo::Exception::System->throw( error => "Error storing object id $id in Berkeley DB: $BerkeleyDB::Error" )
	unless $status == 0 || $status == DB_KEYEXIST;
}

sub delete_from_cache
{
    my $self = shift;

    $self->{dbm}->db_del(shift);
}

__END__

=head1 NAME

Alzabo::ObjectCache::Store::BerkeleyDB - Cache objects in a BerkeleyDB file

=head1 SYNOPSIS

  use Alzabo::ObjectCache( store => 'Alzabo::ObjectCache::Store::BerkeleyDB',
                           sync  => 'Alzabo::ObjectCache::Sync::Null',
                           store_dbm_file => '/tmp/alzabo_storage.db' );

=head1 DESCRIPTION

This class simply stores cached objects in a DBM file using the
C<BerkeleyDB> module.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
