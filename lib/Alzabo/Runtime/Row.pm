package Alzabo::Runtime::Row;

use strict;
use vars qw($VERSION);

use Alzabo;

use Alzabo::Exceptions ( abbr => [ qw( logic_exception no_such_row_exception
                                       params_exception storable_exception ) ] );

use Alzabo::Runtime;
use Alzabo::Runtime::RowState::Deleted;
use Alzabo::Runtime::RowState::Live;
use Alzabo::Runtime::RowState::Potential;

use Params::Validate qw( validate UNDEF SCALAR HASHREF );
Params::Validate::validation_options
    ( on_fail => sub { params_exception join '', @_ } );

use Storable ();

$VERSION = 2.0;

BEGIN
{
    no strict 'refs';
    foreach my $meth ( qw( select select_hash update refresh delete
                           id_as_string is_live is_deleted ) )
    {
        *{ __PACKAGE__ . "::$meth" } =
            sub { my $s = shift;
                  $s->{state}->$meth( $s, @_ ) };
    }
}

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    my %p =
        validate( @_,
                  { table => { isa => 'Alzabo::Runtime::Table' },
                    pk    => { type => SCALAR | HASHREF,
                               optional => 1,
                             },
                    prefetch => { type => UNDEF | HASHREF,
                                  optional => 1,
                                },
                    state => { type => SCALAR,
                               default => 'Alzabo::Runtime::RowState::Live',
                             },
                    potential_row => { isa => 'Alzabo::Runtime::Row',
                                       optional => 1,
                                     },
                    values => { type => HASHREF,
                                default => {},
                              }
                  }
                );

    my $self = $p{potential_row} ? $p{potential_row} : {};

    bless $self, $class;

    $self->{table} = $p{table};
    $self->{state} = $p{state};

    $self->{state}->_init($self, @_) or return;

    return $self;
}

sub table
{
    my $self = shift;

    return $self->{table};
}

sub schema
{
    my $self = shift;

    return $self->table->schema;
}

sub set_state { $_[0]->{state} = $_[1] };

sub rows_by_foreign_key
{
    my $self = shift;

    my %p = @_;

    my $fk = delete $p{foreign_key};

    if ($p{where})
    {
	$p{where} = [ $p{where} ] unless UNIVERSAL::isa( $p{where}[0], 'ARRAY' );
    }

    push @{ $p{where} },
	map { [ $_->[1], '=', $self->select( $_->[0]->name ) ] } $fk->column_pairs;

    # if the relationship is not 1..n, then only one row can be
    # returned (or referential integrity has been hosed in the
    # database).
    return $fk->is_one_to_many ? $fk->table_to->rows_where(%p) : $fk->table_to->one_row(%p);
}

# class method
sub id_as_string_ext
{
    my $class = shift;
    my %p = @_;
    my $id_hash = $class->_make_id_hash(%p);

    local $^W; # weirdly, enough there are code paths that can
    # lead here that'd lead to $id_hash having some
    # values that are undef
    return join ';:;_;:;', ( $p{table}->schema->name,
                             $p{table}->name,
                             map { $_, $id_hash->{$_} } sort keys %$id_hash );
}

sub _make_id_hash
{
    my $self = shift;
    my %p = @_;

    return $p{pk} if ref $p{pk};

    return { ($p{table}->primary_key)[0]->name => $p{pk} };
}

sub _update_pk_hash
{
    my $self = shift;

    my @pk = keys %{ $self->{pk} };

    @{ $self->{pk} }{ @pk } = @{ $self->{data} }{ @pk };

    delete $self->{id_string};
}

sub make_live
{
    my $self = shift;

    logic_exception "Can only call make_live on potential rows"
	unless $self->{state}->is_potential;

    my %p = @_;

    my %values;
    foreach ( $self->table->columns )
    {
	next unless exists $p{values}->{ $_->name } || exists $self->{data}->{ $_->name };
	$values{ $_->name } = ( exists $p{values}->{ $_->name } ?
				$p{values}->{ $_->name } :
				$self->{data}->{ $_->name } );
    }

    my $table = $self->table;
    delete @{ $self }{keys %$self}; # clear out everything

    $table->insert( @_,
		    potential_row => $self,
		    %values ? ( values => \%values ) : (),
		  );
}

sub _no_such_row_error
{
    my $self = shift;

    my $err = 'Unable to find a row in ' . $self->table->name . ' where ';
    my @vals;
    while ( my( $k, $v ) = each %{ $self->{pk} } )
    {
	$v = '<NULL>' unless defined $v;
	my $val = "$k = $v";
	push @vals, $val;
    }
    $err .= join ', ', @vals;

    no_such_row_exception $err;
}

sub STORABLE_freeze
{
    my $self = shift;
    my $cloning = shift;

    my %data = %$self;

    my $table = delete $data{table};

    $data{schema} = $table->schema->name;
    $data{table_name} = $table->name;

    my $ser = eval { Storable::nfreeze(\%data) };

    storable_exception $@ if $@;

    return $ser;
}

