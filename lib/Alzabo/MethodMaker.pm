package Alzabo::MethodMaker;

use strict;
use vars qw($VERSION $DEBUG);

use Alzabo::Runtime::Schema;

$VERSION = sprintf '%2d.%02d', q$Revision: 1.9 $ =~ /(\d+)\.(\d+)/;

$DEBUG = $ENV{ALZABO_DEBUG} || 0;

1;

sub import
{
    my $class = shift;
    my %p = @_;


    return unless exists $p{schema};
    return unless grep { exists $p{$_} && $p{$_} }
	qw( all table_columns row_columns foreign_keys insert tables update );

    my $maker = $class->new(%p);

    $maker->make;
}

sub new
{
    my $class = shift;
    my %p = @_;

    map { $p{$_} = 1 } qw( foreign_keys insert linking_tables lookup_tables row_columns tables table_columns update )
	if delete $p{all};

    my $s = eval { Alzabo::Runtime::Schema->load_from_file( name => delete $p{schema} ); };
    warn $@ if $@ && $DEBUG;
    return if $@;

    my $class_root;
    if ( $p{class_root} )
    {
	$class_root = $p{class_root};
    }
    else
    {
	my $x = 0;
	do
	{
	    $class_root = caller($x++);
	    last unless $class_root;
	} while ( $class_root->isa(__PACKAGE__) );
    }
    die "No base class could be determined\n" unless $class_root;

    $p{pluralize} = \&pluralize unless ref $p{pluralize};

    my $self = bless { opts => \%p, class_root => $class_root, schema => $s }, $class;

    return $self;
}

sub make
{
    my $self = shift;

    $self->{schema_class} = join '::', $self->{class_root}, 'Schema';
    bless $self->{schema}, $self->{schema_class};

    $self->eval_schema_class;
    $self->load_class( $self->{schema_class} );

    foreach my $t ( $self->{schema}->tables )
    {
	$self->{table_class} = join '::', $self->{class_root}, 'Table', $t->name;
	$self->{row_class} = join '::', $self->{class_root}, 'Row', $t->name;

	bless $t, $self->{table_class};
	$self->eval_table_class;

	$self->eval_row_class;

	if ( $self->{opts}{tables} )
	{
	    $self->make_table_method($t);
	}

	$self->load_class( $self->{table_class} );

	if ( $self->{opts}{table_columns} )
	{
	    $self->make_table_column_methods($t);
	}

	if ( $self->{opts}{row_columns} )
	{
	    $self->make_row_column_methods($t);
	}
	if ( $self->{opts}{foreign_keys} )
	{
	    $self->make_foreign_key_methods($t);
	}
	if ( $self->{opts}{insert} )
	{
	    $self->make_insert_method;
	}
	if ( $self->{opts}{update} )
	{
	    $self->make_update_method($t);
	}

	$self->load_class( $self->{row_class} );
    }
}

sub eval_schema_class
{
    my $self = shift;

    eval <<"EOF";
package $self->{schema_class};

use base qw( Alzabo::Runtime::Schema );

1;
EOF
}

sub make_table_method
{
    my $class = shift;
    my $t = shift;

    my $method = join '::', ref $t->schema, $t->name;

    {
	no strict 'refs';

	return if $t->schema->can( $t->name );

	warn "Making table access method $method: returns table\n" if $DEBUG;
	*{$method} = sub { return $t; };
    }
}

sub eval_table_class
{
    my $self = shift;

    eval <<"EOF";
package $self->{table_class};

use base qw( Alzabo::Runtime::Table );

sub row_by_pk
{
    my \$self = shift;

    return bless \$self->SUPER::row_by_pk(\@_), '$self->{row_class}';
}

1;
EOF
}

sub eval_row_class
{
    my $self = shift;

    eval <<"EOF";
package $self->{row_class};

use base qw( Alzabo::Runtime::Row );

1;
EOF
}

sub load_class
{
    my $self = shift;
    my $class = shift;

    eval "use $class;";

    die $@ if $@ && $@ !~ /^Can\'t locate .* in \@INC/;
}

sub make_table_column_methods
{
    my $self = shift;
    my $t = shift;

    foreach my $c ( $t->columns )
    {
	my $method = join '::', $self->{table_class}, $c->name;

	{
	    no strict 'refs';

	    return if $t->can( $c->name );

	    warn "Making column object $method: returns column object\n" if $DEBUG;
	    *{$method} = sub { return $c };
	}
    }
}

