package Alzabo::MethodMaker;

use strict;
use vars qw($VERSION $DEBUG);

use Alzabo::Exceptions;
use Alzabo::Runtime;

use Params::Validate qw( :all );
Params::Validate::validation_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.51 $ =~ /(\d+)\.(\d+)/;

$DEBUG = $ENV{ALZABO_DEBUG} || 0;

# types of methods that can be made - only ones that haven't been
# deprecated
my @options = qw( foreign_keys
		  linking_tables
		  lookup_columns
		  row_columns
		  self_relations

		  tables
		  table_columns

                  insert_hooks
		  update_hooks
		  select_hooks
		  delete_hooks
		);

# deprecated options
my @deprecated = qw( insert
                     update
                   );

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
		    ( map { $_ => { optional => 1 } } 'all', @options, @deprecated ) } );
    my %p = @_;

    return unless exists $p{schema};
    return unless grep { exists $p{$_} && $p{$_} } 'all', @options, @deprecated;

    my $maker = $class->new(%p);

    $maker->make;
}

sub new
{
    my $class = shift;
    my %p = @_;

    if ( delete $p{all} )
    {
	foreach (@options)
	{
	    $p{$_} = 1 unless exists $p{$_} && ! $p{$_};
	}
    }

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

    foreach my $t ( sort { $a->name cmp $b->name  } $self->{schema}->tables )
    {
	$self->{table_class} = join '::', $self->{class_root}, 'Table', $t->name;
	$self->{row_class} = join '::', $self->{class_root}, 'Row', $t->name;
	$self->{uncached_row_class} = join '::', $self->{class_root}, 'UncachedRow', $t->name;
	$self->{cached_row_class} = join '::', $self->{class_root}, 'CachedRow', $t->name;
	$self->{potential_row_class} = join '::', $self->{class_root}, 'PotentialRow', $t->name;

	bless $t, $self->{table_class};
	$self->eval_table_class;

	$self->eval_row_class;

	if ( $self->{opts}{tables} )
	{
	    $self->make_table_method($t);
	}

	$self->load_class( $self->{table_class} );
	$self->load_class( $self->{row_class} );

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

	foreach ( qw( insert update select delete ) )
	{
	    if ( $self->{opts}{"$_\_hooks"} )
	    {
		$self->make_hooks($t, $_);
	    }
	}

	# deprecated
	if ( $self->{opts}{insert} )
	{
	    $self->make_insert_method;
	}
	if ( $self->{opts}{update} )
	{
	    $self->make_update_method;
	}
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

    Alzabo::Exception::Eval->throw( error => $@ ) if $@;
}

sub make_table_method
{
    my $self = shift;
    my $t = shift;

    my $name = $self->{opts}{name_maker}->( type => 'table',
					    table => $t );
    return unless $name;
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

sub potential_row
{
    my \$self = shift;

    return '$self->{potential_row_class}'->Alzabo::Runtime::PotentialRow::new( \@_, table => \$self );
}

1;
EOF

    Alzabo::Exception::Eval->throw( error => $@ ) if $@;
}

sub eval_row_class
{
    my $self = shift;

    # Need to load these so that ->can checks can see them
    require Alzabo::Runtime::Row;
    require Alzabo::Runtime::CachedRow;
    require Alzabo::Runtime::PotentialRow;

    eval <<"EOF";
package $self->{row_class};

sub new
{
    my \$class = shift;

    my \%p = \@_;
    my \$row = Alzabo::Runtime::Row->new(\@_);

    if ( \$p{no_cache} || ! defined \$Alzabo::ObjectCache::VERSION )
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

package $self->{potential_row_class};

\@$self->{potential_row_class}::ISA = qw(Alzabo::Runtime::PotentialRow $self->{row_class});


1;
EOF

    Alzabo::Exception::Eval->throw( error => $@ ) if $@;
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

    foreach my $c ( sort { $a->name cmp $b->name  } $t->columns )
    {
	my $name = $self->{opts}{name_maker}->( type => 'table_column',
						column => $c );
	next unless $name;
	next if $t->can($name);

	my $method = join '::', $self->{table_class}, $name;

	my $col_name = $c->name;

	warn "Making column object $method: returns column object\n" if $DEBUG;
	{
	    no strict 'refs';
	    *{$method} = sub { return $_[0]->column($col_name) };
	}
    }
}

sub make_row_column_methods
{
    my $self = shift;
    my $t = shift;

    foreach my $c ( sort { $a->name cmp $b->name  } $t->columns )
    {
	my $name = $self->{opts}{name_maker}->( type => 'row_column',
						column => $c );
	next unless $name;
	next if $self->{uncached_row_class}->can($name) || $self->{cached_row_class}->can($name);

	my $method = join '::', $self->{row_class}, $name;

	my $col_name = $c->name;

	warn "Making column access $method: returns scalar value/takes new value\n" if $DEBUG;
	{
	    no strict 'refs';
	    *{$method} = sub { my $self = shift;
			       if (@_)
			       {
				   $self->update( $col_name => $_[0] );
			       }
			       return $self->select($col_name); };
	}
    }
}

sub make_foreign_key_methods
{
    my $self = shift;
    my $t = shift;

    foreach my $other_t ( sort { $a->name cmp $b->name  } $t->schema->tables )
    {
	my @fk = $t->foreign_keys_by_table($other_t);

	if ( @fk == 2 && $fk[0]->table_from eq $fk[0]->table_to &&
	     $fk[1]->table_from eq $fk[1]->table_to )
	{
	    unless ($fk[0]->is_one_to_one)
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
	}

	unless ( $fk->is_one_to_many )
	{
	    if ( $self->{opts}{lookup_columns} )
	    {
		$self->make_lookup_columns_methods($fk);
	    }
	}

	# Pluralize the name of the table the relationship is to.
	if ($fk->is_one_to_many)
	{
	    my $name = $self->{opts}{name_maker}->( type => 'foreign_key',
						    foreign_key => $fk,
						    plural => 1 );
	    next unless $name;
	    next if $self->{uncached_row_class}->can($name) || $self->{cached_row_class}->can($name);

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
	    next unless $name;
	    next if $self->{uncached_row_class}->can($name) || $self->{cached_row_class}->can($name);

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
    if ($fk->is_one_to_many)
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

    my $table = $fk->table_from;
    unless ( ! $name || $self->{table_class}->can($name) )
    {
	my $parent = join '::', $self->{row_class}, $name;

	warn "Making self-relation method $parent: returns single row\n" if $DEBUG;
	{
	    no strict 'refs';
	    *{$parent} =
		sub { my $self = shift;
		      my @where = map { [ $_->[0], '=', $self->select( $_->[1] ) ] } @pairs;
		      return $table->one_row( where => \@where, @_ ) };
	}
    }

    $name = $self->{opts}{name_maker}->( type => 'self_relation',
					 foreign_key => $fk,
					 parent => 0 );
    return unless $name;
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
    return unless $name;
    return if $self->{uncached_row_class}->can($name) || $self->{cached_row_class}->can($name);

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

sub make_lookup_columns_methods
{
    my $self = shift;
    my $fk = shift;

    # Make sure the relationship is to the foreign table's primary key
    my @to = $fk->columns_to;
    return unless ( ( scalar grep { $_->is_primary_key } @to ) == @to &&
		    ( scalar $fk->table_to->primary_key ) == @to );

    foreach ( sort { $a->name cmp $b->name  } $fk->table_to->columns )
    {
	my $name = $self->{opts}{name_maker}->( type => 'lookup_columns',
						foreign_key => $fk,
						column => $_ );
	next unless $name;
	next if $self->{uncached_row_class}->can($name) || $self->{cached_row_class}->can($name);

	my $method = join '::', $self->{row_class}, $name;
	my $col_name = $_->name;
	warn "Making lookup columns $method: returns scalar value of column\n" if $DEBUG;
	{
	    no strict 'refs';
	    *{$method} =
		sub { my $self = shift;
		      return $self->rows_by_foreign_key( foreign_key => $fk, @_ )->select($col_name) };
	}
    }
}

sub make_hooks
{
    my $self = shift;
    my $table = shift;
    my $type = shift;

    my $class = $type eq 'insert' ? $self->{table_class} : $self->{row_class};

    my $pre = "pre_$type";
    my $post = "post_$type";

    return unless $class->can($pre) || $class->can($post);

    my $method = join '::', $class, $type;

    {
	no strict 'refs';
	return if *{$method}{CODE};
    }

    warn "Making $type hooks method $method\n" if $DEBUG;

    my $meth = "make_$type\_hooks";
    $self->$meth($table);
}

sub make_insert_hooks
{
    my $self = shift;

    my $code = '';
    $code .= "        return \$s->schema->run_in_transaction( sub {\n";
    $code .= "            my \$new;\n";
    $code .= "            \$s->pre_insert(\\\%p);\n" if $self->{table_class}->can('pre_insert');
    $code .= "            \$new = \$s->SUPER::insert(\%p);\n";
    $code .= "            \$s->post_insert({\%p, row => \$new});\n" if $self->{table_class}->can('post_insert');
    $code .= "            return \$new;\n";
    $code .= "        } );\n";

    eval <<"EOF";
{
    package $self->{table_class};
    sub insert
    {
        my \$s = shift;
        my \%p = \@_;

$code

    }
}
EOF

    Alzabo::Exception::Eval->throw( error => $@ ) if $@;
}

sub make_update_hooks
{
    my $self = shift;

    my $code = '';
    $code .= "        \$s->schema->run_in_transaction( sub {\n";
    $code .= "            \$s->pre_update(\\\%p);\n" if $self->{row_class}->can('pre_update');
    $code .= "            \$s->Alzabo::Runtime::CachedRow::update(\%p);\n";
    $code .= "            \$s->post_update(\\\%p);\n" if $self->{row_class}->can('post_update');

    $code .= "        } );\n";

    eval <<"EOF";
{
    package $self->{cached_row_class};
    sub update
    {
        my \$s = shift;
        my \%p = \@_;

$code

    }
}
EOF

    Alzabo::Exception::Eval->throw( error => $@ ) if $@;

    $code =~ s/CachedRow::/PotentialRow::/;

    eval <<"EOF";
{
    package $self->{potential_row_class};
    sub update
    {
        my \$s = shift;
        my \%p = \@_;

$code

    }
}
EOF

    Alzabo::Exception::Eval->throw( error => $@ ) if $@;

    $code =~ s/PotentialRow::/Row::/;

    eval <<"EOF";
{
    package $self->{uncached_row_class};
    sub update
    {
        my \$s = shift;
        my \%p = \@_;

$code

    }
}
EOF

    Alzabo::Exception::Eval->throw( error => $@ ) if $@;
}

sub make_select_hooks
{
    my $self = shift;

    my $pre = "            \$s->pre_select(\\\@cols);\n" if $self->{row_class}->can('pre_update');
    my $post = "            \$s->post_select(\\\%r);\n" if $self->{row_class}->can('post_update');

    foreach ( qw( cached_row_class uncached_row_class potential_row_class ) )
    {
	eval <<"EOF";
{
    package $self->{$_};
    sub select
    {
        my \$s = shift;
        my \@cols = \@_;

        return \$s->schema->run_in_transaction( sub {

$pre
            my \@r;
            my %r;

            if (wantarray)
            {
                \@r{ \@cols } = \$s->SUPER::select(\@cols);
            }
            else
            {
                \$r{ \$cols[0] } = (scalar \$s->SUPER::select(\$cols[0]));
            }
$post
            return wantarray ? \@r{\@cols} : \$r{ \$cols[0] };
        } );
    }

    sub select_hash
    {
        my \$s = shift;
        my \@cols = \@_;

        return \$s->schema->run_in_transaction( sub {

$pre

            my \%r = \$s->SUPER::select_hash(\@cols);

$post

            return \%r;
        } );
    }
}
EOF

	Alzabo::Exception::Eval->throw( error => $@ ) if $@;

    }
}

sub make_delete_hooks
{
    my $self = shift;

    my $code = '';
    $code .= "        \$s->schema->run_in_transaction( sub {\n";
    $code .= "            \$s->pre_delete(\\\%p);\n" if $self->{row_class}->can('pre_delete');
    $code .= "            \$s->Alzabo::Runtime::CachedRow::delete(\%p);\n";
    $code .= "            \$s->post_delete(\\\%p);\n" if $self->{row_class}->can('post_delete');
    $code .= "        } );\n";

    eval <<"EOF";
{
    package $self->{cached_row_class};
    sub delete
    {
        my \$s = shift;
        my \%p = \@_;

$code

    }
}
EOF

    Alzabo::Exception::Eval->throw( error => $@ ) if $@;

    $code =~ s/CachedRow::/Row::/;

    eval <<"EOF";
{
    package $self->{uncached_row_class};
    sub delete
    {
        my \$s = shift;
        my \%p = \@_;

$code

    }
}
EOF

    Alzabo::Exception::Eval->throw( error => $@ ) if $@;
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

    return join '_', map { lc $_->name } $p{foreign_key}->table_to, $p{column}
	if $p{type} eq 'lookup_columns';

    return $p{column}->name if $p{type} eq 'lookup_columns';

    return $p{parent} ? 'parent' : 'children'
	if $p{type} eq 'self_relation';

    # deprecated
    return (grep { ! $_->is_primary_key } $p{foreign_key}->table_to->columns)[0]->name
	if $p{type} eq 'lookup_table';

    die "unknown type in call to naming sub: $p{type}\n";
}

#
# Deprecated pieces
#

sub make_lookup_table_method
{
    my $self = shift;
    my $fk = shift;

    return unless $fk->table_to->primary_key == 1;

    my $name = $self->{opts}{name_maker}->( type => 'lookup_table',
					    foreign_key => $fk );
    return unless $name;
    return if $self->{uncached_row_class}->can($name) || $self->{cached_row_class}->can($name);

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

    Alzabo::Exception::Eval->throw( error => $@ ) if $@;
}

sub make_update_method
{
    my $self = shift;

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

    Alzabo::Exception::Eval->throw( error => $@ ) if $@;

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

    Alzabo::Exception::Eval->throw( error => $@ ) if $@;
}

1;


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
then the calling module's name is used as the root.  See L<New Class
Names|"New Class Names"> for more information.

=head3 all => $bool

This tells this module to make all of the methods it possibly can.
See L<METHOD CREATION OPTIONS|"METHOD CREATION OPTIONS"> for more
details.

If individual method creation options are set as false, then that
setting will be respected, so you could use

  use Alzabo::MethodMaker( schema => 'foo', all => 1, tables => 0 );

to turn on all of the regular options B<except> for C<tables>.

=head3 name_maker => \&naming_sub

If this option is given, then this callback will be called any time a
method name needs to be generated.  This allows you to have full
control over the resulting names.  Otherwise names are generated as
described in the documentation.

The callback is expected to return a name for the method to be used.
This name should not be fully qualified or contain any class
designation as this will be handled by MethodMaker.

It is important that none of the names returned conflict with existing
methods for the object the method is being added to.

For example, when adding methods that return column objects to a
table, if you have a column called 'name' and try to use that as the
method name, it won't work.  C<Alzabo::Table> objects already have
such a method, which returns the name of the table.  See the relevant
documentation of the schema, table, and row objects for a list of
methods they contain.

The L<Naming Sub Parameters|"NAMING SUB PARAMETERS"> section contains
the details of what parameters are passed to this callback.

=head1 EFFECTS

Using this module has several effects on your schema's objects.

=head2 New Class Names

Your schema, table, and row objects to be blessed into subclasses of
L<C<Alzabo::Runtime::Schema>|Alzabo::Runtime::Schema>,
L<C<Alzabo::Runtime::Table>|Alzabo::Runtime::Table>,
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row>, respectively.  These
subclasses contain the various methods created by this module.  The
new class names are formed by using the
L<C<class_root>|Alzabo::MethodMaker/PARAMETERS> parameter and adding
onto it.

=head3 Schema

C<E<lt>class rootE<gt>::Schema>

=head3 Tables

C<E<lt>class rootE<gt>::Table::<table nameE<gt>>

=head3 Rows

C<E<lt>class rootE<gt>::Row::<table nameE<gt>>, subclassed by
C<E<lt>class rootE<gt>::CachedRow::<table nameE<gt>>, C<E<lt>class
rootE<gt>::UncachedRow::<table nameE<gt>>, and C<E<lt>class
rootE<gt>::PotentialRow::<table nameE<gt>>

With a root of 'My::Stuff', and a schema with only two tables, 'Movie'
and 'Image', this would result in the following class names:

 My::Stuff::Schema
 My::Stuff::Table::Movie
 My::Stuff::Row::Movie
   My::Stuff::CachedRow::Movie
   My::Stuff::UncachedRow::Movie
   My::Stuff::PotentialRow::Movie
 My::Stuff::Table::Image
 My::Stuff::Row::Image
   My::Stuff::CachedRow::Image
   My::Stuff::UncachedRow::Image
   My::Stuff::PotentialRow::Image

=head2 Loading Classes

For each class into which an object is blessed, this module will
attempt to load that class via a C<use> statement.  If there is no
module found this will not cause an error.  If this class defines any
methods that have the same name as those this module generates, then
this module will not attempt to generate them.

=head1 METHOD CREATION OPTIONS

When using Alzabo::MethodMaker, you may specify any of the following
parameters.  Specifying 'all' causes all of them to be used.

=head2 Schema object methods

=head3 tables => $bool

Creates methods for the schema that return the table object matching
the name of the method.

For example, given a schema containing tables named 'Movie' and
'Image', this would create methods that could be called as
C<$schema-E<gt>Movie> and C<$schema-E<gt>Image>.

=head2 Table object methods.

=head3 table_columns => $bool

Creates methods for the tables that return the column object matching
the name of the method.  This is quite similar to the C<tables> option
for schemas.

=head3 insert_hooks => $bool

Look for hooks to wrap around the C<insert> method in
L<C<Alzabo::Runtime::Table>|Alzabo::Runtime::Table>.  See L<Loading
Classes> for more details.  You have to define either a C<pre_insert>
or C<post_insert> method (or both) for the generated table class or
this parameter will not do anything.  See the L<HOOK|/"HOOKS"> section
for more details.

=head2 Row object methods

=head3 row_column => $bool

This tells MethodMaker to create get/set methods for each column a row
has.  These methods take a single optional argument, which if given
will cause that column to be updated for the row.

=head3 update_hooks => $bool

Look for hooks to wrap around the C<update> method in
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row>.  See L<Loading
Classes> for more details.  You have to define either a C<pre_update>
or C<post_update> method (or both) for the generated row class or this
parameter will not do anything.  See the L<HOOK|/"HOOKS"> section for
more details.

=head3 select_hooks => $bool

Look for hooks to wrap around the C<select> method in
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row>.  See L<Loading
Classes> for more details.  You have to define either a C<pre_select>
or C<post_select> method (or both) for the generated row class or this
parameter will not do anything.  See the L<HOOK|/"HOOKS"> section for
more details.

=head3 delete_hooks => $bool

Look for hooks to wrap around the C<delete> method in
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row>.  See L<Loading
Classes> for more details.  You have to define either a C<pre_delete>
or C<post_delete> method (or both) for the generated row class or this
parameter will not do anything.  See the L<HOOK|/"HOOKS"> section for
more details.

=head3 foreign_keys => $bool

Creates methods in row objects named for the table to which the
relationship exists.  These methods return either a single
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> object or a single
L<C<Alzabo::Runtime::RowCursor>|Alzabo::Runtime::RowCursor> object,
depending on the cardinality of the relationship.

Take these tables as an example.

  Movie                     Credit
  ---------                 --------
  movie_id                  movie_id
  title                     person_id
                            role_name

NOTE: This option must be true if you want any of the following
options to be used.

=head3 linking_tables => $bool

A linking table, as defined here, is a table with a two column primary
key that, with each column being a foreign key to another table's
primary key.  These tables exist to facilitate n..n logical
relationships.  If both C<foreign_keys> and C<linking_tables> are
true, then methods will be created that skip the intermediate linking
tables

=head3 lookup_columns => $bool

Lookup columns are columns in foreign tables to which a table has a
many-to-one or one-to-one relationship to the foreign table's primary
key.  For example, given the tables below:

  Restaurant                    Cuisine
  ---------                     --------
  restaurant_id                 cuisine_id
  name              (n..1)      description
  phone                         spiciness
  cuisine_id

If we have a Restaurant row, we might want to have methods available
such as ->cuisine_description or ->cuisine_spiciness.

=head3 self_relations => $bool

A self relation is when a table has a parent/child relationship with
itself.  Here is an example:

 Location
 --------
 location_id
 name
 parent_location_id

NOTE: If the relationship has a cardinality of 1..1 then no methods
will be created, as this option is really intended for parent/child
relationships.  This may change in the future.

=head1 HOOKS

As was mentioned before, it is possible to create pre- and
post-execution hooks to wrap around a number of methods.  This allow
you to do data validation on inserts and updates as well as giving you
a chance to filter incoming our outgoing data as needed (for example,
if you need to convert dates to and from a specific RDBMS format).

All hooks are inside a transaction which is rolled back if any part of
the process fails.

It should be noted that Alzabo uses both the C<<
Alzabo::Runtime::Row->select >> and C<< Alzabo::Runtime::Row->delete
>> methods internally.  If their behavior is radically altered through
the use of hooks, then some of Alzabo's functionality may be broken.

Given this, it may be safer to create new methods to fetch and massage
data rather than to create post-select hooks that alter data.

Each of these hooks receives different parameters, documented below:

=head2 Insert Hooks

=over 4

=item * pre_insert

This method receives a hash reference of all the parameters that are
passed to the
L<C<Alzabo::Runtime::Table-E<gt>insert>|Alzabo::Runtime::Table/insert>
method.

These are the actual parameters that will be passed to the C<insert>
method so alterations to this reference will be seen by that method.
This allows you to alter the values that actually end up going into
the database or change any other parameters as you see fit.

=item * post_insert

This method also receives a hash reference containing all of the
parameters passed to the C<insert> method.  In addition, the hash
reference contains an additional key, C<row>, which contains the newly
created row.

=back

=head2 Update Hooks

=over 4

=item * pre_update

This method receives a hash reference of the parameters that will be
passed to the
L<C<Alzabo::Runtime::Row-E<gt>update>|Alzabo::Runtime::Row/update>
method.  Again, alterations to these parameters will be seen by the
C<update> method.

=item * post_update

This method receives the same parameters as C<pre_update>

=back

=head2 Select Hooks

=over 4

=item * pre_select

This method receives an array reference containing the names of the
requested columns.  This is called when either the
L<C<Alzabo::Runtime::Row-E<gt>select>|Alzabo::Runtime::Row/select> or
L<C<Alzabo::Runtime::Row-E<gt>select_hash>|Alzabo::Runtime::Row/select_hash>
methods are called.

=item * post_select

This method is called after the
L<C<Alzabo::Runtime::Row-E<gt>select>|Alzabo::Runtime::Row/select> or
L<C<Alzabo::Runtime::Row-E<gt>select_hash>|Alzabo::Runtime::Row/select_hash>
methods.  It receives a hash containing the name and values returned
from the revelant method, which it may modify.  If the values of this
hash reference are modified, then this will be seen by the original
caller.

=back

=head2 Delete hooks

=over 4

=item * pre_delete

This method receives no parameters.

=back

=head1 NAMING SUB PARAMETERS

The naming sub will receive a hash containing the following parameters:

=over 4

=item * type => $method_type

This will always be the same as one of the parameters you give to the
import method.  It will be one of the following: C<foreign_key>,
C<linking_table>, C<lookup_columns>, C<row_column>, C<self_relation>,
C<table>, C<table_column>.

=back

The following parameters vary from case to case, depending on the
value of C<type>.

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

When the type is C<foreign_key>, C<linking_table>, or
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

When the type is C<lookup_columns>:

=over 4

=item * column => Alzabo::Column object

When making lookup column methods, this column is the column in the
foreign table for which a method is being made.

=back

When the type is C<self_relation>:

=over 4

=item * parent => $boolean

This indicates whether or not the method being created will return
parent objects (true) or child objects (false).

=back

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

     # Lookup columns are columns if foreign tables for which there
     # exists a one-to-one or many-to-one relationship.  In cases such
     # as these, it is often the case that the foreign table is rarely
     # used on its own, but rather it primarily used as a lookup table
     # for values that should appear to be part of other tables.
     #
     # For example, an Address table might have a many-to-one
     # relationship with a State table.  The State table would contain
     # the columns 'name' and 'abbreviation'.  If we have
     # an Address table row, it is convenient to simply be able to say
     # $address->state_name and $address->state_abbreviation.

     if ( $p{type} eq 'lookup_columns' )
     {
         return join '_', map { lc $_->name } $p{foreign_key}->table_to, $p{column};
     }

     # This should be fairly self-explanatory.
     return $p{parent} ? 'parent' : 'children'
	 if $p{type} eq 'self_relation';

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
