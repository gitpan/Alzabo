use strict;

use Alzabo::Create;
use Alzabo::Config;
use Cwd;

use lib '.', './t';

require 'base.pl';

my ($db, $tests);
if ( eval { require DBD::mysql } && ! $@ )
{
    $db = 'MySQL';
    $tests = 95;
}
elsif ( eval { require DBD::Pg } && ! $@ )
{
    $db = 'PostgreSQL';
    $tests = 93;
}
else
{
    print "1..0\n";
    exit;
}

my $cwd = Cwd::cwd();
mkdir "$cwd/schemas", 0755
    or die "Can't make dir '$cwd/schemas' for testing: $!\n";

print "1..$tests\n";

ok(1);

my $s = Alzabo::Create::Schema->new( name => 'foo',
				     rdbms => $db,
				   );

ok( $s && ref $s,
    "Unable to create schema object" );

ok( $s->name eq 'foo',
    "Schema name should be 'foo' but it's " . $s->name );

ok( ref $s->rules eq "Alzabo::RDBMSRules::$db",
    "Schema's rules should be in the 'Alzabo::RDBMSRules::$db' class but they're in the " . ref $s->rules . " class" );

ok( ref $s->driver eq "Alzabo::Driver::$db",
    "Schema's driver should be in the 'Alzabo::Driver::$db' class but they're in the " . ref $s->driver . " class" );

my $dir = Alzabo::Config->schema_dir;
{
    $s->save_to_file;

    my $base = "$dir/" . $s->name;
    my $name = $s->name;
    ok( -d $base,
        "'$base' should exist but it doesn't" );

    ok( -e "$base/$name.create.alz",
	"'$base/$name.create.alz' file should exist but it doesn't" );
    ok( -e "$base/$name.runtime.alz",
	"'$base/$name.runtime.alz' file should exist but it doesn't" );
    ok( -e "$base/$name.rdbms",
	"'$base/$name.rdbms' file should exist but it doesn't" );
}

eval { $s->make_table( name => 'footab' ); };
ok( ! $@,
    "Unable to make table 'footab': $@" );

my $t1;
eval { $t1 = $s->table('footab'); };
ok( ! $@ && $t1,
    "Unable to retrieve 'footab' from schema: $@" );

my $att = $db eq 'MySQL' ? 'unsigned' : 'check > 5';
eval { $t1->make_column( name => 'foo_pk',
			 type => 'int',
			 attributes => [ $att ],
			 sequenced => 1,
			 nullable => 0,
		       ); };
ok( ! $@,
    "Unable to make column 'foo_pk': $@" );

my $t1_c1;
eval { $t1_c1 = $t1->column('foo_pk'); };
ok( ! $@,
    "Unable to retrieve column 'foo_pk': $@" );
ok( defined $t1_c1,
    "\$t1->column('foo_pk') returned undefined value\n" );

ok( $t1_c1->type eq 'int',
    "foo_pk type should be 'int'" );
ok( $t1_c1->attributes == 1 && ($t1_c1->attributes)[0] eq $att,
    "foo_pk should have one attribute, '$att'" );
ok( $t1_c1->has_attribute( attribute => uc $att ),
    "foo_pk should have attribute '\U$att\E' (case-insensitive check)" );
ok( ! $t1_c1->has_attribute( attribute => uc $att, case_sensitive => 1 ),
    "foo_pk should _not_ have attribute '\U$att\E' (case-sensitive check)" );
ok( ! $t1_c1->nullable,
    "foo_pk should not be nullable" );

eval { $t1->add_primary_key($t1_c1); };
ok( ! $@,
    "Unable to make 'foo_pk' a primary key: $@" );

my $true;
eval { $true = $t1_c1->is_primary_key; };
ok( $true,
    "'foo_pk' should be a primary key: $@" );

eval { $s->make_table( name => 'bartab' ); };
ok( ! $@,
    "Unable to make table 'bartab': $@" );

my $t2;
eval { $t2 = $s->table('bartab'); };
ok( ! $@ && $t2,
    "Unable to retrieve table 'bartab': $@" );

eval { $t2->make_column( name => 'bar_pk',
			 type => 'int',
			 default => 10,
			 sequenced => 1,
			 nullable => 0,
		       ); };
ok( ! $@,
    "Unable to make column bar_pk: $@" );

my $t2_c1;
eval { $t2_c1 = $t2->column('bar_pk'); };
ok( ! $@ && $t2_c1,
    "Unable to retrieve column 'bar_pk': $@" );

ok( $t2_c1->default eq '10',
    "bar_pk default should be '10'" );

eval { $t2->add_primary_key($t2_c1); };
ok( ! $@,
    "Unable to make bar_pk a primary key: $@" );

