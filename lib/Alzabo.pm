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

use 5.005;

$VERSION = '0.62';

1;

__END__

=head1 NAME

Alzabo - A data modelling tool and RDBMS-OO mapper

=head1 SYNOPSIS

  Cannot be summarized here.

=head1 DESCRIPTION

=head2 What is Alzabo?

Alzabo is a program and a suite of modules, with two core functions.
Its first use is as a data modelling tool.  Through either a schema
creation interface or a perl program, you can create a set of schema,
table, column, etc. objects to represent your data model.  Alzabo is
also capable of reverse engineering your data model from an existing
system.

Its second function is as an RDBMS to object mapping system.  Once you
have created a schema, you can use the
L<C<Alzabo::Runtime::Table>|Alzabo::Runtime::Table> and
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> classes to access its
data.  These classes offer a high level interface to common operations
such as SQL SELECT, INSERT, DELETE, and UPDATE commands.

A higher level interface can be created through the use of the
L<C<Alzabo::MethodMaker>|Alzabo::MethodMaker> module.  This module
takes a schema object and auto-generates useful methods based on the
tables, columns, and relationships it finds in the module.  The code
is generates can be integrated with your own code quite easily.

To take it a step further, you could then aggregate a set of rows from
different tables into a larger container object which could understand
the logical relationship between these tables.

The L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> objects support
the use of a caching system.  Caching modules are included with the
distribution.  However, you may substitute any caching system you like
provided it has the appropriate method interface.

=head2 What to Read?

Alzabo has a lot of documentation.  If you are primarily interested in
using Alzabo as an RDBMS-OO wrapper, much of the documentation can be
skipped.  This assumes that you will create your schema via the schema
creation interface or via L<reverse engineering|Alzabo::Create::Schema/reverse_engineer>.

Here is the suggested reading order:

L<Alzabo - Alzabo concepts|Alzabo concepts>

L<Alzabo - Rows and cursors|"rows and cursors">

L<Alzabo - How to use Alzabo|"How to use Alzabo">

L<Alzabo - Exceptions|"Exceptions">

L<Alzabo - Usage Examples|"Usage Examples">

The section for your RDBMS:

=over 4

L<Alzabo and MySQL|Alzabo::MySQL>

L<Alzabo and PostgreSQL|Alzabo::PostgreSQL>

=back

L<The Alzabo::Runtime::Schema docs|Alzabo::Runtime::Schema> - The most
important parts here are those related to loading a schema and
connecting to a database.  Also be sure to read about the
L<C<join>|Alzabo::Runtime::Schema/join> method.

L<The Alzabo::Runtime::Table docs|Alzabo::Runtime::Table> - This
contains most of the methods used to fetch rows from the database, as
well as the L<C<insert>|Alzabo::Runtime::Table/insert> method.

L<The Alzabo::Runtime::Row docs|Alzabo::Runtime::Row> - The row
objects contain the methods used to update, delete, and retrieve data
from the database.

L<The Alzabo::Runtime::PotentialRow
docs|Alzabo::Runtime::PotentialRow> - Potential rows are objects that
look like real rows but have yet been inserted into the database.

L<The Alzabo::Runtime::Cursor docs|Alzabo::Runtime::Cursor> - The most
important part of the documentation here is the L<HANDLING
ERRORS|Alzabo::Runtime::Cursor/"HANDLING ERRORS"> section.

L<The Alzabo::Runtime::RowCursor docs|Alzabo::Runtime::RowCursor> - A
cursor object that returns only a single row.

L<The Alzabo::Runtime::JoinCursor docs|Alzabo::Runtime::JoinCursor> -
A cursor object that returns multiple rows at once.

L<The Alzabo::Runtime::OuterJoinCursor
docs|Alzabo::Runtime::OuterJoinCursor> - Returns multiple rows/undefs
at once.

L<The Alzabo::MethodMaker docs|Alzabo::MethodMaker> - One of the most
useful parts of Alzabo.  This module can be used to auto-generate
methods based on the structure of your schema.

L<The Alzabo::ObjectCache docs|Alzabo::ObjectCache> - This describes
how to select the caching modules you want to use.  It contains a
number of scenarios and describes how they are affected by caching.
If you plan on using Alzabo in a multi-process environment (such as
mod_perl) this is very important.

