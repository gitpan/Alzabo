package Alzabo::Schema;

use strict;
use vars qw($VERSION %CACHE);

use Alzabo;
use Alzabo::Config;
use Alzabo::Driver;
use Alzabo::RDBMSRules;
use Alzabo::SQLMaker;

use File::Spec;

use Params::Validate qw( :all );
Params::Validate::validation_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

use Storable ();
use Tie::IxHash ();

$VERSION = sprintf '%2d.%02d', q$Revision: 1.46 $ =~ /(\d+)\.(\d+)/;

1;

sub _load_from_file
{
    my $class = shift;

    my %p = validate( @_, { name => { type => SCALAR },
			  } );

    # Making these (particularly from files) is expensive.
    return $class->_cached_schema($p{name}) if $class->_cached_schema($p{name});

    my $schema_dir = Alzabo::Config::schema_dir;
    my $file =  $class->_schema_filename( $p{name} );

    -e $file or Alzabo::Exception::Params->throw( error => "No saved schema named $p{name} ($file)" );

    my $version_file = File::Spec->catfile( $schema_dir, $p{name}, "$p{name}.version" );

    my $version = 0;

    my $fh = do { local *FH; };
    if ( -e $version_file )
    {
	open $fh, "<$version_file"
	    or Alzabo::Exception::System->throw( error => "Unable to open $version_file: $!\n" );
	$version = join '', <$fh>;
	close $fh
	    or Alzabo::Exception::System->throw( error => "Unable to close $version_file: $!" );
    }

    if ( $version < $Alzabo::VERSION )
    {
	require Alzabo::BackCompat;

	Alzabo::BackCompat::update_schema( name => $p{name},
					   version => $version );
    }

    open $fh, "<$file"
	or Alzabo::Exception::System->throw( error => "Unable to open $file: $!" );
    my $schema = Storable::retrieve_fd($fh)
	or Alzabo::Exception::System->throw( error => "Can't retrieve from filehandle" );
    close $fh
	or Alzabo::Exception::System->throw( error => "Unable to close $file: $!" );

    my $rdbms_file = File::Spec->catfile( $schema_dir, $p{name}, "$p{name}.rdbms" );
    open $fh, "<$rdbms_file"
	or Alzabo::Exception::System->throw( error => "Unable to open $rdbms_file: $!\n" );
    my $rdbms = join '', <$fh>;
    close $fh
	or Alzabo::Exception::System->throw( error => "Unable to close $rdbms_file: $!" );

    $rdbms =~ s/\s//g;

    ($rdbms) = $rdbms =~ /(\w+)/;

    $schema->{driver} = Alzabo::Driver->new( rdbms => $rdbms,
					     schema => $schema );

    $schema->{rules} = Alzabo::RDBMSRules->new( rdbms => $rdbms );

    $schema->{sql} = Alzabo::SQLMaker->load( rdbms => $rdbms );

    $schema->_save_to_cache;

    return $schema;
}

sub _cached_schema
{
    my $class = shift->isa('Alzabo::Runtime::Schema') ? 'Alzabo::Runtime::Schema' : 'Alzabo::Create::Schema';

    validate_pos( @_, { type => SCALAR } );
    my $name = shift;

    my $schema_dir = Alzabo::Config::schema_dir;
    my $file = $class->_schema_filename($name);

    if (exists $CACHE{$name}{$class}{object})
    {
	my $mtime = (stat($file))[9]
	    or Alzabo::Exception::System->throw( error => "can't stat $file: $!" );

	return $CACHE{$name}{$class}{object}
	    if $mtime <= $CACHE{$name}{$class}{mtime};
    }
}

sub _schema_filename
{
    my $class = shift;

    return $class->_base_filename(shift) . '.' . $class->_schema_file_type . '.alz';
}

sub _base_filename
{
    shift;
    my $name = shift;

    return File::Spec->catfile( Alzabo::Config::schema_dir(), $name, $name );
}

