package Alzabo::Driver::PostgreSQL;

use strict;
use vars qw($VERSION);

use DBI;
use DBD::Pg;

use base qw(Alzabo::Driver);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.8 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    return bless {}, $class;
}

sub connect
{
    my $self = shift;
    my %p = @_;

    $self->{tran_count} = undef;

    return if $self->{dbh} && $self->{dbh}->ping;

    $self->disconnect if $self->{dbh};
    $self->{dbh} = $self->_make_dbh( %p, name => $self->{schema}->name );
}

sub create_database
{
    my $self = shift;

    my $dbh = $self->_make_dbh( @_, name => 'template1' );

    eval { $dbh->do( "CREATE DATABASE " . $self->{schema}->name ); };
    my $e = $@;
    eval { $dbh->disconnect; };
    Alzabo::Exception::Driver->throw( error => $e ) if $e;
}

sub drop_database
{
    my $self = shift;

    $self->{dbh}->disconnect if $self->{dbh};

    my $dbh = $self->_make_dbh( @_, name => 'template1' );

    eval { $dbh->do( "DROP DATABASE " . $self->{schema}->name ); };
    my $e = $@;
    eval { $dbh->disconnect; };
    Alzabo::Exception::Driver->throw( error => $e ) if $e;
}

sub _make_dbh
{
    my $self = shift;
    my %p = @_;

    my $dsn = "DBI:Pg:dbname=$p{name}";
    foreach ( qw( host port options tty ) )
    {
	$dsn .= ";$_=$p{$_}" if $p{$_};
    }

    my $dbh;
    eval
    {
	$dbh = DBI->connect( $dsn,
			     $p{user},
			     $p{password},
			     { RaiseError => 1,
			       AutoCommit => 1,
			     }
			   );
    };

    Alzabo::Exception::Driver->throw( error => $@ ) if $@;
    Alzabo::Exception::Driver->throw( error => "Unable to connect to database\n" ) unless $dbh;

    return $dbh;
}

sub next_sequence_number
{
    my $self = shift;
    my $col = shift;

    Alzabo::Exception::Params->throw( error => "This column (" . $col->name . ") is not sequenced" )
	unless $col->sequenced;

    my $seq_name = join '___', $col->table->name, $col->name;

    $self->{last_id} = $self->one_row( sql => "SELECT NEXTVAL('$seq_name')" );

    return $self->{last_id};
}

sub get_last_id
{
    my $self = shift;
    return $self->{last_id};
}

sub start_transaction
{
    my $self = shift;

    $self->{tran_count} = 0 unless defined $self->{tran_count};
    $self->{tran_count}++;

    $self->{dbh}->{AutoCommit} = 0;
}

sub rollback
{
    my $self = shift;

    $self->{dbh}->rollback unless $self->{dbh}->{AutoCommit};

    $self->{dbh}->{AutoCommit} = 1;

    $self->{tran_count} = undef;
}

sub finish_transaction
{
    my $self = shift;

    # More commits than begin_tran.  Not correct.
    if ( defined $self->{tran_count} )
    {
	$self->{tran_count}--;
    }
    else
    {
	my $callee = (caller(1))[3];
	warn "$callee called commit without corresponding begin_tran call\n";
    }

    # Don't actually commit until we reach 'uber-commit'
    return if $self->{tran_count};

    unless ( $self->{dbh}->{AutoCommit} )
    {
        $self->{dbh}->commit;
    }
    $self->{dbh}->{AutoCommit} = 1;

    $self->{tran_count} = undef;
}

sub create_large_object
{
    my $self = shift;
    my $data = shift;

    $self->start_transaction;

    my $lo_id = $self->{dbh}->func( $self->{dbh}->{pg_INV_WRITE}, 'lo_creat' );

    Alzabo::Exception::Driver->throw( error => "Can't create new large object" )
	unless defined $lo_id;

    my $lo_fd = $self->{dbh}->func( $lo_id, $self->{dbh}->{pg_INV_WRITE}, 'lo_open' );

    Alzabo::Exception::Driver->throw( error => "Can't open large object for writing (id: $lo_id)" )
	unless defined $lo_fd;

    my $bytes = $self->{dbh}->func( $lo_fd, $data, length $data, 'lo_write' );

    Alzabo::Exception::Driver->throw( error => "Can't write message body to large object (id: $lo_id)" )
	unless defined $bytes;

    $self->{dbh}->func( $lo_fd, 'lo_close' )
	or Alzabo::Exception::Driver->throw( error => "Can't close large object (id: $lo_id)" );

    $self->finish_transaction;

    return $lo_id;
}

sub delete_large_object
{
    my $self = shift;
    my $lo_id = shift;

    $self->start_transaction;

    $self->get_dbh->func( $lo_id, 'lo_unlink' )
	or Alzabo::Exception::Driver->throw( error => "Unable to unlink large object (id: $lo_id)" );

    $self->finish_transaction;
}

sub driver_id
{
    return 'PostgreSQL';
}

__END__

=head1 NAME

Alzabo::Driver::PostgreSQL - PostgreSQL specific Alzabo driver subclass

=head1 SYNOPSIS

  use Alzabo::Driver::PostgreSQL;

=head1 DESCRIPTION

This provides some PostgreSQL specific implementations for the virtual
methods in Alzabo::Driver.

=head1 METHODS

=head2 connect, create_database, drop_database

Besides the parameters listed in L<the Alzabo::Driver
docs|Alzabo::Driver/Parameters for the connect, create_database, and
drop_database>, the following parameters are accepted:

=over 4

=item * options

=item * tty

=back

=head2 get_last_id

Returns the last id created for a sequenced column.

=head1 BUGS

In testing, I found that there were some problems using Postgres in a
situation where you start the app, connect to the database, get some
data, fork, reconnect, and and then get more data.  I suspect that
this has more to do with the DBD::Pg driver and/or Postgres itself
than Alzabo.  I don't believe this would be a problem with an app
which forks before ever connecting to the database (such as mod_perl).

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
