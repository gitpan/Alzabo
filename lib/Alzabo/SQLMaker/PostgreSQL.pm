package Alzabo::SQLMaker::PostgreSQL;

use strict;
use vars qw($VERSION $AUTOLOAD @EXPORT_OK %EXPORT_TAGS);

use Alzabo::Exceptions;

use Alzabo::SQLMaker;
use base qw(Alzabo::SQLMaker);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.10 $ =~ /(\d+)\.(\d+)/;

my $MADE_LITERALS;
my %functions;

sub import
{
    _make_literals() unless $MADE_LITERALS;

    # used to export literal functions
    require Exporter;
    *_import = \&Exporter::import;

    goto &_import;
}

sub _make_literals
{
    *make_literal = \&Alzabo::SQLMaker::make_literal;

    foreach ( [ NOW => [ 'datetime', 'common' ] ],
	      [ CURRENT_DATE => [ 'datetime' ] ],
	      [ CURRENT_TIME => [ 'datetime' ] ],
	      [ CURRENT_TIMESTAMP => [ 'datetime' ] ],
	      [ TIMEOFDAY => [ 'datetime' ] ],

	      [ PI => [ 'math' ] ],
	      [ RANDOM => [ 'math' ] ],

	      [ CURRENT_USER => [ 'system' ] ],
	      [ SYSTEM_USER => [ 'system' ] ],
	      [ USER => [ 'system' ] ],
	    )
    {
	make_literal( literal => $_->[0],
		      min => 0,
		      max => 0,
		      groups => $_->[1],
		    );
    }

    foreach ( [ LENGTH => [1], [ 'string' ] ],
	      [ CHAR_LENGTH => [1], [ 'string' ] ],
	      [ CHARACTER_LENGTH => [1], [ 'string' ] ],
	      [ OCTET_LENGTH => [1], [ 'string' ] ],
	      [ TRIM => [1], [ 'string' ] ],
	      [ UPPER => [1], [ 'string' ] ],
	      [ LOWER => [1], [ 'string' ] ],
	      [ INITCAP => [1], [ 'string' ] ],
	      [ ASCII => [1], [ 'string' ] ],

	      [ ABS => [0], [ 'math' ] ],
	      [ CEIL => [0], [ 'math' ] ],
	      [ DEGREES => [0], [ 'math' ] ],
	      [ FLOOR => [0], [ 'math' ] ],
	      [ FACTORIAL => [0], [ 'math' ] ],
	      [ SQRT => [0], [ 'math' ] ],
	      [ CBRT => [0], [ 'math' ] ],
	      [ EXP => [0], [ 'math' ] ],
	      [ LN => [0], [ 'math' ] ],
	      [ RADIANS => [0], [ 'math' ] ],

	      [ ACOS => [0], [ 'math' ] ],
	      [ ASIN => [0], [ 'math' ] ],
	      [ ATAN => [0], [ 'math' ] ],
	      [ COS => [0], [ 'math' ] ],
	      [ COT => [0], [ 'math' ] ],
	      [ SIN => [0], [ 'math' ] ],
	      [ TAN => [0], [ 'math' ] ],

	      [ ISFINITE => [1], [ 'datetime' ] ],

	      [ BROADCAST => [1], [ 'network' ] ],
	      [ HOST => [1], [ 'network' ] ],
	      [ NETMASK => [1], [ 'network' ] ],
	      [ MASKLEN => [1], [ 'network' ] ],
	      [ NETWORK => [1], [ 'network' ] ],
	      [ TEXT => [1], [ 'network' ] ],
	      [ ABBREV => [1], [ 'network' ] ],
	    )
    {
	make_literal( literal => $_->[0],
		      min => 1,
		      max => 1,
		      quote => $_->[1],
		      groups => $_->[2],
		    );
    }

    foreach ( [ TO_ASCII => [1,0], [ 'string' ] ],

	      [ ROUND => [0,0], [ 'math' ] ],
	      [ TRUNC => [0,0], [ 'math' ] ],
	      [ LOG => [0,0], [ 'math' ] ],
	      [ POW => [0,0], [ 'math' ] ],

	      [ TIMESTAMP => [1,1], [ 'datetime' ] ],
	    )
    {
	make_literal( literal => $_->[0],
		      min => 1,
		      max => 2,
		      quote => $_->[1],
		      groups => $_->[2],
		    );
    }

    foreach ( [ STRPOS => [1,1], [ 'string' ] ],
	      [ POSITION => [1,1], [ 'string' ], '%s IN %s' ],
	      [ TO_NUMBER => [1,1], [ 'string' ] ],
	      [ TO_DATE => [1,1], [ 'string' ] ],
	      [ TO_TIMESTAMP => [1,1], [ 'string' ] ],
	      [ REPEAT => [1,0], [ 'string' ] ],

	      [ MOD => [0,0], [ 'math' ] ],
	      [ ATAN2 => [0,0], [ 'math' ] ],

	      [ TO_CHAR => [0,1], [ 'math', 'datetime' ] ],

	      [ DATE_PART => [1,1], [ 'datetime' ] ],
	      [ EXTRACT => [0,1], [ 'datetime' ], '%s FROM %s' ],

	      [ NULLIF => [0,0], [ 'misc' ] ],
	    )
    {
	make_literal( literal => $_->[0],
		      min => 2,
		      max => 2,
		      quote => $_->[1],
		      groups => $_->[2],
		      $_->[3] ? ( format => $_->[3] ) : (),
		    );
    }

    foreach ( [ RPAD => [0,0,1], [ 'string' ] ],
	      [ LPAD => [0,0,1], [ 'string' ] ],
	      [ SUBSTR => [0,0,0], [ 'string' ] ],
	    )
    {
	make_literal( literal => $_->[0],
		      min => 2,
		      max => 3,
		      quote => $_->[1],
		      groups => $_->[2],
		    );
    }

    make_literal( literal => 'COALESCE',
		  min => 2,
		  max => undef,
		  quote => [1,1,1],
		  groups => [ 'misc' ],
		);

    make_literal( literal => 'OVERLAPS',
		  min => 4,
		  max => 4,
		  quote => [1,1,1,1],
		  groups => [ 'datetime' ],
		);

    foreach ( [ COUNT  => [0], [ 'aggregate', 'common' ] ],
	      [ AVG  => [0], [ 'aggregate', 'common' ] ],
	      [ MIN  => [0], [ 'aggregate', 'common' ] ],
	      [ MAX  => [0], [ 'aggregate', 'common' ] ],
	      [ SUM  => [0], [ 'aggregate', 'common' ] ],
	      [ STDDEV  => [0], [ 'aggregate', 'common' ] ],
	      [ VARIANCE  => [0], [ 'aggregate', 'common' ] ],

	      [ DISTINCT  => [0], [ 'aggregate', 'common' ] ],
	    )
    {
	make_literal( literal => $_->[0],
		      min => 1,
		      max => 1,
		      quote => $_->[1],
		      groups => $_->[2],
		    );
    }

    %functions = map { $_ => 1 } @EXPORT_OK;

    $MADE_LITERALS = 1;
}

