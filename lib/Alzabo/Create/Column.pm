package Alzabo::Create::Column;

use strict;
use vars qw($VERSION);

use Alzabo::Create;

use base qw(Alzabo::Column);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.16 $ =~ /(\d+)\.(\d+)/;

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
    my Alzabo::Create::Column $self = shift;
    my %p = @_;

    AlzaboException->throw( error => 'No table provided' )
	unless $p{table};
    $self->set_table( $p{table} );

    $self->set_name( $p{name} );

    $self->{null} = $p{null} || 0;

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
}

sub set_table
{
    my Alzabo::Create::Column $self = shift;

    $self->{table} = shift;
}

sub set_name
{
    my Alzabo::Create::Column $self = shift;
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

sub set_null
{
    my Alzabo::Create::Column $self = shift;
    my $n = shift;

    AlzaboException->throw( error => "Invalid value for null/not null attribute: $n" )
	unless $n eq '1' || $n eq '0';

    AlzaboException->throw( error => "Primary key column cannot be null" )
	if $n eq '1' && $self->table->column_is_primary_key($self);

    $self->{null} = $n;
}

sub set_attributes
{
    my Alzabo::Create::Column $self = shift;

    tie %{ $self->{attributes} }, 'Tie::IxHash';

    foreach (@_)
    {
	$self->add_attribute($_);
    }
}

sub add_attribute
{
    my Alzabo::Create::Column $self = shift;
    my $attr = shift;

    $attr =~ s/^\s+//;
    $attr =~ s/\s+$//;

    $self->table->schema->rules->validate_column_attribute( column => $self,
							    attribute => $attr );

    $self->{attributes}{$attr} = 1;
}

sub delete_attribute
{
    my Alzabo::Create::Column $self = shift;
    my $attr = shift;

    AlzaboException->throw( error => "Column " . $self->name . " doesn't have attribute $attr" )
	unless exists $self->{attributes}{$attr};

    delete $self->{attributes}{$attr};
}

sub set_type
{
    my Alzabo::Create::Column $self = shift;
    my $t = shift;

    $self->{definition}->set_type($t);
}

sub set_sequenced
{
    my Alzabo::Create::Column $self = shift;
    my $s = shift;

    AlzaboException->throw( error => "Invalid value for sequenced attribute: $s" )
	unless $s eq '1' || $s eq '0';

    $self->table->schema->rules->validate_sequenced_attribute($self)
	if $s eq '1';

    $self->{sequenced} = $s;
}

sub set_definition
{
    my Alzabo::Create::Column $self = shift;
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
Additional data is held in a ColumnDefinition object, which is used to
allow two columns to share a type (which is good when two columns in
different tables are related as it means that if the type of one is
changed, the other is also.)

=head1 METHODS

=over 4

=item * new

Takes the following parameters:

=item -- table => Alzabo::Table object

=item -- name => $name

=item -- null => 0 or 1

=item -- sequenced => 0 or 1

=item -- attributes => \@attributes

One of either ...

=item -- type => $type

... or ...

=item -- definition => Alzabo::Create::ColumnDefinition object

Returns a new Alzabo::Create::Column object.

Exceptions:

 AlzaboException - An invalid value for one of the parameters was
 given.

=item * set_table (Alzabo::Table object)

Returns/sets the table object in which this column is located.

Exceptions:

=item * set_name ($name)

Returns/sets the column's name (a string).

Exceptions:

 AlzaboRDBMSRulesException - invalid column name

=item * set_null (0 or 1)

Returns/sets the null value of the column (this determines whether
nulls are allowed in the column or not).  Must be 0 or 1.

Exceptions:

 AlzaboException - invalid value or attempt to set primary key
 column's null value to true.

=item * set_attributes (@attributes)

Returns/sets the column's attributes.  These are strings describing
the column (for example, valid attributes in MySQL are 'PRIMARY KEY'
or 'AUTO_INCREMENT'.

The return value of this method is a list.

Exceptions:

 AlzaboRDBMSRulesException - invalid attribute

=item * add_attribute ($attribute)

Add an attribute to the column's list of attributes.

Exceptions:

 AlzaboRDBMSRulesException - invalid attribute

=item * delete_attribute ($attribute)

Delete the given attribute from the column.

Exceptions:

 AlzaboException - column does not have this attribute.

=item * set_type ($type)

Sets the column's type.

Exceptions:

 AlzaboException - invalid type.

=item * set_sequenced (0 or 1)

Sets the value of the column's sequenced attribute.

Exceptions:

 AlzaboException - invalid argument value.

=item * set_definition (Alzabo::Create::ColumnDefinition object)

Sets the Alzabo::Create::ColumnDefinition object which holds this
column's type information.

=back

=cut