sub STORABLE_thaw
{
    my ( $self, $cloning, $ser ) = @_;

    my $data = eval { Storable::thaw($ser) };

    storable_exception $@ if $@;

    %$self = %$data;

    my $s = Alzabo::Runtime::Schema->load_from_file( name => delete $self->{schema} );
    $self->{table} = $s->table( delete $self->{table_name} );

    # If the caching system is loaded we want to return the existing
    # reference, not a copy.
    #
    # Requires a patched Storable (at least for now)
    if ( Alzabo::Runtime::UniqueRowCache->can('row_in_cache') )
    {
	if ( my $row =
	     Alzabo::Runtime::UniqueRowCache->row_in_cache
	         ( $self->table->name, $self->id_as_string ) )
	{
            $_[0] = $row;
	}
    }
}

BEGIN
{
    # dumb hack to fix bugs in Storable 2.00 - 2.03 w/ a non-threaded
    # Perl
    #
    # Basically, Storable somehow screws up the hooks business the
    # _first_ time an object from a class with hooks is stored.  So
    # we'll just _force_ it do it once right away.
    if ( $Storable::VERSION >= 2 && $Storable::VERSION <= 2.03 )
    {
	eval <<'EOF';
	{ package ___name; sub name { 'foo' } }
	{ package ___table;  @table::ISA = '___name'; sub schema { bless {}, '___name' } }
	my $row = bless { table => bless {}, '___table' }, __PACKAGE__;
	Storable::thaw(Storable::nfreeze($row));
EOF
    }
}


1;

__END__

=head1 NAME

Alzabo::Runtime::Row - Row objects

=head1 SYNOPSIS

  use Alzabo::Runtime::Row;

=head1 DESCRIPTION

These objects represent actual rows from the database containing
actual data.  In general, you will want to use the
L<C<Alzabo::Runtime::Table>|Alzabo::Runtime::Table> object to retrieve
rows.  The L<C<Alzabo::Runtime::Table>|Alzabo::Runtime::Table> object
can return either single rows or L<row
cursors|Alzabo::Runtime::RowCursor>.

=head1 METHODS

=head2 select (@list_of_column_names)

=head3 Returns

Returns a list of values matching the specified columns in a list
context.  In scalar context it returns only a single value (the first
column specified).

If no columns are specified, it will return the values for all of the
columns in the table, in the order that are returned by
L<C<Alzabo::Runtime::Table-E<gt>columns>|Alzabo::Runtime::Table/columns>.

=head2 select_hash (@list_of_column_names)

=head3 Returns

Returns a hash of column names to values matching the specified
columns.

If no columns are specified, it will return the values for all of the
columns in the table.

=head2 update (%hash_of_columns_and_values)

Given a hash of columns and values, attempts to update the database to
and the object to represent these new values.

=head2 delete

Deletes the row from the RDBMS.

=head2 id_as_string

Returns the row's id value as a string.  This can be passed to the
L<C<Alzabo::Runtime::Table-E<gt>row_by_id>|Alzabo::Runtime::Table/row_by_id>
method to recreate the row later.

=head2 is_live

Indicates whether or not the given row is a real or potential row.

=head2 table

Returns the L<C<Alzabo::Runtime::Table>|Alzabo::Runtime::Table> object
that this row belongs to.

=head2 schema

Returns the L<C<Alzabo::Runtime::Schema>|Alzabo::Runtime::Schema>
object that this row's table belongs to.  This is a shortcut for C<<
$row->table->schema >>.

=head2 rows_by_foreign_key

=head3 Parameters

=over 4

=item * foreign_key => C<Alzabo::Runtime::ForeignKey> object

=back

Given a foreign key object, this method returns either an
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> object or an
L<C<Alzabo::Runtime::RowCursor>|Alzabo::Runtime::RowCursor> object for
the row(s) in the table that to which the relationship exists, based
on the value of the relevant column(s) in the current row.

The type of object returned is based on the cardinality of the
relationship.  If the relationship says that there could only be one
matching row, then a row object is returned, otherwise it returns a
cursor.

All other parameters given will be passed directly to the
L<C<new>|new> method.

=head2 new

=head3 Parameters

=over 4

=item * table => C<Alzabo::Runtime::Table> object

=item * pk => (see below)

The C<pk> parameter may be one of two things.  If the table has only a
single column primary key, it can be a simple scalar with the value of
that primary key for this row.

If the primary key is more than one column than it must be a hash
reference containing column names and values such as:

  { pk_column1 => 1,
    pk_column2 => 'foo' }

=back

=head3 Returns

A new C<Alzabo::Runtime::Row> object.  If no object matches these
values then an exception will be thrown.

=head3 Throws

L<C<Alzabo::Exception::NoSuchRow>|Alzabo::Exceptions>

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