sub init
{
    1;
}

sub DESTROY { }

sub _valid_function
{
    shift;

    return $functions{ uc shift };
}

sub limit
{
    my $self = shift;
    my ($max, $offset) = @_;

    $self->_assert_last_op( qw( from function where and or condition order_by group_by ) );

    $self->{sql} .= " LIMIT $max";
    $self->{sql} .= " OFFSET $offset" if $offset;

    $self->{last_op} = 'limit';

    return $self;
}

sub get_limit
{
    return undef;
}

sub sqlmaker_id
{
    return 'PostgreSQL';
}

1;

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

=head1 EXPORTED SQL FUNCTIONS

SQL may be imported by name or by tags.  They take arguments as
documented in the PostgreSQL documentation (version 3.23.39).  The
functions (organized by tag) are:

=head2 :math

 PI
 RANDOM
 ABD
 CEIL
 DEGREES
 FLOOR
 FACTORIAL
 SQRT
 CBRT
 EXP
 LN
 RADIANS
 ACOS
 ASIN
 ATAN
 ATAN2
 COS
 COT
 SIN
 TAN
 ROUND
 TRUNC
 LOG
 POW
 MOD
 TO_CHAR

=head2 :string

 LENGTH
 CHAR_LENGTH
 CHARACTER_LENGTh
 OCTET_LENGTH
 TIRM
 UPPER
 LOWER
 INITCAP
 ASCII
 TO_ASCII
 STRPOS
 POSITION
 TO_NUMBER
 TO_DATE
 TO_TIMESTAMP
 REPEAT
 RPAD
 LPAD
 SUBSTR

=head2 :datetime

 NOW
 CURRENT_DATE
 CURRENT_TIME
 CURRENT_TIMESTAMP
 TIMEOFDAY
 ISFINIT
 TIMESTAMP
 TO_CHAR
 DATE_PART
 EXTRACT
 OVERLAPS

=head2 :network

 BROADCAST
 HOST
 NETMASK
 MASKLEN
 NETWORK
 TEXT
 ABBREV

=head2 :aggregate

These are functions which operate on an aggregate set of values all at
once.

 COUNT
 AVG
 MIN
 MAX
 SUM
 STDDEV
 VARIANCE
 DISTINCT

=head2 :system

These are functions which return information about the MySQL server.

 CURRENT_USER
 SYSTEM_USER
 USER

=head2 :misc

These are functions which don't fit into any other categories.

 ENCRYPT
 ENCODE
 DECODE
 FORMAT
 INET_NTOA
 INET_ATON
 BIT_OR
 BIT_AND
 PASSWORD
 MD5
 LOAD_FILE

=head2 :common

These are functions from other groups that are most commonly used.

 NOW
 COUNT
 AVG
 MIN
 MAX
 SUM
 DISTINCT

=head1 AUTHOR

Dave Rolsky, <dave@urth.org>

=cut

