package Alzabo::RDBMSRules;

use strict;
use vars qw($VERSION);

use Alzabo::Exceptions;
use Alzabo::Util;

$VERSION = sprintf '%2d.%02d', q$Revision: 1.18 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    shift;
    my $subclass = shift;
    $subclass =~ s/Alzabo::RDBMSRules:://;
    eval "use Alzabo::RDBMSRules::$subclass;";
    EvalException->throw( error => $@ ) if $@;
    return "Alzabo::RDBMSRules::$subclass"->new(@_);
}

sub available
{
    return Alzabo::Util::subclasses(__PACKAGE__);
}

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

sub schema_sql
{
    shift()->_virtual;
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
    shift()->_virtual;
}

sub foreign_key_sql
{
    shift()->_virtual;
}

sub drop_table_sql
{
    shift()->_virtual;
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
    shift()->_virtual;
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

sub schema_sql_diff
{
    my $self = shift;
    my %p = @_;
    my $new = $p{new};
    my $old = $p{old};

    my @sql;
    foreach my $new_t ($new->tables)
    {
	if ( my $old_t = eval { $old->table($new_t->name) } )
	{
	    push @sql, $self->table_sql_diff( new => $new_t,
					      old => $old_t );
	}
	else
	{
	    push @sql, $self->table_sql($new_t);
	}
    }

    foreach my $old_t ($old->tables)
    {
	unless ( eval { $new->table( $old_t->name ) } )
	{
	    push @sql, $self->drop_table_sql($old_t);
	}
    }

    return @sql;
}

sub table_sql_diff
{
    my $self = shift;
    my %p = @_;
    my $new = $p{new};
    my $old = $p{old};

    my @sql;
    foreach my $new_c ($new->columns)
    {
	if ( my $old_c = eval { $old->column( $new_c->name ) } )
	{
	    push @sql, $self->column_sql_diff( new => $new_c,
					       old => $old_c );
	}
	else
	{
	    push @sql, $self->column_sql_add($new_c)
	}
    }
    foreach my $old_c ($old->columns)
    {
	unless ( eval { $new->column( $old_c->name ) } )
	{
	    push @sql, $self->drop_column_sql($old_c);
	}
    }

    foreach my $new_i ($new->indexes)
    {
	if ( my $old_i = eval { $old->index( $new_i->id ) } )
	{
	    push @sql, $self->index_sql_diff( new => $new_i,
					      old => $old_i );
	}
	else
	{
	    push @sql, $self->index_sql($new_i)
	}
    }
    foreach my $old_i ($old->indexes)
    {
	unless ( eval { $new->index( $old_i->id ) } )
	{
	    push @sql, $self->drop_index_sql($old_i);
	}
    }

    foreach my $new_fk ($new->all_foreign_keys)
    {
	if ( my @old_fk = eval { $old->foreign_keys( table => $new_fk->table_to,
						     column => $new_fk->column_from ) } )
	{
	    foreach my $old_fk (@old_fk)
	    {
		if ( $old_fk->column_to->name eq $new_fk->column_to->name )
		{
		    push @sql, $self->foreign_key_sql_diff( new => $new_fk,
							    old => $old_fk );
		}
		else
		{
		    push @sql, $self->foreign_key_sql($new_fk)
		}
	    }
	}
    }
    foreach my $old_fk ($old->all_foreign_keys)
    {
	unless ( my @new_fk = eval { $new->foreign_keys( table => $old_fk->table_to,
							 column => $old_fk->column_from ) } )
	{
	    foreach my $new_fk (@new_fk)
	    {
		push @sql, $self->drop_foreign_key_sql($old_fk)
		    unless $old_fk->column_to->name eq $new_fk->column_to->name;
	    }
	}
    }

    my $pk_changed;
    foreach my $old_pk ($old->primary_key)
    {
	unless ( eval { $new->column_is_primary_key($old_pk) } )
	{
	    push @sql, $self->alter_primary_key_sql( new => $new,
						     old => $old );
	    $pk_changed = 1;
	    last;
	}
    }

    unless ($pk_changed)
    {
	foreach my $new_pk ($new->primary_key)
	{
	    unless ( eval { $old->column_is_primary_key($new_pk) } )
	    {
		push @sql, $self->alter_primary_key_sql( new => $new,
							 old => $old );
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
    VirtualMethodException->throw( error =>
				   "$sub is a virtual method and must be subclassed in " . ref $self );
}

__END__

=head1 NAME

Alzabo::RDBMSRules - Base class for Alzabo RDBMS rulesets

=head1 SYNOPSIS

  use Alzabo::RDBMSRules;

  my $rules = Alzabo::RDBMSRules( rules => 'MySQL' );

=head1 DESCRIPTION

This class is the base class for all Alzabo::RDBMSRules modules.  To
instantiate a subclass call this class's C<new> method.  See the
L<SUBCLASSING Alzabo::RDBMRul/es> section for information on how to
make a ruleset for the RDBMS of your choice.

=head1 METHODS

=over 4

=item * available

Returns a list of strings listing the avaiable Alzabo::Driver
subclasses.  This is a class method.

=item * new

Takes the following parameters:

=item -- rules => $string

A string giving the name of a ruleset to instantiate.  Ruleset names
are the name of the Alzabo::RDBMSRules subclass without the leading
'Alzabo::RDBMSRules::' part.  For example, the driver name of the
Alzabo::RDBMSRules::MySQL class is 'MySQL'.

Some subclasses may accept additional values.

The return value of this method is a new Alzabo::RDBMRules object of
the appropriate subclass.

=item * schema_sql_diff

Takes the following parameters:

=item -- new => Alzabo::Schema object

=item -- old => Alzabo::Schema object

Given two schema objects, this method compares them and returns an
array of SQL statements which would turn the old schema into the new
schema.

=item * table_sql_diff

Takes the following parameters:

=item -- new => Alzabo::Table object

=item -- old => Alzabo::Table object

Given two table objects, this method compares them and returns an
array of SQL statements which would turn the old table into the new
table.

=back

=head2 Virtual Methods

The following methods are not implemented in Alzabo::RDBMRules itself
and must be implemented in its subclasses.

=over 4

=item * validate_schema_name (Alzabo::Schema object)

Given a schema object, indicates whether its current name is
acceptable under the ruleset.

Exceptions:

AlzaboRDBMSRulesException - The name is not acceptable

=item * validate_table_name (Alzabo::Table object)

Given a table object, indicates whether its current name is acceptable
under the ruleset.

Exceptions:

AlzaboRDBMSRulesException - The name is not acceptable

=item * validate_column_name (Alzabo::Column object)

Given a column object, indicates whether its current name is
acceptable under the ruleset.

Exceptions:

AlzaboRDBMSRulesException - The name is not acceptable

=item * validate_column_type ($type_as_string)

Given a string indicating a column type (such as 'INT' or 'CHAR'),
indicates whether or not this is a valid column type.

Exceptions:

AlzaboRDBMSRulesException - The column type is not valid

=item * validate_column_attribute

Takes the following parameters:

=item -- column => Alzabo::Column object

=item -- attribute => $attribute

Given a column and a potential attribute, indicates whether that
attribute is valid for the column.

Exceptions:

AlzaboRDBMSRulesException - The attribute is not valid

=item * validate_primary_key (Alzabo::Column object)

Given a column object, indicates whether or not the column can be part
of a primary key.

Exceptions:

AlzaboRDBMSRulesException - The column cannot be part of a primary key

=item * validate_sequenced_attribute (Alzabo::Column object)

Given a column object, indicates whether or not the column can be
sequenced.

Exceptions:

AlzaboRDBMSRulesException - The column cannot be sequenced.

=item * validate_index

Given an index object, indicates whether or not it is valid.

Exceptions:

AlzaboRDBMSRulesException - The index is not valid

=item * schema_sql

Given a schema object, returns an array of SQL statements which would
create that schema.

=item * table_sql

Given a table object, returns an array of SQL statements which would
create that table.

=item * column_sql

Given a column object, returns an array of SQL statements which would
create that column.

=item * index_sql

Given a index object, returns an array of SQL statements which wouldcreate that index

=item * foreign_key_sql

Given a foreign key object, returns an array of SQL statements which
would create that foreign key.  .

=item * drop_table_sql

Given a table object, returns an array of SQL statements which would
drop that table.

=item * drop_column_sql

Given a column object, returns an array of SQL statements which would
drop that column.

=item * drop_index_sql

Given a index object, returns an array of SQL statements which would
drop that index.

=item * drop_foreign_key_sql

Given a foreign key object, returns an array of SQL statements which
would drop that foreign key.

=item * column_sql_add

Given a column object, returns an array of SQL statements which would
add that column to the appropriate table.

=item * column_sql_diff

Takes the following parameters:

=item -- new => Alzabo::Column object

=item -- old => Alzabo::Column object

Given two column objects, this method compares them and returns an
array of SQL statements which would turn the old column into the new
column.

=item * index_sql_diff

Takes the following parameters:

=item -- new => Alzabo::Index object

=item -- old => Alzabo::Index object

Given two index objects, this method compares them and returns an
array of SQL statements which would turn the old index into the new
index.

=item * foreign_key_sql_diff

Takes the following parameters:

=item -- new => Alzabo::ForeignKey object

=item -- old => Alzabo::ForeignKey object

Given two foreign key objects, this method compares them and returns
an array of SQL statements which would turn the old foreign key into
the new foreign key.

=item * alter_primary_key_sql

Takes the following parameters:

=item -- new => Alzabo::Table object

=item -- old => Alzabo::Table object

Given two table objects with different primary keys, this method
compares them and returns an array of SQL statements which would turn
the old table's primary key into the new table's primary key.

=item * reverse_engineer (Alzabo::Schema object)

Given a schema object (which presumably has no tables), this method
uses the schema's Alzabo::Driver object to connect to an existing
database and reverse engineer it into the appopriate Alzabo objects.

=head1 SUBCLASSING Alzabo::RDBMSRules

To create a subclass of Alzabo::Driver for your particular RDBMS is
fairly simple.

Here's a sample header to the module using a fictional RDBMS called FooDB:

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

The hash %p contains any values passed to the Alzabo::Driver->new
method by its caller.

Lines 1-7 should probably be copied verbatim into your own C<new>
method.  Line 5 can be deleted if you don't need to look at the
parameters.

The rest of your module should simply implement the methods listed
under the L<Virtual Methods> section of this documentation.

Look at the included Alzabo::RDBMSRules subclasses for examples.  Feel
free to contact me for further help if you get stuck.  Please tell me
what database you're attempting to implement, and include the code
you've written so far.

=head1 AUTHOR

Dave Rolsky, <dave@urth.org>

=cut