L<The Alzabo::Exceptions docs|Alzabo::Exceptions> - Describes the
nature of all the exceptions used in Alzabo.

L<The FAQ|Alzabo::FAQ>.

L<The quick reference|Alzabo::QuickRef> - A quick reference for the
various methods of the Alzabo objects.

Other areas of interest may include the L<Validating data>, L<Using
SQL functions>, L<Referential integrity>, and L<Changing the schema>
sections in this document.

=head2 Alzabo concepts

=head3 Instantiation

Every schema keeps track of whether it has been instantiated or not.
A schema that is instantiated is one that exists in an RDBMS backend.
This can be done explicitly by calling the schema's
L<C<create>|Alzabo::Create::Schema/create> method.  It is also
implicitly set when a schema is created as the result of L<reverse
engineering|Alzabo::Create::Schema/reverse_engineer>.

Instantiation has several effects.  The most important part of this is
to realize that once a schema is instantiated, the way it generates
SQL for itself changes.  Before it is instantiated, if you ask it to
generate SQL via L<the C<make_sql> the
method|Alzabo::Create::Schema/make_sql>, it will generate the set of
SQL statements that are needed to create the schema in the RDBMS.

After is instantiated, the schema will instead generate the SQL
necessary to convert the version in the RDBMS backend to match the
object's current state.  This can be thought of as a SQL 'diff'.

While this feature is quite useful, it can be confusing too.  The most
surprising aspect of this is that if you create a schema via L<reverse
engineering|Alzabo::Create::Schema/reverse_engineer> and then call
L<the C<make_sql> method|Alzabo::Create::Schema/make_sql>, you will
not get any SQL.  This is because the schema knows that it is
instantiated and it also knows that it is the same as the version in
the RDBMS, so no SQL is necessary.

The way to deal with this is to call L<the C<set_instantiated>
method|Alzabo::Create::Schema/set_instantiated ($bool)> with a
false value.  Use this method with care.

=head3 Rows and cursors

In Alzabo, data is returned in the form of a L<row
object|Alzabo::Runtime::Row>.  This object can be used to access the
data for an individual row.

Unless you are retrieving a row via a unique identifier (usually its
primary key), you will be given a L<cursor|Alzabo::Runtime::RowCursor>
object.  This is quite similar to how C<DBI> uses statement handles
and is done for similar reasons.

=head2 How to use Alzabo

The first thing you'll want to do is create a schema.  The easiest way
to do this is via the included web based schema creation interface,
which requires the HTML::Mason package from CPAN (www.cpan.org) to
run.

This interface can be installed during the normal installation
process, and you will be prompted as to whether or not you want to use
it.

