package Alzabo::Create::ForeignKey;

use strict;
use vars qw($VERSION);

use Alzabo::Create;

use base qw(Alzabo::ForeignKey);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.15 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;
    my %p = @_;

    my $self = bless {}, $class;

    $self->set_column_from( $p{column_from} );
    $self->set_column_to( $p{column_to} );

    $self->set_min_max_from( $p{min_max_from} );
    $self->set_min_max_to( $p{min_max_to} );

    return $self;
}

sub set_column_from
{
    my Alzabo::Create::ForeignKey $self = shift;

    $self->{column_from} = shift;
}

sub set_column_to
{
    my Alzabo::Create::ForeignKey $self = shift;

    $self->{column_to} = shift;
}

sub set_min_max_from
{
    my Alzabo::Create::ForeignKey $self = shift;
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
    my Alzabo::Create::ForeignKey $self = shift;
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

=item * column_from => C<Alzabo::Create::Column> object

=item * column_to => C<Alzabo::Create::Column> object

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

=for pod_merge column_from

=for pod_merge column_to

=head2 set_column_from (C<Alzabo::Create::Column> object)

Set the column that the relation is from.

=head2 set_column_to (C<Alzabo::Create::Column> object)

Set the column that the relation is to.

=for pod_merge min_max_from

=for pod_merge min_max_to

=head2 set_min_max_from (\@min_max_value) see above for details

Sets the min_max value of the relation of the 'from' table to the 'to'
table.

=head2 set_min_max_to (\@min_max_value) see above for details

Sets the min_max value of the relation of the 'to' table to the 'from'
table.

=for pod_merge cardinality

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
