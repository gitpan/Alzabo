package Alzabo::MethodMaker;

use strict;
use vars qw($VERSION $DEBUG);

use Alzabo::Runtime::Schema;

use Params::Validate qw( :all );
Params::Validate::set_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.23 $ =~ /(\d+)\.(\d+)/;

$DEBUG = $ENV{ALZABO_DEBUG} || 0;

1;

# types of methods that can be made
my @options = qw( foreign_keys insert linking_tables lookup_tables
		  row_columns self_relations tables table_columns update );

sub import
{
    my $class = shift;

    validate( @_, { schema     => { type => SCALAR },
		    class_root => { type => SCALAR,
				    optional => 1 },
		    name_maker => { type => CODEREF,
				    optional => 1 },
		    pluralize  => { type => CODEREF,
				    optional => 1 },
		    ( map { $_ => { optional => 1 } } 'all', @options ) } );
    my %p = @_;

    return unless exists $p{schema};
    return unless grep { exists $p{$_} && $p{$_} } 'all', @options;

    my $maker = $class->new(%p);

    $maker->make;
}

sub new
{
    my $class = shift;
    my %p = @_;

    map { $p{$_} = 1 } @options if delete $p{all};

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
	    die "No base class could be determined\n" unless $class_root;
	} while ( $class_root->isa(__PACKAGE__) );
    }

    $p{pluralize} = sub { return shift } unless ref $p{pluralize};

    my $self;

    $p{name_maker} = sub { $self->name(@_) } unless ref $p{name_maker};

    $self = bless { opts => \%p, class_root => $class_root, schema => $s }, $class;

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
	$self->{uncached_row_class} = join '::', $self->{class_root}, 'UncachedRow', $t->name;
	$self->{cached_row_class} = join '::', $self->{class_root}, 'CachedRow', $t->name;

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
	    $self->make_insert_method($t);
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
    my $self = shift;
    my $t = shift;

    my $name = $self->{opts}{name_maker}->( type => 'table',
					    table => $t );
    return if $t->schema->can($name);

    my $method = join '::', $self->{schema_class}, $name;

    warn "Making table access method $method: returns table\n" if $DEBUG;
    {
	no strict 'refs';
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

    return \$self->SUPER::row_by_pk(\@_, row_class => '$self->{row_class}');
}

1;
EOF
}

sub eval_row_class
{
    my $self = shift;

    eval <<"EOF";
package $self->{row_class};

sub new
{
    my \$class = shift;

    my \%p = \@_;
    my \$row = Alzabo::Runtime::Row->new(\@_);

    if ( \$p{no_cache} || ! \$Alzabo::ObjectCache::VERSION )
    {
        return bless \$row, '$self->{uncached_row_class}';
    }
    else
    {
        return bless \$row, '$self->{cached_row_class}';
    }
}

package $self->{uncached_row_class};

\@$self->{uncached_row_class}::ISA = qw($self->{row_class} Alzabo::Runtime::Row);

package $self->{cached_row_class};

\@$self->{cached_row_class}::ISA = qw($self->{row_class} Alzabo::Runtime::CachedRow);


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
	my $name = $self->{opts}{name_maker}->( type => 'table_column',
						column => $c );
	next if $t->can($name);

	my $method = join '::', $self->{table_class}, $name;

	warn "Making column object $method: returns column object\n" if $DEBUG;
	{
	    no strict 'refs';
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
	my $name = $self->{opts}{name_maker}->( type => 'row_column',
						column => $c );
	next if $self->{row_class}->can($name);

	my $method = join '::', $self->{row_class}, $name;

	my $col_name = $c->name;

	warn "Making column access $method: returns scalar value of column\n" if $DEBUG;
	{
	    no strict 'refs';
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

	if ( @fk == 2 && $fk[0]->table_from eq $fk[0]->table_to &&
	     $fk[1]->table_from eq $fk[1]->table_to )
	{
	    unless ( ($fk[0]->min_max_from)[1] eq '1' && ($fk[0]->min_max_to)[1] eq '1' )
	    {
		$self->make_self_relation($fk[0]) if $self->{opts}{self_relations};
	    }
	    next;
	}

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
		$self->make_linking_table_method($fk);
	    }
	    if ( $self->{opts}{lookup_tables} )
	    {
		$self->make_lookup_table_method($fk);
	    }
	}

	# Pluralize the name of the table the relationship is to.
	if ( ($fk->min_max_from)[1] eq 'n' )
	{
	    my $name = $self->{opts}{name_maker}->( type => 'foreign_key',
						    foreign_key => $fk,
						    plural => 1 );
	    next if $self->{row_class}->can($name);

	    my $method = join '::', $self->{row_class}, $name;

	    warn "Making foreign key $method: returns row cursor\n" if $DEBUG;
	    {
		no strict 'refs';
		*{$method} =
		    sub { my $self = shift;
			  return $self->rows_by_foreign_key( foreign_key => $fk, @_ ); };
	    }
	}
	# Singular method name
	else
	{
	    my $name = $self->{opts}{name_maker}->( type => 'foreign_key',
						    foreign_key => $fk,
						    plural => 0 );
	    next if $self->{row_class}->can($name);

	    my $method = join '::', $self->{row_class}, $name;

	    warn "Making foreign key $method: returns single row\n" if $DEBUG;
	    {
		no strict 'refs';
		*{$method} =
		    sub { my $self = shift;
			  return $self->rows_by_foreign_key( foreign_key => $fk, @_ ); };
	    }
	}
    }
}

