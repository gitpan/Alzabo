package Alzabo::Driver::MySQL;

use strict;
use vars qw($VERSION);

use Alzabo::Driver;

use DBI;
use DBD::mysql;

use base qw(Alzabo::Driver);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.26 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    my $self = bless {}, $class;
    $self->{prepare_method} = 'prepare_cached';

    return $self;
}

sub connect
{
    my $self = shift;

    return if $self->{dbh} && $self->{dbh}->ping;

    $self->{dbh} = $self->_make_dbh(@_);
}

sub create_database
{
    my $self = shift;
    my %p = @_;

    my $db = $self->{schema}->name;
    my $drh = DBI->install_driver('mysql');

    my $host;
    if ($p{host})
    {
	$host = $p{host};
	$host .= ":$p{port}" if $p{port};
    }

    $drh->func( 'createdb', $db, $host, $p{user}, $p{password}, 'admin' )
	or Alzabo::Exception::Driver->throw( error => $DBI::errstr );
}

sub drop_database
{
    my $self = shift;
    my %p = @_;

    my $db = $self->{schema}->name;
    my $drh = DBI->install_driver('mysql');

    my $host;
    if ($p{host})
    {
	$host = $p{host};
	$host .= ":$p{port}" if $p{port};
    }

    $drh->func( 'dropdb', $db, $host, $p{user}, $p{password}, 'admin' )
	or Alzabo::Exception::Driver->throw( error => $DBI::errstr );
}

sub _make_dbh
{
    my $self = shift;
    my %p = @_;

    my $dsn = 'DBI:mysql:' . $self->{schema}->name;
    $dsn .= ";host=$p{host}" if $p{host};
    $dsn .= ";post=$p{port}" if $p{port};

    my $dbh;
    eval
    {
	$dbh = DBI->connect( $dsn,
			     $p{user},
			     $p{password},
			     { RaiseError => 1 } );
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

sub get_last_id
{
     my $self = shift;

     return $self->{dbh}->{mysql_insertid};
}

sub start_transaction
{
    return;
}

# someday this might do something, wouldn't that be cool?
sub rollback
{
    return;
}

sub finish_transaction
{
    return;
}

sub driver_id
{
    return 'MySQL';
}

__END__

=head1 NAME

Alzabo::Driver::MySQL - MySQL specific Alzabo driver subclass

=head1 SYNOPSIS

  use Alzabo::Driver::MySQL;

=head1 DESCRIPTION

This provides some MySQL specific implementations for the virtual
methods in Alzabo::Driver.

=head1 METHODS

=head2 connect

This functions exactly as described in Alzabo::Driver.

=head2 create_database

This functions exactly as described in Alzabo::Driver.

=head2 get_last_id

Returns the last id created via an AUTO_INCREMENT column.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
