package Alzabo::Driver::MySQL;

use strict;
use vars qw($VERSION);

use Alzabo::Driver;

use DBD::mysql;
use DBI;

use Params::Validate qw( :all );
Params::Validate::validation_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.39 $ =~ /(\d+)\.(\d+)/;

use base qw(Alzabo::Driver);

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    my $self = bless {}, $class;

    return $self;
}

sub connect
{
    my $self = shift;
    my %p = @_;

    return if $self->{dbh} && $self->{dbh}->ping;

    $self->disconnect if $self->{dbh};
    $self->{dbh} = $self->_make_dbh(%p, name => $self->{schema}->name);
}

sub supports_referential_integrity
{
    my $self = shift;

    $self->_check_dbh;

    my $version = $self->{dbh}{mysql_serverinfo};

    $version =~ s/\D//;

    my ($maj, $min, $p) = split /\./, $version;

    if ( $maj == 3 )
    {
	return 0 if $min < 23;

	# 3.23.50 && 4.0.2 are the first versions where InnoDB
	# actually honored CASCADE, SET NULL, and SET DEFAULT
	return 0 if $p < 50;
    }

    # same deal
    return 0 if $maj == 4 && $min == 0 && $p < 2;

    foreach my $row ( $self->rows_hashref( sql => 'SHOW TABLE STATUS' ) )
    {
	return 0 if $row->{TYPE} !~ /innodb/i;
    }
}

sub schemas
{
    my $self = shift;

    return ( map { /dbi:\w+:(\w+)/i; defined $1 ? $1 : () }
	     DBI->data_sources( $self->dbi_driver_name ) );
}

sub create_database
{
    my $self = shift;

    my %p = @_;

    my $db = $self->{schema}->name;

    my $dbh = $self->_make_dbh( name => '',
				%p );

    eval { $dbh->func( 'createdb', $db, 'admin' ) };
    Alzabo::Exception::Driver->throw( error => $@ ) if $@;

    $dbh->disconnect;
}

sub drop_database
{
    my $self = shift;
    my %p = @_;

    my $db = $self->{schema}->name;

    my $dbh = $self->_make_dbh( name => '',
				%p );

    eval { $dbh->func( 'dropdb', $db, 'admin' ) };
    Alzabo::Exception::Driver->throw( error => $@ ) if $@;

    $dbh->disconnect;
}

sub _make_dbh
{
    my $self = shift;

    my %p = @_;

    %p = validate( @_, { name => { type => SCALAR },
			 user => { type => SCALAR | UNDEF,
				   optional => 1 },
			 password => { type => SCALAR | UNDEF,
				       optional => 1 },
			 host => { type => SCALAR | UNDEF,
				   optional => 1 },
			 port => { type => SCALAR | UNDEF,
				   optional => 1 },
			 map { $_ => 0 } grep { /^mysql_/ } keys %p,
		       } );

    my $dsn = "DBI:mysql:$p{name}";
    $dsn .= ";host=$p{host}" if $p{host};
    $dsn .= ";port=$p{port}" if $p{port};

    foreach my $k (keys %p)
    {
	$dsn .= ";$k=$p{$k}" if $k =~ /^mysql/i;
    }

    my $dbh;
    eval
    {
	$dbh = DBI->connect( $dsn,
			     $p{user},
			     $p{password},
			     { RaiseError => 1,
			       AutoCommit => 1,
			       PrintError => 0,
			     }
			   );
    };

    Alzabo::Exception::Driver->throw( error => $@ ) if $@;
    Alzabo::Exception::Driver->throw( error => "Unable to connect to database\n" ) unless $dbh;

    return $dbh;
}

sub next_sequence_number
{
    # This will cause an auto_increment column to go up (because we're
    # inserting a NULL into it).
    return undef;
}

sub rollback
{
    my $self = shift;

    eval { $self->SUPER::rollback };

    if ($@)
    {
	unless ( $@->error =~ /Some non-transactional changed tables/ )
	{
	    if ( UNIVERSAL::can( $@, 'rethrow' ) )
	    {
		$@->rethrow;
	    }
	    else
	    {
		Alzabo::Exception->throw( error => $@ );
	    }
	}
    }
}

sub get_last_id
{
     my $self = shift;

     return $self->{dbh}->{mysql_insertid};
}

sub driver_id
{
    return 'MySQL';
}

sub dbi_driver_name
{
    return 'mysql';
}

1;

__END__

=head1 NAME

Alzabo::Driver::MySQL - MySQL specific Alzabo driver subclass

=head1 SYNOPSIS

  use Alzabo::Driver::MySQL;

=head1 DESCRIPTION

This provides some MySQL specific implementations for the virtual
methods in Alzabo::Driver.

=head1 METHODS

=head2 connect, create_database, drop_database

Besides the parameters listed in L<the Alzabo::Driver
docs|Alzabo::Driver/Parameters for the connect, create_database, and
drop_database>, these methods will also include any parameter starting
with C<mysql_> in the DSN used to connect to the database.  This
allows you to pass parameters such as C<mysql_default_file>.  See the
L<DBD::mysql docs|DBD::mysql> for more details.

=head2 get_last_id

Returns the last id created via an AUTO_INCREMENT column.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
