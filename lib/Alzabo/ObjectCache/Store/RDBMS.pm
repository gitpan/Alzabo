package Alzabo::ObjectCache::Store::RDBMS;

use strict;

use vars qw($VERSION $SCHEMA %CONNECT_PARAMS);

use Digest::MD5 ();
use Storable ();

$VERSION = 2.0;

sub import
{
    my $class = shift;
    my %p = @_;

    Alzabo::Exception::Params->throw( error => "Alzabo::ObjectCache::RDBMS requires a schema_name parameter" )
	unless exists $p{store_schema_name};

    foreach ( qw( user password host ) )
    {
	$CONNECT_PARAMS{$_} = $p{"store_$_"} if exists $p{"store_$_"};
    }
    %CONNECT_PARAMS = ( %CONNECT_PARAMS,
			exists $p{store_connect_params} ? %{ $p{store_connect_params} } : (),
		      );

    $SCHEMA = eval { Alzabo::Runtime::Schema->load_from_file( name => $p{store_schema_name} ) };
    if ($@)
    {
	if ( UNIVERSAL::isa( $@, 'Alzabo::Exception::Params' ) )
	{
	    _load_create_code();

	    Alzabo::Exception::Params->throw
                ( error =>
                  "Alzabo::ObjectCache::RDBMS requires a store_rdbms" .
                  " parameter if it is going to create a new schema" )
                    unless exists $p{store_rdbms};

	    $SCHEMA = Alzabo::Create::Schema->new( name  => $p{store_schema_name},
						   rdbms => $p{store_rdbms} );
	    $SCHEMA->save_to_file;
	}
    }

    my $store_table =
	$SCHEMA->table('AlzaboObjectCacheStore')
            if $SCHEMA->has_table('AlzaboObjectCacheStore');

    if ($store_table)
    {
	my %col;

	foreach ( qw( object_id object_data ) )
	{
	    Alzabo::Exception->throw( error => "Your schema has an AlzaboObjectCacheStore table but it does not have a $_ table" )
		unless $store_table->has_column($_);

	    $col{$_} = $store_table->column($_);
	}

	Alzabo::Exception->throw( error => "AlzaboObjectCacheStore.object_id column is not the right type (should be a char/varchar)" )
	    unless $col{object_id}->is_character;

	Alzabo::Exception->throw( error => "AlzaboObjectCacheStore.object_id column is not long enough (must be >= 22)" )
	    unless $col{object_id}->length && $col{object_id}->length >= 22;

	Alzabo::Exception->throw( error => "AlzaboObjectCacheStore.sync_time column is not the right type (should be a char/varchar)" )
	    unless $col{sync_time}->is_character;

	Alzabo::Exception->throw( error => "AlzaboObjectCacheStore.sync_time column should be nullable" )
	    unless $col{sync_time}->nullable;

	Alzabo::Exception->throw( error => "AlzaboObjectCacheStore.sync_time column is not long enough (must be >= 40)" )
	    unless $col{sync_time}->length && $col{sync_time}->length >= 40;
    }
    else
    {
	_load_create_code();

	my $create = Alzabo::Create::Schema->load_from_file( name => $p{store_schema_name} );
	my $store_table = $create->make_table( name => 'AlzaboObjectCacheStore' );

	$store_table->make_column( name   => 'object_id',
				   type   => 'varchar',
				   length => 22,
				   primary_key => 1,
				 );

	my $blob_type = $SCHEMA->rules->blob_type;

	$store_table->make_column( name   => 'object_data',
				   type   => $blob_type,
				 );

	$create->create(%CONNECT_PARAMS);

	$create->save_to_file;
    }

    $SCHEMA = Alzabo::Runtime::Schema->load_from_file( name => $p{store_schema_name} );

    if ( $SCHEMA->driver->driver_id eq 'PostgreSQL' )
    {
	require MIME::Base64;
    }
}

sub _load_create_code
{
    unless ($Alzabo::Create::VERSION)
    {
	require Alzabo::Create;
	warn "Had to load Alzabo::Create.  If this is a persistent" .
             " environment your processes will be bloated.\n"
	    if $^W;
    }
}

sub new
{
    my $class = shift;

    my $self = bless {}, $class;

    $SCHEMA->connect(%CONNECT_PARAMS);

    $self->{driver} = $SCHEMA->driver;
    $self->{table}  = $self->{driver}->quote_identifier('AlzaboObjectCacheStore');
    $self->{is_pg}  = $self->{driver}->driver_id eq 'PostgreSQL';

    return $self;
}

sub clear
{
    my $self = shift;

    $self->{driver}->do( sql => "DELETE FROM $self->{table}" );
}

sub fetch_object
{
    my $self = shift;
    my $id = Digest::MD5::md5_base64(shift);

    my $ser =
	$self->{driver}->one_row
	    ( sql  => "SELECT object_data FROM $self->{table} WHERE object_id = ?",
	      bind => $id );

    return unless $ser;

    $ser = MIME::Base64::decode_base64($ser) if $self->{is_pg};

    return Storable::thaw($ser);
}

sub store_object
{
    my $self = shift;
    my $obj = shift;

    my $id = Digest::MD5::md5_base64( $obj->id_as_string );

    my $ser = Storable::nfreeze($obj);

    $ser = MIME::Base64::encode_base64($ser) if $self->{is_pg};

    # Must just try to insert, otherwise we have race conditions
    eval
    {
	$self->{driver}->begin_work;

	# For Postgres, we don't want to try an insert that might fail
	# with a duplicate key error because that will abort any
	# current transactions
	if ( $self->{is_pg} )
	{
	    if ( $self->{driver}->one_row
		     ( sql  => "SELECT 1 FROM $self->{table} WHERE object_id = ?",
		       bind => $id ) )
	    {
		$self->{driver}->commit;
		return; # exits eval {} block
	    }
	}

	$self->{driver}->do
	    ( sql  => "INSERT INTO $self->{table} (object_id, object_data) VALUES (?, ?)",
	      bind => [ $id, $ser ] );

	$self->{driver}->commit;
    };

    return unless $@;

    # If we got an exception it may just be that the row exists.  If
    # not, we ignore the error and try again.  If the row gets deleted
    # between these two attempts we're kind of screwed.  Maybe we
    # should lock the table?  But that won't help speed.
    $self->{driver}->do
	( sql  => "UPDATE $self->{table} SET object_data = ? WHERE object_id = ?",
	  bind => [ $ser, $id ] );
}

sub delete_from_cache
{
    my $self = shift;
    my $id = Digest::MD5::md5_base64(shift);

    $self->{driver}->do
	( sql  => "DELETE FROM $self->{table} WHERE object_id = ?",
	  bind => $id );

}


1;


__END__

=head1 NAME

Alzabo::ObjectCache::Store::RDBMS - Cache objects in an RDBMS backend

=head1 SYNOPSIS

  use Alzabo::ObjectCache
      ( store => 'Alzabo::ObjectCache::Store::RDBMS',
        sync  => 'Alzabo::ObjectCache::Sync::Null',
        store_rdbms => 'MySQL',
        store_schema_name => 'something',
        store_user => 'foo' );

=head1 DESCRIPTION

This class stores serialized objects in an RDBMS backend.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
