package Alzabo::Runtime::Schema;

use strict;
use vars qw($VERSION);

use Alzabo::Runtime;

use Params::Validate qw( :all );
Params::Validate::validation_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

use base qw(Alzabo::Schema);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.42 $ =~ /(\d+)\.(\d+)/;

1;

sub load_from_file
{
    my $self = shift;

    $self->_load_from_file(@_);
}

sub _schema_file_type
{
    return 'runtime';
}

sub user
{
    my $self = shift;

    return $self->{user};
}

sub password
{
    my $self = shift;

    return $self->{password};
}

sub host
{
    my $self = shift;

    return $self->{host};
}

sub referential_integrity
{
    my $self = shift;

    return defined $self->{maintain_integrity} ? $self->{maintain_integrity} : 0;
}

sub set_user
{
    my $self = shift;

    $self->{user} = shift;
}

sub set_password
{
    my $self = shift;

    $self->{password} = shift;
}

sub set_host
{
    my $self = shift;

    $self->{host} = shift;
}

sub set_referential_integrity
{
    my $self = shift;
    my $val = shift;

    $self->{maintain_integrity} = $val if defined $val;
}

sub connect
{
    my $self = shift;

    my %p;
    $p{user} = $self->user if defined $self->user;
    $p{password} = $self->password if defined $self->password;
    $p{host} = $self->host if defined $self->host;
    $self->driver->connect( %p, @_ );
}

sub join
{
    my $self = shift;
    my %p = validate( @_, { tables => { type => ARRAYREF | OBJECT },
			    select => { type => ARRAYREF | OBJECT,
					optional => 1 },
			    where => { type => ARRAYREF,
				       optional => 1 },
			    order_by => { type => ARRAYREF | HASHREF | OBJECT,
					  optional => 1 },
			    limit => { type => SCALAR | ARRAYREF,
				       optional => 1 },
			    distinct => { isa => 'Alzabo::Table',
					  optional => 1 },
			  } );

    $p{tables} = [ $p{tables} ] unless UNIVERSAL::isa($p{tables}, 'ARRAY');

    my @tables;

    if ( UNIVERSAL::isa( $p{tables}->[0], 'ARRAY' ) )
    {
	# flattens the nested structure and produces a unique set of
	# tables
	@tables = values %{ { map { $_ => $_ }
			      map { @$_ } @{ $p{tables} } } };
    }
    else
    {
	@tables = @{ $p{tables} };
    }

    my @select_tables = $p{select} ? ( UNIVERSAL::isa( $p{select}, 'ARRAY' ) ? @{ $p{select} } : $p{select} ) : @tables;

    my @select_cols;
    # If the table has a multi-column primary key we have to jump
    # through hoops later.
    if ( $p{distinct} && $p{distinct}->primary_key == 1 )
    {
	@select_cols = $self->sqlmaker->DISTINCT( $p{distinct}->primary_key );
	foreach (@select_tables)
	{
	    next if $_ eq $p{distinct};
	    push @select_cols, $_->primary_key;
	}

	@select_tables = ( $p{distinct}, grep { $_ ne $p{distinct} } @select_tables );
	delete $p{distinct};
    }
    else
    {
	@select_cols = map { $_->primary_key } @select_tables;
    }

    my $sql = ( $self->sqlmaker->
		select(@select_cols)->
		from(@tables) );

    $self->_join_all_tables( sql => $sql,
			     tables => $p{tables} );

    Alzabo::Runtime::process_where_clause( $sql, $p{where}, 1 ) if exists $p{where};

    Alzabo::Runtime::process_order_by_clause( $sql, $p{order_by} ) if exists $p{order_by};

    $sql->limit( ref $p{limit} ? @{ $p{limit} } : $p{limit} ) if $p{limit};

    my $statement = $self->driver->statement( sql => $sql->sql,
					      bind => $sql->bind );

    if (@select_tables == 1)
    {
	return Alzabo::Runtime::RowCursor->new( statement => $statement,
						table => $select_tables[0],
						distinct => $p{distinct} );
    }
    else
    {
	return Alzabo::Runtime::JoinCursor->new( statement => $statement,
						 tables => \@select_tables,
						 distinct => $p{distinct} );
    }
}

sub left_outer_join
{
    shift->_outer_join( @_, type => 'left' );
}

sub right_outer_join
{
    shift->_outer_join( @_, type => 'right' );
}

sub full_outer_join
{
    shift->_outer_join( @_, type => 'full' );
}

