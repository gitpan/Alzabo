package Alzabo::Runtime::ForeignKey;

use strict;
use vars qw( $VERSION %DELETED );

use Alzabo::Runtime;

use base qw(Alzabo::ForeignKey);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.15 $ =~ /(\d+)\.(\d+)/;

1;

sub register_insert
{
    my $self = shift;
    my %vals = @_;

    # if we're inserting into a table we don't check if its primary
    # key exists elsewhere, no matter what the cardinality of the
    # relation.  Otherwise, we end up in cycles where it is impossible
    # to insert things into the table.
    foreach my $pair ( $self->column_pairs )
    {
	next if $pair->[0]->is_primary_key;
	if ( !defined $vals{ $pair->[0]->name } && ($self->min_max_from)[0] eq '1' )
	{
	    Alzabo::Exception::ReferentialIntegrity->throw( error => 'Referential integrity requires that this column (' . $self->table_from->name . '.' . $pair->[0]->name . ') not be null.' )
	}

	$self->_check_existence( $pair->[1] => $vals{ $pair->[0]->name } )
	    if defined $vals{ $pair->[0]->name };
    }
}

sub register_update
{
    my $self = shift;
    my %vals = @_;

    my $driver = $self->table_from->schema->driver;

    foreach my $pair ( $self->column_pairs )
    {
	if ( !defined $vals{ $pair->[0]->name } && ($self->min_max_from)[0] eq '1' )
	{
	    Alzabo::Exception::ReferentialIntegrity->throw( error => 'Referential integrity requires that this column (' . $self->table_from->name . '.' . $pair->[0]->name . ') not be null.' )
	}

	$self->_check_existence( $pair->[1] => $vals{ $pair->[0]->name } )
	    if defined $vals{ $pair->[0]->name };

	# This should rarely be triggered.
	unless ( ($self->min_max_to)[1] eq 'n' )
	{
	    my $sql = ( $self->table->schema->sql->
			count('*')->
			from( $self->table_form )->
			where( $pair->[0], '=', $vals{ $pair->[0]->name } )
		      );

	    if ( $driver->one_row( sql => $sql->sql,
				   bind => $sql->bind ) )
	    {
		Alzabo::Exception::ReferentialIntegrity->throw( error => "Value (" . $vals{ $pair->[0]->name } . ") already exists in table " . $self->table_from->name . '.' );
	    }
	}
    }
}

sub _check_existence
{
    my $self = shift;
    my ($col, $val) = @_;

    my $driver = $self->table_from->schema->driver;

    my $sql = ( $self->table_from->schema->sqlmaker->
		select->count('*')->
		from( $self->table_to )
	      );

    $sql->where( $col, '=', $val );

    unless ( $driver->one_row( sql => $sql->sql,
			       bind => $sql->bind ) )
    {
	Alzabo::Exception::ReferentialIntegrity->throw( error => 'Foreign key must exist in foreign table.  No rows in ' . $self->table_to->name . ' where ' . $col->name . " = $val" );
    }
}

sub register_delete
{
    my $self = shift;
    my $row = shift;

    my $delete = ($self->min_max_to)[0] eq '1';
    my @update = grep { ! $_->is_primary_key } $self->columns_to;

    return unless $delete || @update;

    # Make the rows in the other table that contain the relation to
    # the row being deleted.
    my @where = map { [ $_->[1], '=', $row->select( $_->[0]->name ) ] } $self->column_pairs;
    my $cursor = $self->table_to->rows_where( where => \@where );
    while ( my $row = $cursor->next_row )
    {
	($cursor->errors)[0]->rethrow if $cursor->errors;

	# This is a class variable so that multiple foreign key
	# objects don't try to delete the same rows
	next if $DELETED{ $row->id };

	if ($delete)
	{
	    local %DELETED = %DELETED;
	    $DELETED{ $row->id } = 1;
	    # dependent relationship so delete other row (may begin a
	    # chain reaction!)
	    $row->delete;
	}
	elsif (@update)
	{
	    # not dependent so set the column(s) to null
	    $row->update( map { $_->name => undef } @update );
	}
    }
}

__END__

=head1 NAME

Alzabo::Runtime::ForeignKey - Foreign key objects

=head1 SYNOPSIS

  $fk->register_insert( $value_for_column );
  $fk->register_update( $new_value_for_column );
  $fk->register_delete( $row_being_deleted );

=head1 DESCRIPTION

Objects in this class maintain referential integrity.  This is really
only useful when your RDBMS can't do this itself (like MySQL).  For a
RDBMS that can do this, this feature can be turned off
(by doing C<$schema-E<gt>set_referential_integrity(0)>).

=head1 INHERITS FROM

C<Alzabo::ForeignKey>

=for pod_merge merged

=head1 METHODS

=for pod_merge table_from

=for pod_merge table_to

=for pod_merge columns_from

=for pod_merge columns_to

=for pod_merge min_max_from

=for pod_merge min_max_to

=for pod_merge cardinality

=head2 register_insert ($new_value)

This method takes the proposed column value for a new row and makes
sure that it is valid based on relationship that this object
represents.

=head3 Throws

L<C<Alzabo::Exception::ReferentialIntegrity>Alzabo::Exceptions>

=head2 register_update ($new_value)

This method takes the proposed new value for a column and makes sure
that it is valid based on relationship that this object represents.

=head3 Throws

L<C<Alzabo::Exception::ReferentialIntegrity>Alzabo::Exceptions>

=head2 register_delete (C<Alzabo::Runtime::Row> object)

Allows the foreign key to delete rows dependent on the row being
deleted.  Note, this can lead to a chain reaction of cascading
deletions.  You have been warned.

=head3 Throws

L<C<Alzabo::Exception::ReferentialIntegrity>Alzabo::Exceptions>

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
