package Alzabo::Runtime::ForeignKey;

use strict;
use vars qw( $VERSION %DELETED );

use Alzabo::Runtime;

use base qw(Alzabo::ForeignKey);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.7 $ =~ /(\d+)\.(\d+)/;

1;

sub register_update
{
    my Alzabo::Runtime::ForeignKey $self = shift;
    my $newval = shift;

    my $driver = $self->table_from->schema->driver;

    if (defined $newval)
    {
	my $sql = 'SELECT 1 FROM  ' . $self->table_to->name . ' WHERE ' . $self->column_to->name . ' = ?';

	unless ( $driver->one_row( sql => $sql,
				   bind => $newval ) )
	{
	    AlzaboReferentialIntegrityException->throw( error => 'Foreign key must exist in foreign table.  No rows in ' . $self->table_to->name . ' where ' . $self->column_to->name . " = $newval" );
	}
    }
    else
    {
	if ( ($self->min_max_from)[0] eq '1' )
	{
	    AlzaboReferentialIntegrityException->throw( error => 'Referential integrity requires that this column (' . $self->table_from->name . '.' . $self->column_from->name . ' not be null.' );
	}
    }

    # This should rarely be triggered except for inserts
    unless ( ($self->min_max_to)[1] eq 'n' )
    {
	my $sql = 'SELECT COUNT(*) FROM  ' . $self->table_from->name . ' WHERE ' . $self->column_from->name . ' = ?';
	AlzaboReferentialIntegrityException->throw( error => "Value ($newval) already exists in table " . $self->table_from->name . '.' )
	    if $driver->one_row( sql => $sql,
				 bind => $newval );
    }
}

sub register_delete
{
    my Alzabo::Runtime::ForeignKey $self = shift;
    my $row = shift;

    my $delete = ($self->min_max_to)[0] eq '1';
    my $update = ! $self->column_to->is_primary_key;

    return unless $delete || $update;

    # Make the rows in the other table that contain the relation to
    # the row being deleted.
    my $col = $self->column_from->name;

    my $cursor = $self->table_to->rows_where( where => { $self->column_to->name => $row->select($col) } );
    while ( my $row = $cursor->next_row )
    {
	($cursor->errors)[0]->rethrow if $cursor->errors;

	# This is a class variable so that multiple foreign key
	# objects don't try to delete the same rows
	next if $DELETED{ $row->id };

	if ($delete)
	{
	    $DELETED{ $row->id } = 1;
	    # dependent relationship so delete other row (may begin a
	    # chain reaction!)
	    $row->delete;

	    delete $DELETED{ $row->id };
	}
	elsif ($update)
	{
	    # not dependent so set the column to null
	    $row->update( $self->column_to->name => undef );
	}
    }
}

__END__

=head1 NAME

Alzabo::Runtime::ForeignKey - Foreign key objects

=head1 SYNOPSIS

  use Alzabo::Runtime::ForeignKey;

=head1 DESCRIPTION

Objects in this class maintain referential integrity.  This is really
only useful when your RDBMS can't do this itself (like MySQL).  For a
RDBMS that can do this, this feature can be turned off (see the
Alzabo::Runtime documentation).

=head1 METHODS

=over 4

=item * register_update ($new_value)

This method takes the proposed new value for a column and makes sure
that it is valid based on the type of relationship between the two
tables.

Exceptions:

 AlzaboReferentialIntegrityException - something about this update
 violates referential integrity.

=item * register_delete (Alzabo::Runtime::Row object)

Allows the foreign key to delete rows dependent on the row being
deleted.  Note, this can lead to a chain reaction of cascading
deletions.  You have been warned.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
