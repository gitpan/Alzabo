package Alzabo::Runtime::OuterJoinCursor;

use strict;
use vars qw($VERSION);

use Alzabo::Runtime;

use Params::Validate qw( :all );
Params::Validate::validation_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

use base qw( Alzabo::Runtime::JoinCursor );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.7 $ =~ /(\d+)\.(\d+)/;

sub new
{
    my $proto = shift;
    my %p = @_;

    my $type = delete $p{type};

    my $self = $proto->SUPER::new(%p);

    $self->{type} = $type;

    return $self;
}

sub next
{
    my $self = shift;

    my @rows;
    do
    {
	$self->{errors} = [];

	my @data = $self->{statement}->next
	    or return;

    TABLES:
	foreach my $t ( @{ $self->{tables} } )
	{
	    my @pk = $t->primary_key;
	    my @pk_vals = splice @data, 0, scalar @pk;

	    if ( $t eq $self->{tables}[-1] && ( grep { ! defined } @pk_vals ) == @pk_vals )
	    {
		push @rows, undef;
		next TABLES;
	    }

	    my %hash = map { $pk[$_]->name => $pk_vals[$_] } 0..$#pk_vals;

	    my $row = eval { $t->row_by_pk( @_,
					    pk => \%hash,
					    no_cache => $self->{no_cache}
					  ); };
	    if ($@)
	    {
		if ( $@->isa('Alzabo::Exception::NoSuchRow') )
		{
		    push @{ $self->{errors} },  $@;
		}
		else
		{
		    if ( UNIVERSAL::can( $@, 'rethrow' ) )
		    {
			$@->rethrow;
		    }
		    else
		    {
			Alzabo::Exception->throw( error => $@ );
		    }
		}
	    }
	    push @rows, $row;
	}
    } until ( scalar @rows == scalar @{ $self->{tables} } );

    return $self->{type} eq 'right' ? @rows[1,0] : @rows;
}
*next_rows = \&next;

1;

__END__

=head1 NAME

Alzabo::Runtime::OuterJoinCursor - Cursor that returns arrays of C<Alzabo::Runtime::Row> objects or undef

=head1 SYNOPSIS

  my $cursor = $schema->left_outer_join( tables => [ $foo, $bar ] );

  while ( my @rows = $cursor->next )
  {
      print $rows[0]->select('foo'), "\n";
      print $rows[1]->select('bar'), "\n" if defined $row[1];
  }

=head1 DESCRIPTION

This class exists to handle the return values from outer joins
properly.  If the join returns NULL, then it returns C<undef> instead
of a row object for a that row, instead of a row object.

=head1 INHERITS FROM

L<C<Alzabo::Runtime::JoinCursor>|Alzabo::Runtime::JoinCursor>

=head2 next

=head3 Returns

The next array of L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row>
objects and/or C<undef>s, or an empty list if no more arrays of rows
are available.

This behavior can mask errors in your database's referential
integrity.  For more information on how to deal with this see L<the
HANDLING ERRORS section in
Alzabo::Runtime::Cursor|Alzabo::Runtime::Cursor/HANDLING ERRORS>.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
