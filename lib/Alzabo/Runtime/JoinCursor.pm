package Alzabo::Runtime::JoinCursor;

use strict;
use vars qw($VERSION);

use Alzabo::Runtime;

use base qw( Alzabo::Runtime::Cursor );
use fields qw( table );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.1 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;
    my %p = @_;

    my $self;

    $self->{statement} = $p{statement};
    $self->{tables} = $p{tables};
    $self->{errors} = [];
    $self->{no_cache} = $p{no_cache};

    return bless $self, $class;
}

sub next_rows
{
    my $self = shift;

    my @rows;
    do
    {
	$self->{errors} = [];

	my @data = $self->{statement}->next_row
	    or return;

	foreach my $t ( @{ $self->{tables} } )
	{
	    my @pk = $t->primary_key;
	    my @pk_vals = splice @data, 0, scalar @pk;
	    my %hash = map { $pk[$_]->name => $pk_vals[$_] } 0..$#pk_vals;

	    my $row = eval { $t->row_by_pk( @_,
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
	    push @rows, $row;
	}
    } until ( scalar @rows == scalar @{ $self->{tables} } );

    return @rows;
}

sub all_rows
{
    my $self = shift;

    my @all;
    my @errors;
    while ( my @rows = $self->next_rows )
    {
	push @all, \@rows;
	push @errors, $self->errors if $self->errors;
    }

    $self->{errors} = \@errors;
    return @all;
}

__END__

=head1 NAME

Alzabo::Runtime::JoinCursor - Cursor that returns Alzabo::Runtime::Row
arrays of objects

=head1 SYNOPSIS

  use Alzabo::Runtime::JoinCursor;

  my $cursor = $schema->join( tables => [ $foo, $bar ],
                              where => [ $foo->column('foo_id') => 1 ] );

  while ( my @rows = $cursor->next_rows )
  {
      print $row[0]->select('foo'), "\n";
      print $row[1]->select('bar'), "\n";
  }

=head1 DESCRIPTION

Objects in this class are used to return arrays Alzabo::Runtime::Row
objects when requested.  The cursor does not preload objects but
rather creates them on demand, which is much more efficient.  For more
details on the rational please see L<the RATIONALE FOR CURSORS
section|RATIONALE FOR CURSORS>.

NOTE: This class is considered experimental.

=head1 METHODS

=over 4

=item * new

Takes the following parameters:

=item -- statement => Alzabo::Driver::Statement object

=item -- tables => [ Alzabo::Table objects ]

=item * next_rows

Returns the next array Alzabo::Runtime::Row objects or and empty list
if no more are available.  This behavior can mask errors in your
database's referntial integrity.  For more information on how to deal
with this see L<the HANDLING ERRORS section|HANDLING ERRORS>.

=item * all_rows

Returns all the rows available from the current point onwards.  This
means that if there are five rows that will be returned when the
object is created and you call C<next_row> twice, calling all_rows
after it will only return three.  Calling the C<errors> method after
this will return all errors trapped during the fetching of these rows.
The return value is an array of array references.  Each of these
references represents a single set of rows as they would be returned
from the C<next_rows> method.

=item * errors

L<Alzabo::Runtime::Cursor>.

=item * reset

Resets the cursor so that the next C<next_rows> call will return the
first row of the set.

=back

=head1 HANDLING ERRORS

See L<Alzabo::Runtime::Cursor>.

=head1 RATIONALE FOR CURSORS

See L<Alzabo::Runtime::Cursor>.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
