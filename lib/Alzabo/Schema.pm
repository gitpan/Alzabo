package Alzabo::Schema;

use strict;
use vars qw($VERSION %CACHE);

use Alzabo;
use Alzabo::Config;
use Alzabo::Driver;
use Alzabo::RDBMSRules;
use Alzabo::SQLMaker;

use Storable ();
use Tie::IxHash ();

#use fields qw( name driver tables );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.28 $ =~ /(\d+)\.(\d+)/;

1;

sub _load_from_file
{
    my $class = shift;
    my %p = @_;

    my $name = $p{name};

    # Making these (particularly from files) is expensive.
    return $class->_cached_schema($p{name}) if $class->_cached_schema($p{name});

    my $schema_dir = Alzabo::Config::schema_dir;
    my $file =  "$schema_dir/$p{name}/$p{name}." . $class->_schema_file_type . '.alz';

    -e $file or Alzabo::Exception::Params->throw( error => "No saved schema named $name ($file)" );

    my $fh = do { local *FH; };
    open $fh, $file
	or Alzabo::Exception::System->throw( error => "Unable to open $file: $!" );
    my $schema = Storable::retrieve_fd($fh);
    close $fh
	or Alzabo::Exception::System->throw( error => "Unable to close $file: $!" );

    open $fh, "$schema_dir/$name/$name.rdbms"
	or Alzabo::Exception::System->throw( error => "Unable to open $schema_dir/$name/$name.driver: $!\n" );
    my $rdbms = join '', <$fh>;
    close $fh
	or Alzabo::Exception::System->throw( error => "Unable to close $schema_dir/$name/$name.driver: $!" );

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
    my $name = shift;

    my $schema_dir = Alzabo::Config::schema_dir;
    my $file =  "$schema_dir/$name/$name." . $class->_schema_file_type . '.alz';

    if (exists $CACHE{$name}{$class}{object})
    {
	my $mtime = (stat($file))[9]
	    or Alzabo::Exception::System->throw( error => "can't stat $file" );

	return $CACHE{$name}{$class}{object}
	    if $mtime <= $CACHE{$name}{$class}{mtime};
    }
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
    my Alzabo::Schema $self = shift;

    return $self->{name};
}

sub table
{
    my Alzabo::Schema $self = shift;
    my $name = shift;

    Alzabo::Exception::Params->throw( error => "Table $name doesn't exist in schema" )
	unless $self->{tables}->EXISTS($name);

    return $self->{tables}->FETCH($name);
}

sub tables
{
    my Alzabo::Schema $self = shift;

    if (@_)
    {
	return map { $self->table($_) } @_;
    }

    return $self->{tables}->Values;
}

sub driver
{
    my Alzabo::Schema $self = shift;

    return $self->{driver};
}

sub rules
{
    my Alzabo::Schema $self = shift;

    return $self->{rules};
}

sub sqlmaker
{
    my Alzabo::Schema $self = shift;

    return $self->{sql};
}

__END__

=head1 NAME

Alzabo::Schema - Schema objects

=head1 SYNOPSIS

  use Alzabo::Schema;

  my $schema = Alzabo::Schema->load_from_file('foo');

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

=head2 driver

=head3 Returns

The L<C<Alzabo::Driver>|Alzabo::Driver> subclass object for the
schema.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