sub make_self_relation
{
    my $self = shift;
    my $fk = shift;

    my (@pairs, @reverse_pairs);
    if ( ($fk->min_max_from)[1] eq 'n' && ($fk->min_max_to)[1] eq '1' )
    {
	@pairs = map { [ $_->[0], $_->[1]->name ] } $fk->column_pairs;
	@reverse_pairs = map { [ $_->[1], $_->[0]->name ] } $fk->column_pairs;
    }
    else
    {
	@pairs = map { [ $_->[1], $_->[0]->name ] } $fk->column_pairs;
	@reverse_pairs = map { [ $_->[0], $_->[1]->name ] } $fk->column_pairs;
    }

    my $name = $self->{opts}{name_maker}->( type => 'self_relation',
					    foreign_key => $fk,
					    parent => 1 );
    return if $self->{table_class}->can($name);

    my $parent = join '::', $self->{row_class}, $name;

    my $table = $fk->table_from;

    warn "Making self-relation method $parent: returns single row\n" if $DEBUG;
    {
	no strict 'refs';
	*{$parent} =
	    sub { my $self = shift;
		  my @where = map { [ $_->[0], '=', $self->select( $_->[1] ) ] } @pairs;
		  return $table->rows_where( where => \@where,
					     @_ )->next_row; };
    }

    $name = $self->{opts}{name_maker}->( type => 'self_relation',
					 foreign_key => $fk,
					 parent => 0 );
    return if $self->{table_class}->can($name);

    my $children = join '::', $self->{row_class}, $name;

    warn "Making self-relation method $children: returns row cursor\n" if $DEBUG;
    {
	no strict 'refs';
	*{$children} =
	    sub { my $self = shift;
		  my @where = map { [ $_->[0], '=', $self->select( $_->[1] ) ] } @reverse_pairs;
		  return $table->rows_where( where => \@where,
					     @_ ); };
    }
}

sub make_linking_table_method
{
    my $self = shift;
    my $fk = shift;

    my @fk = $fk->table_to->all_foreign_keys;
    return if @fk != 2;

    my $fk_2;
    foreach my $c ( $fk->table_to->columns )
    {
	# skip the column where the foreign key is from the linking
	# table to the source table
	next if eval { $fk->table_to->foreign_keys( table => $fk->table_from,
						    column => $c) };

	# The foreign key from the linking table to the _other_ table
	$fk_2 = $fk->table_to->foreign_keys_by_column($c);
	last;
    }

    return unless $fk_2;

    # Return unless all the columns in the linking table are part of
    # the link.
    return unless ( $fk->table_to->primary_key ==
		    ( $fk->table_from->primary_key + $fk_2->table_to->primary_key ) );

    my $name = $self->{opts}{name_maker}->( type => 'linking_table',
					    foreign_key => $fk,
					    foreign_key_2 => $fk_2,
					  );

    return if $self->{row_class}->can($name);

    my $method = join '::', $self->{row_class}, $name;

    my $s = $fk->table_to->schema;
    my @t = ( $fk->table_to, $fk_2->table_to );
    my $select = [ $t[1] ];

    warn "Making linking table method $method: returns row cursor\n" if $DEBUG;
    {
	no strict 'refs';
	*{$method} =
	    sub { my $self = shift;
		  my %p = @_;
		  if ( $p{where} )
		  {
		      $p{where} = [ $p{where} ] unless UNIVERSAL::isa( $p{where}[0], 'ARRAY' );
		  }
		  foreach my $pair ( $fk->column_pairs )
		  {
		      push @{ $p{where} }, [ $pair->[1], '=', $self->select( $pair->[0]->name ) ];
		  }

		  return $s->join( tables => \@t,
				   select => $select,
				   %p ); };
    }

    return 1;
}

