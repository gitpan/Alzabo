package Alzabo::Runtime::JoinCursor;

use strict;
use vars qw($VERSION);

use Alzabo::Runtime;

use Params::Validate qw( :all );
Params::Validate::validation_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

use base qw( Alzabo::Runtime::Cursor );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.32 $ =~ /(\d+)\.(\d+)/;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    my %p = validate( @_, { statement => { isa => 'Alzabo::DriverStatement' },
			    tables => { type => ARRAYREF },
			    no_cache => { optional => 1 },
			  } );

    my $self = bless { %p,
		       time => sprintf( '%11.23f', time ),
		       seen => {},
		       errors => [],
		       count => 0,
		     }, $class;

    return $self;
}

sub next
{
    my $self = shift;

    my @rows;

    $self->{errors} = [];

    my @data = $self->{statement}->next;

    return unless @data;

    my $i = 0;
    foreach my $t ( @{ $self->{tables} } )
    {
        my %pk;
        my $def = 0;
        foreach my $c ( $t->primary_key )
        {
            $pk{ $c->name } = $data[$i];

            $def = 1 if defined $data[$i];

            $i++;
        }

        unless ($def)
        {
            push @rows, undef;
            next;
        }

        my %prefetch;
        {
            my @pre;
            if ( @pre = $t->prefetch )
            {
                @prefetch{@pre} = @data[ $i .. ($i + $#pre) ];
                $i += @pre;
            }
        }

        my $row = eval { $t->row_by_pk( pk => \%pk,
                                        prefetch => \%prefetch,
                                        time => $self->{time},
                                        no_cache => $self->{no_cache},
                                        @_,
                                      ) };
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

    $self->{count}++;

    return @rows;
}

sub all_rows
{
    my $self = shift;

    my @all;
    my @errors;
    while ( my @rows = $self->next )
    {
	push @all, [@rows];
	push @errors, $self->errors if $self->errors;
    }

    $self->{errors} = \@errors;

    $self->{count} = scalar @all;

    return @all;
}

1;

__END__

=head1 NAME

Alzabo::Runtime::JoinCursor - Cursor that returns arrays of C<Alzabo::Runtime::Row> objects

=head1 SYNOPSIS

  use Alzabo::Runtime::JoinCursor;

  my $cursor = $schema->join( tables => [ $foo, $bar ],
                              where => [ $foo->column('foo_id') => 1 ] );

  while ( my @rows = $cursor->next )
  {
      print $rows[0]->select('foo'), "\n";
      print $rows[1]->select('bar'), "\n";
  }

=head1 DESCRIPTION

Objects in this class are used to return arrays Alzabo::Runtime::Row
objects when requested.  The cursor does not preload objects but
rather creates them on demand, which is much more efficient.  For more
details on the rational please see L<the HANDLING ERRORS section in
Alzabo::Runtime::Cursor|Alzabo::Runtime::Cursor/HANDLING ERRORS>.

=head1 INHERITS FROM

L<C<Alzabo::Runtime::Cursor>|Alzabo::Runtime::Cursor>

=head1 METHODS

=head2 new

=head3 Parameters

=over 4

=item * statement => C<Alzabo::Driver::Statement> object

=item * tables => [ C<Alzabo::Table> objects ]

=back

=head2 next

=head3 Returns

The next array of L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row>
objects or an empty list if no more are available.

This behavior can mask errors in your database's referential
integrity.  For more information on how to deal with this see L<the
HANDLING ERRORS section in
Alzabo::Runtime::Cursor|Alzabo::Runtime::Cursor/HANDLING ERRORS>.

=head2 all_rows

=head3 Returns

All the rows available from the current point onwards.  These are
returned as an array of array references.  Each reference is to an
array of L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> objects.

This means that if there are five set of rows that will be returned
when the object is created and you call C<next> twice, calling
C<all_rows> after it will only return three sets.  Calling the
C<errors> method after this will return all errors trapped during the
fetching of these sets of rows.  The return value is an array of array
references.  Each of these references represents a single set of rows
as they would be returned from the C<next> method.

=head2 errors

See L<C<Alzabo::Runtime::Cursor>|Alzabo::Runtime::Cursor>.

=head2 reset

Resets the cursor so that the next L<C<next>|next> call will
return the first row of the set.

=head2 count

=head3 Returns

The number of rowsets returned by the cursor so far.

=head2 next_as_hash

=head3 Returns

The next row or rows in a hash, where the hash key is the table name
and the hash value is the row object.  Tables included in the join via
an outer join will only be included if they are available.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
