package Alzabo::Driver::MySQL;

use strict;
use vars qw($VERSION);

use Alzabo::Driver;

use DBI;
use DBD::mysql;
use Digest::MD5;

use base qw(Alzabo::Driver);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.19 $ =~ /(\d+)\.(\d+)/;

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
    my %p = @_;

    my $dsn = 'DBI:mysql:' . $self->{schema}->name;
    $dsn .= ";host=$p{host}" if $p{host};

    eval
    {
	# If I don't do this I get weirdness with Apache::DBI.  Help?
	if ($self->{dbh})
	{
	    eval { $self->{dbh}->disconnect; };
	    undef $self->{dbh};
	}
	$self->{dbh} = DBI->connect( $dsn,
				     $p{user},
				     $p{password},
				     { RaiseError => 1 } );
    };
    DBIException->throw( error => $@ ) if $@;
    AlzaboException->throw( error => "Unable to connect to database\n" ) unless $self->{dbh};
}

sub create_database
{
    my $self = shift;
    my %p = @_;

    my $db = $self->{schema}->name;
    my $drh = DBI->install_driver('mysql');

    $drh->func( 'createdb', $db, $p{host}, $p{user}, $p{password}, 'admin' )
	or DBIException->throw( error => $DBI::errstr );
}

sub drop_database
{
    my $self = shift;
    my %p = @_;

    my $db = $self->{schema}->name;
    my $drh = DBI->install_driver('mysql');

    $drh->func( 'dropdb', $db, $p{host}, $p{user}, $p{password}, 'admin' )
	or DBIException->throw( error => $DBI::errstr );
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


__END__

=head1 NAME

Alzabo::Driver::MySQL - MySQL specific Alzabo driver subclass

=head1 SYNOPSIS

  use Alzabo::Driver::MySQL;

=head1 DESCRIPTION

This provides some MySQL specific implementations for the virtual
methods in Alzabo::Driver.

=head1 METHODS

=over 4

=item * connect

This functions exactly as described in Alzabo::Driver.

=item * create_database

This functions exactly as described in Alzabo::Driver.

=item * get_last_id

Returns the last id created via an AUTO_INCREMENT column.

=back

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