sub _outer_join
{
    my $self = shift;

    my %p = @_;

    my @select = defined $p{tables}->[0] && UNIVERSAL::isa( $p{tables}->[0], 'ARRAY' ) ? @{ shift @{ $p{tables} } } : ( shift @{ $p{tables} }, pop @{ $p{tables} } );

    # This gets flipped again later in the OuterJoinCursor object so
    # the results make sense
    @select = @select[1, 0] if $p{type} eq 'right';

    # Tables for which we are not selecting but which are involved in
    # the join
    my %other_tables;
    foreach ( defined $p{tables}->[0] && UNIVERSAL::isa( $p{tables}->[0], 'ARRAY' ) ? map { @$_ } @{ $p{tables} } : @{ $p{tables} } )
    {
	$other_tables{$_} = $_;
    }
    my @other_tables = values %other_tables;

    my $join_method = $p{type} eq 'full' ? 'full_outer_join' : 'left_outer_join';

    my $sql = ( $self->sqlmaker->
		select( map {$_->primary_key} @select )->
		$join_method( @select, @other_tables ) );

    if (@other_tables)
    {
	$self->_join_all_tables( sql => $sql,
				 tables => $p{tables} );
    }

    Alzabo::Runtime::process_where_clause( $sql, $p{where}, 1 ) if exists $p{where};

    Alzabo::Runtime::process_order_by_clause( $sql, $p{order_by} ) if exists $p{order_by};

    $sql->limit( ref $p{limit} ? @{ $p{limit} } : $p{limit} ) if $p{limit};

    my $statement = $self->driver->statement( sql => $sql->sql,
					      bind => $sql->bind );

    return Alzabo::Runtime::OuterJoinCursor->new( type => $p{type},
						  statement => $statement,
						  tables => \@select );
}

sub function
{
    my $self = shift;
    my %p = @_;

    my $sql = $self->_select_sql(%p);

    my $method = UNIVERSAL::isa( $p{select}, 'ARRAY' ) && @{ $p{select} } > 1 ? 'rows' : 'column';

    return $self->driver->$method( sql => $sql->sql,
				   bind => $sql->bind );
}

sub select
{
    my $self = shift;

    my $sql = $self->_select_sql(@_);

    return $self->driver->statement( sql => $sql->sql,
				     bind => $sql->bind );
}

sub _select_sql
{
    my $self = shift;
    my %p = validate( @_, { select => { type => ARRAYREF | OBJECT,
					optional => 1 },
			    tables => { type => ARRAYREF | OBJECT },
			    where => { type => ARRAYREF,
				       optional => 1 },
			    order_by => { type => ARRAYREF | HASHREF | OBJECT,
					  optional => 1 },
			    group_by => { type => ARRAYREF | HASHREF | OBJECT,
					  optional => 1 },
			    limit => { type => SCALAR | ARRAYREF,
				       optional => 1 },
			  } );

    $p{tables} = [ $p{tables} ] unless UNIVERSAL::isa($p{tables}, 'ARRAY');

    my @tables;

    if ( UNIVERSAL::isa( $p{tables}->[0], 'ARRAY' ) )
    {
	# flattens the nested structure and produces a unique set of
	# tables
	@tables = values %{ { map { $_ => $_ }
			      map { @$_ } @{ $p{tables} } } };
    }
    else
    {
	@tables = @{ $p{tables} };
    }

    my @funcs = UNIVERSAL::isa( $p{select}, 'ARRAY' ) ? @{ $p{select} } : $p{select};

    my $sql = ( $self->sqlmaker->
		select(@funcs)->
		from(@tables) );

    $self->_join_all_tables( sql => $sql,
			     tables => $p{tables} );

    Alzabo::Runtime::process_where_clause( $sql, $p{where}, 1 ) if exists $p{where};

    Alzabo::Runtime::process_order_by_clause( $sql, $p{order_by} ) if exists $p{order_by};

    Alzabo::Runtime::process_group_by_clause( $sql, $p{group_by} ) if exists $p{group_by};

    $sql->limit( ref $p{limit} ? @{ $p{limit} } : $p{limit} ) if $p{limit};

    return $sql;
}