sub make_row_column_methods
{
    my $self = shift;
    my $t = shift;

    foreach my $c ( $t->columns )
    {
	my $col_name = $c->name;
	my $method = join '::', $self->{row_class}, $col_name;

	{
	    no strict 'refs';

	    return if $self->{row_class}->can( $col_name );

	    warn "Making column access $method: returns scalar value of column\n" if $DEBUG;
	    *{$method} = sub { return shift->select($col_name); };
	}
    }
}

sub make_foreign_key_methods
{
    my $self = shift;
    my $t = shift;

    foreach my $other_t ( $t->schema->tables )
    {
	my @fk = $t->foreign_keys_by_table($other_t);

	# No way to auto-create methods when there is more (or less)
	# than one relationship between the two tables.
	next unless @fk == 1;

	my $fk = $fk[0];
	my $table_to = $fk->table_to->name;

	# The table may be a linking or lookup table.  If we are
	# supposed to make that kind of method we will and then we'll
	# skip to the next foreign table.
	if ( $fk->table_to->columns == 2 )
	{
	    if ( $self->{opts}{linking_tables} )
	    {
		next if $self->make_linking_table_method($fk);
	    }
	    if ( $self->{opts}{lookup_tables} )
	    {
		next if $self->make_lookup_table_method($fk);
	    }
	}

	# Pluralize the name of the table the relationship is to.
	if ( ($fk->min_max_from)[1] eq 'n' )
	{
	    my $method = join '::', $self->{row_class}, $self->{opts}{pluralize}->( $other_t->name );

	    {
		no strict 'refs';

		return if $self->{row_class}->can( $self->{opts}{pluralize}->( $other_t->name ) );

		warn "Making foreign key $method: returns row cursor\n" if $DEBUG;
		*{$method} =
		    sub { my $self = shift;
			  return $self->rows_by_foreign_key( foreign_key => $fk, @_ ); };
	    }
	}
	# Singular method name
	else
	{
	    my $method = join '::', $self->{row_class}, $other_t->name;

	    {
		no strict 'refs';

		return if $self->{row_class}->can( $other_t->name );

		warn "Making foreign key $method: returns single row\n" if $DEBUG;
		*{$method} =
		    sub { my $self = shift;
			  return $self->rows_by_foreign_key( foreign_key => $fk, @_ ); };
	    }
	}
    }
}

sub make_linking_table_method
{
    my $self = shift;
    my $fk = shift;

    return unless $fk->table_to->primary_key == 2;

    my $t = $fk->table_from;

    my $non_link = (grep { $_->name ne $fk->column_to->name } $fk->table_to->primary_key)[0];

    # The foreign key from the linking table to the _other_ table
    my $fk_2 = $fk->table_to->foreign_keys_by_column( $non_link );

    my $method = $fk->table_to->name;
    my $tname = $t->name;
    $method =~ s/^$tname\_?//;
    $method =~ s/?_$tname$//;

    $method = join '::', $self->{row_class}, $self->{opts}{pluralize}->($method);

    {
	my $s = $t->schema;
	my @t = ( $fk->table_to->name, $fk_2->table_to->name );
	my $select = [ $t[1] ];
	my $col_from = $fk->column_from->name;

	no strict 'refs';

	return if $self->{row_class}->can( $self->{opts}{pluralize}->($method) );

	warn "Making linking table method $method: returns row cursor\n" if $DEBUG;
	*{$method} =
	    sub { my $self = shift;
		  my %p = @_;
		  if ( $p{where} )
		  {
		      $p{where} = [ $p{where} ] unless UNIVERSAL::isa( $p{where}[0], 'ARRAY' );
		  }
		  push @{ $p{where} }, [ $non_link, '=', $self->select($col_from) ];
		  return $s->join( tables => \@t,
				   select => $select,
				   @_ ); };
    }

    return 1;
}

sub make_lookup_table_method
{
    my $self = shift;
    my $fk = shift;

    return unless $fk->table_to->primary_key == 1;

    my $t = $fk->table_from;

    my $non_pk_name = (grep { ! $_->is_primary_key } $fk->table_to->columns)[0]->name;
    my $method = join '::', $self->{row_class}, $non_pk_name;

    {
	no strict 'refs';

	return if $self->{row_class}->can( $non_pk_name );

	warn "Making lookup table $method: returns scalar value of column\n" if $DEBUG;
	*{$method} =
	    sub { my $self = shift;
		  return $self->rows_by_foreign_key( foreign_key => $fk, @_ )->select($non_pk_name) };
    }

    return 1;
}

