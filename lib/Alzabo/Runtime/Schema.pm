package Alzabo::Runtime::Schema;

use strict;
use vars qw($VERSION);

use Alzabo::Runtime;

use base qw(Alzabo::Schema);

use fields qw( user password host maintain_integrity );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.9 $ =~ /(\d+)\.(\d+)/;

1;

sub load_from_file
{
    my Alzabo::Runtime::Schema $self = shift;

    $self->_load_from_file(@_);
}

sub _schema_file_type
{
    return 'runtime';
}

sub user
{
    my Alzabo::Runtime::Schema $self = shift;

    return $self->{user};
}

sub password
{
    my Alzabo::Runtime::Schema $self = shift;

    return $self->{password};
}

sub host
{
    my Alzabo::Runtime::Schema $self = shift;

    return $self->{host};
}

sub referential_integrity
{
    my Alzabo::Runtime::Schema $self = shift;

    return defined $self->{maintain_integrity} ? $self->{maintain_integrity} : 0;
}

sub set_user
{
    my Alzabo::Runtime::Schema $self = shift;

    $self->{user} = shift;
}

sub set_password
{
    my Alzabo::Runtime::Schema $self = shift;

    $self->{password} = shift;
}

sub set_host
{
    my Alzabo::Runtime::Schema $self = shift;

    $self->{host} = shift;
}

sub set_referential_integrity
{
    my Alzabo::Runtime::Schema $self = shift;
    my $val = shift;

    $self->{maintain_integrity} = $val if defined $val;
}

sub connect
{
    my Alzabo::Runtime::Schema $self = shift;

    my %p;
    $p{user} = $self->user if $self->user;
    $p{password} = $self->password if $self->password;
    $p{host} = $self->host if $self->host;
    $self->driver->connect( %p,
			    @_ );
}

sub join
{
    my Alzabo::Runtime::Schema $self = shift;
    my %p = @_;

    my $select = $p{select} || $p{tables};

    my $sql = 'SELECT ';
    $sql .= join ', ', map { $_->table->name . '.' . $_->name } map {$_->primary_key} @$select;
    $sql .= ' FROM ';
    $sql .= join ', ', map { $_->name } @{ $p{tables} };
    $sql .= ' WHERE ';

    my @join_fk;
    for (my $x = 0; $x < @{ $p{tables} } - 1; $x++)
    {
	my $cur_t = $p{tables}->[$x];
	my $next_t = $p{tables}->[$x + 1];

	AlzaboException->throw( error => "Table " . $cur_t->name . " doesn't exist in schema" )
	    unless $self->{tables}->EXISTS( $cur_t->name );

	my @fk = $cur_t->foreign_keys_by_table($next_t);
	AlzaboException->throw( error => "The " . $cur_t->name . " table has no foreign keys to the " . $next_t->name . " table" )
	    unless @fk;
	AlzaboException->throw( error => "The " . $cur_t->name . " table has more than 1 foreign key to the " . $next_t->name . " table" )
	    if @fk > 1;

	push @join_fk, @fk;
    }

    $sql .= join ' AND ', ( map { $_->table_from->name . '.' . $_->column_from->name .
				  ' = ' .
				  $_->table_to->name . '.' . $_->column_to->name } @join_fk
			  );
    $sql .= ' AND ';
    my @bind;
    if ( $p{where} )
    {
	while ( my @pair = splice @{ $p{where} }, 0, 2 )
	{
	    $sql .= $pair[0]->table->name . '.' . $pair[0]->name;
	    $sql .= defined $pair[1] ? " = ?" : " IS NULL";
	    push @bind, $pair[1] if defined $pair[1];
	}
    }

    my $statement = $self->driver->statement( sql => $sql,
					      bind => \@bind );

    if (@$select == 1)
    {
	return Alzabo::Runtime::JoinCursor->new( statement => $statement,
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

=head1 DESCRIPTION

This object can only be loaded from a file.  The file is created
whenever a corresponding Alzabo::Create::Schema object is saved.

=head1 METHODS

=over 4

=item * load_from_file

Takes the following parameter:

=item -- name => $schema_name

Loads a schema from a file.  This is the only constructor for this
class.

 AlzaboException - No saved schema of the given name.
 FileSystemException - Can't open, close or stat a file.
 EvalException - Unable to evaluate the contents of a file.

=item * user

Returns the username used by the schema when connecting to the
database.

=item * password

Returns the password used by the schema when connecting to the
database.

=item * host

Returns the host used by the schema when connecting to the database.

=item * referential_integrity

Returns a true/false value indicating whether this schema will attempt
to maintain referential integrity.  Defaults to false.

=item * set_user ($user)

Set the username to use when connecting to the database.

=item * set_password ($password)

Set the password to use when connecting to the database.

=item * set_host ($host)

Set the host to use when connecting to the database.

=item * set_referential_integrity ($boolean)

Sets the value returned by the C<referential_integrity> method.  If
true, then when Alzabo::Runtime::Row objects are deleted or updated,
they will use report this to the Alzabo::Runtime::ForeignKey objects
for the row so that they can take appropriate action.

=item * connect (%params)

Call the Alzabo::Driver C<connect> method for the driver owned by the
schema.  The username, password, and host set for the schema will be
passed to the driver, as will any additional parameters given to this
method.

=item * join

NOTE: This method is currently considered experimental.

Takes the following parameters:

=item -- tables => [ Alzabo::Runtime::Table objects ]

The tables being joined together.

=item -- where => [ Alzabo::Runtime::Column => $value ]  (optional)

This parameter must be an array reference, not a hash reference.  It
specifies the values to be used in the where clause (in addition to
those necessary to create the join).

=item -- select => [ Alzabo::Runtime::Table objects ]  (optional)

This parameter specified which tables you want to get rows back from.
If this parameter is not given, then the tables parameter will be used
instead.

If the select parameter (or tables parameter) specified that more than
one table is desired, then this method will return an
Alzabo::Runtime::JoinCursor object representing the results of the
join.  Otherwise, the method returns an Alzabo::Runtime::RowCursor
object.

The join is done by taking the tables in order and finding a relation
between them.  If any given table pair has more than one relation,
then this method will fail.  The relations, along with the values
given in the optional where clause will then be used to generate the
necessary SQL.  See L<Alzabo::Runtime::JoinCursor> for more
information.

=back

=head1 USER AND PASSWORD INFORMATION

This information is never saved to disk.  This means that if you're
operating in an environment where the schema object is reloaded from
disk every time it is used (as in a CGI program spanning multiple
requests) then you will have to make a new connection every time.  In
a persistent evironment, this is not a problem.  In a mod_perl
environment, you could load the schema and call the C<set_user> and
C<set_password> methods in the server startup file.  Then all the
mod_perl children will inherit the schema with the user and password
already set.  Otherwise you will have to provide it for each request.

You may ask why you have to go to all this trouble to deal with the
user and password information.  The basic reason was that I did not
want to try to come up with a security solution that was secure, easy
to use and configure, and cross-platform compatible.  Rather, I prefer
to let each person decide on a security practice that they feel
comfortable with.

=head1 CAVEATS

=head2 Refential Integrity

If Alzabo is attempting to maintain referential integrity and you are
not using either the Alzabo::ObjectCache or Alzabo::ObjectCacheIPC
module then situations can arise where objects you are holding onto in
memory can get out of sync with the database.  Please see
L<Alzabo::ObjectCache> for more details.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
