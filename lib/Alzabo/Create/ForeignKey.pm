package Alzabo::Create::ForeignKey;

use strict;
use vars qw($VERSION);

use Alzabo::Create;

use Params::Validate qw( :all );
Params::Validate::set_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

use base qw(Alzabo::ForeignKey);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.19 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    validate( @_, { columns_from => { type => ARRAYREF | OBJECT },
		    columns_to   => { type => ARRAYREF | OBJECT },
		    min_max_from => { type => ARRAYREF },
		    min_max_to   => { type => ARRAYREF } } );
    my %p = @_;

    my $self = bless {}, $class;

    $self->set_columns_from( $p{columns_from} );
    $self->set_columns_to( $p{columns_to} );

    $self->set_min_max_from( $p{min_max_from} );
    $self->set_min_max_to( $p{min_max_to} );

    return $self;
}

sub set_columns_from
{
    my $self = shift;

    my $c = UNIVERSAL::isa( $_[0], 'ARRAY' ) ? shift : [ shift ];
    validate_pos( @$c, ( { isa => 'Alzabo::Create::Column' } ) x @$c );

    if ( exists $self->{columns_to} )
    {
	Alzabo::Exception::Params->throw( error => "The number of columns in each part of the relationship must be the same" )
	    unless @{ $self->{columns_to} } == @$c;
    }

    $self->{columns_from} = $c;
}

sub set_columns_to
{
    my $self = shift;

    my $c = UNIVERSAL::isa( $_[0], 'ARRAY' ) ? shift : [ shift ];
    validate_pos( @$c, ( { isa => 'Alzabo::Create::Column' } ) x @$c );

    if ( exists $self->{columns_from} )
    {
	Alzabo::Exception::Params->throw( error => "The number of columns in each part of the relationship must be the same" )
	    unless @{ $self->{columns_from} } == @$c;
    }

    $self->{columns_to} = $c;
}

sub set_min_max_from
{
    my $self = shift;

    validate_pos( @_, { type => ARRAYREF } );
    my $mm = shift;

    Alzabo::Exception::Params->throw( error => "Incorrect number of min/max elements" )
	unless scalar @$mm == 2;

    foreach my $c ( @$mm )
    {
	Alzabo::Exception::Params->throw( error => "Invalid min/max: $c" )
	    unless $c =~ /^[01n]$/i;
    }

    Alzabo::Exception::Params->throw( error => "Invalid min/max: $mm->[0]..$mm->[1]" )
	if $mm->[0] eq 'n' || $mm->[1] eq '0';

    $self->{min_max_from} = $mm;
}

sub set_min_max_to
{
    my $self = shift;

    validate_pos( @_, { type => ARRAYREF } );
    my $mm = shift;

    Alzabo::Exception::Params->throw( error => "Incorrect number of min/max elements" )
	unless scalar @$mm == 2;

    foreach my $c ( @$mm )
    {
	Alzabo::Exception::Params->throw( error => "Invalid min/max: $c" )
	    unless $c =~ /^[01n]$/i;
    }

    $self->{min_max_to} = $mm;
}

__END__

=head1 NAME

Alzabo::Create::ForeignKey - Foreign key objects for schema creation.

=head1 SYNOPSIS

  use Alzabo::Create::ForeignKey;

=for pod_merge DESCRIPTION

=head1 INHERITS FROM

C<Alzabo::ForeignKey>

=for pod_merge merged

=head1 METHODS

=head2 new

Parameters:

=over 4

=item * columns_from => C<Alzabo::Create::Column> object(s)

=item * columns_to => C<Alzabo::Create::Column> object(s)

These two parameters may be either a single column or a reference to
an array columns.  The number of columns in the two parameters must
match.

=item * min_max_from => see below

=item * min_max_to => see below

The two min_max attributes both take the same kind of argument, an
array reference two scalars long.

The first of these scalars can be the value '0' or '1' while the
second can be '1' or 'n'.

=back

=head3 Returns

A new L<C<Alzabo::Create::ForeignKey>|Alzabo::Create::ForeignKey>
object.

=for pod_merge table_from

=for pod_merge table_to

=for pod_merge columns_from

=for pod_merge columns_to

=for pod_merge column_pairs

=head2 set_columns_from (C<Alzabo::Create::Column> object(s))

Set the column(s) that the relation is from.  This can be either a
single a column object or a reference to an array of column objects.

=head2 set_columns_to (C<Alzabo::Create::Column> object(s))

Set the column(s) that the relation is to.  This can be either a
single a column object or a reference to an array of column objects.

=for pod_merge cardinality

=for pod_merge dependent

=for pod_merge min_max_from

=for pod_merge min_max_to

=head2 set_min_max_from (\@min_max_value) see above for details

Sets the min_max value of the relation of the 'from' table to the 'to'
table.

=head2 set_min_max_to (\@min_max_value) see above for details

Sets the min_max value of the relation of the 'to' table to the 'from'
table.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
