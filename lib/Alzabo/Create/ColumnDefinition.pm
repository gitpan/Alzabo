package Alzabo::Create::ColumnDefinition;

use strict;
use vars qw($VERSION);

use Alzabo::Create;

use base qw(Alzabo::ColumnDefinition);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.7 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    my $self;
    {
	no strict 'refs';
	$self = bless [ \%{"${class}::FIELDS"} ], $class;
    }

    $self->_init(@_);

    return $self;
}

sub _init
{
    my Alzabo::Create::ColumnDefinition $self = shift;
    my %p = @_;

    $self->{owner} = $p{owner};

    $self->set_type( $p{type} );
}

sub set_type
{
    my Alzabo::Create::ColumnDefinition $self = shift;
    my $type = shift;

    my $old_type = $self->{type};
    $self->{type} = $type;
    eval
    {
	$self->owner->table->schema->rules->validate_column_type($type);
    };
    if ($@)
    {
	$self->{type} = $old_type;
	$@->rethrow;
    }
}


__END__

=head1 NAME

Alzabo::Create::ColumnDefinition - Column definition object for schema
creation

=head1 SYNOPSIS

  use Alzabo::Create::ColumnDefinition;

=head1 DESCRIPTION

This object holds information on a column that might need to be shared
with another column.  The idea is that if a column is a key in two or
more tables, then some of the information related to that column
should change automatically for all tables (and all columns) whenever
it changes at all.  Right now this is only type ('VARCHAR', 'NUMBER',
etc) information.  This object also has an 'owner', which is the
column which created it.

=head1 METHODS

=over 4

=item * new

Takes the following parameters:

=item -- owner => Alzabo::Create::ColumnDefinition object

=item -- type => $type

Returns a new Alzabo::Create::ColumnDefinition object.

=item * set_type ($string)

Sets the object's type.

Exceptions:

 AlzaboException - invalid type

=back

=cut
