package Alzabo::RDBMSRules;

use strict;
use vars qw($VERSION);

use Alzabo::Exceptions;
use Alzabo::Util;
use Params::Validate qw( validate validate_pos );
Params::Validate::set_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.33 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    shift;
    my %p = @_;

    eval "use Alzabo::RDBMSRules::$p{rdbms};";
    Alzabo::Exception::Eval->throw( error => $@ ) if $@;
    return "Alzabo::RDBMSRules::$p{rdbms}"->new(@_);
}

sub available
{
    return Alzabo::Util::subclasses(__PACKAGE__);
}

# validation

sub validate_schema_name
{
    shift()->_virtual;
}

sub validate_table_name
{
    shift()->_virtual;
}

sub validate_column_name
{
    shift()->_virtual;
}

sub validate_column_type
{
    shift()->_virtual;
}

sub validate_column_length
{
    shift()->_virtual;
}

sub validate_column_attribute
{
    shift()->_virtual;
}

sub validate_primary_key
{
    shift()->_virtual;
}

sub validate_sequenced_attribute
{
    shift()->_virtual;
}

sub validate_index
{
    shift()->_virtual;
}

sub type_is_numeric
{
    shift()->_virtual;
}

sub type_is_character
{
    shift()->_virtual;
}

sub type_is_blob
{
    shift()->_virtual;
}

# feature probing

sub column_types
{
    shift()->_virtual;
}

sub feature
{
    return 0;
}

sub schema_attributes
{
    shift()->_virtual;
}

sub table_attributes
{
    shift()->_virtual;
}

sub column_attributes
{
    shift()->_virtual;
}

sub schema_sql
{
    my $self = shift;

    validate_pos( @_, { isa => 'Alzabo::Schema' } );

    my $schema = shift;

    my @sql;

    $self->_start_sql;

    foreach my $t ( $schema->tables )
    {
	push @sql, $self->table_sql($t);
    }

    $self->_end_sql;

    return @sql;
}

sub _start_sql
{
    1;
}

sub _end_sql
{
    1;
}

sub table_sql
{
    shift()->_virtual;
}

sub column_sql
{
    shift()->_virtual;
}

sub index_sql
{
    my $self = shift;
    my $index = shift;

    my $index_name = $index->id;

    my $sql = 'CREATE';
    $sql .= ' UNIQUE' if $index->unique;
    $sql .= " INDEX $index_name ON " . $index->table->name . ' ( ';
    $sql .= join ', ', map { $_->name } $index->columns;
    $sql .= ' )';

    return $sql;
}

sub foreign_key_sql
{
    shift()->_virtual;
}

sub drop_table_sql
{
    my $self = shift;

    return 'DROP TABLE ' . shift->name;
}

sub drop_column_sql
{
    shift()->_virtual;
}

sub drop_index_sql
{
    shift()->_virtual;
}

sub drop_foreign_key_sql
{
    shift()->_virtual;
}

sub column_sql_add
{
    shift()->_virtual;
}

sub column_sql_diff
{
    shift()->_virtual;
}

sub index_sql_diff
{
    my $self = shift;

    validate( @_, { new => { isa => 'Alzabo::Index' },
		    old => { isa => 'Alzabo::Index' } } );

    my %p = @_;

    my $new_sql = $self->index_sql($p{new});

    my @sql;
    if ( $new_sql ne $self->index_sql($p{old}) )
    {
	push @sql, $self->drop_index_sql($p{old});
	push @sql, $new_sql;
    }

    return @sql;
}

sub foreign_key_sql_diff
{
    shift()->_virtual;
}

sub alter_primary_key_sql
{
    shift()->_virtual;
}

sub reverse_engineer
{
    shift()->_virtual;
}

sub rules_id
{
    shift()->_virtual;
}

sub schema_sql_diff
{
    my $self = shift;

    validate( @_, { new => { isa => 'Alzabo::Schema' },
		    old => { isa => 'Alzabo::Schema' } } );

    my %p = @_;

    $self->_start_sql;

    my @sql;
    foreach my $new_t ($p{new}->tables)
    {
	if ( my $old_t = eval { $p{old}->table($new_t->name) } )
	{
	    push @sql, $self->table_sql_diff( new => $new_t,
					      old => $old_t );
	}
	else
	{
	    push @sql, $self->table_sql($new_t);
	}
    }

    foreach my $old_t ($p{old}->tables)
    {
	unless ( eval { $p{new}->table( $old_t->name ) } )
	{
	    push @sql, $self->drop_table_sql($old_t);
	}
    }

    $self->_end_sql;

    return @sql;
}

