package Alzabo::Create::ForeignKey;

use strict;
use vars qw($VERSION);

use Alzabo::Create;

use base qw(Alzabo::ForeignKey);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.7 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;
    my %p = @_;

    my $self;
    {
	no strict 'refs';
	$self = bless [ \%{"${class}::FIELDS"} ], $class;
    }

    $self->set_table_from( $p{table_from} );
    $self->set_table_to( $p{table_to} );

    $self->set_column_from( $p{column_from} );
    $self->set_column_to( $p{column_to} );

    $self->set_min_max_from( $p{min_max_from} );
    $self->set_min_max_to( $p{min_max_to} );

    return $self;
}

sub set_table_from
{
    my Alzabo::Create::ForeignKey $self = shift;

    $self->{table_from} = shift;
}

sub set_table_to
{
    my Alzabo::Create::ForeignKey $self = shift;

    $self->{table_to} = shift;
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

    AlzaboException->throw( error => "Incorrect number of min/max elements" )
	unless scalar @$mm == 2;

    foreach my $c ( @$mm )
    {
	AlzaboException->throw( error => "Invalid min/max: $c" )
	    unless $c =~ /^[01n]$/i;
    }

    AlzaboException->throw( error => "Invalid min/max: $mm->[0]..$mm->[1]" )
	if $mm->[0] eq 'n' || $mm->[1] eq '0';

    $self->{min_max_from} = $mm;
}

sub set_min_max_to
{
    my Alzabo::Create::ForeignKey $self = shift;
    my $mm = shift;

    AlzaboException->throw( error => "Incorrect number of min/max elements" )
	unless scalar @$mm == 2;

    foreach my $c ( @$mm )
    {
	AlzaboException->throw( error => "Invalid min/max: $c" )
	    unless $c =~ /^[01n]$/i;
    }

    $self->{min_max_to} = $mm;
}

__END__

=head1 NAME

Alzabo::Create::ForeignKey - Foreign key objects for schema creation.

=head1 SYNOPSIS

  use Alzabo::Create::ForeignKey;

=head1 DESCRIPTION

Holds information on one table's relationship to another.  It knows
what columns the relationship belongs to and what the cardinality of
the relationship is.

=head1 METHODS

=over 4

=item * new

Takes the following parameters:

=item -- table_from => Alzabo::Create::Table object

=item -- table_to => Alzabo::Create::Table object

=item -- column_from => Alzabo::Create::Column object

=item -- column_to => Alzabo::Create::Column object

=item -- min_max_from => see below

=item -- min_max_to => see below

The two min_max attributes both take the same kind of argument, an
array reference two scalars long.

The first of these scalars can be the value '0' or '1' while the
second can be '1' or 'n'.

Returns a new Alzabo::Create::ForeignKey object.

Exceptions:

 AlzaboException - invalid min_max values

=item * set_table_from (Alzabo::Create::Table object)

Set the table that the relation is from.

=item * set_table_to (Alzabo::Create::Table object)

Set the table that the relation is to.

=item * set_column_from (Alzabo::Create::Column object)

Set the column that the relation is from.

=item * set_column_to (Alzabo::Create::Column object)

Set the column that the relation is to.

=item * set_min_max_from (\@min_max_value) see above for details

Sets the min_max value of the relation of the 'from' table to the 'to'
table.

Exceptions:

 AlzaboException - invalid min_max values

=item * set_min_max_to (\@min_max_value) see above for details

Sets the min_max value of the relation of the 'to' table to the 'from'
table.

Exceptions:

 AlzaboException - invalid min_max values

=back

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=head1 SEE ALSO

See the Alzabo::ForeignKey documentation for more details on how
relationships are defined in Alzabo.

=cut
