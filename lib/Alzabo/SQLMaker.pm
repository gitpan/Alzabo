package Alzabo::SQLMaker;

use strict;
use vars qw($VERSION $AUTOLOAD);

use Alzabo::Exceptions;

use Class::Factory::Util;
use Params::Validate qw( :all );
Params::Validate::validation_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.62 $ =~ /(\d+)\.(\d+)/;

1;

sub make_function
{
    my $class = caller;

    my %p =
	validate( @_,
		  { function => { type => SCALAR },
		    min => { type => SCALAR, optional => 1 },
		    max => { type => UNDEF | SCALAR, optional => 1 },
		    groups => { type => ARRAYREF },
		    quote => { type => ARRAYREF, optional => 1 },
		    format => { type => SCALAR, optional => 1 },
		    is_modifier => { type => SCALAR, default => 0 },
		    has_spaces => { type => SCALAR, default => 0 },
		    allows_alias => { type => SCALAR, default => 1 },
		  } );

    my $valid = '';
    if ( $p{min} || $p{max} )
    {
	$valid .= 'validate_pos( @_, ';
	$valid .= join ', ', ('1') x $p{min};
    }

    if ( defined $p{min} && defined $p{max} && $p{max} > $p{min} )
    {
	$valid .= ', ';
	$valid .= join ', ', ('0') x ( $p{max} - $p{min} );
    }
    elsif ( exists $p{min} && ! defined $p{max} )
    {
	$valid .= ", ('1') x (\@_ - $p{min})";
    }
    $valid .= ' );' if $valid;

    my @args = "function => '$p{function}'";

    if ( ! defined $p{max} || $p{max} > 0 )
    {
	push @args, '                                      args => [@_]';
    }

    if ( $p{format} )
    {
	push @args, "                                      format => '$p{format}'";
    }

    if ( $p{quote} )
    {
	my $quote .= '                                      quote => [';
	$quote .= join ', ', @{ $p{quote} };
	$quote .= ']';
	push @args, $quote;
    }

    if ( $p{is_modifier} )
    {
	push @args, '                                      is_modifier => 1';
    }

    if ( $p{has_spaces} )
    {
	push @args, '                                      has_spaces => 1';
    }

    if ( $p{allows_alias} )
    {
	push @args, '                                      allows_alias => 1';
    }

    my $args = join ",\n", @args;

    my $code = <<"EOF";
sub ${class}::$p{function}
{
    shift if defined \$_[0] && UNIVERSAL::isa( \$_[0], 'Alzabo::SQLMaker' );
    $valid
    return Alzabo::SQLMaker::Function->new( $args );
}
EOF

    eval $code;

    {
	no strict 'refs';
	push @{ "$class\::EXPORT_OK" }, $p{function};
	my $exp = \%{ "$class\::EXPORT_TAGS" };
	foreach ( @{ $p{groups} } )
	{
	    push @{ $exp->{$_}  }, $p{function};
	}
	push @{ $exp->{all} }, $p{function};
    }
}

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

sub available { __PACKAGE__->subclasses }

sub init
{
    1;
}

sub new
{
    my $class = shift;
    my %p = validate( @_, { driver => { isa => 'Alzabo::Driver' },
                            quote_identifiers  => { type => BOOLEAN,
                                                    default => 0 },
                          },
                    );

    return bless { last_op => undef,
		   expect => undef,
		   type => undef,
		   sql => '',
		   bind => [],
		   as_id => 'aaaaa10000',
                   alias_in_having => 1,
                   %p,
		 }, $class;
}

sub last_op
{
    return shift->{last_op};
}

