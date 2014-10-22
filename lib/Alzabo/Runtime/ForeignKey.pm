package Alzabo::Runtime::ForeignKey;

use strict;
use vars qw( $VERSION %DELETED );

use Alzabo::Runtime;

use base qw(Alzabo::ForeignKey);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.26 $ =~ /(\d+)\.(\d+)/;

1;

sub register_insert
{
    shift->_insert_or_update( 'insert', @_ );
}

sub register_update
{
    shift->_insert_or_update( 'update', @_ );
}

sub _insert_or_update
{
    my $self = shift;
    my $type = shift;
    my %vals = @_;

    my $driver = $self->table_from->schema->driver;

    my @where;
    my @vals;

    my $has_nulls = grep { ! defined } values %vals;

    foreach my $pair ( $self->column_pairs )
    {
	# if we're inserting into a table we don't check if its primary
	# key exists elsewhere, no matter what the cardinality of the
	# relation.  Otherwise, we end up in cycles where it is impossible
	# to insert things into the table.
	next if $type eq 'insert' && $pair->[0]->is_primary_key;

	# This code may be unreachable because this may always be
	# caught in Alzabo::Runtime::Table::insert or
	# Alzabo::Runtime::Row::update where it won't let you use null
	# for a non-nullable column.  And in
	# Alzabo::Create::Schema::add_relation we make sure that
	# dependent columns are not nullable.
	if ( ! defined $vals{ $pair->[0]->name } && $self->from_is_dependent )
	{
	    Alzabo::Exception::ReferentialIntegrity->throw( error => 'Referential integrity requires that this column (' . $self->table_from->name . '.' . $pair->[0]->name . ') not be null.' )
	}

	if ( $type eq 'update' || $pair->[1]->is_primary_key )
	{
	    $self->_check_existence( $pair->[1] => $vals{ $pair->[0]->name } )
		if defined $vals{ $pair->[0]->name };
	}

	if ( $self->is_one_to_one && ! $has_nulls )
	{
	    push @where, [ $pair->[0], '=', $vals{ $pair->[0]->name } ];
	    push @vals, $pair->[0]->name . ' = ' . $vals{ $pair->[0]->name };
	}
    }

    if ( $self->is_one_to_one && ! $has_nulls )
    {
	if ( @where && $self->table_from->row_count( where => \@where ) )
	{
	    my $err = '(' . (join ', ', @vals) . ') already exists in the ' . $self->table_from->name . ' table';
	    Alzabo::Exception::ReferentialIntegrity->throw( error => $err );
	}
    }
}

sub _check_existence
{
    my $self = shift;
    my ($col, $val) = @_;

    unless ( $self->table_to->row_count( where => [ $col, '=', $val ] ) )
    {
	Alzabo::Exception::ReferentialIntegrity->throw( error => 'Foreign key must exist in foreign table.  No rows in ' . $self->table_to->name . ' where ' . $col->name . " = $val" );
    }
}

sub register_delete
{
    my $self = shift;
    my $row = shift;

    my @update = grep { $_->nullable } $self->columns_to;

    return unless $self->to_is_dependent || @update;

    # Find the rows in the other table that are related to the row
    # being deleted.
    my @where = map { [ $_->[1], '=', $row->select( $_->[0]->name ) ] } $self->column_pairs;
    my $cursor = $self->table_to->rows_where( where => \@where );

    while ( my $related_row = $cursor->next )
    {
	($cursor->errors)[0]->rethrow if $cursor->errors;

	# This is a class variable so that multiple foreign key
	# objects don't try to delete the same rows
	next if $DELETED{ $related_row->id_as_string };

	if ($self->to_is_dependent)
	{
	    local %DELETED = %DELETED;
	    $DELETED{ $related_row->id_as_string } = 1;
	    # dependent relationship so delete other row (may begin a
	    # chain reaction!)
	    $related_row->delete;
	}
	elsif (@update)
	{
	    # not dependent so set the column(s) to null
	    $related_row->update( map { $_->name => undef } @update );
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

=for pod_merge cardinality

=for pod_merge from_is_dependent

=for pod_merge to_is_dependent

=for pod_merge is_one_to_one

=for pod_merge is_one_to_many

=for pod_merge is_many_to_one

=head2 register_insert ($new_value)

This method takes the proposed column value for a new row and makes
sure that it is valid based on relationship that this object
represents.

=head3 Throws

L<C<Alzabo::Exception::ReferentialIntegrity>|Alzabo::Exceptions>

=head2 register_update ($new_value)

This method takes the proposed new value for a column and makes sure
that it is valid based on relationship that this object represents.

=head3 Throws

L<C<Alzabo::Exception::ReferentialIntegrity>|Alzabo::Exceptions>

=head2 register_delete (C<Alzabo::Runtime::Row> object)

Allows the foreign key to delete rows dependent on the row being
deleted.  Note, this can lead to a chain reaction of cascading
deletions.  You have been warned.

=head3 Throws

L<C<Alzabo::Exception::ReferentialIntegrity>|Alzabo::Exceptions>

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
