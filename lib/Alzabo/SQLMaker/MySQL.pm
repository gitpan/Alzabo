package Alzabo::SQLMaker::MySQL;

use strict;
use vars qw($VERSION $AUTOLOAD);

use Alzabo::Exceptions;

use base qw(Alzabo::SQLMaker);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.6 $ =~ /(\d+)\.(\d+)/;

1;

sub init
{
    1;
}

sub DESTROY { }

my %functions = map { $_ => 1 } qw( abs sign mod floor ceiling
				    round exp log log10 pow power
				    sqrt pi cos sin tan acos
				    asin atan atan2 cot rand least
				    greatest degrees radians truncate
				    asci ord conv bin oct hex char
				    concat concat_ws length
				    octet_length char_length character_length
				    locate position instr lpad rpad
				    left right substring mid
				    substring_index ltrim rtrim trim
				    soundex space replace repeat
				    reverse insert elt field find_in_set
				    make_set export_set lcase lower
				    ucase upper dayofweek weekday
				    dayofyear month dayname monthname
				    quarter week yearweek hour minute
				    second period_add period_diff
				    date_add date_sub adddate subdate
				    to_days from_days date_format
				    time_format curdate current_date
				    curtime current_time now sysdate
				    current_timestamp unix_timestamp
				    from_unixtime sec_to_time time_to_sec
				    database user system_user session_user
				    password encrypt encode decode
				    md5 last_insert_id format version
				    connection_id get_lock releast_lock
				    benchmark inet_ntoa inet_aton
				    count avg min max sum std stddev
				    bit_or bit_and distinct );

sub _valid_function
{
    shift;

    return $functions{ lc shift };
}

sub _subselect
{
    Alzabo::Exception::SQL->throw( error => "MySQL does not support subselects" );
}

sub limit
{
    my $self = shift;
    my ($max, $offset) = @_;

    $self->_assert_last_op( qw( from function where and or asc desc ) );

    if ($offset)
    {
	$self->{sql} .= " LIMIT $offset, $max";
    }
    else
    {
	$self->{sql} .= " LIMIT $max";
    }

    $self->{last_op} = 'limit';

    return $self;
}

sub get_limit
{
    return undef;
}

__END__

=head1 NAME

Alzabo::SQLMaker::MySQL - Alzabo SQL making class for MySQL

=head1 SYNOPSIS

  use Alzabo::SQLMaker;

  my $sql = Alzabo::SQLMaker->new( sql => 'MySQL' );

=head1 DESCRIPTION

MySQL-specific SQL creation.  It is worth noting that MySQL does not
allow subselects.  Any attempt to use a subselect (by passing an
C<Alzabo::SQMaker> object in as parameter to a method) will result in
an L<C<Alzabo::Exception::SQL>|Alzabo::Exceptions> error.

=head1 METHODS

Almost all of the functionality inherited from Alzabo::SQLMaker is
used as is.  The only overridden methods are C<limit> and
C<get_limit>, as MySQL does allow for a C<LIMIT> clause in its SQL.

=head1 AUTHOR

Dave Rolsky, <dave@urth.org>

=cut