sub _join_all_tables
{
    my $self = shift;
    my %p = @_;

    # A structure like:
    #
    # [ [ $t_1 => $t_2 ],
    #   [ $t_1 => $t_3 ],
    #   [ $t_3 => $t_4 ] ]
    #
    if ( UNIVERSAL::isa( $p{tables}->[0], 'ARRAY' ) )
    {
	my %map;
	my %tables;

	foreach ( @{ $p{tables} } )
	{
	    Alzabo::Exception::Params->throw( error => 'The table map must contain only two tables per array refernce' )
		if @$_ > 2;

	    $self->_join_two_tables( @$_, $p{sql} );

	    # Track the tables we've seen
	    @tables{ $_->[0]->name, $_->[1]->name } = (1, 1);

	    # Track their relationships
	    push @{ $map{ $_->[0]->name } }, $_->[1]->name;
	    push @{ $map{ $_->[1]->name } }, $_->[0]->name;
	}

	my $key = $p{tables}->[0]->[0]->name;
	delete $tables{$key};
	my @t = @{ delete $map{$key} };
	while (my $t = shift @t)
	{
	    delete $tables{$t};
	    push @t, @{ delete $map{$t} } if $map{$t};
	}

	Alzabo::Exception::Logic->throw( error => "The specified table parameter does not connect all the tables involved in the join" )
	    if keys %tables;
    }
    # A structure like:
    #
    # [ $t_1 => $t_2 => $t_3 => $t_4 ]
    #
    else
    {
	for (my $x = 0; $x < @{ $p{tables} } - 1; $x++)
	{
	    my $cur_t = $p{tables}->[$x];
	    my $next_t = $p{tables}->[$x + 1];

	    $self->_join_two_tables( $cur_t, $next_t, $p{sql} );
	}
    }
}

sub _join_two_tables
{
    my $self = shift;
    my ($table_1, $table_2, $sql) = @_;
    my $op =  $sql->last_op eq 'and' || $sql->last_op eq 'condition' ? 'and' : 'where';

    Alzabo::Exception::Logic->throw( error => "Table " . $table_1->name . " doesn't exist in schema" )
	unless $self->{tables}->EXISTS( $table_1->name );

    my @fk = $table_1->foreign_keys_by_table($table_2);

    Alzabo::Exception::Logic->throw( error => "The " . $table_1->name . " table has no foreign keys to the " . $table_2->name . " table" )
	unless @fk;

    Alzabo::Exception::Logic->throw( error => "The " . $table_1->name . " table has more than 1 foreign key to the " . $table_2->name . " table" )
	if @fk > 1;

    foreach my $cp ( $fk[0]->column_pairs )
    {
	$sql->$op( $cp->[0], '=', $cp->[1] );
	$op = 'and';
    }
}


__END__

=head1 NAME

Alzabo::Runtime::Schema - Schema objects

=head1 SYNOPSIS

  use Alzabo::Runtime::Schema qw(some_schema);

  my $schema = Alzabo::Runtime::Schema->load_from_file( name => 'foo' );
  $schema->set_user( $username );
  $schema->set_password( $password );

  $schema->connect;

=head1 DESCRIPTION

This object can only be loaded from a file.  The file is created
whenever a corresponding Alzabo::Create::Schema object is saved.

=head1 INHERITS FROM

C<Alzabo::Schema>

=for pod_merge merged

=head1 METHODS

=head2 load_from_file

Loads a schema from a file.  This is the only constructor for this
class.

=head3 Parameters

=over 4

=item * name => $schema_name

=back

=head3 Returns

An C<Alzabo::Runtime::Schema> object.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=head2 user

=head3 Returns

The username used by the schema when connecting to the database.

=head2 set_user ($user)

Set the username to use when connecting to the database.

=head2 password

=head3 Returns

The password used by the schema when connecting to the database.

=head2 set_password ($password)

Set the password to use when connecting to the database.

=head2 host

=head3 Returns

The host used by the schema when connecting to the database.

=head2 set_host ($host)

Set the host to use when connecting to the database.

=head2 referential_integrity

=head3 Returns

A boolean value indicating whether this schema will attempt to
maintain referential integrity.

=head2 set_referential_integrity ($boolean)

Sets the value returned by the
L<C<referential_integrity>|referential_integrity> method.  If true,
then when L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> objects are
deleted, updated, or inserted, they will report this activity to any
relevant L<C<Alzabo::Runtime::ForeignKey>|Alzabo::Runtime::ForeignKey>
objects for the row, so that the foreign key objects can take
appropriate action.

Defaults to false.

=head2 connect (%params)

Calls the L<C<Alzabo::Driver-E<gt>connect>|Alzabo::Driver/connect>
method for the driver owned by the schema.  The username, password,
and host set for the schema will be passed to the driver, as will any
additional parameters given to this method.  See the
L<C<Alzabo::Driver-E<gt>connect>|Alzabo::Driver/connect> method for
more details.