sub make_lookup_table_method
{
    my $self = shift;
    my $fk = shift;

    return unless $fk->table_to->primary_key == 1;

    my $name = $self->{opts}{name_maker}->( type => 'lookup_table',
					    foreign_key => $fk );
    return if $self->{row_class}->can($name);

    my $method = join '::', $self->{row_class}, $name;

    my $non_pk_name = (grep { ! $_->is_primary_key } $fk->table_to->columns)[0]->name;
    warn "Making lookup table $method: returns scalar value of column\n" if $DEBUG;
    {
	no strict 'refs';
	*{$method} =
	    sub { my $self = shift;
		  return $self->rows_by_foreign_key( foreign_key => $fk, @_ )->select($non_pk_name) };
    }

    return 1;
}

sub make_insert_method
{
    my $self = shift;
    my $table = shift;

    return unless $self->{table_class}->can('validate_insert');

    my $method = join '::', $self->{table_class}, 'insert';

    {
	no strict 'refs';
	return if *{$method}{CODE};
    }

    warn "Making insert method $method\n" if $DEBUG;
    eval <<"EOF";
{
    package $self->{table_class};
    sub insert
    {
        my \$s = shift;
        my \%p = \@_;
        \$s->validate_insert( %{ \$p{values} } );
        \$s->SUPER::insert(\%p);
    }
}
EOF
}

sub make_update_method
{
    my $self = shift;
    my $table = shift;

    return unless $self->{row_class}->can('validate_update');

    my $method = join '::', $self->{cached_row_class}, 'update';

    {
	no strict 'refs';
	goto UNCACHED if *{$method}{CODE};
    }

    warn "Making update method $method\n" if $DEBUG;

    eval <<"EOF";
{
    package $self->{cached_row_class};
    sub update
    {
        my \$s = shift;
        my \%p = \@_;
        \$s->validate_update(\%p);
        \$s->Alzabo::Runtime::CachedRow::update(\%p);
    }
}
EOF

 UNCACHED:

    $method = join '::', $self->{uncached_row_class}, 'update';

    {
	no strict 'refs';
	return if *{$method}{CODE};
    }

    warn "Making update method $method\n" if $DEBUG;

    eval <<"EOF";
{
    package $self->{uncached_row_class};
    sub update
    {
        my \$s = shift;
        my \%p = \@_;
        \$s->validate_update(\%p);
        \$s->Alzabo::Runtime::Row::update(\%p);
    }
}
EOF
}

