package Alzabo::Create::Table;

use strict;
use vars qw($VERSION);

use Alzabo::Create;

use Tie::IxHash;

use base qw(Alzabo::Table);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.23 $ =~ /(\d+)\.(\d+)/;

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

    $self->{schema} = $p{schema};

    AlzaboException->throw( error => "No name provided for new table" )
	unless exists $p{name};
    $self->set_name($p{name});

    $self->{columns} = Tie::IxHash->new;
    $self->{pk} = Tie::IxHash->new;
    $self->{indexes} = Tie::IxHash->new;

    # Setting this prevents run time type errors.
    $self->{fk} = {};

    return $self;
}

sub set_name
{
    my Alzabo::Create::Table $self = shift;
    my $name = shift;

    my $old_name = $self->{name};
    $self->{name} = $name;
    eval
    {
	$self->schema->rules->validate_table_name($self);
    };
    $self->{name} = $old_name if $@;
    if ($@)
    {
	$@->rethrow;
    }

    if ( $old_name && $self->schema->table($old_name) )
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
    my Alzabo::Create::Table $self = shift;
    my %p = @_;

    my $is_pk = delete $p{primary_key};

    $self->add_column( column => Alzabo::Create::Column->new( table => $self,
							      %p ),
		       %p );

    my $col = $self->column( $p{name} );
    $self->add_primary_key($col) if $is_pk;

    return $col;
}

sub add_column
{
    my Alzabo::Create::Table $self = shift;
    my %p = @_;

    my $col = $p{column};

    AlzaboException->throw( error => "Column " . $col->name . " already exists" )
	if $self->{columns}->EXISTS( $col->name );

    $col->set_table($self) unless $col->table eq $self;

    $self->{columns}->STORE( $col->name, $col);

    if ( exists $p{after} )
    {
	$self->move_column( after => $p{after},
			    column => $self->column( $p{name} ) );
    }
}