=head2 join

Joins are done by taking the tables provided in order, and finding a
relation between them.  If any given table pair has more than one
relation, then this method will fail.  The relations, along with the
values given in the optional where clause will then be used to
generate the necessary SQL.  See
L<C<Alzabo::Runtime::JoinCursor>|Alzabo::Runtime::JoinCursor> for more
information.

=head3 Parameters

=over 4

=item * tables => <see below>

This parameter can either be a simple array reference of tables or a
reference to an array containing more arrays, each of which contain
two tables.

If a simple array reference is given, then the order of these tables
is significant when there are more than 2 tables.  Alzabo expects to
find relationships between tables 1 & 2, 2 & 3, 3 & 4, etc.

For example, given:

  tables => [ $table_A, $table_B, $table_C ]

Alzabo would expect that table A has a relationship to table B, which
in turn has a relationship to table C.

If you need to specify a more complicated set of relationships, this
can be done with a slightly more complicated data structure, which
looks like this:

  tables => [ [ $table_A, $table_B ],
              [ $table_A, $table_C ],
              [ $table_C, $table_D ],
              [ $table_C, $table_E ] ]

This is fairly self explanatory in that each pair of tables describes
a pair of tables between which Alzabo should expect to find a
relationship.  This allows for the construction of arbitrarily complex
join clauses.

If the latter method of specifying tables is used and no C<select>
parameter is provided, then order of the rows returned from calling
C<next> on the cursor is not guaranteed.  In other words, the array
that the cursor returns will contain a row from each table involved in
the join, but the which row belongs to which table cannot be
determined except by examining each row in turn.  The order will be
the same every time C<next> is called, however.

=item * select => C<Alzabo::Runtime::Table> object or objects (optional)

This parameter specifies from which tables you would like rows
returned.  If this parameter is not given, then the tables parameter
will be used instead.

This can be either a single table or an array reference of table
objects.

=item * distinct => C<Alzabo::Runtime::Table> object (optional)

If this parameter is given, it indicates that results from the join
should never repeat rows for the given table.  This is useful if your
join contains multiple tables but you are only interested in rows from
some of them.

If you are expecting rows from multiple tables, then it is important
that this parameter be set to the table that would have the least
repeated rows.  Otherwise, you will lose information.  For example, if
a join would return the following rows:

  A        B
 ---      ---
  1        1
  1        1
  1        2
  2        2
  2        3
  2        3
  3        4
  3        4
  3        5

etc.

If you set A as distinct, it is possible that you could entirely miss
certain relevant rows from B.

=item * where

See the L<documentation on where clauses for the
Alzabo::Runtime::Table class|Alzabo::Runtime::Table/Common
Parameters>.

=item * order_by

See the L<documentation on order by clauses for the
Alzabo::Runtime::Table class|Alzabo::Runtime::Table/Common
Parameters>.

=item * limit

See the L<documentation on limit clauses for the
Alzabo::Runtime::Table class|Alzabo::Runtime::Table/Common
Parameters>.

=back

=head3 Returns

If the C<select> parameter (or C<tables> parameter) specified that
more than one table is desired, then this method will return an
L<C<Alzabo::Runtime::JoinCursor>|Alzabo::Runtime::JoinCursor> object
representing the results of the join.  Otherwise, the method returns
an L<C<Alzabo::Runtime::RowCursor>|Alzabo::Runtime::RowCursor> object.

=head3 Throws

L<C<Alzabo::Exception::Logic>|Alzabo::Exceptions>

=head2 left_outer_join

=head2 right_outer_join

Joins are done by taking the tables provided, in order, and finding a
relation between them, excluding the last table given.  If any given
table pair has more than one relation, then this method will fail.
The relations, along with the values given in the optional where
clause will then be used to generate the necessary SQL.  See
L<C<Alzabo::Runtime::OuterJoinCursor>|Alzabo::Runtime::OuterJoinCursor>
for more information.

=head3 Parameters

=over 4

=item * tables

See the L<documentation on the table parameter for the join
method|Alzabo::Runtime::Schema/join E<lt>see belowE<gt>>.

If you pass a simple array reference of tables for this parameter,
then the outer join is done between the first and last table given.

If you pass a reference to an array of array references, then the
outer join will be between the first pair of tables.

=item * where