eval { $s->add_relation( table_from => $t1,
			 table_to   => $t2,
			 min_max_from => ['1', 'n'],
			 min_max_to   => ['0', 'n'] ) };
ok( ! $@,
    "Unable to add a relation from footab to bartab: $@" );

my $link;
eval { $link = $s->table('footab_bartab'); };
ok( ! $@ && $link,
    "No linking table was created: $@" );

my @t1_fk;
eval { @t1_fk = $t1->foreign_keys( table => $link,
				   column => $t1_c1 ); };
ok( ! $@ && defined $t1_fk[0],
    "footab has no foreign keys to the footab_bartab table: $@" );

ok( $t1_fk[0]->columns_from->name, 'foo_pk',
    "The foreign key from footab to the footab_bartab table's columns_from value should be 'foo_pk'" );
ok( $t1_fk[0]->columns_from->table->name, 'footab',
    "The foreign key columns_from for the footab table does not belong to the footab table" );
ok( $t1_fk[0]->columns_to->name, 'foo_pk',
    "The foreign key from footab to the footab_bartab table's columns_to value should be 'foo_pk'" );
ok( $t1_fk[0]->columns_to->table->name, 'footab_bartab',
    "The foreign key columns_to for the footab table does not belong to the footab_bartab table" );
ok( $t1_fk[0]->table_from->name, 'footab',
    "The table_from for the foreign key should be footab" );
ok( $t1_fk[0]->table_to->name, 'footab_bartab',
    "The table_to for the foreign key should be footab_bartab" );

my @t2_fk;
eval { @t2_fk = $t2->foreign_keys( table => $link,
				   column => $t2_c1 ); };

ok( ! $@ && $t2_fk[0],
    "bartab has no foreign keys to the footab_bartab table: $@" );

ok( $t2_fk[0]->columns_from->name, 'foo_pk',
    "The foreign key from bartab to the  table's columns_from value should be 'foo_pk'" );
ok( $t2_fk[0]->columns_from->table->name, 'bartab',
    "The foreign key columns_from for the bartab table does not belong to the bartab table" );
ok( $t2_fk[0]->columns_to->name, 'foo_pk',
    "The foreign key from bartab to the linking table's columns_to value should be 'foo_pk'" );
ok( $t2_fk[0]->columns_to->table->name, 'footab_bartab',
    "The foreign key columns_to for the bartab table does not belong to the footab_bartab table" );
ok( $t2_fk[0]->table_from->name, 'bartab',
    "The table_from for the foreign key should be bartab" );
ok( $t2_fk[0]->table_to->name, 'footab_bartab',
    "The table_to for the foreign key should be footab_bartab" );

my @link_fk;
eval { @link_fk = $link->foreign_keys( table => $t1,
				       column => $link->column('foo_pk') ); };

ok( ! $@ && $link_fk[0],
    "footab_bartab has no foreign keys to the footab table: $@" );

ok( $link_fk[0]->columns_from->name, 'foo_pk',
    "The foreign key from footab_bartab to the table's columns_from value should be 'foo_pk'" );
ok( $link_fk[0]->columns_from->table->name, 'footab_bartab',
    "The foreign key columns_from for the footab_bartab table does not belong to the footab_bartab table" );
ok( $link_fk[0]->columns_to->name, 'foo_pk',
    "The foreign key from footab_bartab to the linking table's columns_to value should be 'foo_pk'" );
ok( $link_fk[0]->columns_to->table->name, 'footab',
    "The foreign key columns_to for the footab_bartab table does not belong to the footab table" );
ok( $link_fk[0]->table_from->name, 'footab_bartab',
    "The table_from for the foreign key should be footab_bartab" );
ok( $link_fk[0]->table_to->name, 'footab',
    "The table_to for the foreign key should be footab" );

eval { @link_fk = $link->foreign_keys( table => $t2,
				       column => $link->column('bar_pk') ); };

ok( ! $@ && $link_fk[0],
    "footab_bartab has no foreign keys to the bartab table: $@" );

ok( $link_fk[0]->columns_from->name, 'foo_pk',
    "The foreign key from footab_bartab to the table's columns_from value should be 'foo_pk'" );
ok( $link_fk[0]->columns_from->table->name, 'footab_bartab',
    "The foreign key columns_from for the footab_bartab table does not belong to the footab_bartab table" );
ok( $link_fk[0]->columns_to->name, 'foo_pk',
    "The foreign key from footab_bartab to the linking table's columns_to value should be 'foo_pk'" );
ok( $link_fk[0]->columns_to->table->name, 'bartab',
    "The foreign key columns_to for the footab_bartab table does not belong to the bartab table" );
