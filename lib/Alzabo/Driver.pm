package Alzabo::Driver;

use strict;
use vars qw($VERSION);

use Alzabo::Exceptions;
use Alzabo::Util;

use DBI;

use fields qw( dbh prepare_method schema );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.23 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    shift;
    my %p = @_;

    $p{driver} =~ s/Alzabo::Driver:://;
    eval "use Alzabo::Driver::$p{driver}";
    EvalException->throw( error => $@ ) if $@;

    my $self = "Alzabo::Driver::$p{driver}"->new(@_);
    $self->{dbh}->{RaiseError} = 1;

    $self->{schema} = $p{schema};

    $self->{prepare_method} ||= 'prepare';

    return $self;
}

sub available
{
    return Alzabo::Util::subclasses(__PACKAGE__);
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
	Alzabo::Driver::Exception->throw( error => $@,
					  sql => $p{sql},
					  bind => \@bind );
    }

    return @data;
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
	$sth->bind_columns( \ ( @hash{ @{ $sth->{NAME} } } ) );

	push @data, {%hash} while $sth->fetch;

	$sth->finish;
    };
    if ($@)
    {
	my @bind = exists $p{bind} ? ( ref $p{bind} ? $p{bind} : [$p{bind}] ) : ();
	Alzabo::Driver::Exception->throw( error => $@,
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
	Alzabo::Driver::Exception->throw( error => $@,
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
	$sth->bind_columns( \ ( @hash{ @{ $sth->{NAME} } } ) );
	%hash = () unless $sth->fetch;
	$sth->finish;
    };
    if ($@)
    {
	my @bind = exists $p{bind} ? ( ref $p{bind} ? $p{bind} : [$p{bind}] ) : ();
	Alzabo::Driver::Exception->throw( error => $@,
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
	Alzabo::Driver::Exception->throw( error => $@,
					  sql => $p{sql},
					  bind => \@bind );
    }

    return wantarray ? @data : $data[0];
}

sub _prepare_and_execute
{
    my $self = shift;
    my %p = @_;

    my @bind = exists $p{bind} ? ( ref $p{bind} ? @{ $p{bind} } : $p{bind} ) : ();

    my $prep = $self->{prepare_method};
    my $sth;
    eval
    {
	$sth = $self->{dbh}->$prep( $p{sql} );
	$sth->execute(@bind);
    };
    if ($@)
    {
	Alzabo::Driver::Exception->throw( error => $@,
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
	Alzabo::Driver::Exception->throw( error => $@,
					  sql => $p{sql},
					  bind => \@bind );
    }

    return $rows;
}

sub tables
{
    my $self = shift;

    my @t = eval {  $self->{dbh}->tables; };
    Alzabo::Driver::Exception->throw( error => $@ ) if $@;

    return @t;
}

sub statement
{
    my $self = shift;

    return Alzabo::DriverStatement->new( dbh => $self->{dbh},
					 prepare_method => $self->{prepare_method},
					 @_ );
}

sub DESTROY
{
    my $self = shift;

    $self->{dbh}->disconnect if ref $self->{dbh};
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
    shift()->_virtual;
}

sub rollback
{
    shift()->_virtual;
}

sub finish_transaction
{
    shift()->_virtual;
}

sub get_last_id
{
    shift()->_virtual;
}

sub _virtual
{
    my $self = shift;

    my $sub = (caller(1))[3];
    VirtualMethodException->throw( error =>
				   "$sub is a virtual method and must be subclassed in " . ref $self );
}

package Alzabo::DriverStatement;

use strict;
use vars qw($VERSION);

use Alzabo::Exceptions;
use Alzabo::Util;

use DBI;

use fields qw( dbh sth sql bind );

$VERSION = '0.1';

1;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;
    my %p = @_;

    my $self = bless {}, $class;

    my $prep = $p{prepare_method};
    $self->{dbh} = $p{dbh};

    $self->{sql} = $p{sql};
    eval
    {
	$self->{sth} = $self->{dbh}->$prep( $p{sql} );

	$self->{bind} = exists $p{bind} ? ( ref $p{bind} ? $p{bind} : [ $p{bind} ] ) : [];
	$self->{sth}->execute( @{ $self->{bind} } );
    };
    Alzabo::Driver::Exception->throw( error => $@,
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
	$self->{sth}->execute(@_);
    };
    Alzabo::Driver::Exception->throw( error => $@,
			 sql => $self->{sql},
			 bind => $self->{bind} ) if $@;
}

sub next_row
{
    my $self = shift;

    my @row;
    eval
    {
	$self->{sth}->bind_columns( \ (@row[ 0..$#{ $self->{sth}->{NAME} } ] ) );
	$self->{sth}->fetch;
    };
    Alzabo::Driver::Exception->throw( error => $@,
				      sql => $self->{sql},
				      bind => $self->{bind} ) if $@;

    return @row;
}

sub next_row_hash
{
    my $self = shift;

    my %hash;
    my $active;
    eval
    {
	$self->{sth}->bind_columns( \ ( @hash{ @{ $self->{sth}->{NAME} } } ) );
	$active = $self->{sth}->fetch;
    };
    Alzabo::Driver::Exception->throw( error => $@,
				      sql => $self->{sql},
				      bind => $self->{bind} ) if $@;

    return $active ? %hash : ();
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
    Alzabo::Driver::Exception->throw( error => $@ ) if $@;
}

__END__

=head1 NAME

Alzabo::Driver - Alzabo base class for RDBMS drivers

=head1 SYNOPSIS

  use Alzabo::Driver;

  my $driver = Alzabo::Driver->new( driver => 'MySQL',
                                    schema => $schema );

=head1 DESCRIPTION

This is the base class for all Alzabo::Driver modules.  To instantiate
a driver call this class's C<new> method.  See the L<SUBCLASSING
Alzabo::Driver> section for information on how to make a driver for
the RDBMS of your choice.

=head1 EXCEPTIONS

Alzabo::Driver::Exception - This is an error in database
communications.  This exception class has extra methods (see the
L<Alzabo::Driver::Exception METHODS> section.

VirtualMethodException - A method you called should have been
subclassed in the Alzabo::Driver subclass you are using but it wasn't.

EvalException - An attempt to eval a string failed.

=head1 METHODS

=over 4

=item * available

Returns a list of strings listing the avaiable Alzabo::Driver
subclasses.  This is a class method.

=item * new

Takes the following parameters:

=item -- driver => $string

A string giving the name of a driver to instantiate.  Driver names are
the name of the Alzabo::Driver subclass without the leading
'Alzabo::Driver::' part.  For example, the driver name of the
Alzabo::Driver::MySQL class is 'MySQL'.

=item -- schema => Alzabo::Schema object

This should be an Alzabo::Schema object (either Alzabo::Create::Schema
or Alzabo::Runtime::Schema).

The return value of this method is a new Alzabo::Driver object of the
appropriate subclass.

=item * tables

Returns a list of strings containing the names of the tables in the
database.  See the L<DBI> documentation for more details.

=back

=head2 Data Retrieval methods

Some of these methods return lists of data (the C<rows>,
C<rows_hashref>, and C<column> methods).  With large result sets, this
will increase memory usage for the list that is created as the return
value.  To avoid this, it may be desirable to use the functionality
provided by the Alzabo::DriverStatement class, which allows you to
fetch results one row at a time.  This class is documented further on.

The following methods all take the same parameters:

=over 4

=item -- sql => $sql_string

=item -- bind => $bind_value or \@bind_values

=item * rows

Executes a SQL statement with the given bind value(s) and returns an
array of array references containing the data returned.

=item * rows_hashref

Executes a SQL statement with the given bind value(s) and returns an
array of hash references containing the data returned.

=item * one_row

Executes a SQL statement with the given bind value(s) and returns an
array or scalar containing the data returned, depending on context.

=item * one_row_hash

Executes a SQL statement with the given bind value(s) and returns a
hash containing the data returned.

=item * column

Executes a SQL statement with the given bind value(s) and returns an
array containing the values for the first column returned of each row.

=item * do

Executes a SQL statement with the given bind value(s) and returns the
number of rows affected.  Use this for non-SELECT SQL statements.

=item * statement

Returns a new Alzabo::DriverStatement handle, ready to return data via
one of its C<next_row*> methods.

=back

=head1 Alzabo::DriverStatement

This class is a wrapper around DBI's statement handles.  It finishes
automatically as appropriate so the end user need not worry about
doing this.

=over 4

=item * next_row

 while (my @row = $statement->next_row) { ... }

Returns an array containing the next row of data for statement or an
empty list if no more data is available.

=item * next_row_hash

 while (my %row = $statement->next_row_hash) { ... }

Returns a hash containing the next row of data for statement or an
empty list if no more data is available.

=item * execute (@bound_parameters)

Executes the associated statement handle with the given bound
parameters.  If the statement handle is still active (it was
previously executed and has more data left) then its C<finish> method
will be called first.

=back

=head1 Alzabo::Driver VIRTUAL METHODS

The following methods are not implemented in Alzabo::Driver itself and
must be implemented in its subclasses.

=over 4

The following two methods take these optional parameters:

=item -- host => $string

=item -- user => $string

=item -- password => $string

All of these default to undef.  See the appropriate DBD driver
documentation for more details.

=item * connect

Some drivers may accept or require more arguments than specified
above.

Note that Alzabo::Driver subclasses are not expected to cache
connections.  If you want to do this please use Apache::DBI under
mod_perl or don't call connect more than once per process.

=item * create_database

Attempts to create a new database for the schema attached to the
driver.  Some drivers may accept or require more arguments than
specified above.

=item * next_sequence_number (Alzabo::Column object)

This method is expected to return the value of the next sequence
number based on a column object.

=item * start_transaction

<parameters not yet determined>

=item * rollback

Rolls back the current transaction.

=item * finish_transaction

<parameters not yet determined>

Commits a transaction.

=item * get_last_id

This returns the last primary key id created via a sequenced column.

=back

=head1 SUBCLASSING Alzabo::Driver

To create a subclass of Alzabo::Driver for your particular RDBMS is
fairly simple.  First of all, there must be a DBD::* driver for it, as
Alzabo::Driver is built on top of DBI.

Here's a sample header to the module using a fictional RDBMS called FooDB:

 package Alzabo::Driver::FooDB;

 use strict;
 use vars qw($VERSION);

 use Alzabo::Driver;

 use DBI;
 use DBD::FooDB;

 use base qw(Alzabo::Driver);

The next step is to implement a C<new> method and the methods listed
under the section L<Virtual Methods>.  The new method should look a
bit like this:

 1:  sub new
 2:  {
 3:      my $proto = shift;
 4:      my $class = ref $proto || $proto;
 5:      my %p = @_;
 6:
 7:      my $self = bless {}, $class;
 8:      $self->{prepare_method} = 'prepare';
 9:
 10:     return $self;
 11:  }

The hash %p contains any values passed to the Alzabo::Driver->new
method by its caller.

Lines 1-7 should probably be copied verbatim into your own C<new>
method.  Line 5 can be deleted if you don't need to look at the
parameters (which you probably don't).

Line 8 sets an internal hash entry.  This is a string that defines
which DBI method to use to prepare a statement.  For some databases
(such as Oracle), it may be advantageous to change this to
'prepare_cached'.

Look at the included Alzabo::Driver subclasses for examples.  Feel
free to contact me for further help if you get stuck.  Please tell me
what database you're attempting to implement, what its DBD::* driver
is, and include the code you've written so far.

=head1 AUTHOR

Dave Rolsky, <dave@urth.org>

=cut