sub select
{
    my $self = shift;

    Alzabo::Exception::Params->throw( error => "The select method requires at least one parameter" )
	unless @_;

    $self->{sql} .= 'SELECT ';

    if ( lc $_[0] eq 'distinct' )
    {
	$self->{sql} .= ' DISTINCT ';
	shift;
    }

    my @sql;
    foreach my $elt (@_)
    {
	if ( UNIVERSAL::can( $elt, 'table' ) )
	{
            my $table = $elt->table;

	    $self->{column_tables}{"$table"} = 1;

            my $sql =
                ( $self->{quote_identifiers} ?
                  $self->{driver}->quote_identifier
                      ( $table->alias_name, $elt->name ) :
                  $table->alias_name . '.' . $elt->name );

            $sql .= ' AS ' .
                ( $self->{quote_identifiers} ?
                  $self->{driver}->quote_identifier( $elt->alias_name ) :
                  $elt->alias_name );

	    push @sql, $sql;
	}
	elsif ( UNIVERSAL::can( $elt, 'columns' ) )
	{
	    $self->{column_tables}{"$elt"} = 1;

            my @cols;

            foreach my $col ( $elt->columns )
            {
                my $sql =
                    ( $self->{quote_identifiers} ?
                      $self->{driver}->quote_identifier
                      ( $elt->alias_name, $col->name ) :
                      $elt->alias_name . '.' . $col->name );

                $sql .= ' AS ' .
                    ( $self->{quote_identifiers} ?
                      $self->{driver}->quote_identifier( $elt->alias_name ) :
                      $elt->alias_name );

                push @cols, $sql;
            }

	    push @sql, join ', ', @cols;
	}
	elsif ( UNIVERSAL::isa( $elt, 'Alzabo::SQLMaker::Function' ) )
	{
	    my $string = $elt->as_string( $self->{driver}, $self->{quote_identifiers} );

	    if ( $elt->allows_alias )
	    {
		push @sql, " $string AS " . $self->{as_id};
		$self->{functions}{$string} = $self->{as_id};
		++$self->{as_id};
	    }
	    else
	    {
		push @sql, $string;
	    }
	}
	elsif ( ! ref $elt )
	{
	    push @sql, $elt;
	}
	else
	{
	    Alzabo::Exception::SQL->throw
                    ( error => 'Arguments to select must be either column objects,' .
                               ' table objects, function objects, or plain scalars' );
	}
    }

    $self->{sql} .= join ', ', @sql;

    $self->{type} = 'select';
    $self->{last_op} = 'select';

    return $self;
}

sub from
{
    my $self = shift;

    $self->_assert_last_op( qw( select delete function ) );

    my $spec =
        $self->{last_op} eq 'select' ? { type => OBJECT | ARRAYREF } : { can => 'alias_name' };

    validate_pos( @_, ( $spec ) x @_ );

    $self->{sql} .= ' FROM ';

    if ( $self->{last_op} eq 'delete' )
    {
	$self->{sql} .=
	    join ', ', map { ( $self->{quote_identifiers} ?
                               $self->{driver}->quote_identifier( $_->name ) :
                               $_->name ) } @_;

	$self->{tables} = { map { $_ => 1 } @_ };
    }
    else
    {
        my $sql;

	$self->{tables} = {};

        my @plain;
	foreach my $elt (@_)
	{
	    if ( UNIVERSAL::isa( $elt, 'ARRAY' ) )
	    {
		$sql .= ' ' if $sql;

                $sql .= $self->_outer_join(@$elt);
	    }
            else
            {
                push @plain, $elt;
            }
        }

        foreach my $elt ( grep { ! exists $self->{tables}{$_ } } @plain )
        {
            $sql .= ', ' if $sql;

            if ( $self->{quote_identifiers} )
            {
                $sql .=
                    ( $self->{driver}->quote_identifier( $elt->name ) .
                      ' AS ' .
                      $self->{driver}->quote_identifier( $elt->alias_name ) );
            }
            else
            {
                $sql .= $elt->name . ' AS ' . $elt->alias_name;
            }

            $self->{tables}{$elt} = 1;
	}

        $self->{sql} .= $sql;
    }

    if ($self->{type} eq 'select')
    {
        foreach my $t ( keys %{ $self->{column_tables} } )
        {
	    unless ( $self->{tables}{$t} )
	    {
		my $err = 'Cannot select column ';
		$err .= 'unless its table is included in the FROM clause';
		Alzabo::Exception::SQL->throw( error => $err );
	    }
	}
    }

    $self->{last_op} = 'from';

    return $self;
}

