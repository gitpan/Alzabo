package Alzabo::SQLMaker::PostgreSQL;

use strict;
use vars qw($VERSION $AUTOLOAD);

use Alzabo::Exceptions;

use base qw(Alzabo::SQLMaker);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.3 $ =~ /(\d+)\.(\d+)/;

1;

sub init
{
    1;
}

sub DESTROY { }

my %functions = map { $_ => 1 } qw( abs degrees exp ln log pi
				    pow radians round sqrt cbrt
				    trunc float float4 integer
				    acos asin atan atan2
				    cos cot sin tan
				    char_length character_length
				    lower octet_length position
				    substring trim upper
				    char initcap lpad ltrim
				    textpad rpos rtrim substr
				    text translate varchar
				    abstime age date_part
				    date_trunc interval isfinite
				    reltime timestamp to_char
				    to_date to_timestamp
				    to_number
				    area box center diameter
				    height isclosed isopen
				    length pclose npoint
				    popen radius width
				    circle lset path
				    point polygon
				    isoldpath revertpoly
				    upgradepath upgradepoly
				    broadcast host masklen printmask
				    count
				  );

sub _valid_function
{
    shift;

    return $functions{ lc shift };
}

sub _subselect
{
    Alzabo::Exception::SQL->throw( error => "PostgreSQL does not support subselects" );
}

sub limit
{
    my $self = shift;
    my ($max, $offset) = @_;

    $self->_assert_last_op( qw( from function where and or asc desc ) );

    $self->{sql} .= " LIMIT $max";
    $self->{sql} .= " OFFSET $offset" if $offset;

    $self->{last_op} = 'limit';

    return $self;
}

sub get_limit
{
    return undef;
}

sub rules_id
{
    return 'PostgreSQL';
}

__END__

=head1 NAME

Alzabo::SQLMaker::PostgreSQL - Alzabo SQL making class for PostgreSQL

=head1 SYNOPSIS

  use Alzabo::SQLMaker;

  my $sql = Alzabo::SQLMaker->new( sql => 'PostgreSQL' );

=head1 DESCRIPTION

PostgreSQL-specific SQL creation.

=head1 METHODS

Almost all of the functionality inherited from Alzabo::SQLMaker is
used as is.  The only overridden methods are C<limit> and
C<get_limit>, as PostgreSQL does allow for a C<LIMIT> clause in its
SQL.

=head1 AUTHOR

Dave Rolsky, <dave@urth.org>

=cut