The other way to create a schema is via a perl script.  Here's the
beginning of such a script:

  use Alzabo::Create::Schema;

  eval
  {
      my $s = Alzabo::Create::Schema->new( name => 'foo',
                                           rdbms => 'MySQL' );

      my $table = $s->make_table( name => 'some_table' );

      my $a_col = $table->make_column( name => 'a_column',
                                       type => 'int',
                                       nullable => 0,
                                       sequenced => 0,
                                       attributes => [ 'unsigned' ] );

      $table->add_primary_key($a_col);

      my $b_col = $table->make_column( name => 'b_column',
                                       type => 'varchar',
                                       length => 240,
                                       nullable => 0 );

      $table->make_index( columns => [ { column => $b_col,
                                         prefix => 10 } ] );

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
value of C<$@>.  See the code of the included C<HTML::Mason> based
interface for examples.

Also see the L<C<Alzabo::Exceptions>|Alzabo::Exceptions> documentation,
which lists all of the different exception used by Alzabo.

Its important to note that some metohds (such as the driver's rollback
method) may use C<eval> internally.  This means that if you intend to
use them as part of the cleanup after an exception, you may need to
store the original exception as C<$@> will be overwritten at the next
C<eval>.

In addition, some methods you might use during cleanup can throw
exceptions of their own.

This is the point where I start wishing Perl had a B<real> exception
handling mechanism built into the language.

=head2 Usage Examples

Alzabo is a powerful tool but as with many powerful tools it can also
be a bit overwhelming at first.  The easiest way to understand some of
its basic capabilities is through some examples..  Let's first assume
that you've created the following schema:

  TABLE: Movie
  movie_id                 tinyint      -- primary key
  title                    varchar(200)
  release_year             year

  TABLE: Person
  person_id                tinyint      -- primary key
  name                     varchar(200)
  birthdate                date
  birthplace_location_id   tinyint      -- foreign key to location

  TABLE: Job
  job_id                   tinyint      -- primary key
  job                      varchar(200) -- something like 'actor' or 'director'

  TABLE: Credit
  movie_id                 tinyint      -- primary key part 1, foreign key to movie
  person_id                tinyint      -- primary key part 2, foreign key to person
  job_id                   tinyint      -- primary key part 3, foreign key to job

  TABLE: Location
  location_id              tinyint      -- primary key
  location                 varchar(200) -- 'New York City' or 'USA'
  parent_location_id       tinyint      -- foreign key to location

This is a vastly scaled down version of the 90+ table database that
Alzabo was written to support.

=head3 Fetching data

First of all, let's do something simple. Let's assume I have a
person_id value and I want to find all the movies that they were in
and print the title, year of release, and the job they did in the
movie.  Here's what it looks like:

  my $schema = Alzabo::Runtime::Schema->load_from_file( name => 'movies' );

  my $person_t = $schema->table('Person');
  my $credit_t = $schema->table('Credit');
  my $movie_t  = $schema->table('Movie');
  my $job_t    = $schema->table('Job');

  # returns a row representing this person.
  my $person = $person_t->row_by_pk( pk => 42 );

  # all the rows in the credit table that have the person_id of 42.
  my $cursor = $person->rows_by_foreign_key( foreign_key =>
                                             $person_t->foreign_keys_by_table($credit_t) );

  print $person->select('name'), " was in the following films:\n\n";
  while (my $credit = $cursor->next)
  {
      # rows_by_foreign_key returns a RowCursor object.  We immediately
      # call its next method, knowing it will only have one row (if
      # it doesn't then our referential integrity is in trouble!)
      my $movie =
          $credit->rows_by_foreign_key( foreign_key =>
                                        $credit_t->foreign_keys_by_table($movie_t) )->next;

      my $job =
          $credit->rows_by_foreign_key( foreign_key =>
                                        $credit_t->foreign_keys_by_table($job_t) )->next;

      print $movie->select('title'), " released in ", $movie->select('release_year'), "\n";
      print '  ', $job->('job'), "\n";
  }

A more sophisticated version of this code would take into account that
a person can do more than one job in the same movie.

The method names are admittedly verbose but the end result code is
significantly simpler to read than the equivalent using raw SQL and
DBI calls.

Let's redo the example using
L<C<Alzabo::MethodMaker>|Alzabo::MethodMaker>;

  # I'm assuming that the pluralize_english subroutine pluralizes
  # things as one would expect.
  use Alzabo::MethodMaker( schema      => 'movies',
                           all         => 1,
                           name_maker  => \&method_namer );

  my $schema = Alzabo::Runtime::Schema->load_from_file( name => 'movies' );

  # instantiates a row representing this person.
  my $person = $schema->Person->row_by_pk( pk => 42 );

  # all the rows in the credit table that have the person_id of 42.
  my $cursor = $person->Credits;

  print $person->name, " was in the following films:\n\n";
  while (my $credit = $cursor->next)
  {
      my $movie = $credit->Movie;

      my $job = $credit->Job;

      print $movie->title, " released in ", $movie->release_year, "\n";
      print '  ', $job->job, "\n";
  }

=head3 Validating data

Let's assume that we've been passed a hash of values representing an
update to the location table. Here's a way of making sure that that
this update won't lead to a loop in terms of the parent/child
relationships.

  sub update_location
  {
      my $self = shift; # this is the row object
      my %data = @_;
      if ( $data{parent_location_id} )
      {
	  my $parent_location_id = $data{parent_location_id};
	  my $location_t = $schema->table('Location');
          while ( my $location = eval { $location_t->row_by_pk( pk => $parent_location_id ) } )
	  {
              die "Insert into location would create loop"
                  if $location->select('parent_location_id') == $data{location_id};

	      $parent_location_id = $location->select('parent_location_id');
          }
      }
  }

Once again, let's rewrite the code to use
L<C<Alzabo::MethodMaker>|Alzabo::MethodMaker>:

  sub update_location
  {
      my $self = shift; # this is the row object
      my %data = @_;
      if ( $data{parent_location_id} )
      {
	  my $location = $self;
          while ( my $location = eval { $location->parent } )
	  {
              die "Insert into location would create loop"
                  if $location->parent_location_id == $data{location_id};
          }
      }
  }

=head3 Using SQL functions

Each subclass of Alzabo::SQLMaker is capable of exporting functions
that allow you to use all the SQL functions that your RDBMS provides.
These functions are normal Perl functions.  They take as argument
normal scalars (strings and numbers), C<Alzabo::Column> objects, or
the return value of another SQL function.  They may be used to select
data via the C<select> and C<function> methods in both the
L<C<Alzabo::Runtime::Table>|Alzabo::Runtime::Table/"function/select">
and
L<C<Alzabo::Runtime::Schema>|Alzabo::Runtime::Schema/"function/select">
classes.  They may also be used as part updates, inserts, and where
clauses, any place that is appropriate.

Examples:

 use Alzabo::SQLMaker::MySQL qw(MAX NOW PI);

 my $max = $table->function( function => MAX( $table->column('budget') ),
                             where => [ $table->column('country'), '=', 'USA' ] );

 $table->insert( values => { create_date => NOW() } );

 $row->update( pi => PI() );

 my $cursor = $table->rows_where( where =>
                                  [ $table->column('expire_date'), '<=', NOW() ] );

 my $cursor = $table->rows_where( where =>
                                  [ LENGTH( $table->column('password'), '<=', 5 ] );

The documentation for the Alzabo::SQLMaker subclass for your RDBMS
will contain a detailed list of all exportable functions.

=head3 Changing the schema

In MySQL, there are a number of various types of integers.  The type
TINYINT can hold values from -128 to 127.  But what if have more than
127 movies?  And if that's the case we might have more than 127 people
too.

For safety's sake, it might be best to make all of the primary key
integer columns INT columns instead.  And while we're at it we want to
make them UNSIGNED as well, as we don't need to insert negative
numbers into these columns.

You could break out the RDBMS manual (because you probably forgot the
exact ALTER TABLE syntax you'll need).  Or you could use Alzabo.  Note
that this time it is an
L<C<Alzabo::Create::Schema>|Alzabo::Create::Schema> object, not
L<C<Alzabo::Runtime::Schema>|Alzabo::Runtime::Schema>.

  my $schema = Alzabo::Create::Schema->load_from_file( name => 'movies' );

  foreach my $t ( $schema->tables )
  {
      foreach my $c ( $t->columns )
      {
           if ( $c->is_primary_key and lc $c->type eq 'tinyint' )
           {
                $c->set_type('int');
                $c->add_attribute('unsigned');
           }
      }
  }
  $schema->create( user => 'user', password => 'password' );
  $schema->save_to_file;

=head2 Multiple RDBMS Support

Alzabo aims to be as cross-platform as possible.  To that end, RDBMS
specific operations are contained in several module hierarchies.  The
goal here is to isolate RDBMS-specific behavior and try to provide
generic wrappers around it, inasmuch as is possible.

The first, the C<Alzabo::Driver::*> hierarchy, is used to handle
communication with the database.  It uses C<DBI> and the appropriate
C<DBD::*> module to handle communications.  It provides a higher level
of abstraction than C<DBI>, requiring that the RDBMS specific modules
implement methods to do such things as create databases or return the
next value in a sequence.

The second, the C<Alzabo::RDBMSRules::*> hierarchy, is used during
schema creation in order to validate user input such as schema and
table names.  It also generates SQL to create the database or turn one
schema into another (sort of a SQL diff).  Finally, it also handles
reverse engineering an existing database.

The this, the C<Alzabo::SQLMaker::*> hierarchy, is used to generate
SQL and handle bound parameters for select, insert, update, and delete
operations.

The RDBMS to be used is specified when creating the schema.
Currently, there is no easy way to convert a schema from one RDBMS to
another, though this is a future goal.

=head2 Referential integrity

By default, Alzabo will maintain referential integrity in your
database based on the relationships you have defined.  This can be
turned off via L<< the
C<Alzabo::Runtime::Schema-E<gt>set_referential_integrity>
method|Alzabo::Runtime::Schema/set_referential_integrity >>.

Alzabo enforces these referential integrity rules:

=over 4

=item * Inserts

An attempt to insert a value into a table's foreign key column(s) will
fail if the value does not exist in the foreign table.

If a table is dependent on another table, any columns from the
dependent table involved in the relationship will be treated as not
nullable.

If the relationship is one-to-one, all columns involved in the foreign
key will be treated as if they had a unique constraint on them (as a
group if there is more than one) unless any of the columns being
inserted are NULL.

No attempt is made to enforce constraints on a table's primary key, as
that could conceivably make it impossible to insert a row into the
table.

=item * Updates

Updates follow the same rules as inserts.  Since Alzabo does not allow
you to update a row's primary key, the last rule above does not apply.

=item * Deletes

When a row is deleted, foreign tables which are dependent on the one
being deleted will have the relevant rows deleted.  Otherwise, the
foreign table's related column(s) will simply be set to NULL.

=back

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

                      Schema - makes--Alzabo::SQLMaker subclass object (many)
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
(this is explained in the
L<C<Alzabo::Create::ColumnDefinition>|Alzabo::Create::ColumnDefinition>
documentation).  This is only relevant if you are writing a schema
creation interface.

=head3 Other classes

=over 4

=item * C<Alzabo::Driver>

These objects handle all the actual communication with the database,
using a thin wrapper over DBI.  The subclasses are used to implement
functionality that must be handled uniquely for a given RDBMS, such as
creating new values for sequenced columns.

=item * C<Alzabo::SQLMaker>

These objects handle the generation of all SQL for runtime operations.
The subclasses are used to implement functionality that varies between
RDBMS's, such as outer joins.

=item * C<Alzabo::RDBMSRules>

These objects perform several funtions.  First, they validate things
such as schema or table names, column type and length, etc.

Second they are used to generate SQL for creating and updating the
database and its tables.

And finally, they also handle the reverse engineering of an existing
database.

=item * C<Alzabo::ObjectCache>, C<Alzabo::ObjectCache::Store::*> and C<Alzabo::ObjectCache::Sync::*>

These are object caching modules.  The modules in the
C<Alzabo::ObjectCache::Store> hierarchy are used to store row objects
persistently.  The modules in C<Alzabo::ObjectCache::Sync> are used to
make sure that multiple instances of the same row objects in different
processes don't step on each other's toes.

=item * C<Alzabo::Runtime::Row>

This object represents a row from a table.  These objects are created
by L<C<Alzabo::Runtime::Table>|Alzabo::Runtime::Table>,
L<C<Alzabo::Runtime::RowCursor>|Alzabo::Runtime::RowCursor>, and
L<C<Alzabo::Runtime::JoinCursor>|Alzabo::Runtime::JoinCursor> objects.
It is the sole interface by which actual data is retrieved, updated,
or deleted in a table.

=item * C<Alzabo::Runtime::JoinCursor> and C<Alzabo::Runtime::RowCursor>

This object is a cursor that returns row objects.  Using a cursor
saves a lot of memory for big selects.

=item * C<Alzabo::Config>

This class is generated by Makefile.PL during installation and
contains information such as what directory contains saved schemas and
other configuration information.

=item * C<Alzabo::ChangeTracker>

This object provides a method for an object to register a series to
backout from multiple changes.  This is done by providing the
ChangeTracker object with a callback after a change is succesfully
made to an object or objects.  If a future change in a set of
operations fail, the tracker can be told to back the changes out. This
is used primarily in
L<C<Alzabo::Create::Schema>|Alzabo::Create::Schema>.

=item * C<Alzabo::MethodMaker>

This module can auto-generate useful methods for you schema, table,
and row objects based on the structure of your schema.

=item * C<Alzabo::Exceptions>

This object creates the exception subclasses used by Alzabo.

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

=head1 SUPPORT

The Alzabo docs are conveniently located online at
http://alzabo.sourceforge.net/docs/.

There is also a mailing list.  You can sign up at
http://lists.sourceforge.net/lists/listinfo/alzabo-general.

Please don't email me directly.  Use the list instead so others can
see your questions.

=head1 LICENSE

Copyright (c) 2000-2001 Dave Rolsky

All rights reserved.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
