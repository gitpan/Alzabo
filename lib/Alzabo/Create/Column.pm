package Alzabo::Create::Column;

use strict;
use vars qw($VERSION);

use Alzabo::Create;

use Params::Validate qw( :all );
Params::Validate::set_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

use base qw(Alzabo::Column);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.30 $ =~ /(\d+)\.(\d+)/;

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

    validate( @_, { table => { isa => 'Alzabo::Table' },
		    name  => { type => SCALAR },
		    null  => { optional => 1 },
		    nullable => { optional => 1 },
		    type  => { type => SCALAR,
			       optional => 1 },
		    attributes => { type => ARRAYREF,
				    optional => 1 },
		    default    => { type => UNDEF | SCALAR,
				    optional => 1 },
		    sequenced  => { optional => 1 },
		    length => { type => UNDEF | SCALAR,
				optional => 1 },
		    precision  => { type => UNDEF | SCALAR,
				    optional => 1 },
		    definition => { isa => 'Alzabo::Create::ColumnDefinition',
				    optional => 1 },
		  } );
    my %p = @_;

    $self->set_table( $p{table} );

    $self->set_name( $p{name} );

    $self->{nullable} = $p{nullable} || $p{null} || 0;

    if ($p{definition})
    {
	$self->set_definition( $p{definition} );
    }
    else
    {
	$self->set_definition( Alzabo::Create::ColumnDefinition->new( owner => $self,
								      type => $p{type},
								    ) );
    }

    my %attr;
    tie %{ $self->{attributes} }, 'Tie::IxHash';

    $self->set_attributes( @{ $p{attributes} } );

    $self->set_sequenced( $p{sequenced} || 0 );

    $self->set_default( $p{default} );

    $self->set_length( length => $p{length}, precision => $p{precision} );
}

sub set_table
{
    my $self = shift;

    validate_pos( @_, { isa => 'Alzabo::Create::Table' } );
    $self->{table} = shift;
}

sub set_name
{
    my $self = shift;

    validate_pos( @_, { type => SCALAR } );
    my $name = shift;

    my $old_name = $self->{name};
    $self->{name} = $name;
    eval
    {
	$self->table->schema->rules->validate_column_name($self);
    };
    if ($@)
    {
	$self->{name} = $old_name;
	$@->rethrow;
    }

    $self->table->register_column_name_change( column => $self,
					       old_name => $old_name )
	if $old_name;
}

*set_null = \&set_nullable;
sub set_nullable
{
    my $self = shift;

    validate_pos( @_, { type => SCALAR } );
    my $n = shift;

    Alzabo::Exception::Params->throw( error => "Invalid value for nullable attribute: $n" )
	unless $n eq '1' || $n eq '0';

    Alzabo::Exception::Params->throw( error => "Primary key column cannot be nullable" )
	if $n eq '1' && $self->is_primary_key;

    $self->{nullable} = $n;
}

sub set_default
{
    my $self = shift;

    validate_pos( @_, { type => UNDEF | SCALAR } );
    $self->{default} = shift;
}

sub set_length
{
    my $self = shift;

    $self->{definition}->set_length(@_);
}

sub set_attributes
{
    my $self = shift;

    validate_pos( @_, ( { type => SCALAR } ) x @_ );

    %{ $self->{attributes} } = ();

    foreach (@_)
    {
	$self->add_attribute($_);
    }
}

sub add_attribute
{
    my $self = shift;

    validate_pos( @_, { type => SCALAR } );
    my $attr = shift;

    $attr =~ s/^\s+//;
    $attr =~ s/\s+$//;

    $self->table->schema->rules->validate_column_attribute( column => $self,
							    attribute => $attr );

    $self->{attributes}{$attr} = 1;
}

sub delete_attribute
{
    my $self = shift;

    validate_pos( @_, { type => SCALAR } );
    my $attr = shift;

    Alzabo::Exception::Params->throw( error => "Column " . $self->name . " doesn't have attribute $attr" )
	unless exists $self->{attributes}{$attr};

    delete $self->{attributes}{$attr};
}

sub alter
{
    my $self = shift;
    $self->{definition}->alter(@_);

    # this will force them to go through the rules code again.
    # Attributes that don't work with the new type are silently
    # discarded.
    foreach ( $self->attributes )
    {
	$self->delete_attribute($_);
	eval { $self->add_attribute($_) };
    }
}