sub _outer_join
{
    my $self = shift;

    my $tables = @_ - 1;
    validate_pos( @_,
		  { type => SCALAR },
		  ( { can => 'alias_name' } ) x 2,
		  { type => UNDEF | ARRAYREF | OBJECT, optional => 1 },
		  { type => UNDEF | ARRAYREF, optional => 1 },
                );

    my $type = uc shift;

    my $join_from = shift;
    my $join_on = shift;
    my $fk;
    $fk = shift if @_ && UNIVERSAL::isa( $_[0], 'Alzabo::ForeignKey' );
    my $where = shift;

    unless ($fk)
    {
	my @fk = $join_from->foreign_keys_by_table($join_on);

	Alzabo::Exception::Params->throw( error => "The " . $join_from->name . " table has no foreign keys to the " . $join_on->name . " table" )
	    unless @fk;

	Alzabo::Exception::Params->throw( error => "The " . $join_from->name . " table has more than 1 foreign key to the " . $join_on->name . " table" )
	    if @fk > 1;

	$fk = $fk[0];
    }

    my $sql;
    unless ( $self->{tables}{$join_from} )
    {
        $sql .=
            ( $self->{quote_identifiers} ?
              $self->{driver}->quote_identifier( $join_from->name ) :
              $join_from->name );

        $sql .= ' AS ' . $join_from->alias_name;
    }

    $sql .= " $type OUTER JOIN ";

    $sql .= ( $self->{quote_identifiers} ?
              $self->{driver}->quote_identifier( $join_on->name ) :
              $join_on->name );

    $sql .= ' AS ' . $join_on->alias_name;

    $sql .= ' ON ';

    if ( $self->{quote_identifiers} )
    {
        $sql .=
            ( join ' AND ',
              map { $self->{driver}->quote_identifier
                        ( $join_from->alias_name, $_->[0]->name ) .
                    ' = ' .
                    $self->{driver}->quote_identifier
                        ( $join_on->alias_name, $_->[1]->name )
                  } $fk->column_pairs );
    }
    else
    {
        $sql .=
            ( join ' AND ',
              map { $join_from->alias_name . '.' . $_->[0]->name .
                    ' = ' .
                    $join_on->alias_name . '.' .  $_->[1]->name
                  } $fk->column_pairs );
    }

    @{ $self->{tables} }{ $join_from, $join_on } = (1, 1);

    if ($where)
    {
        $sql .= ' AND ';

        # make a clone
        my $sql_maker = bless { %$self }, ref $self;
        $sql_maker->{sql} = '';
        # sharing same ref intentionally
        $sql_maker->{bind} = $self->{bind};
        $sql_maker->{tables} = $self->{tables};

        # lie to Alzabo::Runtime::process_where_clause
        $sql_maker->{last_op} = 'where';

        Alzabo::Runtime::process_where_clause( $sql_maker, $where );

        $sql .= $sql_maker->sql;

        $sql .= ' ';

        $self->{as_id} = $sql_maker->{as_id};
    }

    return $sql;
}

sub where
{
    my $self = shift;

    $self->_assert_last_op( qw( from set ) );

    $self->{sql} .= ' WHERE ';

    $self->{last_op} = 'where';

    $self->condition(@_) if @_;

    return $self;
}

sub having
{
    my $self = shift;

    $self->_assert_last_op( qw( group_by ) );

    $self->{sql} .= ' HAVING ';

    $self->{last_op} = 'having';

    $self->condition(@_) if @_;

    return $self;
}

sub and
{
    my $self = shift;

    $self->_assert_last_op( qw( subgroup_end condition ) );

    return $self->_and_or( 'and', @_ );
}

sub or
{
    my $self = shift;

    $self->_assert_last_op( qw( subgroup_end condition ) );

    return $self->_and_or( 'or', @_ );
}

sub _and_or
{
    my $self = shift;
    my $op = shift;

    $self->{sql} .= " \U$op ";

    $self->{last_op} = $op;

    $self->condition(@_) if @_;

    return $self;
}

sub subgroup_start
{
    my $self = shift;

    $self->_assert_last_op( qw( where having and or subgroup_start ) );

    $self->{sql} .= ' (';
    $self->{subgroup} ||= 0;
    $self->{subgroup}++;

    $self->{last_op} = 'subgroup_start';

    return $self;
}

sub subgroup_end
{
    my $self = shift;

    $self->_assert_last_op( qw( condition subgroup_end ) );

    Alzabo::Exception::SQL->throw( error => "Can't end a subgroup unless one has been started already" )
	unless $self->{subgroup};

    $self->{sql} .= ' )';
    $self->{subgroup}--;

    $self->{last_op} = $self->{subgroup} ? 'subgroup_end' : 'condition';

    return $self;
}