sub table_sql_diff
{
    my $self = shift;

    validate( @_, { new => { isa => 'Alzabo::Table' },
		    old => { isa => 'Alzabo::Table' } } );

    my %p = @_;

    my @sql;
    foreach my $old_c ($p{old}->columns)
    {
	unless ( my $new_c = eval { $p{new}->column( $old_c->name ) } )
	{
	    push @sql, $self->drop_column_sql( new_table => $p{new},
					       old => $old_c );
	}
    }

    foreach my $new_c ($p{new}->columns)
    {
	if ( my $old_c = eval { $p{old}->column( $new_c->name ) } )
	{
	    push @sql, $self->column_sql_diff( new => $new_c,
					       old => $old_c );
	}
	else
	{
	    push @sql, $self->column_sql_add($new_c)
	}
    }

    foreach my $old_i ($p{old}->indexes)
    {
	unless ( eval { $p{new}->index( $old_i->id ) } )
	{
	    push @sql, $self->drop_index_sql($old_i);
	}
    }

    foreach my $new_i ($p{new}->indexes)
    {
	if ( my $old_i = eval { $p{old}->index( $new_i->id ) } )
	{
	    push @sql, $self->index_sql_diff( new => $new_i,
					      old => $old_i );
	}
	else
	{
	    push @sql, $self->index_sql($new_i)
	}
    }

    foreach my $new_fk ($p{new}->all_foreign_keys)
    {
	my @fk = grep { $new_fk->id eq $_->id } $p{old}->all_foreign_keys;

	if (@fk == 1)
	{
	    push @sql, $self->foreign_key_sql_diff( new => $new_fk,
						    old => $fk[0] );
	}
	elsif (@fk > 1)
	{
	    Alzabo::Exception::RDBMSRules->throw( error => "More than one foreign key had the same id in " . $p{old}->name );
	}
	else
	{
	    push @sql, $self->foreign_key_sql($new_fk)
	}
    }

    foreach my $old_fk ($p{old}->all_foreign_keys)
    {
	my @fk = grep { $old_fk->id eq $_->id } $p{new}->all_foreign_keys;

	if (! @fk)
	{
	    push @sql, $self->drop_foreign_key_sql($old_fk);
	}
	elsif (@fk > 1)
	{
	    Alzabo::Exception::RDBMSRules->throw( error => "More than one foreign key had the same id in " . $p{new}->name );
	}
    }

    my $pk_changed;
    foreach my $old_pk ($p{old}->primary_key)
    {
	unless ( eval { $p{new}->column_is_primary_key($old_pk) } )
	{
	    push @sql, $self->alter_primary_key_sql( new => $p{new},
						     old => $p{old} );
	    $pk_changed = 1;
	    last;
	}
    }

    unless ($pk_changed)
    {
	foreach my $new_pk ($p{new}->primary_key)
	{
	    unless ( eval { $p{old}->column_is_primary_key($new_pk) } )
	    {
		push @sql, $self->alter_primary_key_sql( new => $p{new},
							 old => $p{old} );
		last;
	    }
	}
    }

    return @sql;
}


sub _virtual
{
    my $self = shift;

    my $sub = (caller(1))[3];
    Alzabo::Exception::VirtualMethod->throw( error =>
					     "$sub is a virtual method and must be subclassed in " . ref $self );
}

__END__

=head1 NAME

Alzabo::RDBMSRules - Base class for Alzabo RDBMS rulesets

=head1 SYNOPSIS

  use Alzabo::RDBMSRules;

  my $rules = Alzabo::RDBMSRules( rules => 'MySQL' );

=head1 DESCRIPTION

This class is the base class for all C<Alzabo::RDBMSRules> modules.
To instantiate a subclass call this class's C<new> method.  See the
L<SUBCLASSING Alzabo::RDBMSRules> section for information on how to
make a ruleset for the RDBMS of your choice.

=head1 METHODS

=head2 available

