package Alzabo::Create::Table;

use strict;
use vars qw($VERSION);

use Alzabo::Create;
use Alzabo::Exceptions ( abbr => 'params_exception' );

use Params::Validate qw( :all );
Params::Validate::validation_options
    ( on_fail => sub { params_exception join '', @_ } );

use Tie::IxHash;

use base qw(Alzabo::Table);

$VERSION = 2.0;

1;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    validate( @_, { schema => { isa => 'Alzabo::Create::Schema' },
		    name => { type => SCALAR },
		    comment => { type => UNDEF | SCALAR,
				 default => '' },
		  } );
    my %p = @_;

    my $self = bless {}, $class;

    $self->{schema} = $p{schema};

    $self->set_name($p{name});

    $self->{columns} = Tie::IxHash->new;
    $self->{pk} = [];
    $self->{indexes} = Tie::IxHash->new;

    $self->set_comment( $p{comment} );

    # Setting this prevents run time type errors.
    $self->{fk} = {};

    return $self;
}

sub set_name
{
    my $self = shift;

    validate_pos( @_, { type => SCALAR } );
    my $name = shift;

    params_exception "Table $name already exists in schema"
        if $self->schema->has_table($name);

    my @i;
    if ($self->{indexes})
    {
	@i = $self->indexes;
	$self->delete_index($_) foreach @i;
    }

    my $old_name = $self->{name};
    $self->{name} = $name;

    eval
    {
	$self->schema->rules->validate_table_name($self);
    };

    $self->add_index($_) foreach @i;

    if ($@)
    {
	$self->{name} = $old_name;

        rethrow_exception($@);
    }

    if ( $old_name && eval { $self->schema->table($old_name) } )
    {
	$self->schema->register_table_name_change( table => $self,
						   old_name => $old_name );

	foreach my $fk ($self->all_foreign_keys)
	{
	    $fk->table_to->register_table_name_change( table => $self,
						       old_name => $old_name );
	}
    }
}

sub make_column
{
    my $self = shift;
    my %p = @_;

    my $is_pk = delete $p{primary_key};

    my %p2;
    foreach ( qw( before after ) )
    {
	$p2{$_} = delete $p{$_} if exists $p{$_};
    }
    $self->add_column( column => Alzabo::Create::Column->new( table => $self,
							      %p ),
		       %p2 );

    my $col = $self->column( $p{name} );
    $self->add_primary_key($col) if $is_pk;

    return $col;
}

sub add_column
{
    my $self = shift;

    validate( @_, { column => { isa => 'Alzabo::Create::Column' },
		    before => { optional => 1 },
		    after  => { optional => 1 } } );
    my %p = @_;

    my $col = $p{column};

    params_exception "Column " . $col->name . " already exists in " . $self->name
	if $self->{columns}->EXISTS( $col->name );

    $col->set_table($self) unless $col->table eq $self;

    $self->{columns}->STORE( $col->name, $col);

    foreach ( qw( before after ) )
    {
	if ( exists $p{$_} )
	{
	    $self->move_column( $_ => $p{$_},
				column => $col );
	    last;
	}
    }
}

sub delete_column
{
    my $self = shift;

    validate_pos( @_, { isa => 'Alzabo::Create::Column' } );
    my $col = shift;

    params_exception"Column $col doesn't exist in $self->{name}"
	unless $self->{columns}->EXISTS( $col->name );

    $self->delete_primary_key($col) if $col->is_primary_key;

    foreach my $fk ($self->foreign_keys_by_column($col))
    {
	$self->delete_foreign_key($fk);

	foreach my $other_fk ($fk->table_to->foreign_keys( table => $self,
                                                           column => $fk->columns_to ) )
	{
	    $fk->table_to->delete_foreign_key( $other_fk );
	}
    }

    foreach my $i ($self->indexes)
    {
	$self->delete_index($i) if grep { $_ eq $col } $i->columns;
    }

    $self->{columns}->DELETE( $col->name );
}

sub move_column
{
    my $self = shift;

    validate( @_, { column  => { isa => 'Alzabo::Create::Column' },
		    before  => { isa => 'Alzabo::Create::Column',
				 optional => 1 },
		    after   => { isa => 'Alzabo::Create::Column',
				 optional => 1 } } );
    my %p = @_;

    if ( exists $p{before} && exists $p{after} )
    {
	params_exception
            "move_column method cannot be called with both 'before' and 'after' parameters";
    }

    if ( exists $p{before} )
    {
	params_exception "Column " . $p{before}->name . " doesn't exist in schema"
	    unless $self->{columns}->EXISTS( $p{before}->name );
    }
    else
    {
	params_exception "Column " . $p{after}->name . " doesn't exist in schema"
	    unless $self->{columns}->EXISTS( $p{after}->name );
    }

    params_exception "Column " . $p{column}->name . " doesn't exist in schema"
	unless $self->{columns}->EXISTS( $p{column}->name );

    my @pk = $self->primary_key;

    $self->{columns}->DELETE( $p{column}->name );

    my $index;
    if ( $p{before} )
    {
	$index = $self->{columns}->Indices( $p{before}->name );
    }
    else
    {
	$index = $self->{columns}->Indices( $p{after}->name ) + 1;
    }

    $self->{columns}->Splice( $index, 0, $p{column}->name => $p{column} );

    $self->{pk} = [ $self->{columns}->Indices( map { $_->name } @pk ) ];
}

