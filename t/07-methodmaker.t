# This is just to test whether this stuff compiles.

use strict;

BEGIN
{
    unless (defined $ENV{ALZABO_RDBMS_TESTS})
    {
	print "1..0\n";
	exit;
    }
}

use Alzabo::Create;
use Alzabo::Runtime;

use Alzabo::ObjectCache( store => 'Alzabo::ObjectCache::Store::Memory',
			 sync  => 'Alzabo::ObjectCache::Sync::Null' );

require Alzabo::MethodMaker;

use lib '.', './t';

require 'base.pl';

my $tests = eval $ENV{ALZABO_RDBMS_TESTS};
die $@ if $@;

eval "use Test::More ( tests => 52 )";
die $@ if $@;

my $t = $tests->[0];
make_schema(%$t);

Alzabo::MethodMaker->import( schema => $t->{db_name},
			     all => 1,
			     class_root => 'Alzabo::MM::Test',
			     name_maker => \&namer,
			   );

my $s = Alzabo::Runtime::Schema->load_from_file( name => $t->{db_name} );

foreach my $t ($s->tables)
{
    my $t_meth = $t->name . '_t';
    ok( $s->can($t_meth),
	"Schema object should have $t_meth method" );

    is( $s->$t_meth(), $t,
	"Results of \$s->$t_meth() should be same as existing table object" );

    foreach my $c ($t->columns)
    {
	my $c_meth = $c->name . '_c';
	ok( $t->can($c_meth),
	    "Table object should have  $t_meth method" );

	is( $t->$c_meth(), $c,
	    "Results of \$t->$c_meth() should be same as existing column object" );
    }
}

{
    $s->set_user($t->{user}) if $t->{user};
    $s->set_password($t->{password}) if $t->{password};
    $s->set_host($t->{host}) if $t->{host};
    $s->set_referential_integrity(1);
    $s->connect;

    my $char = 'a';
    my $loc1 = $s->Location_t->insert( values => { location_id => 1,
						   location => $a++ } );
    $s->Location_t->insert( values => { location_id => 2,
					location => $a++,
					parent_location_id => 1 } );
    $s->Location_t->insert( values => { location_id => 3,
					location => $a++,
					parent_location_id => 1 } );
    $s->Location_t->insert( values => { location_id => 4,
					location => $a++,
					parent_location_id => 2 } );
    my $loc5 = $s->Location_t->insert( values => { location_id => 5,
						   location => $a++,
						   parent_location_id => 4 } );

    ok( ! defined $loc1->parent,
	"First location should not have a parent" );

    my @c = $loc1->children( order_by => { columns => $s->Location_t->location_id_c } ) ->all_rows;
    is( scalar @c, 2,
	"First location should have 2 children" );

    is( $c[0]->location_id, 2,
	"First child location id should be 2" );

    is( $c[1]->location_id, 3,
	"Second child location id should be 3" );

    is( $loc5->parent->location_id, 4,
	"Location 5's parent should be 4" );

    $loc1->location('Set method');
    is( $loc1->location, 'Set method',
	"Update location column via ->location method" );
}

{
    eval { $s->Location_t->insert( values => { location_id => 100,
					       location => 'die' } ) };
    my_isa_ok( $@, 'Alzabo::Exception',
	    "validate_insert should have thrown an Alzabo::Exception exception" );
    is( $@->error, 'TEST',
	"validate_insert error message should be TEST" );

    my $loc100 = $s->Location_t->insert( values => { location_id => 100,
						     location => 'a'} );
    eval { $loc100->update( location => 'die' ); };
    my_isa_ok( $@, 'Alzabo::Exception',
	    "validate_update should have thrown an Alzabo::Exception exception" );
    is( $@->error, 'TEST',
	"validate_update error message should be TEST" );

    $s->ToiletType_t->insert( values => { toilet_type_id => 1,
					  material => 'porcelain',
					  quality => 5 } );
    my $t = $s->Toilet_t->insert( values => { toilet_id => 1,
					      toilet_type_id => 1 } );

    is( $t->material, 'porcelain',
	"New toilet's material method should return 'porcelain'" );
    is( $t->quality, 5,
	"New toilet's quality method should return 5" );

    $s->ToiletLocation_t->insert( values => { toilet_id => 1,
					      location_id => 100 } );

    $s->ToiletLocation_t->insert( values => { toilet_id => 1,
					      location_id => 1 } );

    my @l = $t->Locations( order_by => $s->Location_t->location_id_c )->all_rows;

    is( scalar @l, 2,
	"The toilet should have two locations" );

    is( $l[0]->location_id, 1,
	"The first location id should be 1" );

    is( $l[1]->location_id, 100,
	"The second location id should be 2" );

    my @t = $l[0]->Toilets->all_rows;
    is( scalar @t, 1,
	"The location should have one toilet" );

    is( $t[0]->toilet_id, 1,
	"Location's toilet id should be 1" );

    my @tl = $t->ToiletLocations->all_rows;

    is( scalar @tl, 2,
	"The toilet should have two ToiletLocation rows" );

    is( $tl[0]->location_id, 1,
	"First row's location id should be 1" );
    is( $tl[0]->toilet_id, 1,
	"First row's toilet id should 1" );
    is( $tl[1]->location_id, 100,
 	"Second row's location id should be 100" );
    is( $tl[1]->toilet_id, 1,
	"Second row's toilet id should 1" );

    my $row = $s->Toilet_t->row_by_pk( pk => 1 );
    my_isa_ok( $row, 'Alzabo::MM::Test::CachedRow::Toilet',
	    "The Toilet object should be of the Alzabo::MM::Test::CachedRow::Toilet class" );

    $row = $s->Toilet_t->row_by_pk( pk => 1, no_cache => 1 );
    my_isa_ok( $row, 'Alzabo::MM::Test::UncachedRow::Toilet',
	    "The Toilet object should be of the Alzabo::MM::Test::UncachedRow::Toilet" );
}

