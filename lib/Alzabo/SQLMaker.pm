package Alzabo::SQLMaker;

use strict;
use vars qw($VERSION $AUTOLOAD);

use Alzabo::Exceptions;
use Alzabo::Util;

$VERSION = sprintf '%2d.%02d', q$Revision: 1.10 $ =~ /(\d+)\.(\d+)/;

1;

sub load
{
    shift;
    my %p = @_;

    my $class = "Alzabo::SQLMaker::$p{rdbms}";
    eval "use $class";
    Alzabo::Exception::Eval->throw( error => $@ ) if $@;

    $class->init(@_);

    return $class;
}

sub available
{
    return Alzabo::Util::subclasses(__PACKAGE__);
}

sub init
{
    1;
}

sub _object
{
    return bless { last_op => undef,
		   expect => undef,
		   type => undef,
		   sql => '',
		   bind => [],
		 }, shift;
}

sub select
{
    my $class = ref $_[0] || $_[0];
    shift;

    my $self = $class->_object;

    $self->{sql} .= 'SELECT ';

    if (@_)
    {
	$self->{columns} = [ map { $_->isa('Alzabo::Table') ? $_->columns : $_ } @_ ];

	$self->{sql} .= join ', ', map { join '.', $_->table->name, $_->name } @{ $self->{columns} };
    }

    $self->{type} = 'select';
    $self->{last_op} = 'select';

    return $self;
}

sub AUTOLOAD
{
    my $self = shift;

    my ($func) = $AUTOLOAD =~ /::([^:]+)$/;

    $self->_assert_last_op( qw( select function where and or ) );
    return $self->_function( $func, @_ );

    Alzabo::Exception->throw( error => "'$func' is not supported by this RDBMS\n" );
}

sub DESTROY { }

sub _function
{
    my $self = shift;
    my ($func, @params) = @_;

    $self->_assert_last_op( qw( select function ) );

    Alzabo::Exception::SQL->throw( error => $self->rules_id . " does not support the '$func' function" )
	unless $self->_valid_function($func);

    $self->{sql} .= ',' if $self->{last_op} eq 'function';

    $self->{sql} .= " $func(";
    $self->{sql} .= join ', ', map { UNIVERSAL::isa( $_, 'Alzabo::Column' ) ? $_->name : $_ } @params;
    $self->{sql} .= ')';

    $self->{last_op} = 'function';

    return $self;
}

sub _valid_function
{
    1;
}

sub from
{
    my $self = shift;

    $self->_assert_last_op( qw( select delete function ) );

    $self->{sql} .= ' FROM ';
    $self->{sql} .= join ', ', map { $_->name } @_;

    $self->{tables} = [ @_ ];

    if ($self->{type} eq 'SELECT')
    {
	foreach my $c ( @{ $self->{columns} } )
	{
	    unless ( grep { $_ eq $c->table } @{ $self->{tables} } )
	    {
		my $err = 'Cannot select column (';
		$err .= join '.', $c->table->name, $c->name;
		$err .= ') unless its table is included in the FROM clause';
		Alzabo::Exception::SQL->throw( error => $err );
	    }
	}
    }

    $self->{last_op} = 'from';

    return $self;
}

sub where
{
    my $self = shift;

    $self->_assert_last_op( qw( from set ) );

    $self->{sql} .= ' WHERE ';

    $self->_condition(@_);

    $self->{last_op} = 'where';

    return $self;
}

sub and
{
    my $self = shift;

    return $self->_and_or( 'and', @_ );
}

sub or
{
    my $self = shift;

    return $self->_and_or( 'or', @_ );
}

sub _and_or
{
    my $self = shift;
    my $op = shift;

    $self->_assert_last_op( qw( where and or ) );

    $self->{sql} .= " \U$op ";

    $self->_condition(@_);

    $self->{last_op} = $op;

    return $self;
}

