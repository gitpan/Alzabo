use strict;

use Alzabo::Create;
use Alzabo::Config;
use Cwd;

my $count = 0;
$| = 1;
print "1..77\n";

ok(1);

my $s = Alzabo::Create::Schema->new( name => 'foo',
				     rules => 'MySQL',
				     driver => 'MySQL' );

ok( $s && ref $s,
    "Unable to create schema object" );

ok( $s->name, 'foo',
    "Schema name should be 'foo' but it's " . $s->name );

ok( ref $s->rules, 'Alzabo::RDBMSRules::MySQL',
    "Schema's rules should be in the 'Alzabo::RDBMSRules::MySQL' class but they're in the " . ref $s->rules . " class" );

ok( ref $s->driver, 'Alzabo::Driver::MySQL',
    "Schema's driver should be in the 'Alzabo::Driver::MySQL' class but they're in the " . ref $s->driver . " class" );

my $cwd = Cwd::cwd;
$Alzabo::Config::CONFIG{root_dir} = $cwd;
mkdir "$cwd/schemas", 0755
    or die "Can't make dir '$cwd/schemas' for testing: $!\n";

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
    ok( -e "$base/$name.rules",
	"'$base/$name.rules' file should exist but it doesn't" );
    ok( -e "$base/$name.driver",
	"'$base/$name.driver' file should exist but it doesn't" );
}

eval { $s->make_table( name => 'footab' ); };
ok( ! $@,
    "Unable to make table 'footab': $@" );

my $t1;
eval { $t1 = $s->table('footab'); };
ok( ! $@ && $t1,
    "Unable to retrieve 'footab' from schema: $@" );

eval { $t1->make_column( name => 'foo_pk',
			 type => 'int',
			 attributes => [ 'default 10' ],
			 sequenced => 1,
			 null => 0 ); };
ok( ! $@,
    "Unable to make column 'foo_pk': $@" );

my $t1_c1;
eval { $t1_c1 = $t1->column('foo_pk'); };
ok( (! $@) && defined $t1_c1,
    "Unable to retrieve column 'foo_pk': $@" );

ok( $t1_c1->type eq 'int',
    "foo_pk type should be 'int'" );
ok( $t1_c1->attributes == 1 && ($t1_c1->attributes)[0], 'default 10',
    "foo_pk should have one attribute, 'default 10'" );
ok( ! $t1_c1->null,
    "foo_pk should not be NULLable" );

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
			 attributes => [ 'default 10' ],
			 sequenced => 1,
			 null => 0 ); };
ok( ! $@,
    "Unable to make column bar_pk: $@" );

my $t2_c1;
eval { $t2_c1 = $t2->column('bar_pk'); };
ok( ! $@ && $t2_c1,
    "Unable to retrieve column 'bar_pk': $@" );

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
ok( ! $@ && $t1_fk[0],
    "footab has no foreign keys to the footab_bartab table: $@" );

ok( $t1_fk[0]->column_from->name, 'foo_pk',
    "The foreign key from footab to the footab_bartab table's column_from value should be 'foo_pk'" );
ok( $t1_fk[0]->column_from->table->name, 'footab',
    "The foreign key column_from for the footab table does not belong to the footab table" );
ok( $t1_fk[0]->column_to->name, 'foo_pk',
    "The foreign key from footab to the footab_bartab table's column_to value should be 'foo_pk'" );
ok( $t1_fk[0]->column_to->table->name, 'footab_bartab',
    "The foreign key column_to for the footab table does not belong to the footab_bartab table" );
ok( $t1_fk[0]->table_from->name, 'footab',
    "The table_from for the foreign key should be footab" );
ok( $t1_fk[0]->table_to->name, 'footab_bartab',
    "The table_to for the foreign key should be footab_bartab" );

my @t2_fk;
eval { @t2_fk = $t2->foreign_keys( table => $link,
				   column => $t2_c1 ); };