ok( $link_fk[0]->table_from->name, 'footab_bartab',
    "The table_from for the foreign key should be footab_bartab" );
ok( $link_fk[0]->table_to->name, 'bartab',
    "The table_to for the foreign key should be bartab" );


eval { $s->add_relation( table_from => $t1,
			 table_to => $t2,
			 min_max_from => [ '0', '1' ],
			 min_max_to => [ '0', 'n' ]
		       ); };

ok( ! $@,
    "Unable to create relation from footab to bartab: $@" );

my $new_col;
eval { $new_col = $t1->column('bar_pk'); };
ok( ! $@ && $new_col,
    "Unable to retrieve 'bar_pk' column from footab: $!" );

ok( $new_col->definition eq $t2->column('bar_pk')->definition,
    "bar_pk columns in footab and bartab should share the same definition object" );

my @fk;
eval { @fk = $t1->foreign_keys( table => $t2,
				column => $new_col ); };
ok( @fk && scalar @fk == 1,
    "footab has no foreign key to bartab from bar_pk (or has more than one)" );

eval { @fk = $t2->foreign_keys( table => $t1,
				column => $t2->column('bar_pk') ); };
ok( @fk && scalar @fk == 1,
    "bartab has no foreign key to footab from bar_pk (or has more than one)" );

eval { $s->add_relation( table_from => $t1,
			 table_to => $t2,
			 min_max_from => [ '0', 'n' ],
			 min_max_to => [ '0', '1' ]
		       ); };

ok( ! $@,
    "Unable to create second relation from footab to bartab: $@" );

eval { $new_col = $t2->column('foo_pk'); };
ok( ! $@ && $new_col,
    "Unable to retrieve 'foo_pk' column from bartab: $!" );

ok( $new_col->definition eq $t1->column('foo_pk')->definition,
    "foo_pk columns in footab and bartab should share the same definition object" );

eval { @fk = $t2->foreign_keys( table => $t1,
				column => $new_col ); };
ok( @fk && scalar @fk == 1,
    "bartab has no foreign keys to footab from foo_pk (or has more than one)" );

eval { @fk = $t1->foreign_keys( table => $t2,
				column => $t1->column('foo_pk') ); };
ok( @fk && scalar @fk == 1,
    "footab has no foreign keys to bartab from foo_pk (or has more than one)" );

eval { $s->save_to_file };
ok( ! $@,
    "Unable to save the schema to a file: $@" );

$s->make_table( name => 'baztab' );
my $t3 = $s->table('baztab');

eval { $s->add_relation( table_from => $t1,
			 table_to => $t3,
			 min_max_from => [ '0', 'n' ],
			 min_max_to => [ '0', '1' ]
		       ); };

ok( ! $@,
    "Unable to create relation from footab to baztab: $@" );

eval { $new_col = $t3->column('foo_pk'); };
ok( ! $@ && $new_col,
    "Unable to retrieve 'foo_pk' column from baztab: $!" );

ok( $new_col->definition eq $t1->column('foo_pk')->definition,
    "foo_pk columns in footab and baztab should share the same definition object" );

eval { @fk = $t3->foreign_keys( table => $t1,
				column => $new_col ); };
ok( @fk && scalar @fk == 1,
    "baztab has no foreign keys to footab from foo_pk (or has more than one)" );

eval { @fk = $t1->foreign_keys( table => $t3,
				column => $t1->column('foo_pk') ); };
ok( @fk && scalar @fk == 1,
    "footab has no foreign keys to baztab from foo_pk (or has more than one)" );

eval { $s->delete_table($link) };

ok( ! $@,
    "Unable to delete footab_bartab table: $@" );

@fk = $t1->all_foreign_keys;
ok( @fk == 3,
    "footab table should have 3 foreign key after deleting footab_bartab table but it has", scalar @fk );

@fk = $t2->all_foreign_keys;
ok( @fk == 2,
    "bartab table should have 2 foreign keys after deleting footab_bartab table but it has", scalar @fk );

$s->delete_table($t1);

@fk = $t3->all_foreign_keys;
ok( @fk == 0,
    "baztab table should have 0 foreign keys after deleting footab table but it has", scalar @fk );

ok( ! exists $t2->{fk}{footab},
    "The $t2 object's internal {fk} hash should not have a {footab} entry" );

my $tc = $s->make_table( name => 'two_col_pk' );
$tc->make_column( name => 'pk1',
		  type => 'int',
		  primary_key => 1 );

$tc->make_column( name => 'pk2',
		  type => 'int',
		  primary_key => 1 );

