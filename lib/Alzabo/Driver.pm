package Alzabo::Driver;

use strict;
use vars qw($VERSION);

use Alzabo::Exceptions;

use Class::Factory::Util;
use DBI;
use Params::Validate qw( :all );
Params::Validate::validation_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.56 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    shift;
    my %p = @_;

    eval "use Alzabo::Driver::$p{rdbms}";
    Alzabo::Exception::Eval->throw( error => $@ ) if $@;

    my $self = "Alzabo::Driver::$p{rdbms}"->new(@_);

    $self->{schema} = $p{schema};

    return $self;
}

sub available
{
    return Class::Factory::Util::subclasses(__PACKAGE__);
}

sub quote
{
    my $self = shift;

    return $self->{dbh}->quote(@_);
}

sub rows
{
    my $self = shift;

    my %p = @_;

    my $sth = $self->_prepare_and_execute(%p);

    my @data;
    eval
    {
	my @row;
	$sth->bind_columns( \ (@row[ 0..$#{ $sth->{NAME} } ] ) );

	push @data, [@row] while $sth->fetch;

	$sth->finish;
    };
    if ($@)
    {
	my @bind = exists $p{bind} ? ( ref $p{bind} ? $p{bind} : [$p{bind}] ) : ();
	Alzabo::Exception::Driver->throw( error => $@,
					  sql => $p{sql},
					  bind => \@bind );
    }

    return wantarray ? @data : $data[0];
}

sub rows_hashref
{
    my $self = shift;
    my %p = @_;

    my $sth = $self->_prepare_and_execute(%p);

    my @data;

    eval
    {
	my %hash;
	$sth->bind_columns( \ ( @hash{ @{ $sth->{NAME_uc} } } ) );

	push @data, {%hash} while $sth->fetch;

	$sth->finish;
    };
    if ($@)
    {
	my @bind = exists $p{bind} ? ( ref $p{bind} ? $p{bind} : [$p{bind}] ) : ();
	Alzabo::Exception::Driver->throw( error => $@,
					  sql => $p{sql},
					  bind => \@bind );
    }

    return @data;
}

sub one_row
{
    my $self = shift;
    my %p = @_;

    my $sth = $self->_prepare_and_execute(%p);

    my @row;
    eval
    {
	@row = $sth->fetchrow_array;
	$sth->finish;
    };
    if ($@)
    {
	my @bind = exists $p{bind} ? ( ref $p{bind} ? $p{bind} : [$p{bind}] ) : ();
	Alzabo::Exception::Driver->throw( error => $@,
					  sql => $p{sql},
					  bind => \@bind );
    }

    return wantarray ? @row : $row[0];
}

sub one_row_hash
{
    my $self = shift;
    my %p = @_;

    my $sth = $self->_prepare_and_execute(%p);

    my %hash;
    eval
    {
	my @row = $sth->fetchrow_array;
	@hash{ @{ $sth->{NAME_uc} } } = @row if @row;
	$sth->finish;
    };
    if ($@)
    {
	my @bind = exists $p{bind} ? ( ref $p{bind} ? $p{bind} : [$p{bind}] ) : ();
	Alzabo::Exception::Driver->throw( error => $@,
					  sql => $p{sql},
					  bind => \@bind );
    }

    return %hash;
}

sub column
{
    my $self = shift;
    my %p = @_;

    my $sth = $self->_prepare_and_execute(%p);

    my @data;
    eval
    {
	my @row;
	$sth->bind_columns( \ (@row[ 0..$#{ $sth->{NAME} } ] ) );
	push @data, $row[0] while ($sth->fetch);
	$sth->finish;
    };
    if ($@)
    {
	my @bind = exists $p{bind} ? ( ref $p{bind} ? $p{bind} : [$p{bind}] ) : ();
	Alzabo::Exception::Driver->throw( error => $@,
					  sql => $p{sql},
					  bind => \@bind );
    }

    return wantarray ? @data : $data[0];
}

sub _prepare_and_execute
{
    my $self = shift;

    validate( @_, { sql => { type => SCALAR },
		    bind => { type => UNDEF | SCALAR | ARRAYREF,
			      optional => 1 } } );
    my %p = @_;

    Alzabo::Exception::Driver->throw( error => "Attempt to access the database without database handle.  Was ->connect called?" )
	unless $self->{dbh};

    my @bind = exists $p{bind} ? ( ref $p{bind} ? @{ $p{bind} } : $p{bind} ) : ();

    my $sth;
    eval
    {
	$sth = $self->{dbh}->prepare( $p{sql} );
	$sth->execute(@bind);
    };
    if ($@)
    {
	Alzabo::Exception::Driver->throw( error => $@,
					  sql => $p{sql},
					  bind => \@bind );
    }

    return $sth;
}

sub do
{
    my $self = shift;
    my %p = @_;

    my $sth = $self->_prepare_and_execute(%p);

    my $rows;
    eval
    {
	$rows = $sth->rows;
	$sth->finish;
    };
    if ($@)
    {
	my @bind = exists $p{bind} ? ( ref $p{bind} ? $p{bind} : [$p{bind}] ) : ();
	Alzabo::Exception::Driver->throw( error => $@,
					  sql => $p{sql},
					  bind => \@bind );
    }

    return $rows;
}

sub tables
{
    my $self = shift;

    my @t = eval {  $self->{dbh}->tables; };
    Alzabo::Exception::Driver->throw( error => $@ ) if $@;

    return @t;
}

sub schemas
{
    my $self = shift;

    return map { /dbi:\w+:(\w+)/i; defined $1 ? $1 : () } DBI->data_sources( $self->dbi_driver_name );
}

sub statement
{
    my $self = shift;

    return Alzabo::DriverStatement->new( dbh => $self->{dbh},
					 @_ );
}

sub func
{
    my $self = shift;

    my @r;
    eval
    {
	if (wantarray)
	{
	    @r = $self->{dbh}->func(@_);
	    return @r;
	}
	else
	{
	    $r[0] = $self->{dbh}->func(@_);
	    return $r[0];
	}
    };
    Alzabo::Exception::Driver->throw( error => $@ ) if $@;
}

sub DESTROY
{
    my $self = shift;
    $self->disconnect;
}

sub disconnect
{
    my $self = shift;
    $self->{dbh}->disconnect if $self->{dbh};
    delete $self->{dbh};
}

sub handle
{
    my $self = shift;

    if (@_)
    {
	validate_pos( @_, { isa => 'DBI::db' } );
	$self->{dbh} = shift;
    }

    return $self->{dbh};
}

sub connect
{
    shift()->_virtual;
}

sub create_database
{
    shift()->_virtual;
}

sub drop_database
{
    shift()->_virtual;
}

sub next_sequence_number
{
    shift()->_virtual;
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

    $self->{tran_count} = undef;

    eval { $self->{dbh}->rollback unless $self->{dbh}->{AutoCommit} };

    Alzabo::Exception::Driver->throw( error => $@ ) if $@;

    $self->{dbh}->{AutoCommit} = 1;
}

sub finish_transaction
{
    my $self = shift;

    my $callee = (caller(1))[3];

    # More commits than begin_tran.  Not correct.
    if ( defined $self->{tran_count} )
    {
	$self->{tran_count}--;
    }
    else
    {
	my $callee = (caller(1))[3];
	warn "$callee called finish_transaction without corresponding start_transaction call\n";
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

sub get_last_id
{
    shift()->_virtual;
}

sub driver_id
{
    shift()->_virtual;
}

sub _virtual
{
    my $self = shift;

    my $sub = (caller(1))[3];
    Alzabo::Exception::VirtualMethod->throw( error =>
					     "$sub is a virtual method and must be subclassed in " . ref $self );
}

package Alzabo::DriverStatement;

use strict;
use vars qw($VERSION);

use Alzabo::Exceptions;

use DBI;

use Params::Validate qw( :all );
Params::Validate::validation_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

$VERSION = '0.1';

1;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    validate( @_, { dbh   => { can => 'prepare' },
		    sql   => { type => SCALAR },
		    bind  => { type => SCALAR | ARRAYREF,
			       optional => 1 },
		    limit => { type => UNDEF | ARRAYREF,
			       optional => 1 } } );
    my %p = @_;

    my $self = bless {}, $class;

    $self->{limit} = $p{limit} ? $p{limit}[0] : 0;
    $self->{offset} = $p{limit} && $p{limit}[1] ? $p{limit}[1] : 0;
    $self->{rows_fetched} = 0;

    $self->{dbh} = $p{dbh};

    $self->{sql} = $p{sql};
    eval
    {
	$self->{sth} = $self->{dbh}->prepare( $p{sql} );

	$self->{bind} = exists $p{bind} ? ( ref $p{bind} ? $p{bind} : [ $p{bind} ] ) : [];
	$self->{sth}->execute( @{ $self->{bind} } );
    };

    Alzabo::Exception::Driver->throw( error => $@,
				      sql => $self->{sql},
				      bind => $self->{bind} ) if $@;

    return $self;
}

sub execute
{
    my $self = shift;

    $self->{bind} = [@_];
    eval
    {
	$self->{sth}->finish if $self->{sth}->{Active};
	$self->{rows_fetched} = 0;
	$self->{sth}->execute(@_);
    };
    Alzabo::Exception::Driver->throw( error => $@,
				      sql => $self->{sql},
				      bind => $self->{bind} ) if $@;
}

sub next
{
    my $self = shift;

    return unless $self->{sth}->{Active};

    my @row;
    my $active;
    eval
    {
	$self->{sth}->bind_columns( \ (@row[ 0..$#{ $self->{sth}->{NAME} } ] ) );
	do
	{
	    $active = $self->{sth}->fetch;
	} while ( $active && $self->{rows_fetched}++ < $self->{offset} );

	$self->{sth}->finish if $self->{rows_fetched} == $self->{offset} + $self->{limit};
    };
    Alzabo::Exception::Driver->throw( error => $@,
				      sql => $self->{sql},
				      bind => $self->{bind} ) if $@;

    return unless $active;

    return wantarray ? @row : $row[0];
}

sub next_hash
{
    my $self = shift;

    return unless $self->{sth}->{Active};

    my %hash;
    my $active;
    eval
    {
	$self->{sth}->bind_columns( \ ( @hash{ @{ $self->{sth}->{NAME_lc} } } ) );
	do
	{
	    $active = $self->{sth}->fetch;
	} while ( $active && $self->{rows_fetched}++ < $self->{offset} );

	$self->{sth}->finish if $self->{rows_fetched} == $self->{offset} + $self->{limit};
    };
    Alzabo::Exception::Driver->throw( error => $@,
				      sql => $self->{sql},
				      bind => $self->{bind} ) if $@;

    return unless $active;

    return %hash;
}

sub all_rows
{
    my $self = shift;

    my @rows;

    while (my @row = $self->next)
    {
	push @rows, @row > 1 ? \@row : $row[0];
    }

    return @rows;
}

sub all_rows_hash
{
    my $self = shift;

    my @rows;

    while (my %h = $self->next_hash)
    {
	push @rows, \%h;
    }

    return @rows;
}

sub bind
{
    my $self = shift;

    return @{ $self->{bind} };
}

sub DESTROY
{
    my $self = shift;

    eval { $self->{sth}->finish if $self->{sth}; };
    Alzabo::Exception::Driver->throw( error => $@ ) if $@;
}

__END__

=head1 NAME

Alzabo::Driver - Alzabo base class for RDBMS drivers

=head1 SYNOPSIS

  use Alzabo::Driver;

  my $driver = Alzabo::Driver->new( rdbms => 'MySQL',
                                    schema => $schema );

=head1 DESCRIPTION

This is the base class for all Alzabo::Driver modules.  To instantiate
a driver call this class's C<new> method.  See L<SUBCLASSING
Alzabo::Driver> for information on how to make a driver for the RDBMS
of your choice.

This class throws several, exceptions, one of which,
Alzabo::Exception::Driver, has additional methods not present in other
exception classes.  See L<Alzabo::Exception::Driver METHODS> for a
description of these methods.

=head1 METHODS

=head2 available

=head3 Returns

A list of names representing the available C<Alzabo::Driver>
subclasses.  Any one of these names would be appropriate as the
C<rdbms> parameter for the
L<C<Alzabo::Driver-E<gt>new>|Alzabo::Driver/new> method.

=head2 new

=head3 Parameters

=over 4

=item * rdbms => $rdbms_name

The name of the RDBMS being used.

=item * schema => C<Alzabo::Schema> object

=back

=head3 Returns

A new C<Alzabo::Driver> object of the appropriate subclass.

=head3 Throws

L<C<Alzabo::Exception::Eval>|Alzabo::Exceptions>

=head2 tables

=head3 Returns

A list of strings containing the names of the tables in the database.
See the C<DBI> documentation of the C<DBI-E<gt>tables> method for more
details.

=head3 Throws

L<C<Alzabo::Exception::Driver>|Alzabo::Exceptions>

=head2 handle ($optional_dbh)

=head3 Parameters

This method takes one optional parameter, a connected DBI handle.  If
this is given, then this handle is the new handle for the driver.

=head3 Returns

The active database handle.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=head2 Data Retrieval methods

Some of these methods return lists of data (the
L<C<rows>|Alzabo::Driver/rows>,
L<C<rows_hashref>|Alzabo::Driver/rows_hashref>, and
L<C<column>|Alzabo::Driver/column> methods).  With large result sets,
this can use a lot memory as these lists are created in memory before
being returned to the caller.  To avoid this, it may be desirable to
use the functionality provided by the
L<C<Alzabo::DriverStatement>|Alzabo::DriverStatement> class, which
allows you to fetch results one row at a time.

=head3 Parameters (for all methods below)

=over 4

=item * sql => $sql_string

=item * bind => $bind_value or \@bind_values

=item * limit => [ $max, optional $offset ] (optional)

C<$offset> defaults to 0.

This parameters has no effect for the methods that return only one
row.  For the others, it causes the drivers to skip C<$offset> rows
and then return only C<$max> rows.  This is useful if the RDBMS being
used does not support C<LIMIT> clauses.

=back

=head2 rows

=head3 Returns

An array of array references containing the data requested.

=head2 rows_hashref

=head3 Returns

An array of hash references containing the data requested.  The hash
reference keys are the columns being selected.  All the key names are
in uppercase.

=head2 one_row

=head3 Returns

An array or scalar containing the data returned, depending on context.

=head2 one_row_hash

=head3 Returns

A hash containing the data requested.  The hash keys are the columns
being selected.  All the key names are in uppercase.

=head2 column

=head3 Returns

An array containing the values for the first column of each row
returned.

=head2 do

Use this for non-SELECT SQL statements.

=head3 Returns

The number of rows affected.

=head3 Throws

L<C<Alzabo::Exception::Driver>|Alzabo::Exceptions>

=head2 statement

=head3 Parameters

=over 4

=item * limit => [ $max, optional $offset ] (optional)

=back

C<$offset> defaults to 0.

=head3 Returns

A new L<C<Alzabo::DriverStatement>|Alzabo::DriverStatement> handle,
ready to return data via the
L<C<Alzabo::DriverStatement-E<gt>next>|Alzabo::DriverStatement/next>
or
L<C<Alzabo::DriverStatement-E<gt>next_hash>|Alzabo::DriverStatement/next_hash>
methods.

=head3 Throws

L<C<Alzabo::Exception::Driver>|Alzabo::Exceptions>

=head1 Alzabo::DriverStatement

This class is a wrapper around C<DBI>'s statement handles.  It finishes
automatically as appropriate so the end user does need not worry about
doing this.

=head2 next

Use this method in a while loop to fetch all the data from a
statement.

=head3 Returns

An array containing the next row of data for statement or an empty
list if no more data is available.

=head3 Throws

L<C<Alzabo::Exception::Driver>|Alzabo::Exceptions>

=head2 next_hash

=head3 Returns

A hash containing the next row of data for statement or an empty list
if no more data is available.  All the keys of the hash will be
lowercased.

=head3 Throws

L<C<Alzabo::Exception::Driver>|Alzabo::Exceptions>

=head2 all_rows

=head3 Returns

If the select for which this statement is cursor was for a single
column (or aggregate value), then method returns an array containing
each B<remaining> value from the database.

Otherwise, it returns an array of array references, each one
containing a returned row from the database.

=head3 Throws

L<C<Alzabo::Exception::Driver>|Alzabo::Exceptions>

=head2 all_rows_hash

=head3 Returns

An array of hashes, each hash representing a single row returned from
the database.  The hash keys are all in lowercase.

=head3 Throws

L<C<Alzabo::Exception::Driver>|Alzabo::Exceptions>

=head2 execute (@bind_values)

Executes the associated statement handle with the given bound
parameters.  If the statement handle is still active (it was
previously executed and has more data left) then its C<finish> method
will be called first.

=head3 Throws

L<C<Alzabo::Exception::Driver>|Alzabo::Exceptions>

=head1 Alzabo::Exception::Driver METHODS

In addition to the methods inherited from
L<C<Exception::Class::Base>|Exception::Class::Base>, objects in this
class also contain several methods specific to this subclass.

=head2 sql

=head3 Returns

The SQL statement in use at the time the error occurred, if any.

=head2 bind

=head3 Returns

A list of the the bound parameters for the SQL statement, if any.

=head1 SUBCLASSING Alzabo::Driver

To create a subclass of C<Alzabo::Driver> for your particular RDBMS is
fairly simple.  First of all, there must be a C<DBD::*> driver for it,
as C<Alzabo::Driver> is built on top of C<DBI>.

Here's a sample header to the module using a fictional RDBMS called FooDB:

 package Alzabo::Driver::FooDB;

 use strict;
 use vars qw($VERSION);

 use Alzabo::Driver;

 use DBI;
 use DBD::FooDB;

 use base qw(Alzabo::Driver);

The next step is to implement a C<new> method and the methods listed
under L<Virtual Methods>.  The C<new> method should look a bit like
this:

 1:  sub new
 2:  {
 3:      my $proto = shift;
 4:      my $class = ref $proto || $proto;
 5:      my %p = @_;
 6:
 7:      my $self = bless {}, $class;
 8:
 9:      return $self;
 10:  }

The hash %p contains any values passed to the
C<Alzabo::Driver-E<gt>new> method by its caller.

Lines 1-7 should probably be copied verbatim into your own C<new>
method.  Line 5 can be deleted if you don't need to look at the
parameters.

Look at the included C<Alzabo::Driver> subclasses for examples.  Feel
free to contact me for further help if you get stuck.  Please tell me
what database you're attempting to implement, what its DBD::* driver
is, and include the code you've written so far.

=head2 Virtual Methods

The following methods are not implemented in C<Alzabo::Driver> itself
and must be implemented in a subclass.

=head3 Parameters for the connect, create_database, and drop_database

=over 4

=item * user => $db_username

=item * password => $db_pw

=item * host => $hostname

=item * port => $port

=back

All of these default to undef.  See the appropriate DBD driver
documentation for more details.

=head2 connect

Some drivers may accept or require more arguments than specified
above.

Note that C<Alzabo::Driver> subclasses are not expected to cache
connections.  If you want to do this please use C<Apache::DBI> under
mod_perl or don't call C<connect> more than once per process.

=head2 create_database

Attempts to create a new database for the schema attached to the
driver.  Some drivers may accept or require more arguments than
specified above.

=head2 drop_database

Attempts to drop the database for the schema attached to the driver.

=head2 next_sequence_number (C<Alzabo::Column> object)

This method is expected to return the value of the next sequence
number based on a column object.  For some databases (MySQL, for
example), the appropriate value is C<undef>.  This is accounted for in
Alzabo code that calls this method.

=head2 start_transaction

Notify Alzabo that you wish to start a transaction.

=head2 rollback

Rolls back the current transaction.

=head2 finish_transaction

Notify Alzabo that you wish to finish a transaction.  This is
basically the equivalent of calling commit.

=head2 get_last_id

=head3 Returns

The last primary key id created via a sequenced column.

=head1 AUTHOR

Dave Rolsky, <dave@urth.org>

=cut