sub _condition
{
    my $self = shift;
    my $col = shift;
    my $comp = shift;
    my $rhs = shift;

    unless ( grep { $_ eq $col->table } @{ $self->{tables} } )
    {
	die $@ if $@;
	my $err = 'Cannot use column (';
	$err .= join '.', $col->table->name, $col->name;
	$err .= ") in \U$self->{type}\E unless its table is included in the ";
	$err .= $self->{type} eq 'update' ? 'UPDATE' : 'FROM';
	$err .= ' clause';
	Alzabo::Exception::SQL->throw( error => $err );
    }

    $self->{sql} .= join '.', $col->table->name, $col->name;

    if ( lc $comp eq 'between' )
    {
	Alzabo::Exception::SQL->throw( error => "The BETWEEN comparison operator requires an additional argument" )
	    unless @_ == 1;

	my $rhs2 = shift;

	Alzabo::Exception::SQL->throw( error => "The BETWEEN comparison operator cannot accept a subselect" )
	    if grep { UNIVERSAL::isa( $_, 'Alzabo::SQLMaker' ) } $rhs, $rhs2;

	$self->{sql} .= $self->_rhs($col, $rhs);
	$self->{sql} .= " AND ";
	$self->{sql} .= $self->_rhs($col, $rhs2);

	return;
    }

    if ( lc $comp eq 'in' )
    {
	$self->{sql} .= ' IN (';
	$self->{sql} .= join ', ', map { ( UNIVERSAL::isa( $_, 'Alzabo::SQLMaker' ) ?
					   '(' . $self->_subselect($_) . ')' :
					   $self->_rhs($col, $_) ) } $rhs, @_;
	$self->{sql} .= ')';

	return;
    }

    if ( ref $rhs )
    {
	$self->{sql} .= " $comp ";
	if( $rhs->isa('Alzabo::SQLMaker') )
	{
	    $self->{sql} .= '(';
	    $self->{sql} .= $self->_subselect($rhs);
	    $self->{sql} .= ')';
	}
	else
	{
	    $self->{sql} .= $self->_rhs($col, $rhs);
	}
    }
    elsif ( defined $rhs )
    {
	$self->{sql} .= " $comp ";
	$self->{sql} .= $self->_rhs($col, $rhs);
    }
    elsif ( $comp eq '=' )
    {
	$self->{sql} .= ' IS NULL';
    }
    elsif ( $comp eq '!=' || $comp eq '<>' )
    {
	$self->{sql} .= ' IS NOT NULL';
    }
    else
    {
	Alzabo::Exception::SQL->throw( error => "Cannot compare a column to a NULL with '$comp'" );
    }
}

sub _rhs
{
    my $self = shift;
    my $col = shift;
    my $rhs = shift;

    if ( UNIVERSAL::isa( $rhs, 'Alzabo::Column' ) )
    {
	unless ( grep { $_ eq $rhs->table } @{ $self->{tables} } )
	{
	    my $err = 'Cannot use column (';
	    $err .= join '.', $rhs->table->name, $rhs->name;
	    $err .= ") in \U$self->{type}\Q unless its table is included in the ";
	    $err .= $self->{type} eq 'update' ? 'UPDATE' : 'FROM';
	    $err .= ' clause';
	    Alzabo::Exception::SQL->throw( error => $err );
	}
	return join '.', $rhs->table->name, $rhs->name;
    }
    else
    {
	return $self->_bind_val($col, $rhs);
    }
}

sub _subselect
{
    my $self = shift;
    my $sql = shift;

    push @{ $self->{bind} }, @{ $sql->bind };
    return $sql->sql;
}

sub order_by
{
    my $self = shift;

    $self->_assert_last_op( qw( select from where and or ) );

    Alzabo::Exception::SQL->throw( error => "Cannot use order by in a '$self->{type}' statement" )
	unless $self->{type} eq 'select';

    foreach my $c (@_)
    {
	unless ( grep {  $_ eq $c->table } @{ $self->{tables} } )
	{
	    my $err = 'Cannot use column (';
	    $err .= join '.', $c->table->name, $c->name;
	    $err .= ") in \U$self->{type}\E unless its table is included in the ";
	    $err .= $self->{type} eq 'update' ? 'UPDATE' : 'FROM';
	    $err .= ' clause';
	    Alzabo::Exception::SQL->throw( error => $err );
	}
    }

    $self->{sql} .= ' ORDER BY ';
    $self->{sql} .= join ', ', map { join '.', $_->table->name, $_->name } @_;

    $self->{last_op} = 'order_by';

    return $self;
}

sub asc
{
    shift->_asc_or_desc('asc');
}

sub desc
{
    shift->_asc_or_desc('desc');
}

sub _asc_or_desc
{
    my $self = shift;

    $self->_assert_last_op( qw( order_by ) );

    my $op = shift;
    $self->{sql} .= " \U$op";

    $self->{last_op} = $op;

    return $self;
}

