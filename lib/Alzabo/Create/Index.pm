package Alzabo::Create::Index;

use strict;
use vars qw($VERSION);

use Alzabo::Create;
use Alzabo::Exceptions ( abbr => 'params_exception' );

use Params::Validate qw( :all );
Params::Validate::validation_options
    ( on_fail => sub { params_exception join '', @_ } );

use base qw(Alzabo::Index);

$VERSION = 2.0;

1;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    validate( @_, { table    => { isa => 'Alzabo::Create::Table' },
		    columns  => { type => ARRAYREF },
		    unique   => { type => BOOLEAN, default => 0 },
		    fulltext => { type => BOOLEAN, default => 0 },
		    function => { type => UNDEF | SCALAR,  default => undef },
		  } );
    my %p = @_;

    my $self = bless {}, $class;

    $self->{table} = $p{table};
    $self->{unique} = $p{unique} || 0;
    $self->{fulltext} = $p{fulltext} || 0;
    $self->{function} = $p{function};

    $self->{columns} = Tie::IxHash->new;

    foreach my $c (@{ $p{columns} })
    {
	my %p = UNIVERSAL::isa( $c, 'Alzabo::Column' ) ? ( column => $c ) : %$c;
	$self->add_column(%p);
    }

    $self->table->schema->rules->validate_index($self);

    return $self;
}

sub add_column
{
    my $self = shift;

    validate( @_, { column => { isa => 'Alzabo::Create::Column' },
		    prefix => { type => SCALAR,
				optional => 1 } } );
    my %p = @_;

    my $new_name = $p{column}->name;

    params_exception "Column $new_name already exists in index."
	if $self->{columns}->EXISTS($new_name);

    $self->{columns}->STORE( $new_name, \%p );

    eval { $self->table->schema->rules->validate_index($self); };

    if ($@)
    {
	$self->{columns}->DELETE($new_name);

        rethrow_exception($@);
    }
}

sub delete_column
{
    my $self = shift;

    validate_pos( @_, { isa => 'Alzabo::Create::Column' } );
    my $c = shift;

    params_exception "Column " . $c->name . " is not part of index."
	unless $self->{columns}->EXISTS( $c->name );

    $self->{columns}->DELETE( $c->name );
}

sub set_prefix
{
    my $self = shift;

    validate( @_, { column => { isa => 'Alzabo::Create::Column' },
		    prefix => { type => SCALAR } } );
    my %p = @_;

    params_exception "Column " . $p{column}->name . " is not part of index."
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

        rethrow_exception($@);
    }
}

sub set_unique
{
    my $self = shift;

    validate_pos( @_, 1 );
    $self->{unique} = shift;
}

sub set_fulltext
{
    my $self = shift;

    validate_pos( @_, 1 );
    $self->{fulltext} = shift;
}

sub register_column_name_change
{
    my $self = shift;

    validate( @_, { column => { isa => 'Alzabo::Create::Column' },
		    old_name => { type => SCALAR } } );
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

=item * columns => [ C<Alzabo::Create::Column> object, .. ]

=item * columns => [ { column => C<Alzabo::Create::Column> object,
                       prefix => $prefix },
                      repeat as needed ...
                   ]

This parameter indicates which columns that are being indexed.  It can
either be an array reference of column objects, or an array reference
of hash references, each with a key called column and one called
prefix.

The prefix key is optional.

=item * unique => $boolean

Indicates whether or not this is a unique index.

=item * fulltext => $boolean

Indicates whether or not this is a fulltext index.

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

=for pod_merge fulltext

=head2 set_fulltext ($boolean)

Set whether or not the index is a fulltext index.

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
