package Alzabo::Runtime::Schema;

use strict;
use vars qw($VERSION);

use Alzabo::Runtime;

use base qw(Alzabo::Schema);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.28 $ =~ /(\d+)\.(\d+)/;

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
    my %p = @_;

    my $select = $p{select} || $p{tables};
    $select = [ $select ] unless UNIVERSAL::isa($select, 'ARRAY');

    $p{tables} = [ $p{tables} ] unless UNIVERSAL::isa($p{tables}, 'ARRAY');

    my $sql = ( $self->sqlmaker->
		select( map {$_->primary_key} @$select )->
		from( @{ $p{tables} } ) );

    my $y = 0;
    for (my $x = 0; $x < @{ $p{tables} } - 1; $x++)
    {
	my $cur_t = $p{tables}->[$x];
	my $next_t = $p{tables}->[$x + 1];

	Alzabo::Exception::Params->throw( error => "Table " . $cur_t->name . " doesn't exist in schema" )
	    unless $self->{tables}->EXISTS( $cur_t->name );

	my @fk = $cur_t->foreign_keys_by_table($next_t);

	Alzabo::Exception::Params->throw( error => "The " . $cur_t->name . " table has no foreign keys to the " . $next_t->name . " table" )
	    unless @fk;

	Alzabo::Exception::Params->throw( error => "The " . $cur_t->name . " table has more than 1 foreign key to the " . $next_t->name . " table" )
	    if @fk > 1;

	foreach my $cp ( $fk[0]->column_pairs )
	{
	    my $op = $y++ ? 'and' : 'where';
	    $sql->$op( $cp->[0], '=', $cp->[1] );
	}
    }

    Alzabo::Runtime::process_where_clause( $sql, $p{where}, 1 ) if exists $p{where};

    if ( $p{limit} )
    {
	$sql->limit( ref $p{limit} ? @{ $p{limit} } : $p{limit} );
    }

    if ( exists $p{order_by} )
    {
    }

    my $statement = $self->driver->statement( sql => $sql->sql,
					      bind => $sql->bind );

    if (@$select == 1)
    {
	return Alzabo::Runtime::RowCursor->new( statement => $statement,
						table => $select->[0] );
    }
    else
    {
	return Alzabo::Runtime::JoinCursor->new( statement => $statement,
						 tables => $select );
    }
}

sub outer_join
{
    my $self = shift;

    my %p = @_;

    my $select = $p{select} || $p{tables};

    $p{tables} = [ $p{tables} ] unless UNIVERSAL::isa($p{tables}, 'ARRAY');

    my $sql = ( $self->sqlmaker->
		select( map {$_->primary_key} @$select )->
		from( @{ $p{tables} } )->
		outer_join( @{ $p{tables} }[0,1] ) );


    if ( @{ $p{tables} } > 2 )
    {
	my $y = 0;
	for (my $x = 0; $x < @{ $p{tables} } - 1; $x++)
	{
	    my $cur_t = $p{tables}->[$x];
	    my $next_t = $p{tables}->[$x + 1];

	    Alzabo::Exception::Params->throw( error => "Table " . $cur_t->name . " doesn't exist in schema" )
		    unless $self->{tables}->EXISTS( $cur_t->name );

	    my @fk = $cur_t->foreign_keys_by_table($next_t);

	    Alzabo::Exception::Params->throw( error => "The " . $cur_t->name . " table has no foreign keys to the " . $next_t->name . " table" )
		    unless @fk;

	    Alzabo::Exception::Params->throw( error => "The " . $cur_t->name . " table has more than 1 foreign key to the " . $next_t->name . " table" )
		    if @fk > 1;

	    foreach my $cp ( $fk[0]->column_pairs )
	    {
		my $op = $y++ ? 'and' : 'where';
		$sql->$op( $cp->[0], '=', $cp->[1] );
	    }
	}
    }

    Alzabo::Runtime::process_where_clause( $sql, $p{where}, 1 ) if exists $p{where};

    Alzabo::Runtime::process_order_by_clause( $sql, $p{order_by} ) if exists $p{order_by};

    if ( $p{limit} )
    {
	$sql->limit( ref $p{limit} ? @{ $p{limit} } : $p{limit} );
    }

    my $statement = $self->driver->statement( sql => $sql->sql,
					      bind => $sql->bind );

    if (@$select == 1)
    {
	return Alzabo::Runtime::RowCursor->new( statement => $statement,
						table => $select->[0] );
    }
    else
    {
	return Alzabo::Runtime::JoinCursor->new( statement => $statement,
						 tables => $select );
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

Join tables is done by taking the tables provided, in order, and
finding a relation between them.  If any given table pair has more
than one relation, then this method will fail.  The relations, along
with the values given in the optional where clause will then be used
to generate the necessary SQL.  See
L<C<Alzabo::Runtime::JoinCursor>|Alzabo::Runtime::JoinCursor> for more
information.

NOTE: This method is currently considered experimental.

=head3 Parameters

=over 4

=item * tables => C<Alzabo::Runtime::Table> object or objects

The tables being joined together.  The order of these tables is
significant if there are more than 2 tables, as we expect to find
relationships between tables 1 & 2, 2 & 3, 3 & 4, etc.

This can be either a single table or an array reference of table
objects.

=item * select => C<Alzabo::Runtime::Table> object or objects (optional)

This parameter specifies from which tables you would like rows
returned.  If this parameter is not given, then the tables parameter
will be used instead.

This can be either a single table or an array reference of table
objects.

=item * where

See the L<documentation on where clauses for the
Alzabo::Runtime::Table class|Alzabo::Runtime::Table/rows_where>.

=item * order_by

See the L<documentation on order by clauses for the
Alzabo::Runtime::Table class|Alzabo::Runtime::Table/Common Parameters>.

=item * limit

See the L<documentation on limit clauses for the
Alzabo::Runtime::Table class|Alzabo::Runtime::Table/Common Parameters>.

=back

=head3 Returns

If the C<select> parameter (or C<tables> parameter) specified that
more than one table is desired, then this method will return an
L<C<Alzabo::Runtime::JoinCursor>|Alzabo::Runtime::JoinCursor> object
representing the results of the join.  Otherwise, the method returns
an L<C<Alzabo::Runtime::RowCursor>|Alzabo::Runtime::RowCursor> object.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=for pod_merge name

=for pod_merge tables

=for pod_merge table

=for pod_merge driver

=head1 USER AND PASSWORD INFORMATION

This information is never saved to disk.  This means that if you're
operating in an environment where the schema object is reloaded from
disk every time it is used, such as a CGI program spanning multiple
requests, then you will have to make a new connection every time.  In
a persistent evironment, this is not a problem.  In a mod_perl
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