sub make_insert_method
{
    my $self = shift;

    my $method = join '::', $self->{table_class}, 'insert';

    {
	no strict 'refs';
	return if $self->{table_class}->can('insert');
    }

    my $msg = "Making insert method $method";

    my $code = <<"EOF";
sub $method
{
    my \$self = shift;
    my \%p = \@_;
EOF
    if ( $self->{table_class}->can( 'validate_insert' ) )
    {
	$msg .= "... with validation";
	$code .= <<'EOF';
    $self->validate_insert( %{ $p{values} } );
EOF
    }

    warn "$msg\n" if $DEBUG;
    $code .= <<'EOF';
    $self->SUPER::insert(%p);
}
EOF

    eval $code;
}

sub make_update_method
{
    my $self = shift;

    my $method = join '::', $self->{row_class}, 'update';

    {
	no strict 'refs';
	return if $self->{row_class}->can('update');
    }

    my $msg = "Making update method $method";

    my $code = <<"EOF";
sub $method
{
    my \$self = shift;
    my \%p = \@_;
EOF
    if ( $self->{row_class}->can( 'validate_update' ) )
    {
	$msg .= "... with validation";
	$code .= <<'EOF';
    $self->validate_update(%p);
EOF
    }

    warn "$msg\n" if $DEBUG;
    $code .= <<'EOF';
    $self->SUPER::update(%p);
}
EOF

    eval $code;
}

sub pluralize
{
    return shift;
}

__END__

=head1 NAME

Alzabo::MethodMaker - Auto-generate useful methods based on an existing schema

=head1 SYNOPSIS

  use Alzabo::MethodMaker ( schema => 'schema_name', all => 1 );

=head1 DESCRIPTION

This module can take an existing schema and generate a number of
useful methods for this schema and its tables and rows.  The method
making is controlled by the parameters given along with the use
statement, as seen in the L<SYNOPSIS
section|Alzabo::MethodMaker/SYNOPSIS>.

=head1 PARAMETERS

=head3 schema ($schema_name)

This parameter is B<required>.

=head3 class_root ($class_name)

If given, this will be used as the root of the class names generated
by this module.  This root should not end in '::'.  If none is given,
then the calling module's name is used as the root.  See L<Class
Names> for more information.

=head3 all ($bool)

This tells this module to make all of the methods it possibly can.
See L<METHOD CREATION OPTIONS|METHOD CREATION OPTIONS> for more
details.

=head3 pluralize (\&pluralize)

Some of the methods are designed to return an
L<C<Alzabo::Runtime::RowCursor>|Alzabo::Runtime::RowCursor> object.
If your table names are singular, it may be desirable to use the
plural form for the method names (such as 'movie' becoming 'movies').
If you provide a callback for this parameter, it will be used to make
the plural forms.  If none is provided, then the unaltered table name
will be used.

This callback should expect to receive a single parameter, the word to
be pluralized, and should return its plural form.

=head1 EFFECTS

Using this module has several effects on your schema's objects.

=head2 New Class Names

Using this module causes your schema, table, and row objects to be
blessed into subclasses of
L<C<Alzabo::Runtime::Schema>|Alzabo::Runtime::Schema>,
L<C<Alzabo::Runtime::Table>|Alzabo::Runtime::Table>,
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row>, respectively.  These
subclasses contain the various methods created by this module.  The
new class names are formed by using the
L<C<class_root>|Alzabo::MethodMaker/PARAMETERS> parameter and adding
to it.

=head3 Schema

<class root>::Schema

=head3 Tables

<class root>::Table::<table name>

=head3 Rows

<class root>::Row::<table name>

With a root of 'My::Stuff', and a schema with only two tables, 'movie'
and 'image', this would result in the class names:

 My::Stuff::Schema
 My::Stuff::Table::movie
 My::Stuff::Row::movie
 My::Stuff::Table::image
 My::Stuff::Row::image

=head2 Loading Classes

For each class that an object is blessed into, this module attempts to
load that class via a C<use> statement.  If there is no module found
this will not cause an error.  If this class defines any methods that
have the same name as those this module generates, then this module
will not attempt to generate them.

=head3 C<validate_insert> and C<validate_update> methods

These methods can be defined in the relevant table and row classes,
respectively.  If they are defined then they will be called before any
actual inserts or updates are done.

