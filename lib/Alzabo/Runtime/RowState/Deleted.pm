package Alzabo::Runtime::RowState::Deleted;

use strict;

use Alzabo::Runtime;

use Params::Validate qw( :all );
Params::Validate::validation_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

BEGIN
{
    no strict 'refs';
    foreach my $meth ( qw( select select_hash refresh update delete id_as_string ) )
    {
        *{__PACKAGE__ . "::$meth"} =
            sub { $_[1]->_no_such_row_error };
    }
}

sub is_potential { 0 }

sub is_live { 0 }

sub is_deleted { 1 }


1;

__END__

=head1 NAME

Alzabo::Runtime::PotentialRow - Row objects that aren't yet in the database

=head1 SYNOPSIS

  my $row = $table->potential_row;

  my $other = $table->potential_row( values => { name => 'Ralph' } );

  $row->make_live;  # $row is now a _real_ row object!

=head1 DESCRIPTION

These objects represent potential rows, rows which do not yet exist in
the database.  These are created via the
L<C<Alzabo::Runtime::Table-E<gt>potential_row>|Alzabo::Runtime::Table/potential_row>
method.

These objects do not interact with the caching system.

They are useful when you need a placeholder object which you can
update and select from, but you don't actually want to commit the data
to the database.

Once L<C<make_live>|/make_live> is called, the object is tranformed
into a row of the appropriate class.

When a new object of this class is created, it checks for defaults for
each column and uses them for its value if no other value is provided
by the user.

Potential rows have looser constraints for column values than regular
rows.  When creating a new potential row, it is ok if none of the
columns are defined.  However, you cannot update a column in a
potential row to NULL if the column is not nullable.

=head1 METHODS

For most methods, this object works exactly like an
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> object.  However, this
object cannot be deleted, nor does it have an id.

In addition, no attempt is made to enforce L<referential integrity
constraints|Alzabo/Referential Integrity> on this object.

=head2 select

=head2 select_hash

=head2 update

=head2 table

=head2 rows_by_foreign_key

These methods all operate as they do for
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> objects.

=head2 delete

This method throws an exception as it is not meaningful to try to
delete a row that does not exist in the database.

=head2 id_as_string

This method returns an empty string.  Since primary keys may not be
known til an insert, in the case of sequenced columns, there is no way
to calculate an id.

=head2 is_live

Indicates whether or not a given row is a real or potential row.

=head2 make_live

This method inserts the row into the database and tranforms the row
object, in place, into a row of the appropriate class.

This means that all references to the potential row object will now be
references to the real object (which is a good thing).

This method can take any parameters that can be passed to the
L<C<Alzabo::Runtime::Table-E<gt>insert>|Alzabo::Runtime::Table/insert>
method, such as C<no_cache>.

Any columns already set will be passed to the C<insert> method,
including primary key values.  However, these will be overriddenn, on
a column by column basis, by a C<pk> or C<values> parameters given to
the C<make_live> method.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