sub insert
{
    my $class = ref $_[0] || $_[0];
    shift;

    my $self = $class->_object;

    $self->{sql} .= 'INSERT ';

    $self->{type} = 'insert';
    $self->{last_op} = 'insert';

    return $self;
}

sub into
{
    my $self = shift;

    $self->_assert_last_op( qw( insert ) );

    my $table = shift;
    $self->{tables} = [ $table ];

    foreach my $c (@_)
    {
	unless ( grep { $_ eq $c->table } @{ $self->{tables} } )
	{
	    my $err = 'Cannot into column (';
	    $err .= join '.', $c->table->name, $c->name;
	    $err .= ') because its table was not the one specified in the INTO clause';
	    Alzabo::Exception::SQL->throw( error => $err );
	}
    }

    $self->{columns} = [ @_ ? @_ : $table->columns ];

    $self->{sql} .= 'INTO ' . $table->name . ' (';
    $self->{sql} .= join ', ', map { $_->name } @{ $self->{columns} };
    $self->{sql} .= ') ';

    $self->{last_op} = 'into';

    return $self;
}

sub values
{
    my $self = shift;

    $self->_assert_last_op( qw( into ) );

    if ( ref $_[0] && $_[0]->isa('Alzabo::SQLMaker') )
    {
	$self->{sql} = $_[0]->sql;
	push @{ $self->{bind} }, $_[0]->bind;
    }
    else
    {
	my @vals = @_;

	Alzabo::Exception::Params->throw( error => "'values' method expects key/value pairs of column objects and values'" )
	    if !@vals || @vals % 2;

	my %vals = map { ref $_ && $_->isa('Alzabo::Column') ? $_->name : $_ } @vals;
	foreach my $c ( @vals[ map { $_ * 2 } 0 .. int($#vals/2) ] )
	{
	    Alzabo::Exception::SQL->throw( error => $c->name . " column was not specified in the into method call" )
		unless grep { $c eq $_ } @{ $self->{columns} };
	}

	foreach my $c ( @{ $self->{columns } } )
	{
	    Alzabo::Exception::SQL->throw( error => $c->name . " was specified in the into method call but no value was provided" )
		unless exists $vals{ $c->name };
	}

	$self->{sql} .= 'VALUES (';
	$self->{sql} .= join ', ', ( map { $self->_bind_val(@$_) }
				     ( map { [ $_, $vals{ $_->name } ] }
				       @{ $self->{columns} } ) );
	$self->{sql} .= ')';
    }

    $self->{last_op} = 'values';

    return $self;
}

sub update
{
    my $class = ref $_[0] || $_[0];
    shift;

    my $self = $class->_object;

    my $table = shift;

    $self->{sql} = 'UPDATE ' . $table->name;
    $self->{tables} = [ $table ];

    $self->{type} = 'update';
    $self->{last_op} = 'update';

    return $self;
}

sub set
{
    my $self = shift;
    my @vals = @_;

    $self->_assert_last_op('update');

    Alzabo::Exception::Params->throw( error => "'set' method expects key/value pairs of column objects and values'" )
       if !@vals || @vals % 2;

    $self->{sql} .= ' SET ';

    my @set;
    while ( my ($col, $val) = splice @vals, 0, 2 )
    {
	unless ( $self->{tables}[0] eq $col->table )
	{
	    my $err = 'Cannot set column (';
	    $err .= join '.', $col->table->name, $col->name;
	    $err .= ') unless its table is included in the UPDATE clause';
	    Alzabo::Exception::SQL->throw( error => $err );
	}

	push @set, $col->name . ' = ' . $self->_bind_val($col, $val);
    }
    $self->{sql} .= join ', ', @set;

    $self->{last_op} = 'set';

    return $self;
}

sub delete
{
    my $class = ref $_[0] || $_[0];
    shift;

    my $self = $class->_object;

    $self->{sql} .= 'DELETE ';

    $self->{type} = 'delete';
    $self->{last_op} = 'delete';

    return $self;
}

sub _assert_last_op
{
    my $self = shift;

    unless ( grep { $self->{last_op} eq $_ } @_ )
    {
	my $op = (caller(1))[3];
	$op =~ s/.*::(.*?)$/$1/;
	Alzabo::Exception::SQL->throw( error => "Cannot follow $self->{last_op} with $op" );
    }
}

sub _bind_val
{
    my $self = shift;
    my $column = shift;
    my $val = shift;

    push @{ $self->{bind} }, $val;

    return '?';
}

sub sql
{
    my $self = shift;
    return $self->{sql};
}

sub bind
{
    my $self = shift;
    return $self->{bind};
}

sub limit
{
    shift()->_virtual;
}

sub get_limit
{
    shift()->_virtual;
}

sub rules_id
{
    shift()->_virtual;
}

sub _virtual
{
    my $self = shift;

    my $sub = (caller(1))[3];
    $sub =~ s/.*::(.*?)$/$1/;
    Alzabo::Exception::VirtualMethod->throw( error =>
					     "$sub is a virtual method and must be subclassed in " . ref $self );
}

__END__

=head1 NAME

Alzabo::SQLMaker - Alzabo base class for RDBMS drivers

=head1 SYNOPSIS

  use Alzabo::SQLMaker;

  my $sql = Alzabo::SQLMaker->new( sql => 'MySQL' );

=head1 DESCRIPTION

This is the base class for all Alzabo::SQLMaker modules.  To
instantiate a driver call this class's C<new> method.  See
L<SUBCLASSING Alzabo::SQLMaker> for information on how to make a
driver for the RDBMS of your choice.

=head1 METHODS

=head2 available

=head3 Returns

A list of names representing the available C<Alzabo::SQLMaker>
subclasses.  Any one of these names would be appropriate as a
parameter for the L<C<Alzabo::SQLMaker-E<gt>new>|Alzabo::SQLMaker/new>
method.

=head2 load

Load the specified subclass.

=head3 Parameters

=over 4

=item * rdbms => $rdbms

The name of the RDBMS being used.

=back

=head3 Returns

The name of the C<Alzabo::SQLMaker> subclass that was loaded.

=head3 Throws

L<C<Alzabo::Exception::Eval>|Alzabo::Exceptions>

=head1 GENERATING SQL

This class can be used to generate SQL by calling methods that are the
same as those used in SQL (C<select>, C<update>, etc.) in sequence,
with the appropriate parameters.

There are four entry point methods, L<C<select>|select (Alzabo::Table
and/or Alzabo::Column objects)>, L<C<insert>|insert>,
L<C<update>|update (Alzabo::Table)>, and L<C<delete>|delete>.
Attempting call any other method without first calling one of these is
an error.

=head2 Entry Points

These methods are called as class methods and return a new object.

=head2 select (C<Alzabo::Table> and/or C<Alzabo::Column> objects)

This begins a select.  The columns to be selected are the column(s)
passed in, and/or the columns of the table(s) passed in as arguments.

=head3 Followed by

L<C<from>|Alzabo::SQLMaker/from (Alzabo::Table object, ...)>

L<C<** function>|Alzabo::SQLMaker/** function (Alzabo::Table object(s) and/or $string(s))>

=head2 insert

=head3 Followed by

L<C<into>|Alzabo::SQLMaker/into (Alzabo::Table object, optional Alzabo::Column objects)>

=head2 update (C<Alzabo::Table>)

=head3 Followed by

L<C<set>|Alzabo::SQLMaker/set (Alzabo::Column object =E<gt> $value, ...)>

=head2 delete

=head3 Followed by

L<C<from>|Alzabo::SQLMaker/from (Alzabo::Table object, ...)>

=head2 Other Methods

All of these methods return the object itself, making it possible to
chain together method calls such as:

 Alzabo::SQLMaker->select($column)->from($table)->where($other_column, '>', 2);

=head2 from (C<Alzabo::Table> object, ...)

The table(s) from which we are selecting data.

=head3 Follows

L<C<select>|Alzabo::SQLMaker/select (Alzabo::Table and/or Alzabo::Column objects)>

L<C<** function>|Alzabo::SQLMaker/** function (Alzabo::Table object(s) and/or $string(s))>

L<C<delete>|Alzabo::SQLMaker/delete>

=head3 Followed by

L<C<where>|Alzabo::SQLMaker/where ( (Alzabo::Column object), $comparison, (Alzabo::Column object, $value, or Alzabo::SQLMaker object), [ see below ] )>

L<C<order_by>|Alzabo::SQLMaker/order_by (Alzabo::Column objects)>

=head3 Throws

L<C<Alzabo::Exception::SQL>|Alzabo::Exceptions>

=head2 ** function (C<Alzabo::Table> object(s) and/or $string(s))

There is no publically available method in this class called
C<** function>.  This method represents all available SQL functions, such
as C<COUNT> or C<AVG>.  The name of the method is the name of the
function to be called.  Each subclass knows which functions are legal
for the RDBMS they represent.  All the arguments are joined together
by commas (,) internally.  Here is a simple example:

 Alzabo::SQLMaker->select->count($column)->from($table)->where($other_column, '>', 2);

=head3 Follows

L<C<select>|Alzabo::SQLMaker/select (Alzabo::Table and/or Alzabo::Column objects)>

L<C<** function>|Alzabo::SQLMaker/** function (Alzabo::Table object(s) and/or $string(s))>

=head3 Followed by

L<C<** function>|Alzabo::SQLMaker/** function (Alzabo::Table object(s) and/or $string(s))>

L<C<from>|Alzabo::SQLMaker/from (Alzabo::Table object, ...)>

=head3 Throws

L<C<Alzabo::Exception::SQL>|Alzabo::Exceptions>

=head2 where ( (C<Alzabo::Column> object), $comparison, (C<Alzabo::Column> object, $value, or C<Alzabo::SQLMaker> object), [ see below ] )

The first parameter must be an C<Alzabo::Column> object.  The second
is a comparison operator of some sort, given as a string.  The third
argument can be one of three things.  It can be an C<Alzabo::Column>
object, a value (a number or string), or an C<Alzabo::SQLMaker>
object.  The latter is treated as a subselect.

Values given as parameters will be properly quoted an escaped.

Some comparison operators allow additional parameters.

The C<BETWEEN> comparison operator requires a fourth argument.  This
must be either an C<Alzabo::Column> object or a value.

The C<IN> operator allows any number of additional parameters, which
may be C<Alzabo::Column> objects, values, or C<Alzabo::SQLMaker>
objects.

=head3 Follows

L<C<from>|Alzabo::SQLMaker/from (Alzabo::Table object, ...)>

=head3 Followed by

L<C<and>|Alzabo::SQLMaker/and (same as where)>

L<C<or>|Alzabo::SQLMaker/or (same as where)>

L<C<order_by>|Alzabo::SQLMaker/order_by (Alzabo::Column objects)>

=head3 Throws

L<C<Alzabo::Exception::SQL>|Alzabo::Exceptions>

=head2 and (same as C<where>)

=head2 or (same as C<where>)

These methods take the same parameters as the
L<C<where>|Alzabo::SQLMaker/where ( (Alzabo::Column object), $comparison, (Alzabo::Column object, $value, or Alzabo::SQLMaker object), [ see below ] )> method.  There is currently no way
to group together comparison operators.

=head3 Follows

L<C<where>|Alzabo::SQLMaker/where ( (Alzabo::Column object), $comparison, (Alzabo::Column object, $value, or Alzabo::SQLMaker object), [ see below ] )>

L<C<and>|Alzabo::SQLMaker/and (same as where)>

L<C<or>|Alzabo::SQLMaker/or (same as where)>

=head3 Followed by

L<C<and>|Alzabo::SQLMaker/and (same as where)>

L<C<or>|Alzabo::SQLMaker/or (same as where)>

L<C<order_by>|Alzabo::SQLMaker/order_by (Alzabo::Column objects)>

=head3 Throws

L<C<Alzabo::Exception::SQL>|Alzabo::Exceptions>

=head2 order_by (C<Alzabo::Column> objects)

Adds an C<ORDER BY> clause to your SQL.

=head3 Follows

L<C<from>|Alzabo::SQLMaker/from (Alzabo::Table object, ...)>

L<C<where>|Alzabo::SQLMaker/where ( (Alzabo::Column object), $comparison, (Alzabo::Column object, $value, or Alzabo::SQLMaker object), [ see below ] )>

L<C<and>|Alzabo::SQLMaker/and (same as where)>

L<C<or>|Alzabo::SQLMaker/or (same as where)>

=head3 Followed by

L<C<asc>|Alzabo::SQLMaker/asc>

L<C<desc>|Alzabo::SQLMaker/desc>

=head3 Throws

L<C<Alzabo::Exception::SQL>|Alzabo::Exceptions>

=head2 asc

=head2 desc

Modifies the sorting of an C<ORDER BY> clause.

=head3 Follows

L<C<order_by>|Alzabo::SQLMaker/order_by (Alzabo::Column objects)>

=head3 Followed by

L<C<limit>|Alzabo::SQLMaker/limit ($max, optional $offset)>

=head3 Throws

L<C<Alzabo::Exception::SQL>|Alzabo::Exceptions>

=head2 limit ($max, optional $offset)

Specifies a limit on the number of rows to be returned.  The offset
parameter is optional.

=head3 Follows

L<C<from>|Alzabo::SQLMaker/from (Alzabo::Table object, ...)>

L<C<where>|Alzabo::SQLMaker/where ( (Alzabo::Column object), $comparison, (Alzabo::Column object, $value, or Alzabo::SQLMaker object), [ see below ] )>

L<C<and>|Alzabo::SQLMaker/and (same as where)>

L<C<or>|Alzabo::SQLMaker/or (same as where)>

L<C<order_by>|Alzabo::SQLMaker/order_by (Alzabo::Column objects)>

=head3 Followed by

Nothing.

=head3 Throws

L<C<Alzabo::Exception::SQL>|Alzabo::Exceptions>

=head2 into (C<Alzabo::Table> object, optional C<Alzabo::Column> objects)

Used to specify what table an insert is into.  If column objects are
given then it is expected that values will only be given for that
object.  Otherwise, it assumed that all columns will be specified in
the L<C<values>|Alzabo::SQLMaker/values (Alzabo::Column object =E<gt> $value, ...)> method.

=head3 Follows

L<C<insert>|Alzabo::SQLMaker/insert>

=head3 Followed by

L<C<values>|Alzabo::SQLMaker/values (Alzabo::Column object =E<gt> $value, ...)>

=head3 Throws

L<C<Alzabo::Exception::SQL>|Alzabo::Exceptions>

=head2 values (C<Alzabo::Column> object => $value, ...)

This method expects to recive an structured like a hash where the keys
are C<Alzabo::Column> objects and the values are the value to be
inserted into that column.

=head3 Follows

L<C<into>|Alzabo::SQLMaker/into (Alzabo::Table object, optional Alzabo::Column objects)>

=head3 Followed by

Nothing.

=head3 Throws

L<C<Alzabo::Exception::SQL>|Alzabo::Exceptions>

=head2 set (C<Alzabo::Column> object => $value, ...)

This method'a parameter are exactly like those given to the
L<C<values>|values ( Alzabo::Column object =E<gt> $value, ... )>
method.

=head3 Follows

L<C<update>|Alzabo::SQLMaker/update (Alzabo::Table)>

=head3 Followed by

L<C<where>|Alzabo::SQLMaker/where ( (Alzabo::Column object), $comparison, (Alzabo::Column object, $value, or Alzabo::SQLMaker object), [ see below ] )>

=head3 Throws

L<C<Alzabo::Exception::SQL>|Alzabo::Exceptions>

=head2 Retrieving SQL

=head2 sql

This can be called at any time though obviously it will not return
valid SQL unless called at a natural end point.  In the future, an
exception may be thrown if called when the SQL is not in a valid
state.

=head3 Returns

The SQL generated so far.

=head2 bind

=head3 Returns

An array reference containing the parameters to be bound to the SQL
statement.

=head2 get_limit

This method may return undef even if the
L<C<limit>|Alzabo::SQLMaker/limit ($max, optional $offset)> method was
called.  Some RDBMS's have special SQL syntax for C<LIMIT> clauses.
For those that don't support this, the
L<C<Alzabo::Driver>/Alzabo::Driver> module takes a C<limit> parameter.
The return value of this method can be passed in as that parameter in
all cases.

=head3 Returns

If the RDBMS does not support C<LIMIT> clauses, the return value is an
array reference containing two values, the maximum number of rows
allowed and the row offset (the first row that should be used).

If the RDBMS does support C<LIMIT> clauses, then the return value is
C<undef>.

=head1 SUBCLASSING Alzabo::SQLMaker

To create a subclass of C<Alzabo::SQLMaker> for your particular RDBMS
requires only that the L<virtual methods/Alzabo::SQLMaker/Virtual
Methods> listed below be implemented.

In addition, you may choose to override any of the other methods
listed in L<over-rideable methods|Over-Rideable Methods>.  For
example, the MySQL subclass override the
L<C<_subselect>|Alzabo::SQLMaker/_subselect> method because MySQL
cannot support sub-selects.

=head2 Virtual Methods

=head1 AUTHOR

Dave Rolsky, <dave@urth.org>

=cut