sub condition
{
    my $self = shift;

    validate_pos( @_,
		  { type => OBJECT },
		  { type => SCALAR },
		  { type => UNDEF | SCALAR | OBJECT },
		  ( { type => UNDEF | SCALAR | OBJECT, optional => 1 } ) x (@_ - 3) );

    my $lhs = shift;
    my $comp = uc shift;
    my $rhs = shift;

    my $in_having = $self->{last_op} eq 'having' ? 1 : 0;

    $self->{last_op} = 'condition';

    if ( $lhs->can('table') )
    {
	unless ( $self->{tables}{ $lhs->table } )
	{
	    my $err = 'Cannot use column (';
	    $err .= join '.', $lhs->table->name, $lhs->name;
	    $err .= ") in $self->{type} unless its table is included in the ";
	    $err .= $self->{type} eq 'update' ? 'UPDATE' : 'FROM';
	    $err .= ' clause';
	    Alzabo::Exception::SQL->throw( error => $err );
	}

	$self->{sql} .=
	    ( $self->{quote_identifiers} ?
              $self->{driver}->quote_identifier( $lhs->table->alias_name, $lhs->name ) :
              $lhs->table->alias_name . '.' . $lhs->name );
    }
    elsif ( $lhs->isa('Alzabo::SQLMaker::Function') )
    {
	my $string = $lhs->as_string( $self->{driver}, $self->{quote_identifiers} );

        if ( exists $self->{functions}{$string} &&
             ( ! $in_having || $self->{alias_in_having} ) )
        {
            $self->{sql} .= $self->{functions}{$string};
        }
        else
        {
            $self->{sql} .= $string;
        }
    }
    else
    {
        Alzabo::Exception::SQL->throw
            ( error => "Cannot use " . (ref $lhs) . " object as part of condition" );
    }

    if ( $comp eq 'BETWEEN' )
    {
	Alzabo::Exception::SQL->throw
	    ( error => "The BETWEEN comparison operator requires an additional argument" )
		unless @_ == 1;

	my $rhs2 = shift;

	Alzabo::Exception::SQL->throw
	    ( error => "The BETWEEN comparison operator cannot accept a subselect" )
		if grep { UNIVERSAL::isa( $_, 'Alzabo::SQLMaker' ) } $rhs, $rhs2;

	$self->{sql} .= ' BETWEEN ';
	$self->{sql} .= $self->_rhs($rhs);
	$self->{sql} .= " AND ";
	$self->{sql} .= $self->_rhs($rhs2);

	return;
    }

    if ( $comp eq 'IN' || $comp eq 'NOT IN' )
    {
	$self->{sql} .= " $comp (";
	$self->{sql} .=
	    join ', ', map { ( UNIVERSAL::isa( $_, 'Alzabo::SQLMaker' ) ?
			       '(' . $self->_subselect($_) . ')' :
			       $self->_rhs($_) ) } $rhs, @_;
	$self->{sql} .= ')';

	return;
    }

    Alzabo::Exception::Params->throw
	( error => 'Too many parameters to Alzabo::SQLMaker->condition method' )
	    if @_;

    if ( ! ref $rhs && defined $rhs )
    {
	$self->{sql} .= " $comp ";
	$self->{sql} .= $self->_rhs($rhs);
    }
    elsif ( ! defined $rhs )
    {
	if ( $comp eq '=' )
	{
	    $self->{sql} .= ' IS NULL';
	}
	elsif ( $comp eq '!=' || $comp eq '<>' )
	{
	    $self->{sql} .= ' IS NOT NULL';
	}
	else
	{
	    Alzabo::Exception::SQL->throw
		( error => "Cannot compare a column to a NULL with '$comp'" );
	}
    }
    elsif ( ref $rhs )
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
	    $self->{sql} .= $self->_rhs($rhs);
	}
    }
}

