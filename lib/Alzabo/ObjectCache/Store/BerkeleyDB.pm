package Alzabo::ObjectCache::Store::BerkeleyDB;

use vars qw($SELF $VERSION);

use Alzabo::Exceptions;
use BerkeleyDB qw( DB_CREATE DB_INIT_MPOOL DB_INIT_CDB DB_NEXT DB_NOOVERWRITE DB_KEYEXIST DB_NOTFOUND );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.7 $ =~ /(\d+)\.(\d+)/;

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
    my $cursor = $DB->db_cursor;
    my ($t1, $t2);
    while ( $cursor->c_del == 0 )
    {
	$cursor->c_get( $t1, $t2, DB_NEXT );
    }
}

sub fetch_object
{
    my $self = shift;
    my $id = shift;

    my $ser;
    my $status = $self->{dbm}->db_get( $id, $ser );

    return if $status == DB_NOTFOUND;

    Alzabo::Exception::System->throw( error => "Error retrieving object id '$id' from Berkeley DB: $BerkeleyDB::Error ($status)" )
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
    my $id = shift->id;

    $self->{dbm}->db_del($id);
}

__END__

=head1 NAME

Alzabo::ObjectCache::Store::BerkeleyDB - Cache objects in memory

=head1 SYNOPSIS

  use Alzabo::ObjectCache( store => 'Alzabo::ObjectCache::Store::BerkeleyDB',
                           sync  => 'Alzabo::ObjectCache::Sync::Null',
                           store_dbm_file => '/tmp/alzabo_storage.db' );

=head1 DESCRIPTION

This class simply stores cached objects in a DBM file using the
C<BerkeleyDB> module.

=head1 IMPORT PARAMETERS

=over 4

=item * store_dbm_file => $filename

This parameter is required.  It is the name of the file which will be
used to store the cached row objects.  If the file does not exist, it
will be created.  If it does exist it will not be overwritten.

=item * clear_on_startup => $boolean

If this is true, then a new file is B<always> created on when the
module is loaded, overwriting any existing file.  This is generally
desirable as an existing file may contain spurious entries from
previous executions of the program.  However, in the interests of
safety, this parameter defaults to false.

=back

=head1 METHODS

Note that pretty much all the methods that take an object as an
argument will silently do nothing if the object is not already in the
cache.  The obvious exception is the
L<C<store_object>|Alzabo::ObjectCache::Store::BerkeleyDB/store_object
($object)> method.

=head2 new

=head3 Returns

A new C<Alzabo::ObjectCache::Store::BerkeleyDB> object.

=head2 fetch_object ($id)

=head3 Returns

The specified object if it is in the cache.  Otherwise it returns
undef.

=head2 store_object ($object)

Stores an object in the cache.  This will not overwrite an existing
object in the cache.  To do that you must first call the
L<C<delete_from_cache>|Alzabo::ObjectCache::Store::BerkeleyDB/delete_from_cache
($object)> method.

=head2 delete_from_cache ($object)

This method allows you to remove an object from the cache.  This does
not register the object as deleted.  It is provided solely so that you
can call L<C<store_object>|Alzabo::ObjectCache/store_object ($object)>
after calling this method and have
L<C<store_object>|Alzabo::ObjectCache/store_object ($object)> actually
store the new object.

=head1 CLASS METHOD

=head2 clear

Call this method to completely clear the cache.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