A list of names representing the available C<Alzabo::RDBMSRules>
subclasses.  Any one of these names would be appropriate as the
C<rdbms> parameter for the
L<C<Alzabo::RDBMSRules-E<gt>new>|Alzabo::RDBMSRules/new> method.

=head2 new

=head3 Parameters

=over 4

=item * rdbms => $rdbms_name

The name of the RDBMS being used.

=back

Some subclasses may accept additional values.

=head3 Returns

A new C<Alzabo::RDBMSRules> object of the appropriate subclass.

=head2 schema_sql (C<Alzabo::Create::Schema> object)

=head3 Returns

A list of SQL statements.

=head2 index_sql (C<Alzabo::Create::Index> object)

=head3 Returns

A list of SQL statements.

=head2 drop_table_sql (C<Alzabo::Create::Table> object)

=head3 Returns

A list of SQL statements.

=head2 drop_index_sql (C<Alzabo::Create::Index> object)

=head3 Returns

A list of SQL statements.

=head2 schema_sql_diff

=head3 Parameters

=over 4

=item * new => C<Alzabo::Create::Schema> object

=item * old => C<Alzabo::Create::Schema> object

=back

Given two schema objects, this method compares them and generates the
SQL necessary to turn the 'old' one into the 'new' one.

=head3 Returns

An array of SQL statements.

=head2 table_sql_diff

=head3 Parameters

=over 4

=item * new => C<Alzabo::Create::Table> object

=item * old => C<Alzabo::Create::Table> object

=back

Given two table objects, this method compares them and generates the
SQL necessary to turn the 'old' one into the 'new' one.

=head3 Returns

An array of SQL statements.

=head2 Virtual Methods

The following methods are not implemented in the C<Alzabo::RDBMSRules>
class itself and must be implemented in its subclasses.

=head2 column_types

=head3 Returns

A list of valid column type specifiers.

=head2 feature ($feature)

Given a string defining a feature, this method indicates whether or
not the given RDBMS supports that feature.  By default, this method
always returns false unless overridden in the subclass.

Features that may be asked for:

=over 4

=item * extended_column_types

Column types that must be input directly from a user, as opposed to
being chosen from a list.  MySQL's ENUM and SET column types are
examples of such types.

=item * index_column_prefixes

MySQL supports the notion of column prefixes in indexes, allowing you
to index only a portion of a large text column.

=item * fulltext_indexes

This should be self-explanatory.

=back

=head2 validate_schema_name (C<Alzabo::Schema> object)

=head3 Returns

A boolean value indicate whether the object's name is valid.

=head3 Throws

L<C<Alzabo::Exception::RDBMSRules>|Alzabo::Exceptions>

=head2 validate_table_name (C<Alzabo::Create::Table> object)

=head3 Returns

A boolean value indicate whether the object's name is valid.

=head3 Throws

L<C<Alzabo::Exception::RDBMSRules>|Alzabo::Exceptions>

=head2 validate_column_name (C<Alzabo::Create::Column> object)

=head3 Returns

A boolean value indicate whether the object's name is valid.

=head3 Throws

L<C<Alzabo::Exception::RDBMSRules>|Alzabo::Exceptions>

=head2 validate_column_type ($type_as_string)

=head3 Returns

A boolean value indicate whether or not this type is valid for the
RDBMS.

=head3 Throws

L<C<Alzabo::Exception::RDBMSRules>|Alzabo::Exceptions>

=head2 validate_column_attribute

=head3 Parameters

=over 4

=item * column => C<Alzabo::Create::Column> object

=item * attribute => $attribute

=back

This method is a bit different from the others in that it takes an
existing column object and a B<potential> attribute.

=head3 Returns

A boolean value indicating whether or not this attribute is acceptable
for the column.

=head3 Throws

L<C<Alzabo::Exception::RDBMSRules>|Alzabo::Exceptions>

=head2 validate_primary_key (C<Alzabo::Create::Column> object)

=head3 Returns

Returns a boolean value indicating whether or not the given column can
be part of its table's primary key.

=head3 Throws

L<C<Alzabo::Exception::RDBMSRules>|Alzabo::Exceptions>

=head2 validate_sequenced_attribute (C<Alzabo::Create::Column> object)

Given a column object, indicates whether or not the column can be
sequenced.