ok( ! $@ && $t2_fk[0],
    "bartab has no foreign keys to the footab_bartab table: $@" );

ok( $t2_fk[0]->column_from->name, 'foo_pk',
    "The foreign key from bartab to the  table's column_from value should be 'foo_pk'" );
ok( $t2_fk[0]->column_from->table->name, 'bartab',
    "The foreign key column_from for the bartab table does not belong to the bartab table" );
ok( $t2_fk[0]->column_to->name, 'foo_pk',
    "The foreign key from bartab to the linking table's column_to value should be 'foo_pk'" );
ok( $t2_fk[0]->column_to->table->name, 'footab_bartab',
    "The foreign key column_to for the bartab table does not belong to the footab_bartab table" );
ok( $t2_fk[0]->table_from->name, 'bartab',
    "The table_from for the foreign key should be bartab" );
ok( $t2_fk[0]->table_to->name, 'footab_bartab',
    "The table_to for the foreign key should be footab_bartab" );

my @link_fk;
eval { @link_fk = $link->foreign_keys( table => $t1,
				       column => $link->column('foo_pk') ); };

ok( ! $@ && $link_fk[0],
    "footab_bartab has no foreign keys to the footab table: $@" );

ok( $link_fk[0]->column_from->name, 'foo_pk',
    "The foreign key from footab_bartab to the table's column_from value should be 'foo_pk'" );
ok( $link_fk[0]->column_from->table->name, 'footab_bartab',
    "The foreign key column_from for the footab_bartab table does not belong to the footab_bartab table" );
ok( $link_fk[0]->column_to->name, 'foo_pk',
    "The foreign key from footab_bartab to the linking table's column_to value should be 'foo_pk'" );
ok( $link_fk[0]->column_to->table->name, 'footab',
    "The foreign key column_to for the footab_bartab table does not belong to the footab table" );
ok( $link_fk[0]->table_from->name, 'footab_bartab',
    "The table_from for the foreign key should be footab_bartab" );
ok( $link_fk[0]->table_to->name, 'footab',
    "The table_to for the foreign key should be footab" );

eval { @link_fk = $link->foreign_keys( table => $t2,
				       column => $link->column('bar_pk') ); };

ok( ! $@ && $link_fk[0],
    "footab_bartab has no foreign keys to the bartab table: $@" );

ok( $link_fk[0]->column_from->name, 'foo_pk',
    "The foreign key from footab_bartab to the table's column_from value should be 'foo_pk'" );
ok( $link_fk[0]->column_from->table->name, 'footab_bartab',
    "The foreign key column_from for the footab_bartab table does not belong to the footab_bartab table" );
ok( $link_fk[0]->column_to->name, 'foo_pk',
    "The foreign key from footab_bartab to the linking table's column_to value should be 'foo_pk'" );
ok( $link_fk[0]->column_to->table->name, 'bartab',
    "The foreign key column_to for the footab_bartab table does not belong to the bartab table" );
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

eval { $s->save_to_file };
ok( ! $@,
    "Unable to save the schema to a file: $@" );

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

$s->make_table( name => 'baz' );
my $t3 = $s->table('baz');

eval { $s->add_relation( table_from => $t1,
			 table_to => $t3,
			 min_max_from => [ '0', 'n' ],
			 min_max_to => [ '0', '1' ]
		       ); };

ok( ! $@,
    "Unable to create second relation from footab to bartab: $@" );

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
    "baz table should have 0 foreign keys after deleting footab table but it has", scalar @fk );

ok( ! exists $t2->{fk}{footab},
    "The $t2 object's internal {fk} hash should not have a {footab} entry" );

eval { $s->save_to_file };
ok( ! $@,
    "Unable to save the schema to a file: $@" );

sub ok
{
    my $ok = !!shift;
    print $ok ? 'ok ': 'not ok ';
    print ++$count, "\n";
    print "@_\n" if ! $ok;
}