sub add_primary_key
{
    my $self = shift;

    validate_pos( @_, { isa => 'Alzabo::Create::Column' } );
    my $col = shift;

    my $name = $col->name;
    params_exception "Column $name doesn't exist in $self->{name}"
	unless $self->{columns}->EXISTS($name);

    params_exception "Column $name is already a primary key"
        if $col->is_primary_key;

    $self->schema->rules->validate_primary_key($col);

    $col->set_nullable(0);

    my $idx = $self->{columns}->Indices($name);
    push @{ $self->{pk} }, $idx;
}

sub delete_primary_key
{
    my $self = shift;

    validate_pos( @_, { isa => 'Alzabo::Create::Column' } );
    my $col = shift;

    my $name = $col->name;
    params_exception "Column $name doesn't exist in $self->{name}"
	unless $self->{columns}->EXISTS($name);

    params_exception "Column $name is not a primary key"
        unless $col->is_primary_key;

    my $idx = $self->{columns}->Indices($name);
    $self->{pk} = [ grep { $_ != $idx } @{ $self->{pk} } ];
}

sub make_foreign_key
{
    my $self = shift;

    $self->add_foreign_key( Alzabo::Create::ForeignKey->new( @_ ) );
}

sub add_foreign_key
{
    my $self = shift;

    validate_pos( @_, { isa => 'Alzabo::Create::ForeignKey' } );
    my $fk = shift;

    foreach my $c ( $fk->columns_from )
    {
	push @{ $self->{fk}{ $fk->table_to->name }{ $c->name } }, $fk;
    }
}

sub delete_foreign_key
{
    my $self = shift;

    validate_pos( @_, { isa => 'Alzabo::Create::ForeignKey' } );
    my $fk = shift;

    foreach my $c ( $fk->columns_from )
    {
	params_exception "Column " . $c->name . " doesn't exist in $self->{name}"
	    unless $self->{columns}->EXISTS( $c->name );
    }

    params_exception
        "No foreign keys to " . $fk->table_to->name . " exist in $self->{name}"
            unless exists $self->{fk}{ $fk->table_to->name };

    my @new_fk;
    foreach my $c ( $fk->columns_from )
    {
	params_exception
            "Column " . $c->name . " is not a foreign key to " .
            $fk->table_to->name . " in $self->{name}"
                unless exists $self->{fk}{ $fk->table_to->name }{ $c->name };

	foreach my $current_fk ( @{ $self->{fk}{ $fk->table_to->name }{ $c->name } } )
	{
	    push @new_fk, $current_fk unless $current_fk eq $fk;
	}
    }

    foreach my $c ( $fk->columns_from )
    {
	if (@new_fk)
	{
	    $self->{fk}{ $fk->table_to->name }{ $c->name } = \@new_fk;
	}
	else
	{
	    delete $self->{fk}{ $fk->table_to->name }{ $c->name };
	}
    }

    delete $self->{fk}{ $fk->table_to->name }
	unless keys %{ $self->{fk}{ $fk->table_to->name } };
}

sub make_index
{
    my Alzabo::Table $self = shift;

    $self->add_index( Alzabo::Create::Index->new( table => $self,
						  @_ ) );
}

sub add_index
{
    my Alzabo::Table $self = shift;

    validate_pos( @_, { isa => 'Alzabo::Create::Index' } );
    my $i = shift;

    my $id = $i->id;
    params_exception "Index already exists (id $id)."
	if $self->{indexes}->EXISTS($id);

    $self->{indexes}->STORE( $id, $i );

    return $i;
}

sub delete_index
{
    my Alzabo::Table $self = shift;

    validate_pos( @_, { isa => 'Alzabo::Create::Index' } );
    my $i = shift;

    params_exception "Index does not exist."
	unless $self->{indexes}->EXISTS( $i->id );

    $self->{indexes}->DELETE( $i->id );
}

sub register_table_name_change
{
    my $self = shift;

    validate( @_, { table => { isa => 'Alzabo::Create::Table' },
		    old_name => { type => SCALAR } } );
    my %p = @_;

    $self->{fk}{ $p{table}->name } = delete $self->{fk}{ $p{old_name} }
	if exists $self->{fk}{ $p{old_name} };
}

sub register_column_name_change
{
    my $self = shift;

    validate( @_, { column => { isa => 'Alzabo::Create::Column' },
		    old_name => { type => SCALAR } } );
    my %p = @_;

    my $new_name = $p{column}->name;
    my $index = $self->{columns}->Indices( $p{old_name} );
    $self->{columns}->Replace( $index, $p{column}, $new_name );

    foreach my $t ( keys %{ $self->{fk} } )
    {
	$self->{fk}{$t}{$new_name} = delete $self->{fk}{$t}{ $p{old_name} }
	    if exists $self->{fk}{$t}{ $p{old_name} };
    }

    my @i = $self->{indexes}->Values;
    $self->{indexes} = Tie::IxHash->new;
    foreach my $i (@i)
    {
	$i->register_column_name_change(%p);
	$self->add_index($i);
    }
}