sub set_type
{
    my $self = shift;

    validate_pos( @_, { type => SCALAR } );
    my $t = shift;

    $self->{definition}->set_type($t);

    # this will force them to go through the rules code again.
    # Attributes that don't work with the new type are silently
    # discarded.
    foreach ( $self->attributes )
    {
	$self->delete_attribute($_);
	eval { $self->add_attribute($_) };
    }

    eval { $self->set_length( length => $self->length,
			      precision => $self->precision ) };
    if ($@)
    {
	eval { $self->set_length( length => $self->length, precision => undef ) };
	if ($@)
	{
	    $self->set_length( length => undef,
			       precision => undef );
	}
    }
}

sub set_sequenced
{
    my $self = shift;

    validate_pos( @_, { type => SCALAR } );
    my $s = shift;

    Alzabo::Exception::Params->throw( error => "Invalid value for sequenced attribute: $s" )
	unless $s eq '1' || $s eq '0';

    $self->table->schema->rules->validate_sequenced_attribute($self)
	if $s eq '1';

    $self->{sequenced} = $s;
}

sub set_definition
{
    my $self = shift;

    validate_pos( @_, { isa => 'Alzabo::Create::ColumnDefinition' } );
    my $d = shift;

    $self->{definition} = $d;
}

__END__

=head1 NAME

Alzabo::Create::Column - Column objects for use in schema creation

=head1 SYNOPSIS

  use Alzabo::Create::Column;

=head1 DESCRIPTION

This object represents a column.  It holds data specific to a column.
Additional data is held in a
L<C<Alzabo::Create::ColumnDefinition>|Alzabo::Create::ColumnDefinition>
object, which is used to allow two columns to share a type (which is
good when two columns in different tables are related as it means that
if the type of one is changed, the other is also.)

=head1 INHERITS FROM

C<Alzabo::Column>

=for pod_merge merged

=head1 METHODS

=head2 new

=head3 Parameters

=over 4

=item * table => C<Alzabo::Create::Table> object

=item * name => $name

=item * nullable => 0 or 1 (optional)

Defaults to false.

=item * sequenced => 0 or 1 (optional)

Defaults to false.

=item * default => $default (optional)

=item * attributes => \@attributes (optional)

=item * length => $length (optional)

=item * precision => $precision (optional)

One of either ...

=item * type => $type

... or ...

=item * definition => C<Alzabo::Create::ColumnDefinition> object

=back

=head3 Returns

A new C<Alzabo::Create::Column> object.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=for pod_merge type

=head2 alter

This method allows you to change a column's type, length, and
precision as a single operation and should be instead of calling
C<set_type> followed by C<set_length>.

=head3 Parameters

=over 4

=item * type => $type

=item * length => $length (optional)

=item * precision => $precision (optional)

=back

=head2 set_type ($type)

Sets the column's type.

=head2 set_table (C<Alzabo::Create::Table> object)

Returns/sets the L<C<Alzabo::Create::Table>|Alzabo::Create::Table>
object in which this column is located.

=for pod_merge name

=head2 set_name ($name)

Returns/sets the column's name (a string).

=for pod_merge nullable

=head2 set_nullable (0 or 1)

Sets the nullability of the column (this determines whether nulls are
allowed in the column or not).  Must be 0 or 1.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=for pod_merge attributes

=for pod_merge has_attribute

=head2 set_attributes (@attributes)

Sets the column's attributes.  These are strings describing the column
(for example, valid attributes in MySQL are 'PRIMARY KEY' or
'AUTO_INCREMENT').

=head2 add_attribute ($attribute)

Add an attribute to the column's list of attributes.

=head2 delete_attribute ($attribute)

Delete the given attribute from the column's list of attributes.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=for pod_merge default

=head2 set_default ($default)

Sets the column's default value.

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

=for pod_merge sequenced

=head2 set_sequenced (0 or 1)

Sets the value of the column's sequenced attribute.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=for pod_merge is_primary_key

=for pod_merge is_numeric

=for pod_merge is_character

=for pod_merge is_blob

=for pod_merge definition

=head2 set_definition (C<Alzabo::Create::ColumnDefinition> object)

Sets the
L<C<Alzabo::Create::ColumnDefinition>|Alzabo::Create::ColumnDefinition>
object which holds this column's type information.

=cut