sub _rhs
{
    my $self = shift;
    my $rhs = shift;

    if ( UNIVERSAL::can( $rhs, 'table' ) )
    {
	unless ( $self->{tables}{ $rhs->table } )
	{
	    my $err = 'Cannot use column (';
	    $err .= join '.', $rhs->table->name, $rhs->name;
	    $err .= ") in $self->{type} unless its table is included in the ";
	    $err .= $self->{type} eq 'update' ? 'UPDATE' : 'FROM';
	    $err .= ' clause';
	    Alzabo::Exception::SQL->throw( error => $err );
	}

	return ( $self->{quote_identifiers} ?
                 $self->{driver}->quote_identifier( $rhs->table->alias_name, $rhs->name ) :
                 $rhs->table->alias_name . '.' . $rhs->name );
    }
    else
    {
	return $self->_bind_val($rhs);
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

    $self->_assert_last_op( qw( select from condition group_by ) );

    Alzabo::Exception::SQL->throw
	( error => "Cannot use order by in a '$self->{type}' statement" )
	    unless $self->{type} eq 'select';

    validate_pos( @_, ( { type => SCALAR | OBJECT,
			  callbacks =>
			  { 'column_or_function_or_sort' =>
			    sub { UNIVERSAL::can( $_[0], 'table' ) ||
				  UNIVERSAL::isa( $_[0], 'Alzabo::SQLMaker::Function' ) ||
				  $_[0] =~ /^(?:ASC|DESC)$/i } } }
		      ) x @_ );

    $self->{sql} .= ' ORDER BY ';

    my $x = 0;
    my $last = '';
    foreach my $i (@_)
    {
	if ( UNIVERSAL::can( $i, 'table' ) )
	{
	    unless ( $self->{tables}{ $i->table } )
	    {
		my $err = 'Cannot use column (';
		$err .= join '.', $i->table->name, $i->name;
		$err .= ") in $self->{type} unless its table is included in the FROM clause";
		Alzabo::Exception::SQL->throw( error => $err );
	    }

	    # no comma needed for first column
	    $self->{sql} .= ', ', if $x++;
	    $self->{sql} .=
		( $self->{quote_identifiers} ?
                  $self->{driver}->quote_identifier( $i->table->alias_name, $i->alias_name ) :
                  $i->table->alias_name . '.' . $i->alias_name );

	    $last = 'column';
	}
	elsif ( UNIVERSAL::isa( $i, 'Alzabo::SQLMaker::Function' ) )
	{
	    my $string = $i->as_string( $self->{driver}, $self->{quote_identifiers} );
	    if ( exists $self->{functions}{$string} )
	    {
		$self->{sql} .= ', ', if $x++;
		$self->{sql} .= $self->{functions}{$string};
	    }
	    else
	    {
		$self->{sql} .= ', ', if $x++;
		$self->{sql} .= $string;
	    }
	}
	else
	{
	    Alzabo::Exception::Params->throw
		( error => 'A sort specifier cannot follow another sort specifier in an ORDER BY clause' )
		    if $last eq 'sort';

	    $self->{sql} .= " \U$i";

	    $last = 'sort';
	}
    }

    $self->{last_op} = 'order_by';

    return $self;
}

sub group_by
{
    my $self = shift;

    $self->_assert_last_op( qw( select from condition ) );

    Alzabo::Exception::SQL->throw
	( error => "Cannot use group by in a '$self->{type}' statement" )
	    unless $self->{type} eq 'select';

    validate_pos( @_, ( { can => 'table' } ) x @_ );

    foreach my $c (@_)
    {
	unless ( $self->{tables}{ $c->table } )
	{
	    my $err = 'Cannot use column (';
	    $err .= join '.', $c->table->name, $c->name;
	    $err .= ") in $self->{type} unless its table is included in the FROM clause";
	    Alzabo::Exception::SQL->throw( error => $err );
	}
    }

    $self->{sql} .= ' GROUP BY ';
    $self->{sql} .=
	( join ', ',
	  map { ( $self->{quote_identifiers} ?
                  $self->{driver}->quote_identifier( $_->table->alias_name, $_->alias_name ) :
                  $_->table->alias_name . '.' . $_->alias_name ) }
	  @_ );

    $self->{last_op} = 'group_by';

    return $self;
}

sub insert
{
    my $self = shift;

    $self->{sql} .= 'INSERT ';

    $self->{type} = 'insert';
    $self->{last_op} = 'insert';

    return $self;
}

sub into
{
    my $self = shift;

    $self->_assert_last_op( qw( insert ) );

    validate_pos( @_, { can => 'alias_name' }, ( { can => 'table' } ) x (@_ - 1) );

    my $table = shift;
    $self->{tables} = { $table => 1 };

    foreach my $c (@_)
    {
	unless ( $c->table eq $table )
	{
	    my $err = 'Cannot into column (';
	    $err .= join '.', $c->table->name, $c->name;
	    $err .= ') because its table was not the one specified in the INTO clause';
	    Alzabo::Exception::SQL->throw( error => $err );
	}
    }

    $self->{columns} = [ @_ ? @_ : $table->columns ];

    $self->{sql} .= 'INTO ';

    $self->{sql} .= ( $self->{quote_identifiers} ?
                      $self->{driver}->quote_identifier( $table->name ) :
                      $table->name );

    $self->{sql} .= ' (';

    $self->{sql} .=
	( join ', ',
	  map { ( $self->{quote_identifiers} ?
                  $self->{driver}->quote_identifier( $_->name ) :
                  $_->name ) }
	  @{ $self->{columns} } );

    $self->{sql} .= ') ';

    $self->{last_op} = 'into';

    return $self;
}

sub values
{
    my $self = shift;

    $self->_assert_last_op( qw( into ) );

    validate_pos( @_, ( { type => UNDEF | SCALAR | OBJECT } ) x @_ );

    if ( ref $_[0] && $_[0]->isa('Alzabo::SQLMaker') )
    {
	$self->{sql} = $_[0]->sql;
	push @{ $self->{bind} }, $_[0]->bind;
    }
    else
    {
	my @vals = @_;

	Alzabo::Exception::Params->throw
	    ( error => "'values' method expects key/value pairs of column objects and values'" )
		if !@vals || @vals % 2;

	my %vals = map { ref $_ && $_->can('table') ? $_->name : $_ } @vals;
	foreach my $c ( @vals[ map { $_ * 2 } 0 .. int($#vals/2) ] )
	{
	    Alzabo::Exception::SQL->throw
		( error => $c->name . " column was not specified in the into method call" )
		    unless grep { $c eq $_ } @{ $self->{columns} };
	}

	foreach my $c ( @{ $self->{columns } } )
	{
	    Alzabo::Exception::SQL->throw
		( error => $c->name . " was specified in the into method call but no value was provided" )
		    unless exists $vals{ $c->name };
	}

	$self->{sql} .= 'VALUES (';
	$self->{sql} .= join ', ', ( map { $self->_bind_val($_) }
				     ( map { $vals{ $_->name } }
				       @{ $self->{columns} } ) );
	$self->{sql} .= ')';
    }

    $self->{last_op} = 'values';

    return $self;
}

sub update
{
    my $self = shift;

    validate_pos( @_, { can => 'alias_name' } );

    my $table = shift;

    $self->{sql} = 'UPDATE ';

    $self->{sql} .= ( $self->{quote_identifiers} ?
                      $self->{driver}->quote_identifier( $table->name ) :
                      $table->name );

    $self->{tables} = { $table => 1 };

    $self->{type} = 'update';
    $self->{last_op} = 'update';

    return $self;
}

sub set
{
    my $self = shift;
    my @vals = @_;

    $self->_assert_last_op('update');

    Alzabo::Exception::Params->throw
	( error => "'set' method expects key/value pairs of column objects and values'" )
	    if !@vals || @vals % 2;

    validate_pos( @_, ( { can => 'table' },
			{ type => UNDEF | SCALAR | OBJECT } ) x (@vals / 2) );

    $self->{sql} .= ' SET ';

    my @set;
    my $table = ( keys %{ $self->{tables} } )[0];
    while ( my ($col, $val) = splice @vals, 0, 2 )
    {
	unless ( $table eq $col->table )
	{
	    my $err = 'Cannot set column (';
	    $err .= join '.', $col->table->name, $col->name;
	    $err .= ') unless its table is included in the UPDATE clause';
	    Alzabo::Exception::SQL->throw( error => $err );
	}

	push @set,
	    ( $self->{quote_identifiers} ?
              $self->{driver}->quote_identifier( $col->name ) :
              $col->name ) .
            ' = ' . $self->_bind_val($val);
    }
    $self->{sql} .= join ', ', @set;

    $self->{last_op} = 'set';

    return $self;
}

sub delete
{
    my $self = shift;

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

    validate_pos( @_, { type => UNDEF | SCALAR | OBJECT } );

    unless ( ref $_[0] )
    {
        push @{ $self->{bind} }, $_[0];
        return '?';
    }

    return $_[0]->as_string( $self->{driver}, $self->{quote_identifiers} )
        if UNIVERSAL::isa( $_[0], 'Alzabo::SQLMaker::Function' );

    Alzabo::Exception::Params->throw
        ( error => "Cannot pass a " . (ref $_[0]) . " object to _bind_val" );
}

sub sql
{
    my $self = shift;

    Alzabo::Exception::SQL->throw( error => "SQL contains unbalanced parentheses subgrouping: $self->{sql}" )
	if $self->{subgroup};

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

sub sqlmaker_id
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

sub debug
{
    my $self = shift;
    my $fh = shift;

    print $fh '-' x 75 . "\n";
    print $fh "SQL\n - " . $self->sql . "\n";
    print $fh "Bound values\n";

    foreach my $b ( @{ $self->bind } )
    {
        if ( defined $b )
        {
            if ( length $b > 75 )
            {
                $b = substr( $b, 0, 71 ) . ' ...';
            }
        }
        else
        {
            $b = 'NULL';
        }

        print $fh " - [$b]\n";
    }
}

package Alzabo::SQLMaker::Function;

use Params::Validate qw( :all );
Params::Validate::validation_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

sub new
{
    my $class = shift;
    my %p = @_;

    $p{args} = [] unless defined $p{args};
    $p{quote} ||= [];

    return bless \%p, $class;
}

sub allows_alias { shift->{allows_alias} }

sub as_string
{
    my $self = shift;
    my $driver = shift;
    my $quote = shift;

    my @args;
    foreach ( 0..$#{ $self->{args} } )
    {
	if ( UNIVERSAL::can( $self->{args}[$_], 'table' ) )
	{
	    push @args,
		( $quote ?
                  $driver->quote_identifier( $self->{args}[$_]->table->alias_name,
                                             $self->{args}[$_]->name ) :
                  $self->{args}[$_]->table->alias_name . '.' .
                  $self->{args}[$_]->name );
	    next;
	}
	elsif ( UNIVERSAL::isa( $self->{args}[$_], 'Alzabo::SQLMaker::Function' ) )
	{
	    push @args, $self->{args}[$_]->as_string( $driver, $quote );
	    next;
	}

	# if there are more args than specified in the quote param
	# then this function must allow an unlimited number of
	# arguments, in which case the last value in the quote param
	# is the value that should be used for all of the extra
	# arguments.
	my $i = $_ > $#{ $self->{quote} } ? -1 : $_;
	push @args,
            $self->{quote}[$i] ? $driver->quote( $self->{args}[$_] ) : $self->{args}[$_];
    }

    my $sql = $self->{function};
    $sql =~ s/_/ /g if $self->{has_spaces};

    return $sql if $self->{is_modifier};

    $sql .= '(';

    if ( $self->{format} )
    {
	$sql .= sprintf( $self->{format}, @args );
    }
    else
    {
	$sql .= join ', ', @args;
    }

    $sql .= ')';

    return $sql;
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
parameter for the L<C<Alzabo::SQLMaker-E<gt>new>|"new"> method.

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

There are four entry point methods, L<C<select>|"select (Alzabo::Table
and/or Alzabo::Column objects)">, L<C<insert>|"insert">,
L<C<update>|"update (Alzabo::Table)">, and L<C<delete>|"delete">.
Attempting call any other method without first calling one of these is
an error.

=head2 Entry Points

These methods are called as class methods and return a new object.

=head2 select (C<Alzabo::Table> and/or C<Alzabo::Column> objects)

This begins a select.  The columns to be selected are the column(s)
passed in, and/or the columns of the table(s) passed in as arguments.

=head3 Followed by

L<C<from>|"from (Alzabo::Table object, ...)">

L<C<** function>|"** function (Alzabo::Table object(s) and/or $string(s))">

=head2 insert

=head3 Followed by

L<C<into>|"into (Alzabo::Table object, optional Alzabo::Column objects)">

=head2 update (C<Alzabo::Table>)

=head3 Followed by

L<C<set>|"set (Alzabo::Column object =E<gt> $value, ...)">

=head2 delete

=head3 Followed by

L<C<from>|"from (Alzabo::Table object, ...)">

=head2 Other Methods

All of these methods return the object itself, making it possible to
chain together method calls such as:

 Alzabo::SQLMaker->select($column)->from($table)->where($other_column, '>', 2);

=head2 from (C<Alzabo::Table> object, ...)

The table(s) from which we are selecting data.

=head3 Follows

L<C<select>|"select (Alzabo::Table and/or Alzabo::Column objects)">

L<C<** function>|"** function (Alzabo::Table object(s) and/or $string(s))">

L<C<delete>|"delete">

=head3 Followed by

L<C<where>|"where ( (Alzabo::Column object), $comparison, (Alzabo::Column object, $value, or Alzabo::SQLMaker object), [ see below ] )">

L<C<order_by>|"order_by (Alzabo::Column objects)">

=head3 Throws

L<C<Alzabo::Exception::SQL>|Alzabo::Exceptions>

=head2 where ( (C<Alzabo::Column> object or SQL function), $comparison, (C<Alzabo::Column> object, $value, or C<Alzabo::SQLMaker> object), [ see below ] )

The first parameter must be an C<Alzabo::Column> object or SQL
function.  The second is a comparison operator of some sort, given as
a string.  The third argument can be one of three things.  It can be
an C<Alzabo::Column> object, a value (a number or string), or an
C<Alzabo::SQLMaker> object.  The latter is treated as a subselect.

Values given as parameters will be properly quoted and escaped.

Some comparison operators allow additional parameters.

The C<BETWEEN> comparison operator requires a fourth argument.  This
must be either an C<Alzabo::Column> object or a value.

The C<IN> and <NOT IN> operators allow any number of additional
parameters, which may be C<Alzabo::Column> objects, values, or
C<Alzabo::SQLMaker> objects.

=head3 Follows

L<C<from>|"from (Alzabo::Table object, ...)">

=head3 Followed by

L<C<and>|"and (same as where)">

L<C<or>|"or (same as where)">

L<C<order_by>|"order_by (Alzabo::Column objects)">

=head3 Throws

L<C<Alzabo::Exception::SQL>|Alzabo::Exceptions>

=head2 and (same as C<where>)

=head2 or (same as C<where>)

These methods take the same parameters as the L<C<where>|"where (
(Alzabo::Column object), $comparison, (Alzabo::Column object, $value,
or Alzabo::SQLMaker object), [ see below ] )"> method.  There is
currently no way to group together comparison operators.

=head3 Follows

L<C<where>|"where ( (Alzabo::Column object), $comparison, (Alzabo::Column object, $value, or Alzabo::SQLMaker object), [ see below ] )">

L<C<and>|"and (same as where)">

L<C<or>|"or (same as where)">

=head3 Followed by

L<C<and>|"and (same as where)">

L<C<or>|"or (same as where)">

L<C<order_by>|"order_by (Alzabo::Column objects)">

=head3 Throws

L<C<Alzabo::Exception::SQL>|Alzabo::Exceptions>

=head2 order_by (C<Alzabo::Column> objects)

Adds an C<ORDER BY> clause to your SQL.

=head3 Follows

L<C<from>|"from (Alzabo::Table object, ...)">

L<C<where>|"where ( (Alzabo::Column object), $comparison, (Alzabo::Column object, $value, or Alzabo::SQLMaker object), [ see below ] )">

L<C<and>|"and (same as where)">

L<C<or>|"or (same as where)">

=head3 Followed by

L<C<limit>|"limit ($max, optional $offset)">

=head3 Throws

L<C<Alzabo::Exception::SQL>|Alzabo::Exceptions>

=head2 limit ($max, optional $offset)

Specifies a limit on the number of rows to be returned.  The offset
parameter is optional.

=head3 Follows

L<C<from>|"from (Alzabo::Table object, ...)">

L<C<where>|"where ( (Alzabo::Column object), $comparison, (Alzabo::Column object, $value, or Alzabo::SQLMaker object), [ see below ] )">

L<C<and>|"and (same as where)">

L<C<or>|"or (same as where)">

L<C<order_by>|"order_by (Alzabo::Column objects)">

=head3 Followed by

Nothing.

=head3 Throws

L<C<Alzabo::Exception::SQL>|Alzabo::Exceptions>

=head2 into (C<Alzabo::Table> object, optional C<Alzabo::Column> objects)

Used to specify what table an insert is into.  If column objects are
given then it is expected that values will only be given for that
object.  Otherwise, it assumed that all columns will be specified in
the L<C<values>|"values (Alzabo::Column object =E<gt> $value, ...)">
method.

=head3 Follows

L<C<insert>|"insert">

=head3 Followed by

L<C<values>|"values (Alzabo::Column object =E<gt> $value, ...)">

=head3 Throws

L<C<Alzabo::Exception::SQL>|Alzabo::Exceptions>

=head2 values (C<Alzabo::Column> object => $value, ...)

This method expects to recive an structured like a hash where the keys
are C<Alzabo::Column> objects and the values are the value to be
inserted into that column.

=head3 Follows

L<C<into>|"into (Alzabo::Table object, optional Alzabo::Column objects)">

=head3 Followed by

Nothing.

=head3 Throws

L<C<Alzabo::Exception::SQL>|Alzabo::Exceptions>

=head2 set (C<Alzabo::Column> object => $value, ...)

This method'a parameter are exactly like those given to the
L<C<values>|values ( Alzabo::Column object =E<gt> $value, ... )>
method.

=head3 Follows

L<C<update>|"update (Alzabo::Table)">

=head3 Followed by

L<C<where>|"where ( (Alzabo::Column object), $comparison, (Alzabo::Column object, $value, or Alzabo::SQLMaker object), [ see below ] )">

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

This method may return undef even if the L<C<limit>|"limit ($max,
optional $offset)"> method was called.  Some RDBMS's have special SQL
syntax for C<LIMIT> clauses.  For those that don't support this, the
L<C<Alzabo::Driver>|Alzabo::Driver> module takes a C<limit> parameter.
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
requires only that the L<virtual methods|"Virtual Methods"> listed
below be implemented.

In addition, you may choose to override any of the other methods
listed in L<over-rideable methods|"Over-Rideable Methods">.  For
example, the MySQL subclass override the L<C<_subselect>|"_subselect">
method because MySQL cannot support sub-selects.

=head2 Virtual Methods

=head1 AUTHOR

Dave Rolsky, <dave@urth.org>

=cut
