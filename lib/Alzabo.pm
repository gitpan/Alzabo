package Alzabo;

use Alzabo::Exceptions;

use Alzabo::Column;
use Alzabo::ColumnDefinition;
use Alzabo::ForeignKey;
use Alzabo::Index;
use Alzabo::Schema;
use Alzabo::Table;

use Alzabo::Config;

use vars qw($VERSION);

$VERSION = '0.10';

1;

__END__

=pod

=head1 NAME

Alzabo - Core

=head1 SYNOPSIS

  use Alzabo; # loads the Alzabo core modules but you probably want to
              # use Alzabo::Create or Alzabo::Runtime instead

=head1 DESCRIPTION

=head2 What is Alzabo?

Alzabo is a two-fold program.  Its first function is as a data
modelling tool.  Through either a schema creation interface or a
custom perl program, you can create a set of schema, table, column,
etc. objects that represent your data model.  Alzabo is also capable
of reverse engineering an existing data model.

Its second function is as a RDBMS to object mapping system.  Once you
have created a schema, you can use the Alzabo::Runtime::Table and
Alzabo::Runtime::Row classes to access its data.  These classes offer
a low level interface to common operations such as SQL SELECT, INSERT,
DELETE, and UPDATE commands.

To take it a step further, you could then aggregate a set of rows from
different tables into a larger container object which could understand
the logical relationship between these tables.

This is not intended to be a total object replacement for SQL, as
there is only the most minimal support for more complex operations
such as joins.  Instead, it is intended to replace the drudgery of the
most common types of operations.  In addition, the
Alzabo::Runtime::Row objects support the use of a caching system.  One
such system, the Alzabo::RowCache class, is included.  However, you
may substitute any caching system you like provided it has the
appropriate method interface (see the Alzabo::Runtime::Row and
Alzabo::RowCache documentation for details).

=head2 Drivers and Rulesets

Alzabo aims to be as cross-platform as possible.  To that end, RDBMS
specific operations are contained in two separate module hierarchies.

The first, the Alzabo::Driver::* hierarchy, is used to handle
communication with the database.  It uses DBI and the appropriate
DBD::* module to handle communications.  It provides a higher level of
abstraction than DBI, requiring that the RDBMS specific modules
implement methods to create databases and return the next value in a
sequence.

The second, the Alzabo::RDBMSRules::* hierarchy, is used during schema
creation in order to validate user input.  It also generates SQL to
create the database or generate diffs (when an already instantiated
schema is modified).  Finally, it also handles reverse engineering an
existing database.

Currently, these modules have only been implemented for MySQL.  The
next target platform is PostgreSQL.

=head2 How to use Alzabo

The first thing you'll want to do is create a schema.  The easiest way
to do this is via the included web based schema creation interface,
which requires the HTML::Mason package from CPAN to run.  To install
this, run the install_interfaces.pl program included with the Alzabo
distribution.

The other way to do this is via a perl script.  Here's the beginning
of such a script:

  use Alzabo::Create::Schema;

  eval {
    my $s = Alzabo::Create::Schema->new( name => 'foo',
                                         rules => 'MySQL',
                                         driver => 'MySQL' );

    my $table = $s->make_table( name => 'some_table' );

    my $a_col = $table->make_column( name => 'a_column',
                                     type => 'int',
                                     null => 0,
                                     sequenced => 0,
                                     attributes => [ 'unsigned' ] );

    $table->add_primary_key($a_col);

    my $b_col = $table->make_column( name => 'b_column',
                                    type => 'varchar(240)',
                                    null => 0 );

    $table->make_index( columns => [ column => $b_col,
                                     prefix => 10 ] );

    ...

    $s->save_to_file;
  };

  if ($@) { handle exceptions }

=head2 Exceptions

Alzabo uses exceptions as its error reporting mechanism.  This means
that pretty much all calls to its methods should be wrapped in
C<eval{}>.  This is less onerous than it sounds.  In general, there's
no reason not to wrap all of your calls in one eval, rather than each
one in a seperate eval.  Then at the end of the block simply check the
value of $@.  See the code of the included HTML::Mason based interface
for examples.

=head2 Architecture

The general design of Alzabo is as follows.

There are objects representing the schema, which contains table
objects.  Table objects contain column, foreign key, and index
objects.  Column objects contain column definition objects.  A single
column definition may be shared by multiple columns, but has only one
owner.

This is a diagram of these inheritance relationships:

 Alzabo::* (::Schema, ::Table, ::Column, ::ColumnDefinition, ::ForeignKey, ::Index)
                  /   \
	       is parent to
                /       \
Alzabo::Create::*   Alzabo::Runtime::*

This a diagram of how objects contain other objects:

                      Schema
                     /      \
              contains       contains--Alzabo::Driver subclass object (1)
                  |                 \
               Table (0 or more)     Alzabo::RDBMSRules subclass object (1)
                /  \                  (* Alzabo::Create::Schema only)
               /    \
              contains--------------------
             /        \                   \
            /          \                   \
     ForeignKey      Column (0 or more)    Index (0 or more)
     (0 or more)       |
                    contains
                       |
		  ColumnDefinition (1)

Note that more than one column _may_ share a single definition object
(this is explained in the Alzabo::Create::ColumnDefinition
documentation).

Other classes/objects used in Alzabo include:

=over 4

=item * Alzabo::Config

This class is generated by Makefile.PL during installation and
contains information such as what directory contains saved schemas and
other configuration information.

=item * Alzabo::ChangeTracker

This object provides a method for an object to register a series to
backout from multiple changes.  This is done by providing the
ChangeTracker object with a callback after a change is succesfully
made to an object or objects.  If a future change in a set of
operations fail, the tracker can be told to back the changes out. This
is used primarily in Alzabo::Create::schema

=item * Alzabo::Exceptions

This object creates the exception subclasses used by Alzabo.

=item * Alzabo::ObjectCacheIPC

An object caching module that uses IPC to make sure that cached
objects expired in one process get expired in any other process using
the same caching module.

=item * Alzabo::Runtime::Row

This object represents a row from a table.  It
is made by the Alzabo::Runtime::Table object and contains its parent
table object.  It is the sole interface by which actual data is
inserted/update/deleted in a table.

=item * Alzabo::Runtime::RowCursor

This object is a cursor that returns row objects.  Using a cursor
saves a lot of memory for big selects.

=item * Alzabo::Util

A catchall module to store simple subroutines shared by various
modules.

=back

=head2 Why the subdivision between Alzabo::*, Alzabo::Create::*, and Alzabo::Runtime::*?

There are several reasons for doing this:

=over 4

=item *

In some environments (mod_perl) we would like to optimize for memory.
For an application that uses an existing schema, all we need is to be
able read object information, rather than needing to change the
schema's definition.  This means there is no reason to have the
overhead of compiling all the methods used when creating and modifying
objects.

=item *

In other environments (for example, when running as a separately
spawned CGI process) compile time is important.

=item *

For most people using Alzabo, they will use one of the existing schema
creation interfaces and then write an application using that schema.
At the simplest level, they would only need to learn how to
instantiate Alzabo::Runtime::Row objects and how that class's methods
work.  For more sophisticated users, they can still avoid having to
ever look at documentation on methods that alter the schema and its
contained objects.

=back

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