my @pk = $tc->primary_key;
ok( @pk == 2 && $pk[0]->name eq 'pk1' && $pk[1]->name eq 'pk2',
    "Attempting to add two columns as primary keys failed" );

$tc->make_column( name => 'non_pk',
		  type => 'varchar',
		  length => 2 );

my $other = $s->make_table( name => 'other' );
$other->make_column( name => 'other_pk',
		     type => 'int',
		     primary_key => 1 );
$other->make_column( name => 'somethin',
		     type => 'text' );

eval { $s->add_relation( table_from => $tc,
			 table_to   => $other,
			 min_max_from => [ 0, 'n' ],
			 min_max_to   => [ 0, 1 ],
		       ); };

ok( ! $@,
    "Unable to make a relation from two_col_pk to other: $@" );

my @cols;
eval { @cols = $other->columns( 'pk1', 'pk2' ) };
ok( ! $@,
    "Unable to retrieve 'pk1' and 'pk2' columns from other: $@" );

ok( @cols == 2 && $cols[0]->name eq 'pk1' && $cols[1]->name eq 'pk2',
    "Attempting to retrieve 'pk1' and 'pk2' columns from other returned", scalar @cols, "columns:",
    join ', ', map { $_->name } @cols );

my $fk;
eval { $fk = $other->foreign_keys( table => $tc,
				   column => $tc->column('pk1') ); };
ok( ! $@,
    "Unable to retrieve foreign key from 'other' to 'two_col_pk' on column 'pk1': $@" );

@cols = $fk->columns_from;
ok( @cols == 2 && $cols[0]->name eq 'pk1' && $cols[1]->name eq 'pk2' &&
    $cols[0]->table->name eq 'other' && $cols[1]->table->name eq 'other',
    "columns_from foreign key returned:",
    join ', ', map { join '.', $_->table->name, $_->name } @cols );

@cols = $fk->columns_to;
ok( @cols == 2 && $cols[0]->name eq 'pk1' && $cols[1]->name eq 'pk2' &&
    $cols[0]->table->name eq 'two_col_pk' && $cols[1]->table->name eq 'two_col_pk',
    "columns_to foreign key returned:",
    join ', ', map { join '.', $_->table->name, $_->name } @cols );

my @pairs = $fk->column_pairs;
ok( @pairs == 2 &&
    $pairs[0]->[0]->table->name eq 'other' &&
    $pairs[0]->[1]->table->name eq 'two_col_pk' &&
    $pairs[1]->[0]->table->name eq 'other' &&
    $pairs[1]->[1]->table->name eq 'two_col_pk' &&
    $pairs[0]->[0]->name eq 'pk1' &&
    $pairs[0]->[0]->name eq 'pk1' &&
    $pairs[1]->[0]->name eq 'pk2' &&
    $pairs[1]->[1]->name eq 'pk2',
    "Column pairs returned:\n" .
    join "\n", ( map { join ', ', ( $_->[0]->table->name . '.' . $_->[0]->name,
				    $_->[1]->table->name . '.' . $_->[1]->name ) }
		 @pairs
	       ),
  );

my $tbi = $t1->make_column( name => 'tbi',
			    type => 'int',
			    nullable => 0 );

my $index;
eval { $index = $t1->make_index( columns => [ { column => $tbi } ] ) };
ok( ! $@,
    "Unable to add an index to 't1' on 'tbi': $@" );

eval { $t1->set_name('newt1'); };
ok( ! $@,
    "Unable to change table name from 't1' to 'newt1': $@" );

my $index2;
eval { $index2 = $t1->index($index->id); };
ok( ! $@,
    "Unable to retrieve index ", $index->id, " from 'newt1': $@" );

ok( $index eq $index2,
    "The index retrieved from newt1 should be the same as the one first made but it is not");

$t1->column('foo_pk')->set_type('varchar');
if ($db eq 'MySQL')
{
    ok( ! $t1->column('foo_pk')->attributes,
	"The unsigned attribute should not have survived the change from 'int' to 'varchar'" );
}

if ($db eq 'MySQL')
{
    eval { $t1->column('foo_pk')->set_type('text'); };
    ok( $@,
	"Attempting to set a primary key column to the 'text' type should cause an error" );
}

$tbi->set_type('varchar');
$tbi->set_length( length => 20 );
$tbi->set_type('text');

ok( ! defined $tbi->length,
    "Length should be undef after switching column type from 'varchar' to 'text'" );

$tbi->set_type('varchar');
$tbi->set_length( length => 20 );
$tbi->set_type('char');
ok( $tbi->length == 20,
    "Length should remain the same after switching column type from 'varchar' to 'char'" );

eval { $s->save_to_file };
ok( ! $@,
    "Unable to save the schema to a file: $@" );
