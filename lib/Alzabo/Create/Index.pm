package Alzabo::Create::Index;

use strict;
use vars qw($VERSION);

use Alzabo::Create;

use base qw(Alzabo::Index);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.14 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;
    my %p = @_;

    my $self = bless {}, $class;

    $self->{table} = $p{table};
    $self->{unique} = $p{unique} || 0;

    $self->{columns} = Tie::IxHash->new;

    foreach my $c (@{ $p{columns} })
    {
	$self->add_column(%$c);
    }

    $self->table->schema->rules->validate_index($self);

    return $self;
}

sub add_column
{
    my Alzabo::Create::Index $self = shift;
    my %p = @_;

    my $new_name = $p{column}->name;

    Alzabo::Exception::Params->throw( "Column $new_name already exists in index." )
	if $self->{columns}->EXISTS($new_name);

    $self->{columns}->STORE( $new_name, \%p );

    eval { $self->table->schema->rules->validate_index($self); };

    if ($@)
    {
	$self->{columns}->DELETE($new_name);
	$@->rethrow;
    }
}

sub delete_column
{
    my Alzabo::Create::Index $self = shift;
    my $c = shift;

    Alzabo::Exception::Params->throw( error => "Column " . $c->name . " is not part of index." )
	unless $self->{columns}->EXISTS( $c->name );

    $self->{columns}->DELETE( $c->name );
}

sub set_prefix
{
    my Alzabo::Create::Index $self = shift;
    my %p = @_;

    Alzabo::Exception::Params->throw( error => "Column " . $p{column}->name . " is not part of index." )
	unless $self->{columns}->EXISTS( $p{column}->name );

    my $col = $self->{columns}->FETCH( $p{column}->name );
    my $old_val = delete $col->{prefix};
    $col->{prefix} = $p{prefix};

    eval { $self->table->schema->rules->validate_index($self); };

    if ($@)
    {
	if ($old_val)
	{
	    $col->{prefix} = $old_val;
	}
	else
	{
	    delete $col->{prefix};
	}
	$@->rethrow;
    }
}

sub set_unique
{
    my Alzabo::Create::Index $self = shift;

    $self->{unique} = shift;
}

sub register_column_name_change
{
    my Alzabo::Create::Index $self = shift;
    my %p = @_;

    return unless $self->{columns}->EXISTS( $p{old_name} );

    my $new_name = $p{column}->name;

    my $index = $self->{columns}->Indices( $p{old_name} );
    my $val = $self->{columns}->Values($index);
    $val->{column} = $p{column};
    $self->{columns}->Replace( $index, $val, $new_name );
}

__END__

=head1 NAME

Alzabo::Create::Index - Index objects for schema creation

=head1 SYNOPSIS

  use Alzabo::Create::Index;

=for pod_merge DESCRIPTION

=head1 INHERITS FROM

C<Alzabo::Index>

=for pod_merge merged

=head1 METHODS

=head2 new

=head3 Parameters

=over 4

=item * table => C<Alzabo::Create::Table> object

The table that this index is indexing.

=item * columns => [ { column => C<Alzabo::Create::Column> object,
                       prefix => $prefix },
                      repeat as needed ...
                   ]

This is a list of columns that are being indexes.  The prefix part of
the hashref is optional.

=item * unique => $boolean

Indicates whether or not this is a unique index.

=back

=head3 Returns

A new C<Alzabo::Create::Index> object.

=for pod_merge table

=for pod_merge columns

=head2 add_column

Add a column to the index.

=head3 Parameters

=over 4

=item * column => C<Alzabo::Create::Column> object

=item * prefix => $prefix (optional)

=back

=head2 delete_column (C<Alzabo::Create::Column> object)

Delete the given column from the index.

=for pod_merge prefix

=head2 set_prefix

=head3 Parameters

=over 4

=item * column => C<Alzabo::Create::Column> object

=item * prefix => $prefix

=back

=for pod_merge unique

=head2 set_unique ($boolean)

Set whether or not the index is a unique index.

=head2 register_column_name_change

=head3 Parameters

=over 4

=item * column => C<Alzabo::Create::Column> object

The column (with the new name already set).

=item * old_name => $old_name

=back

Called by the owning table object when a column changes.  You should
never need to call this yourself.

=for pod_merge id

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