sub _save_to_cache
{
    my $self = shift;
    my $class = $self->isa('Alzabo::Runtime::Schema') ? 'Alzabo::Runtime::Schema' : 'Alzabo::Create::Schema';
    my $name = $self->name;

    $CACHE{$name}{$class} = { object => $self,
			      mtime => time };
}

sub name
{
    my $self = shift;

    return $self->{name};
}

sub has_table
{
    my $self = shift;

    validate_pos( @_, { type => SCALAR } );

    return $self->{tables}->FETCH(shift);
}

sub table
{
    my $self = shift;

    validate_pos( @_, { type => SCALAR } );
    my $name = shift;

    Alzabo::Exception::Params->throw( error => "Table $name doesn't exist in schema" )
	unless $self->{tables}->EXISTS($name);

    return $self->has_table($name);
}

sub tables
{
    my $self = shift;

    validate_pos( @_, ( { type => SCALAR } ) x @_ ) if @_;

    if (@_)
    {
	return map { $self->table($_) } @_;
    }

    return $self->{tables}->Values;
}

sub begin_work
{
    shift->driver->begin_work;
}
*start_transaction = \&begin_work;

sub rollback
{
    shift->driver->rollback;
    Alzabo::ObjectCache->new->clear if $Alzabo::Object::VERSION;
}

sub commit
{
    shift->driver->commit;
}
*finish_transaction = \&commit;

sub run_in_transaction
{
    my $self = shift;
    my $code = shift;

    $self->begin_work;

    my @r;
    if (wantarray)
    {
	@r = eval { $code->() };
    }
    else
    {
	$r[0] = eval { $code->() };
    }

    if (my $e = $@)
    {
	eval { $self->rollback };
	if ( UNIVERSAL::can( $e, 'rethrow' ) )
	{
	    $e->rethrow;
	}
	else
	{
	    Alzabo::Exception->throw( error => $e );
	}
    }

    $self->commit;

    return wantarray ? @r : $r[0];
}

sub driver
{
    my $self = shift;

    return $self->{driver};
}

sub rules
{
    my $self = shift;

    return $self->{rules};
}

sub sqlmaker
{
    my $self = shift;

    return $self->{sql}->new( $self->driver );
}

__END__

=head1 NAME

Alzabo::Schema - Schema objects

=head1 SYNOPSIS

  use Alzabo::Schema;

  my $schema = Alzabo::Schema->load_from_file( name => 'foo' );

  foreach my $t ($schema->tables)
  {
     print $t->name;
  }

=head1 DESCRIPTION

Objects in this class represent the entire schema, containing table
objects, which in turn contain foreign key objects and column objects,
which in turn contain column definition objects.

=head1 METHODS

=head2 name

=head3 Returns

A string containing the name of the schema.

=head2 table ($name)

=head3 Returns

An L<C<Alzabo::Table>|Alzabo::Table> object representing the specified
table.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=head2 tables (@optional_list)

=head3 Returns

A list of L<C<Alzabo::Table>|Alzabo::Table> object named in the list
given.  If no list is provided, then it returns all table objects in
the schema.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=head2 has_table ($name)

=head3 Returns

A true or false value depending on whether or not the table exists in
the schema.

=head2 begin_work

Starts a transaction.  Calls to this function may be nested and it
will be handled properly.

=head2 rollback

Rollback a transaction.

=head2 commit

Finishes a transaction with a commit.  If you make multiple calls to
C<begin_work>, make sure to call this method the same number of times.

=head2 run_in_transaction ( sub { code... } )

This method takes a subroutine reference and wraps it in a transaction.

It will preserve the context of the caller and returns whatever the
wrapped code would have returned.

=head2 driver

=head3 Returns

The L<C<Alzabo::Driver>|Alzabo::Driver> subclass object for the
schema.

=head2 rules

=head3 Returns

The L<C<Alzabo::RDBMSRules>|Alzabo::RDBMSRules> subclass object for
the schema.

=head2 sqlmaker

=head3 Returns

The L<C<Alzabo::SQLMaker>|Alzabo::SQLMaker> subclass object for the
schema.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
