package Alzabo::ObjectCache::Sync::RDBMS;

use strict;

use vars qw($VERSION $SCHEMA %CONNECT_PARAMS);

use Alzabo::ObjectCache::Sync;
use base qw(Alzabo::ObjectCache::Sync);

use Digest::MD5 ();

$VERSION = 2.0;

sub import
{
    my $class = shift;
    my %p = @_;

    Alzabo::Exception::Params->throw( error => "Alzabo::ObjectCache::Sync::RDBMS requires a sync_schema_name parameter" )
	unless exists $p{sync_schema_name};

    foreach ( qw( user password host ) )
    {
	$CONNECT_PARAMS{$_} = $p{"sync_$_"} if exists $p{"sync_$_"};
    }
    %CONNECT_PARAMS = ( %CONNECT_PARAMS,
			exists $p{sync_connect_params} ? %{ $p{sync_connect_params} } : (),
		      );

    $SCHEMA = eval { Alzabo::Runtime::Schema->load_from_file( name => $p{sync_schema_name} ) };
    if ($@)
    {
	if ( UNIVERSAL::isa( $@, 'Alzabo::Exception::Params' ) )
	{
	    _load_create_code();

	    Alzabo::Exception::Params->throw( error => "Alzabo::ObjectCache::RDBMS requires a sync_rdbms parameter if it is going to create a new schema" )
		unless exists $p{sync_rdbms};

	    $SCHEMA = Alzabo::Create::Schema->new( name  => $p{sync_schema_name},
						   rdbms => $p{sync_rdbms} );
	    $SCHEMA->save_to_file;
	}
    }

    my $sync_table =
	$SCHEMA->table('AlzaboObjectCacheSync') if $SCHEMA->has_table('AlzaboObjectCacheSync');

    if ($sync_table)
    {
	my %col;

	foreach ( qw( object_id sync_time ) )
	{
	    Alzabo::Exception->throw( error => "Your schema has an AlzaboObjectCacheSync table but it does not have a $_ table" )
		unless $sync_table->has_column($_);

	    $col{$_} = $sync_table->column($_);
	}

	Alzabo::Exception->throw( error => "AlzaboObjectCacheSync.object_id column is not the right type (should be a char/varchar)" )
	    unless $col{object_id}->is_character;

	Alzabo::Exception->throw( error => "AlzaboObjectCacheSync.object_id column is not long enough (must be >= 22)" )
	    unless $col{object_id}->length && $col{object_id}->length >= 22;

	Alzabo::Exception->throw( error => "AlzaboObjectCacheSync.sync_time column is not the right type (should be a char/varchar)" )
	    unless $col{sync_time}->is_character;

	Alzabo::Exception->throw( error => "AlzaboObjectCacheSync.sync_time column should be nullable" )
	    unless $col{sync_time}->nullable;

	Alzabo::Exception->throw( error => "AlzaboObjectCacheSync.sync_time column is not long enough (must be >= 40)" )
	     unless $col{sync_time}->length && $col{sync_time}->length >= 40;
    }
    else
    {
	_load_create_code();

	my $create = Alzabo::Create::Schema->load_from_file( name => $p{sync_schema_name} );
	my $sync_table = $create->make_table( name => 'AlzaboObjectCacheSync' );

	$sync_table->make_column( name   => 'object_id',
				  type   => 'varchar',
				  length => 22,
				  primary_key => 1,
				);

	$sync_table->make_column( name   => 'sync_time',
				  type   => 'varchar',
				  length => 40,
                                  nullable => 1,
				);

	$create->create(%CONNECT_PARAMS);

	$create->save_to_file;
    }

    $SCHEMA = Alzabo::Runtime::Schema->load_from_file( name => $p{sync_schema_name} );
}

sub _load_create_code
{
    unless ($Alzabo::Create::VERSION)
    {
	require Alzabo::Create;
	warn "Had to load Alzabo::Create.  If this is a persistent environment your processes will be bloated.\n"
	    if $^W;
    }
}

sub _init
{
    my $self = shift;

    $SCHEMA->connect(%CONNECT_PARAMS);

    $self->{driver} = $SCHEMA->driver;
    $self->{table}  = $self->{driver}->quote_identifier('AlzaboObjectCacheSync');
    $self->{is_pg}  = $SCHEMA->driver->driver_id eq 'PostgreSQL';
}

sub sync_time
{
    my $self = shift;
    my $id = Digest::MD5::md5_base64(shift);

    return $self->{driver}->one_row
	( sql  => "SELECT sync_time FROM $self->{table} WHERE object_id = ?",
	  bind => $id );
}

sub update
{
    my $self = shift;
    my $id = Digest::MD5::md5_base64(shift);
    my $time = shift;
    my $overwrite = shift;

    # Try to update first.  If that fails we can expect that the row
    # is not present and insert.  If the insert fails then some other
    # process may have inserted the new row between these two points.
    if ($overwrite)
    {
	eval
	{
	    $self->{driver}->do
		( sql  => "UPDATE $self->{table} SET sync_time = ? WHERE object_id = ?",
		  bind => [ $time, $id ] );
	};

	# might as well leave if it works
	return unless $@;
    }

    # If something else inserted before us that is OK because we want
    # the latest sync time to be in there anyway.
    eval
    {
	$self->{driver}->begin_work;

	# For Postgres, we don't want to try an insert that might fail
	# because there's a duplicate key because that will abort any
	# current transactions
	if ( $self->{is_pg} )
	{
	    if ( $self->{driver}->one_row
		     ( sql  => "SELECT 1 FROM $self->{table} WHERE object_id = ?",
		       bind => $id ) )
	    {
		$self->{driver}->commit;
		return;
	    }
	}

	$self->{driver}->do
	    ( sql  => "INSERT INTO $self->{table} (object_id, sync_time) VALUES (?, ?)",
	      bind => [ $id, $time ] );

	$self->{driver}->commit;
    };

    $self->{driver}->rollback if $@;
}


1;


__END__

=head1 NAME

Alzabo::ObjectCache::Sync::RDBMS - Uses an RDBM backend to sync object caches

=head1 SYNOPSIS

  use Alzabo::ObjectCache
      ( store => 'Alzabo::ObjectCache::Store::Memory',
        sync  => 'Alzabo::ObjectCache::Sync::RDBMS',
        sync_rdbms => 'MySQL',
        sync_schema_name => 'something',
        sync_user => 'foo' );

=head1 DESCRIPTION

This class implements object cache syncing in an RDBMS.  This module
is quite useful is you want to sync across multiple machines.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