sub name
{
    my $self = shift;
    my %p = @_;

    return $p{table}->name if $p{type} eq 'table';

    return $p{column}->name if $p{type} eq 'table_column';

    return $p{column}->name if $p{type} eq 'row_column';

    if ( $p{type} eq 'foreign_key' )
    {
	if ($p{plural})
	{
	    return $self->{opts}{pluralize}->( $p{foreign_key}->table_to->name );
	}
	else
	{
	    return $p{foreign_key}->table_to->name;
	}
    }

    if ( $p{type} eq 'linking_table' )
    {
	my $method = $p{foreign_key}->table_to->name;
	my $tname = $p{foreign_key}->table_from->name;
	$method =~ s/^$tname\_?//;
	$method =~ s/_?$tname$//;

	return $self->{opts}{pluralize}->($method);
    }

    return (grep { ! $_->is_primary_key } $p{foreign_key}->table_to->columns)[0]->name
	if $p{type} eq 'lookup_table';

    return $p{parent} ? 'parent' : 'children'
	if $p{type} eq 'self_relation';

    die "unknown type in call to naming sub: $p{type}\n";
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

=head3 schema => $schema_name

This parameter is B<required>.

=head3 class_root => $class_name

If given, this will be used as the root of the class names generated
by this module.  This root should not end in '::'.  If none is given,
then the calling module's name is used as the root.  See L<Class
Names> for more information.

=head3 all => $bool

This tells this module to make all of the methods it possibly can.
See L<METHOD CREATION OPTIONS|METHOD CREATION OPTIONS> for more
details.

=head3 name_maker => \&naming_sub

If this option is given, then this callback will be called any time a
method name needs to be generated.  This allows you to have full
control over the resulting names.  Otherwise names are generated as
described in the documentation.

The callback will receive a hash containing the following parameters:

=over 4

=item * type => $method_type

This will always be the same as one of the parameters you give to the
import method.  It will be one of the following: C<foreign_key>,
C<insert>, C<linking_table>, C<lookup_table>, C<row_column>,
C<self_relation>, C<table>, C<table_column>, or C<update>.

=back

The following parameters vary from case to case:

When the type is C<table>:

=over 4

=item * table => Alzabo::Table object

This parameter will be passed when the type is C<table>.  It is the
table object the schema object's method will return.

=back

When the type is C<table_column> or C<row_column>:

=over 4

=item * column => Alzabo::Column object

When the type is C<table_column>, this is the column object the method
will return.  When the type is C<row_column>, then it is the column
whose B<value> the method will return.

=back

When the type is C<foreign_key>, C<linking_table>, C<lookup_table>, or
C<self_relation>:

=over 4

=item * foreign_key => Alzabo::ForeignKey object

This is the foreign key on which the method is based.

=back

When the type is C<foreign_key>:

=over 4

=item * plural => $bool

This indicates whether or not the method that is being created will
return a cursor object (true) or a row object (false).

=back

When the type is C<linking_table>:

=over 4

=item * foreign_key_2 => Alzabo::ForeignKey object

When making a linking table method, two foreign keys are used.  The
C<foreign_key> is from the table being linked from to the linking
table.  This parameter is the foreign key from the linking table to
the table being linked to.

=back

When the type is C<self_relation>:

=over 4

=item * parent => $boolean

This indicates whether or not the method being created will return
parent objects (true) or child objects (false).

=back

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

C<E<lt>class rootE<gt>::Schema>

=head3 Tables

C<E<lt>class rootE<gt>::Table::<table nameE<gt>>

=head3 Rows

C<E<lt>class rootE<gt>::Row::<table nameE<gt>>, subclassed by
C<E<lt>class rootE<gt>::CachedRow::<table nameE<gt>> and C<E<lt>class
rootE<gt>::UncachedRow::<table nameE<gt>>

With a root of 'My::Stuff', and a schema with only two tables, 'movie'
and 'image', this would result in the following class names:

 My::Stuff::Schema
 My::Stuff::Table::movie
 My::Stuff::Row::movie
   My::Stuff::CachedRow::movie
   My::Stuff::UncachedRow::movie
 My::Stuff::Table::image
 My::Stuff::Row::image
   My::Stuff::CachedRow::image
   My::Stuff::UncachedRow::image

=head2 Loading Classes

For each class into which an object is blessed, this module will
attempt to load that class via a C<use> statement.  If there is no
module found this will not cause an error.  If this class defines any
methods that have the same name as those this module generates, then
this module will not attempt to generate them.

=head3 C<validate_insert> and C<validate_update> methods

These methods can be defined in the relevant table and row class,
respectively.  If they are defined then they will be called before any
actual inserts or updates are done.

The C<validate_update> method should be defined in the C<E<lt>class
rootE<gt>::Row::<table nameE<gt>> class, not its subclasses.

They both should expect to receive a hash of column names to values as
their parameters.  For C<validate_insert>, this will represent the new
row to be inserted.  For C<validate_update>, this will represent the
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
Classes> for more details.  Unless you have already defined a
C<validate_insert> method for the generated table class this method
will not be overridden.

=head2 Row object methods

=head3 update

Create an C<update> method overriding the one in
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row>.  See L<Loading
Classes> for more details.  Unless you have already defined a
C<validate_update> method for the generated row class this method will
not be overridden.

=head3 foreign_keys ($bool)

Creates methods in row objects named for the table to which the
relationship exists.  These methods return either a single
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> object or a single
L<C<Alzabo::Runtime::RowCursor>|Alzabo::Runtime::RowCursor> object,
depending on the cardinality of the relationship.

Take these tables as an example.

  movie                     credit
  ---------                 --------
  movie_id                  movie_id
  title                     person_id
                            role_name
NOTE: This option must be true if you want any of the following
options to be used.

=head3 linking_tables ($bool)

A linking table, as defined here, is a table with a two column primary
key that, with each column being a foreign key to another table's
primary key.  These tables exist to facilitate n..n logical
relationships.  If both C<foreign_keys> and C<linking_tables> are
true, then methods will be created that skip the intermediate linking
tables

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
C<cuisine.description>.

=head3 self_relations ($bool)

A self relation is when a table has a parent/child relationship with
itself.  Here is an example:

 location
 --------
 location_id
 name
 parent_location_id

NOTE: If the relationship has a cardinality of 1..1 then no methods
will be created, as this option is really intended for parent/child
relationships.  This may change in the future.

=head1 NAMING SUB EXAMPLE

Here is an example that covers all of the possible options:

 use Lingua::EN::Inflect;

 sub namer
 {
     my %p = @_;

     # Table object can be returned from the schema via methods such as $schema->User_t;
     return $p{table}->name . '_t' if $p{type} eq 'table';

     # Column objects are returned similarly, via $schema->User_t->username_c;
     return $p{column}->name . '_c' if $p{type} eq 'table_column';

     # If I have a row object, I can get at the columns via their names, for example $user->username;
     return $p{column}->name if $p{type} eq 'row_column';

     # This manipulates the table names a bit to generate names.  For
     # example, if I have a table called UserRating and a 1..n
     # relationship from User to UserRating, I'll end up with a method
     # on rows in the User table called ->Ratings which returns a row
     # cursor of rows from the UserRating table.
     if ( $p{type} eq 'foreign_key' )
     {
       	 my $name = $p{foreign_key}->table_to->name;
	 my $from = $p{foreign_key}->table_from->name;
	 $name =~ s/$from//;

	 if ($p{plural})
	 {
             return my_PL( $name );
	 }
         else
	 {
             return $name;
	 }
     }

     # This is very similar to how foreign keys are handled.  Assume
     # we have the tables Restaurant, Cuisine, and RestaurantCuisine.
     # If we are generating a method for the link from Restaurant
     # through to Cuisine, we'll have a method on Restaurant table
     # rows called ->Cuisines, which will return a cursor of rows from
     # the Cuisine table.
     if ( $p{type} eq 'linking_table' )
     {
     	 my $method = $p{foreign_key}->table_to->name;
	 my $tname = $p{foreign_key}->table_from->name;
	 $method =~ s/$tname//;

	 return my_PL($method);
     }

     # A lookup table is a 2 column table with a single column primary
     # key.  The method we generate is the name of the column that is
     # _not_ a primary key.  With a table named Location with columns
     # location_id and location, we could have a relationship from our
     # Restaurant table to the Location table.  This would give all
     # Restaurant table rows a ->location method which returned the
     # _value_ from the Location table that matched the location_id in
     # the Restaurant row.
     return (grep { ! $_->is_primary_key } $p{foreign_key}->table_to->columns)[0]->name
         if $p{type} eq 'lookup_table';

     # This should be fairly self-explanatory.
     return $p{parent} ? 'parent' : 'children'
	 if $p{type} eq 'self_relation';

     # As should this.
     return $p{type} if grep { $p{type} eq $_ } qw( insert update );

     # And just to make sure that nothing slips by us we do this.
     die "unknown type in call to naming sub: $p{type}\n";
 }

 # Lingua::EN::Inflect did not handle the word 'hours' properly when this was written
 sub my_PL
 {
     my $name = shift;
     return $name if $name =~ /hours$/i;

     return Lingua::EN::Inflect::PL($name);
 }

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
