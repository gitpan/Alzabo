package Alzabo::Runtime::RowCursor;

use strict;
use vars qw($VERSION);

use Alzabo::Runtime;

use base qw( Alzabo::Runtime::Cursor );
use fields qw( table );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.3 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;
    my %p = @_;

    my $self;

    $self->{statement} = $p{statement};
    $self->{table} = $p{table};
    $self->{errors} = [];
    $self->{no_cache} = $p{no_cache};

    return bless $self, $class;
}

sub next_row
{
    my $self = shift;

    my $row;

    # This loop is intended to allow the end caller to ignore rows
    # that can't be created because they're not in the table.
    #
    # For example, imagine that query in the statement is looking at
    # table 'foo' to get PK values for table 'bar'.  If table 'foo'
    # has a record indicating that there is a row in 'bar' where PK ==
    # 1 but no such row actually exists then we want to skip this.
    #
    # If they really want to know we do save the exception.
    do
    {
	$self->{errors} = [];

	my %hash = $self->{statement}->next_row_hash
	    or return;

	$row = eval { $self->{table}->row_by_pk( @_,
						 id => \%hash,
						 no_cache => $self->{no_cache}
					       ); };
	if ($@)
	{
	    if ( $@->isa('AlzaboNoSuchRowException') )
	    {
		push @{ $self->{errors} },  $@;
	    }
	    else
	    {
		$@->rethrow;
	    }
	}
    } until (defined $row);

    return $row;
}

sub all_rows
{
    my $self = shift;

    my @rows;
    my @errors;
    while ( my $row = $self->next_row )
    {
	push @rows, $row;
	push @errors, $self->errors if $self->errors;
    }

    $self->{errors} = \@errors;
    return @rows;
}

__END__

=head1 NAME

Alzabo::Runtime::RowCursor - Cursor that returns Alzabo::Runtime::Row
objects

=head1 SYNOPSIS

  use Alzabo::Runtime::RowCursor;

  my $cursor = $schema->table('foo')->all_rows;

  while ( my $row = $cursor->next_row )
  {
      print $row->select('foo'), "\n";
  }

=head1 DESCRIPTION

Objects in this class are used to return Alzabo::Runtime::Row objects
when requested.  The cursor does not preload objects but rather
creates them on demand, which is much more efficient.  For more
details on the rational please see L<the RATIONALE FOR CURSORS
section|RATIONALE FOR CURSORS>.

=head1 METHODS

=over 4

=item * new

Takes the following parameters:

=item -- statement => Alzabo::Driver::Statement object

=item -- table => Alzabo::Table object

=item * next_row

Returns the next Alzabo::Runtime::Row object or undef if no more are
available.  This behavior can mask errors in your database's
referntial integrity.  For more information on how to deal with this
see L<the HANDLING ERRORS section|HANDLING ERRORS>.

=item * all_rows

Returns all the rows available from the current point onwards.  This
means that if there are five rows that will be returned when the
object is created and you call C<next_row> twice, calling all_rows
after it will only return three.  Calling the C<errors> method after
this will return all errors trapped during the fetching of these rows.

=item * errors

L<Alzabo::Runtime::Cursor>.

=item * reset

Resets the cursor so that the next C<next_row> call will return the
first row of the set.

=back

=head1 HANDLING ERRORS

See L<Alzabo::Runtime::Cursor>.

=head1 RATIONALE FOR CURSORS

See L<Alzabo::Runtime::Cursor>.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