sub delete_column
{
    my Alzabo::Create::Table $self = shift;
    my $col = shift;

    AlzaboException->throw( error => "Column $col doesn't exist in $self->{name}" )
	unless $self->{columns}->EXISTS( $col->name );

    $self->delete_primary_key($col) if $self->column_is_primary_key($col);

    foreach my $fk ($self->foreign_keys_by_column($col))
    {
	$self->delete_foreign_key($fk);

	foreach my $other_fk ($fk->table_to->foreign_keys_by_column( $fk->column_to ) )
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
    my Alzabo::Create::Table $self = shift;
    my %p = @_;

    if ( exists $p{before} && exists $p{after} )
    {
	AlzaboException->throw( error => "move_column method cannot be called with both 'before' and 'after parameters'" );
    }

    if ( exists $p{before} )
    {
	AlzaboException->throw( error => "Column " . $p{before}->name . " doesn't exist in schema" )
	    unless $self->{columns}->EXISTS( $p{before}->name );
    }
    else
    {
	AlzaboException->throw( error => "Column " . $p{after}->name . " doesn't exist in schema" )
	    unless $self->{columns}->EXISTS( $p{after}->name );
    }

    AlzaboException->throw( error => "Column " . $p{column}->name . " doesn't exist in schema" )
	unless $self->{columns}->EXISTS( $p{column}->name );

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
}

sub add_primary_key
{
    my Alzabo::Create::Table $self = shift;
    my $col = shift;

    my $name = $col->name;
    AlzaboException->throw( error => "Column $name doesn't exist in $self->{name}" )
	unless exists $self->{columns}{$name};

    AlzaboException->throw( error => "Column $name is already a primary key" )
	if $self->{pk}->EXISTS($name);

    $self->schema->rules->validate_primary_key($col);

    $col->set_null(0);

    $self->{pk}->STORE( $name, $col );
}

sub delete_primary_key
{
    my Alzabo::Create::Table $self = shift;
    my $col = shift;

    my $name = $col->name;
    AlzaboException->throw( error => "Column $name doesn't exist in $self->{name}" )
	unless $self->{columns}->EXISTS($name);

    AlzaboException->throw( error => "Column $name is not a primary key" )
	unless $self->{pk}->EXISTS($name);

    $self->{pk}->DELETE($name);
}

sub make_foreign_key
{
    my Alzabo::Create::Table $self = shift;

    $self->add_foreign_key( Alzabo::Create::ForeignKey->new( table_from => $self, @_ ) );
}

sub add_foreign_key
{
    my Alzabo::Create::Table $self = shift;
    my $fk = shift;

    push @{ $self->{fk}{ $fk->table_to->name }{ $fk->column_from->name } }, $fk;
}

sub delete_foreign_key
{
    my Alzabo::Create::Table $self = shift;
    my $fk = shift;

    AlzaboException->throw( error => "Column " . $fk->column_from->name . " doesn't exist in $self->{name}" )
	unless exists $self->{columns}{ $fk->column_from->name };

    AlzaboException->throw( error => "No foreign keys to " . $fk->table_to->name . " exist in $self->{name}" )
	unless exists $self->{fk}{ $fk->table_to->name };

    AlzaboException->throw( error => "Column " . $fk->column_from->name . " is not a foreign key to " . $fk->table_to->name . " in $self->{name}" )
	unless exists $self->{fk}{ $fk->table_to->name }{ $fk->column_from->name };

    my @current_fk = @{ $self->{fk}{ $fk->table_to->name }{ $fk->column_from->name } };
    my @new_fk;
    foreach my $current_fk (@current_fk)
    {
	unless ($fk eq $current_fk)
	{
	    push @new_fk, $current_fk;
	}
    }
    if (@new_fk)
    {
	$self->{fk}{ $fk->table_to->name }{ $fk->column_from->name } = \@new_fk;
    }
    else
    {
	delete $self->{fk}{ $fk->table_to->name }{ $fk->column_from->name };
    }

    delete $self->{fk}{ $fk->table_to->name }
	unless keys %{  $self->{fk}{ $fk->table_to->name } };
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
    my $i = shift;

    AlzaboException->throw( error => "Index already exists." )
	if $self->{indexes}->EXISTS( $i->id );

    $self->{indexes}->STORE( $i->id, $i );

    return $i;
}

sub delete_index
{
    my Alzabo::Table $self = shift;
    my $i = shift;

    AlzaboException->throw( error => "Index does not exist." )
	unless $self->{indexes}->EXISTS( $i->id );

    $self->{indexes}->DELETE( $i->id );
}

sub register_table_name_change
{
    my Alzabo::Create::Table $self = shift;
    my %p = @_;

    $self->{fk}{ $p{table}->name } = delete $self->{fk}{ $p{old_name} }
	if exists $self->{fk}{ $p{old_name} };
}

sub register_column_name_change
{
    my Alzabo::Create::Table $self = shift;
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

    if ( $self->{pk}->EXISTS( $p{old_name} ) )
    {
	my $index = $self->{pk}->Indices( $p{old_name} );
	$self->{pk}->Replace( $index, $p{column}, $new_name );
    }
}

__END__

=head1 NAME

Alzabo::Create::Table - Table objects for schema creation

=head1 SYNOPSIS

  use Alzabo::Create::Table;

=head1 DESCRIPTION

This class represents tables in the schema.

=head1 METHODS

=over 4

=item * new

Takes the following parameters:

=item -- schema => Alzabo::Create::Schema object

The schema that this table belongs to.

=item -- name => $name

This method returns a new table object.

Exceptions:

 AlzaboException - missing required parameter.
 AlzaboException - invalid table name.

=item * set_name ($name)

Changes the name of the table.

Exceptions:

 AlzaboException - invalid table name.

=item * make_column

Takes all the parameters the Alzabo::Create::Column method except the
'table' parameter, which is automatically added.  In addition it takes
the following parameter:

=item -- primary_key => 0 or 1

If this value is true, then the C<add_primary_key> method will be
called after this new column is made in order to make a it a primary
key for the table.

Creates a new Alzabo::Create::Column object and adds it to the table.
This object is the function's return value.

In addition, if the 'after' parameter is given, the C<move_column>
method is called to move the new column.

Exceptions:

 AlzaboException - column already exists.

=item * delete_column (Alzabo::Create::Column object)

Deletes a column from the table.

Exeptions:

AlzaboException - column is not in the table.

=item * move_column

Takes the following parameters:

=item -- column => Alzabo::Create::Column object

The column to move.

and either ...

=item -- before => Alzabo::Create::Column object

Move the column before this column

... or ...

=item -- after => Alzabo::Create::Column object

Move the column after this column.

Exceptions:

 AlzaboException - one of the columns passed in is not part of the
 table.
 AlzaboException - both a 'before' and 'after' parameter were
 specified.

=item * add_primary_key (Alzabo::Create::Column)

Make the given column part of the table's primary key.  The primary
key is an ordered list of columns.  The given column will be added to
the end of this list.

Exceptions:

 AlzaboException - the column is not part of the table.
 AlzaboException - the column is already part of the primary key.

=item * delete_primary_key (Alzabo::Create::Column)

Delete the given column from the primary key.

Exceptions:

 AlzaboException - the column is not part of the table.
 AlzaboException - the column is not part of the primary key.

=item * make_foreign_key (see below)

Takes the same parameters as the Alzabo::Create::ForeignKey C<new>
method except for the 'table' parameter, which is automatically added.
The foreign key object that is created is then added to the table.

Exceptions:

 See Alzabo::Create::ForeignKey C<new> documentation.

=item * add_foreign_key (Alzabo::Create::ForeignKey object)

Adds the given foreign key to the table.

Exceptions:

 AlzaboException - a foreign key to the given table from the given
 column already exists.

=item * delete_foreign_key (Alzabo::Create::ForeignKey object)

Deletes the foreign key from the table

Exceptions:

 AlzaboException - no such foreign key exists in the table.

=item * make_index (see below)

Takes the same parameters as the Alzabo::Create::Index C<new> method
except for the 'table' parameter, which is automatically added.  The
index object that is created is then added to the table.

Exceptions:

 See Alzabo::Create::Index C<new> documentation.

=item * delete_index (Alzabo::Create::Index object)

Deletes an index from the table.

Exceptions:

 AlzaboException - the index is not part of the table.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