sub make_schema
{
    my %r = ( mysql => 'MySQL',
	      pg => 'PostgreSQL',
	      oracle => 'Oracle',
	      sybase => 'Sybase',
	    );
    my %p = @_;
    my $s = Alzabo::Create::Schema->new( name => $p{db_name},
					 rdbms => $r{ delete $p{rdbms} },
				       );
    my $loc = $s->make_table( name => 'Location' );

    $loc->make_column( name => 'location_id',
		       type => 'int',
		       primary_key => 1 );
    $loc->make_column( name => 'parent_location_id',
		       type => 'int',
		       nullable => 1 );
    $loc->make_column( name => 'location',
		       type => 'varchar',
		       length => 50 );

    # self relation
    $s->add_relation( columns_from => $loc->column('parent_location_id'),
		      columns_to => $loc->column('location_id'),
		      cardinality => [ 1, 'n' ],
		      from_is_dependent => 0,
		      to_is_dependent => 0,
		    );

    my $toi = $s->make_table( name => 'Toilet' );

    $toi->make_column( name => 'toilet_id',
		       type => 'int',
		       primary_key => 1 );

    # linking table
    $s->add_relation( table_from => $toi,
		      table_to => $loc,
		      cardinality => [ 'n', 'n' ],
		      from_is_dependent => 0,
		      to_is_dependent => 0,
		    );

    my $tt = $s->make_table( name => 'ToiletType' );

    $tt->make_column( name => 'toilet_type_id',
		      type => 'int',
		      primary_key => 1 );
    $tt->make_column( name => 'material',
		      type => 'varchar',
		      length => 50 );
    $tt->make_column( name => 'quality',
		      type => 'int',
		      nullable => 1 );
    # lookup table
    $s->add_relation( table_from => $toi,
		      table_to => $tt,
		      cardinality => [ 'n', 1 ],
		      from_is_dependent => 0,
		      to_is_dependent => 0,
		    );

    $s->save_to_file;
    $s->create(%p);
}

sub namer
{
    my %p = @_;

    return $p{table}->name . '_t' if $p{type} eq 'table';

    return $p{column}->name . '_c' if $p{type} eq 'table_column';

    return $p{column}->name if $p{type} eq 'row_column';

    if ( $p{type} eq 'foreign_key' )
    {
	my $name = $p{foreign_key}->table_to->name;
	if ($p{plural})
	{
	    return my_PL( $name );
	}
	else
	{
	    return $name;
	}
    }

    if ( $p{type} eq 'linking_table' )
    {
	my $method = $p{foreign_key}->table_to->name;
	my $tname = $p{foreign_key}->table_from->name;
	$method =~ s/^$tname\_?//;
	$method =~ s/_?$tname$//;

	return my_PL($method);
    }

    return $p{column}->name if $p{type} eq 'lookup_columns';

    return $p{parent} ? 'parent' : 'children'
	if $p{type} eq 'self_relation';

    return $p{type} if grep { $p{type} eq $_ } qw( insert update );

    die "unknown type in call to naming sub: $p{type}\n";
}

sub my_PL
{
    return shift() . 's';
}

{
    package Alzabo::MM::Test::Table::Location;
    sub validate_insert
    {
	my $self = shift;
	my %p = @_;
	Alzabo::Exception->throw( error => "TEST" ) if $p{location} eq 'die';
    }
}

{
    package Alzabo::MM::Test::Row::Location;
    sub validate_update
    {
	my $self = shift;
	my %p = @_;
	Alzabo::Exception->throw( error => "TEST" ) if $p{location} eq 'die';
    }
}