=head3 Throws

L<C<Alzabo::Exception::RDBMSRules>|Alzabo::Exceptions>

=head2 validate_index (C<Alzabo::Create::Index> object)

=head3 Returns

A boolean value indicating whether or not the index is valid.

=head3 Throws

L<C<Alzabo::Exception::RDBMSRules>|Alzabo::Exceptions>

=head2 table_sql (C<Alzabo::Create::Table> object)

=head3 Returns

A list of SQL statements.

=head2 column_sql (C<Alzabo::Create::Column> object)

=head3 Returns

A list of SQL statements.

=head2 foreign_key_sql (C<Alzabo::Create::ForeignKey> object)

=head3 Returns

A list of SQL statements.

=head2 drop_column_sql (C<Alzabo::Create::Column> object)

=head3 Returns

A list of SQL statements.

=head2 drop_foreign_key_sql (C<Alzabo::Create::ForeignKey> object)

=head3 Returns

A list of SQL statements.

=head2 column_sql_add (C<Alzabo::Create::Column> object)

=head3 Returns

A list of SQL statements.

=head2 column_sql_diff

=head3 Parameters

=over 4

=item * new => C<Alzabo::Create::Column> object

=item * old => C<Alzabo::Create::Column> object

=back

Given two column objects, this method compares them and generates the
SQL necessary to turn the 'old' one into the 'new' one.

=head3 Returns

A list of SQL statements.

=head2 index_sql_diff

=head3 Parameters

=over 4

=item * new => C<Alzabo::Create::Index> object

=item * old => C<Alzabo::Create::Index> object

=back

Given two index objects, this method compares them and generates the
SQL necessary to turn the 'old' one into the 'new' one.

=head3 Returns

A list of SQL statements.

=head2 foreign_key_sql_diff

=head3 Parameters

=over 4

=item * new => C<Alzabo::Create::ForeignKey> object

=item * old => C<Alzabo::Create::ForeignKey> object

=back

Given two foreign key objects, this method compares them and generates
the SQL necessary to turn the 'old' one into the 'new' one.

=head3 Returns

A list of SQL statements.

=head2 alter_primary_key_sql

=head3 Parameters

=over 4

=item * new => C<Alzabo::Create::Table> object

=item * old => C<Alzabo::Create::Table> object

=back

Given two table objects, this method compares them and generates the
SQL necessary to give change the primary key from the 'old' one's
primary key to the 'new' one's primary key.

=head3 Returns

A list of SQL statements.

=head2 reverse_engineer (C<Alzabo::Create::Schema> object)

Given a schema object (which presumably has no tables), this method
uses the schema's L<C<Alzabo::Driver>|Alzabo::Driver> object to
connect to an existing database and reverse engineer it into the
appopriate Alzabo objects.

=head1 SUBCLASSING Alzabo::RDBMSRules

To create a subclass of C<Alzabo::RDBMSRules> for your particular
RDBMS is fairly simple.

Here's a sample header to the module using a fictional RDBMS called
FooDB:

 package Alzabo::RDBMSRules::FooDB;

 use strict;
 use vars qw($VERSION);

 use Alzabo::RDBMSRules;

 use base qw(Alzabo::RDBMSRules);

The next step is to implement a C<new> method and the methods listed
under the section L<Virtual Methods>.  The new method should look a
bit like this:

 1:  sub new
 2:  {
 3:      my $proto = shift;
 4:      my $class = ref $proto || $proto;
 5:      my %p = @_;
 6:
 7:      my $self = bless {}, $self;
 8:
 9:      return $self;
 10:  }

The hash %p contains any values passed to the
L<C<Alzabo::RDBMSRules-E<gt>new>|Alzabo::RDBMSRules/new> method by its
caller.

Lines 1-7 should probably be copied verbatim into your own C<new>
method.  Line 5 can be deleted if you don't need to look at the
parameters.

The rest of your module should simply implement the methods listed
under the L<Virtual Methods> section of this documentation.

Look at the included C<Alzabo::RDBMSRules> subclasses for examples.
Feel free to contact me for further help if you get stuck.  Please
tell me what database you're attempting to implement, and include the
code you've written so far.

=head1 AUTHOR

Dave Rolsky, <dave@urth.org>

=cut