See the L<documentation on where clauses for the
Alzabo::Runtime::Table class|Alzabo::Runtime::Table/Common
Parameters>.

=item * order_by

See the L<documentation on order by clauses for the
Alzabo::Runtime::Table class|Alzabo::Runtime::Table/Common
Parameters>.

=item * limit

See the L<documentation on limit clauses for the
Alzabo::Runtime::Table class|Alzabo::Runtime::Table/Common
Parameters>.

=back

=head3 Returns

An
L<C<Alzabo::Runtime::OuterJoinCursor>|Alzabo::Runtime::OuterJoinCursor>
object.  representing the results of the join.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=head2 function/select

These two methods differ only in their return values.

=head3 Parameters

=over 4

=item * select => $function or [ SQL functions and/or C<Alzabo::Column> objects ]

If you pass an array reference for this parameter, it may contain
either SQL functions or column objects.  For example:

  $schema->function( select => [ $table->column('name'), LENGTH( $table->column('name') ) ] );

=item * tables => <see below>

See the L<documentation on the tables parameter for the join
method|Alzabo::Runtime::Schema/join E<lt>see belowE<gt>>.

=item * where

See the L<documentation on where clauses for the
Alzabo::Runtime::Table class|Alzabo::Runtime::Table/Common
Parameters>.

=item * order_by

See the L<documentation on order by clauses for the
Alzabo::Runtime::Table class|Alzabo::Runtime::Table/Common
Parameters>.

=item * group_by

See the L<documentation on group by clauses for the
Alzabo::Runtime::Table class|Alzabo::Runtime::Table/Common
Parameters>.

=item * limit

See the L<documentation on limit clauses for the
Alzabo::Runtime::Table class|Alzabo::Runtime::Table/Common
Parameters>.

=back

This method is used to call arbitrary SQL functions such as 'AVG' or
'MAX'.  The function (or functions) should be the return values from
the functions exported by the SQLMaker subclass that you are using.
Please see L<Using SQL functions|Alzabo/Using SQL functions> for more
details.

=head3 Returns

=head4 function

The return value of this method is highly context sensitive.

If you only requested a single function ( DISTINCT(foo) ), then it
returns the first value in scalar context and all the values in list
context.

If you requested multiple functions ( AVG(foo), MAX(foo) ) then it
returns a single array reference (the first row of values) in scalar
context and a list of array references in list context.

=head4 select

This method always returns a new
L<C<Alzabo::DriverStatement>|Alzabo::Driver/Alzabo::DriverStatement>
object containing the results of the query.

=for pod_merge name

=for pod_merge tables

=for pod_merge table

=for pod_merge has_table

=for pod_merge start_transaction

=for pod_merge rollback

=for pod_merge finish_transaction

=for pod_merge run_in_transaction ( sub { code... } )

=for pod_merge driver

=for pod_merge rules

=for pod_merge sqlmaker

=head1 USER AND PASSWORD INFORMATION

This information is never saved to disk.  This means that if you're
operating in an environment where the schema object is reloaded from
disk every time it is used, such as a CGI program spanning multiple
requests, then you will have to make a new connection every time.  In
a persistent environment, this is not a problem.  In a mod_perl
environment, you could load the schema and call the
L<C<set_user>|Alzabo::Runtime::Schema/set_user ($user)> and
L<C<set_password>|Alzabo::Runtime::Schema/set_password ($password)>
methods in the server startup file.  Then all the mod_perl children
will inherit the schema with the user and password already set.
Otherwise you will have to provide it for each request.

You may ask why you have to go to all this trouble to deal with the
user and password information.  The basic reason was that I did not
feel I could come up with a solution to this problem that was secure,
easy to configure and use, and cross-platform compatible.  Rather, I
think it is best to let each user decide on a security practice with
which they feel comfortable.  If anybody does come up with such a
scheme, then code submissions are more than welcome.

=head1 CAVEATS

=head2 Refential Integrity

If Alzabo is attempting to maintain referential integrity and you are
not using either the L<C<Alzabo::ObjectCache>|Alzabo::ObjectCache> or
L<C<Alzabo::ObjectCacheIPC>|Alzabo::ObjectCacheIPC> module, then
situations can arise where objects you are holding onto in memory can
get out of sync with the database and you will not know this.  If you
are using one of the cache modules then attempts to access data from
an expired or deleted object will throw an exception, allowing you to
try again (if it is expired) or give up (if it is deleted).  Please
see L<C<Alzabo::ObjectCache>|Alzabo::ObjectCache> for more details.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
