package Alzabo::Create::ColumnDefinition;

use strict;
use vars qw($VERSION);

use Alzabo::Create;

use base qw(Alzabo::ColumnDefinition);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.17 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    my $self = bless {}, $class;

    $self->_init(@_);

    return $self;
}

sub _init
{
    my $self = shift;
    my %p = @_;

    $self->{owner} = $p{owner};

    $self->set_type( $p{type} );
}

sub set_type
{
    my $self = shift;
    my $type = shift;

    $type =~ s/\A\s+//;
    $type =~ s/\s+\z//;

    my $old_type = $self->{type};
    $self->{type} = $type;
    eval
    {
	$self->owner->table->schema->rules->validate_column_type($type);
	$self->owner->table->schema->rules->validate_primary_key($self->owner)
	    if eval { $self->owner->is_primary_key };
	# eval ^^ cause if we're creating the column its not in the table yet
    };
    if ($@)
    {
	$self->{type} = $old_type;
	$@->rethrow;
    }
}

sub set_length
{
    my $self = shift;
    my %p = @_;

    my $old_length = $self->{length};
    my $old_precision = $self->{precision};
    $self->{length} = $p{length};
    $self->{precision} = $p{precision} if exists $p{precision};

    eval
    {
	$self->owner->table->schema->rules->validate_column_length($self->owner);
    };
    if ($@)
    {
	$self->{length} = $old_length;
	$self->{precision} = $old_precision;
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
with another column.  The reason this class exists is that if a column
is a key in two or more tables, then some of the information related
to that column should change automatically in multiple places whenever
it changes at all.  Right now this is only type ('VARCHAR', 'NUMBER',
etc) information.  This object also has an 'owner', which is the
column which created it.

=head1 INHERITS FROM

C<Alzabo::ColumnDefinition>

=for pod_merge merged

=head1 METHODS

=head2 new

=head3 Parameters

=over 4

=item * owner => C<Alzabo::Create::ColumnDefinition> object

=item * type => $type

=back

=head3 Returns

A new C<Alzabo::Create::ColumnDefinition> object.

=for pod_merge type

=head2 set_type ($string)

Sets the object's type.

=for pod_merge length

=for pod_merge precision

=head2 set_length

=head3 Parameters

=over 4

=item * length => $length

=item * precision => $precision (optional)

=back

Sets the column's length and precision.  The precision parameter is
optional (though some column types may require it if the length is
set).

=for pod_merge owner

=cut