sub set_comment { $_[0]->{comment} = defined $_[1] ? $_[1] : '' }

sub save_current_name
{
    my $self = shift;

    $self->{last_instantiated_name} = $self->name;

    foreach my $column ( $self->columns )
    {
        $column->save_current_name;
    }
}

sub former_name { $_[0]->{last_instantiated_name} }

__END__

=head1 NAME

Alzabo::Create::Table - Table objects for schema creation

=head1 SYNOPSIS

  use Alzabo::Create::Table;

=head1 DESCRIPTION

This class represents tables in the schema.  It contains column,
index, and foreign key objects.

=head1 INHERITS FROM

C<Alzabo::Table>

=for pod_merge merged

=head1 METHODS

=head2 new

=head3 Parameters

=over 4

=item * schema => C<Alzabo::Create::Schema> object

The schema to which this table belongs.

=item * name => $name

=item * comment => $comment

An optional comment.

=back

=head3 Returns

A new C<Alzabo::Create::Table> object.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=for pod_merge schema

=for pod_merge name

=head2 set_name ($name)

Changes the name of the table.

=for pod_merge column

=for pod_merge columns

=for pod_merge has_column

=head2 make_column

Creates a new L<C<Alzabo::Create::Column>|Alzabo::Create::Column>
object and adds it to the table.  This object is the function's return
value.

In addition, if the before or after parameter is given, the
L<C<move_column>|move_column> method is called to move the new column.

This method takes all of the same parameters as the
L<C<Alzabo::Create::Column>|Alzabo::Create::Column> method except the
C<table> parameter, which is automatically added.

=head3 Additional Parameters

=over 4

=item * primary_key => 0 or 1

If this value is true, then the
L<C<add_primary_key>|Alzabo::Create::Table/add_primary_key
(Alzabo::Create::Column object)> method will be called after this new
column is made in order to make a it a primary key for the table.

=item * after => C<Alzabo::Create::Column> object

... or ...

=item * before => C<Alzabo::Create::Column> object

=back

=head3 Returns

A new L<C<Alzabo::Create::Column>|Alzabo::Create::Column> object.

=head2 add_column

Adds a column to the table.  If a before or after parameter is given
then the L<C<move_column>|move_column> method will be called to move
the new column to the appropriate position.

=head3 Parameters

=over 4

=item * column => C<Alzabo::Create::Column> object

=item * after => C<Alzabo::Create::Column> object (optional)

... or ...

=item * before => C<Alzabo::Create::Column> object (optional)

=back

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=head2 delete_column (C<Alzabo::Create::Column> object)

Deletes a column from the table.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=head2 move_column

=head3 Parameters

=over 4

=item * column => C<Alzabo::Create::Column> object

The column to move.

and either ...

=item * before => C<Alzabo::Create::Column> object

Move the column before this column

... or ...

=item * after => C<Alzabo::Create::Column> object

Move the column after this column.

=back

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=for pod_merge primary_key

=for pod_merge primary_key_size

=head2 add_primary_key (C<Alzabo::Create::Column> object)

Make the given column part of the table's primary key.  The primary
key is an ordered list of columns.  The given column will be added to
the end of this list.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=head2 delete_primary_key (C<Alzabo::Create::Column> object)

Delete the given column from the primary key.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=for pod_merge foreign_keys

=for pod_merge foreign_keys_by_table

=for pod_merge foreign_keys_by_column

=for pod_merge all_foreign_keys

=head2 make_foreign_key (see below)

Takes the same parameters as the
L<C<Alzabo::Create::ForeignKey-E<gt>new>|Alzabo::Create::ForeignKey/new>
method except for the table parameter, which is automatically added.
The foreign key object that is created is then added to the table.

=head3 returns

A new L<C<Alzabo::Create::ForeignKey>|Alzabo::Create::ForeignKey>
object.

=head2 add_foreign_key (C<Alzabo::Create::ForeignKey> object)

Adds the given foreign key to the table.

=head2 delete_foreign_key (C<Alzabo::Create::ForeignKey> object)

Deletes the given foreign key from the table

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=for pod_merge index

=for pod_merge indexes

=head2 make_index

Takes the same parameters as the
L<C<Alzabo::Create::Index-E<gt>new>|Alzabo::Create::Index/new> method
except for the C<table> parameter, which is automatically added.  The
index object that is created is then added to the table.

=head3 Returns

A new L<C<Alzabo::Create::Index>|Alzabo::Create::Index> object.

=head2 add_index (C<Alzabo::Create::Index> object)

Adds the given index to the table.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=head2 delete_index (C<Alzabo::Create::Index> object)

Deletes an index from the table.

=head3 Throws

L<C<Alzabo::Exception::Params>|Alzabo::Exceptions>

=for pod_merge comment

=head2 set_comment ($comment)

Set the comment for the table object.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