They both should expect to receive a hash of column names to values as
a parameter.  For C<validate_insert>, this will represent the new row
to be inserted.  For C<validate_update>, this will represent the
changes to the existing row.

These methods should throw exceptions if there are errors with this
data.

For this to work, you must specify the C<insert> and/or C<update>
parameters as true when loading the module.  This causes these methods
to be overridden in the generated subclasses.

=head1 METHOD CREATION OPTIONS

=head2 Schema object methods

=head3 tables ($bool)

Creates methods for the schema that return the table object matching
the name of the method.

For example, given a schema containing tables named 'movie' and
'image', this would create methods that could be called as
C<$schema-E<gt>movie> and C<$schema-E<gt>image>.

=head2 Table object methods.

=head3 table_columns ($bool)

Creates methods for the tables that return the column object matching
the name of the method.  This is quite similar to the C<tables> option
for schemas.

=head3 insert

Create an C<insert> method overriding the one in
L<C<Alzabo::Runtime::Table>|Alzabo::Runtime::Table>.  See L<Loading
Classes> for more details.

=head2 Row object methods

=head3 update

Create an C<update> method overriding the one in
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row>.  See L<Loading
Classes> for more details.

=head3 foreign_keys ($bool)

Creates methods in row objects named for the table to which the
relationship exists.  These methods return either a single
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> object or a single
L<C<Alzabo::Runtime::RowCursor>|Alzabo::Runtime::RowCursor> object,
depending on the cardinality of the relationship.

For relationships with 1..n cardinality, the C<pluralize> callback
will be called in an attempt to pluralize the method name.

Take these tables as an example.

  movie                     credit
  ---------                 --------
  movie_id                  movie_id
  title                     person_id
                            role_name

When creating the method that returns rows from the C<credit> table
for the movie row objects, we will attempt to first pluralize the word
'credit'.  Let's assume that pluralization returns the word 'credits'.
This will create a method C<$movie_row-E<gt>credits> that returns an
L<C<Alzabo::Runtime::RowCursor>|Alzabo::Runtime::RowCursor> object.
This cursor will return one
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> object for every
credit containing the movie_id of the calling row.

Conversely, credit row objects will have a method
C<$credit_row-E<gt>movie> which will return the
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> object containing the
movie_id of the credit row.

=head3 linking_tables ($bool)

A linking table, as defined here, is a table with a two column primary
key that, with each column being a foreign key to another table's
primary key.  These tables exist to facilitate n..n logical
relationships.  If both C<foreign_keys> and C<linking_tables> are
true, then methods will be created that skip the intermediate linking
tables

The method name that is used is generated according to the following
rules:

Start with the name of the linking table.  Let's assume that we have a
linking table named 'movie_image' that links together a movie table
and an image table in an n..n relationship.

If the linking table name contains the name of the table for which we
are creating the method, strip it from the beginning of the method
name.  Also strip any underscores that follow this name.

Similarly, strip the name of the table if it occurs at the end of the
linking table name, along with any underscore immediately preceding
it.

Then call the C<pluralize> callback to pluralize the method name.

The previous two rules would leave us with the methods
C<$movie_row-E<gt>images> for the movie table rows and
C<$image_row-E<gt>movies> for the image table rows.

To illustrate further, let's use a slightly more complex example with
the aforementioned movie and image tables.  Let's assume that there
are now two linking tables, one named 'movie_poster_image' and one
named 'movie_premiere_image'.

If we apply the previous rules (and assume an English pluralization)
we will end up with the following methods:

 $movie_row->poster_images
 $movie_row->premiere_images
 $image->movie_posters
 $image->movie_premieres

The name formation rules used herein are no doubt not appropriate to
all languages and circumstances.  Patches are welcome.  In the future
there might be a callback parameter added for this type of name
formations.

=head3 lookup_tables ($bool)

A lookup table is defined as a two column table with a one column
primary key.  It is assumed that the interesting part of this table is
the table is the column that is B<not> the primary key.  Therefore,
this module can create methods for these relationships that returns
the B<data> in this column.  As an example, take the following tables:

  restaurant                cuisine
  ---------                 --------
  restaurant_id             cuisine_id
  name                      description
  phone
  cuisine_id

When given a restaurant table row, we already know its cuisine_id
value.  However, what we really want in most contexts is the value of
C<cuisine.description>.  In the above example, this module would
create a method C<$restaurant_row-E<gt>cuisine> that returns the value
of C<cuisine.description> in the row with the cuisine_id in that
restaurant table row.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
