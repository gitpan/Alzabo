package Alzabo::Runtime::PotentialRow;

use strict;
use vars qw($VERSION);

use Alzabo::Runtime;

use base qw(Alzabo::Runtime::Row);

use Params::Validate qw( :all );
Params::Validate::validation_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.5 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    my %p = validate( @_, { table => { isa => 'Alzabo::Runtime::Table' },
			    values => { type => HASHREF, optional => 1 },
			  } );

    my $self = bless { table => $p{table} }, $class;

    # Can't just call ->update here cause with MethodMaker there may
    # be update hooks that probably shouldn't be invoked here.
    if ( exists $p{values} )
    {
	foreach ( keys %{ $p{values} } )
	{
	    # This will throw an exception if the column doesn't exist.
	    my $c = $self->table->column($_);

	    Alzabo::Exception::Params->throw( error => "Column " . $c->name . " cannot be null." )
		unless defined $p{values}->{$_} || $c->nullable || defined $c->default;

	    $self->{data}{$_} = $p{values}->{$_};
	}
    }

    foreach ( $self->table->columns )
    {
	if ( defined $_->default )
	{
	    $self->{data}{ $_->name } = $_->default unless defined $self->{data}{ $_->name };
	}
    }

    return $self;
}

sub _get_data
{
    my $self = shift;
    my @cols = @_;

    my %data;
    @data{@cols} = @{ $self->{data} }{@cols};

    return %data;
}

sub update
{
    my $self = shift;
    my %data = @_;

    foreach my $k (keys %data)
    {
	# This will throw an exception if the column doesn't exist.
	my $c = $self->table->column($k);

	Alzabo::Exception::Params->throw( error => "Column " . $c->name . " cannot be null." )
	    unless defined $data{$k} || $c->nullable || defined $c->default;
    }

    @{ $self->{data} }{keys %data} = values %data;
}

sub delete
{
    Alzabo::Exception::Logic->throw( error => 'Cannot delete a potential row object' );
}

sub make_live
{
    my $self = shift;
    my %p = @_;

    my %values;
    foreach ( $self->table->columns )
    {
	next unless exists $p{values}->{ $_->name } || exists $self->{data}->{ $_->name };
	$values{ $_->name } = ( exists $p{values}->{ $_->name } ?
				$p{values}->{ $_->name } :
				$self->{data}->{ $_->name } );
    }

    my $table = $self->table;
    delete @{ $self }{keys %$self}; # clear out everything

    $table->insert( @_,
		    potential_row => $self,
		    %values ? ( values => \%values ) : (),
		  );
}

# Class or object method
sub id
{
    return '';
}

__END__

=head1 NAME

Alzabo::Runtime::PotentialRow - Row objects that aren't yet in the database

=head1 SYNOPSIS

  my $row = $table->potential_row;

  my $other = $table->potential_row( values => { name => 'Ralph' } );

  $row->make_live;  # $row is now a _real_ row object!

=head1 DESCRIPTION

These objects represent potential rows, rows which do not yet exist in
the database.  These are created via the
L<C<Alzabo::Runtime::Table-E<gt>potential_row>|Alzabo::Runtime::Table/potential_row>
method.

These objects do not interact with the caching system.

They are useful when you need a placeholder object which you can
update and select from, but you don't actually want to commit the data
to the database.

Once L<C<make_live>|/make_live> is called, the object is tranformed
into a row of the appropriate class.

When a new object of this class is created, it checks for defaults for
each column and uses them for its value if no other value is provided
by the user.

Potential rows have looser constraints for column values than regular
rows.  When creating a new potential row, it is ok if none of the
columns are defined.  However, you cannot update a column in a
potential row to NULL if the column is not nullable.

=head1 METHODS

For most methods, this object works exactly like an
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> object.  However, this
object cannot be deleted, nor does it have an id.

In addition, no attempt is made to enforce L<referential integrity
constraints|Alzabo/Referential Integrity> on this object.

=head2 select

=head2 select_hash

=head2 update

=head2 table

=head2 rows_by_foreign_key

These methods all operate as they do for
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> objects.

=head2 delete

This method throws an exception as it is not meaningful to try to
delete a row that does not exist in the database.

=head2 id

This method returns an empty string.  Since primary keys may not be
known til an insert, in the case of sequenced columns, there is no way
to calculate an id.

=head2 make_live

This method inserts the row into the database and tranforms the row
object, in place, into a row of the appropriate class.

This means that all references to the potential row object will now be
references to the real object (which is a good thing).

This method can take any parameters that can be passed to the
L<C<Alzabo::Runtime::Table-E<gt>insert>|Alzabo::Runtime::Table/insert>
method, such as C<no_cache>.

Any columns already set will be passed to the C<insert> method,
including primary key values.  However, these will be overriddenn, on
a column by column basis, by a C<pk> or C<values> parameters given to
the C<make_live> method.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
