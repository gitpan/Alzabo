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

require Alzabo::MethodMaker;

require 'base.pl';

my $tests = eval $ENV{ALZABO_RDBMS_TESTS};
die $@ if $@;

eval "use Test::More ( tests => 79 )";
die $@ if $@;

my $t = $tests->[0];
make_schema(%$t);

Alzabo::MethodMaker->import( schema => $t->{schema_name},
			     all => 1,
			     class_root => 'Alzabo::MM::Test',
			     name_maker => \&namer,
			   );

my $s = Alzabo::Runtime::Schema->load_from_file( name => $t->{schema_name} );

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
    $s->set_port($t->{port}) if $t->{port};
    $s->set_referential_integrity(1);
    $s->connect;

    # needed for Pg!
    $s->set_quote_identifiers(1);

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
    eval { $s->Location_t->insert( values => { location_id => 666,
					       location => 'pre_die' } ) };
    my $e = $@;
    isa_ok( $e, 'Alzabo::Exception',
	    "Exception thrown from pre_insert" );
    is( $e->error, 'PRE INSERT TEST',
	"pre_insert error message should be PRE INSERT TEST" );

    eval { $s->Location_t->insert( values => { location_id => 666,
					       location => 'post_die' } ) };
    $e = $@;
    isa_ok( $e, 'Alzabo::Exception',
	    "Exception thrown by post_insert" );
    is( $e->error, 'POST INSERT TEST',
	"pre_insert error message should be POST INSERT TEST" );

    my $tweaked = $s->Location_t->insert( values => { location_id => 54321,
						      location => 'insert tweak me' } );
    is ( $tweaked->select('location'), 'insert tweaked',
	 "pre_insert should change the value of location to 'insert tweaked'" );

    eval { $tweaked->update( location => 'pre_die' ) };
    $e = $@;
    isa_ok( $e, 'Alzabo::Exception',
	    "Exception thrown from pre_update" );
    is( $e->error, 'PRE UPDATE TEST',
	"pre_update error message should be PRE UPDATE TEST" );

    eval { $tweaked->update( location => 'post_die' ) };
    $e = $@;
    isa_ok( $e, 'Alzabo::Exception',
	    "Exception thrown by post_update" );
    is( $e->error, 'POST UPDATE TEST',
	"post_update error message should be POST UPDATE TEST" );

    $tweaked->update( location => 'update tweak me' );
    is ( $tweaked->select('location'), 'update tweaked',
	 "pre_update should change the value of location to 'update tweaked'" );

    eval { $tweaked->select('pre_sel_die') };
    $e = $@;
    isa_ok( $e, 'Alzabo::Exception',
	    "Exception thrown by pre_select" );
    is( $e->error, 'PRE SELECT TEST',
	"pre_select error message should be PRE SELECT TEST" );

    $tweaked->update( location => 'post_sel_die' );

    eval { $tweaked->select('location') };
    $e = $@;
    isa_ok( $e, 'Alzabo::Exception',
	    "Exception thrown by post_select" );
    is( $e->error, 'POST SELECT TEST',
	"post_select error message should be POST SELECT TEST" );

    eval { $tweaked->select_hash('location') };
    $e = $@;
    isa_ok( $e, 'Alzabo::Exception',
	    "Exception thrown by post_select" );
    is( $e->error, 'POST SELECT TEST',
	"post_select error message should be POST SELECT TEST" );

    $tweaked->update( location => 'select tweak me' );
    is( $tweaked->select('location'), 'select tweaked',
	 "post_select should change the value of location to 'select tweaked'" );

    my %d = $tweaked->select_hash('location');
    is( $d{location}, 'select tweaked',
	 "post_select_hash should change the value of location to 'select tweaked'" );

    $s->ToiletType_t->insert( values => { toilet_type_id => 1,
					  material => 'porcelain',
					  quality => 5 } );
    my $t = $s->Toilet_t->insert( values => { toilet_id => 1,
					      toilet_type_id => 1 } );

    is( $t->material, 'porcelain',
	"New toilet's material method should return 'porcelain'" );
    is( $t->quality, 5,
	"New toilet's quality method should return 5" );

    $s->Location_t->insert( values => { location_id => 100,
					location => '# 100!' } );
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

    my $expect = $Alzabo::ObjectCache::VERSION ? 'Alzabo::MM::Test::CachedRow::Toilet' : 'Alzabo::MM::Test::UncachedRow::Toilet';
    my $row = $s->Toilet_t->row_by_pk( pk => 1 );
    isa_ok( $row, $expect,
	    "The Toilet object" );

    $row = $s->Toilet_t->row_by_pk( pk => 1, no_cache => 1 );
    isa_ok( $row, 'Alzabo::MM::Test::UncachedRow::Toilet',
	    "The Toilet object" );

    my $p_row = $s->Location_t->potential_row;
    isa_ok( $p_row, 'Alzabo::MM::Test::PotentialRow::Location',
	    "Potential row object" );

    $p_row->location( 'zzz' );
    $p_row->location_id( 999 );
    is( $p_row->location_id, 999,
 	"location_id of potential object should be 99" );
    is( $p_row->location, 'zzz',
 	"Location name of potential object should be 'zzz'" );

    eval { $p_row->update( location => 'pre_die' ); };
    $e = $@;
    isa_ok( $e, 'Alzabo::Exception',
	    "Exception thrown by pre_update" );

    eval { $p_row->update( location => 'post_die' ); };
    $e = $@;
    isa_ok( $e, 'Alzabo::Exception',
	    "Exception thrown by post_update" );

    $p_row->update( location => 'update tweak me' );
    is ( $p_row->select('location'), 'update tweaked',
	 "pre_update should change the value of location to 'update tweaked'" );

    eval { $p_row->select('pre_sel_die') };
    $e = $@;
    isa_ok( $e, 'Alzabo::Exception',
	    "Exception thrown by pre_select" );

    $p_row->update( location => 'select tweak me' );
    is( $p_row->select('location'), 'select tweaked',
	 "post_select should change the value of location to 'select tweaked'" );

    %d = $p_row->select_hash('location');
    is( $d{location}, 'select tweaked',
	 "post_select_hash should change the value of location to 'select tweaked'" );

    $p_row->make_live;
    is( $p_row->location_id, 999,
	"Check that live row has same location id" );

    my $alias = $s->Toilet_t->alias;

    can_ok( $alias, 'toilet_id_c' );
    is( $alias->toilet_id_c->name, $s->Toilet_t->toilet_id_c->name,
	"Alias column has the same name as real table's column" );
    is( $alias->toilet_id_c->table, $alias,
	"The alias column's table should be the alias" );
}

sub make_schema
{
    my %r = ( mysql => 'MySQL',
	      pg => 'PostgreSQL',
	      oracle => 'Oracle',
	      sybase => 'Sybase',
	    );
    my %p = @_;
    my $s = Alzabo::Create::Schema->new( name => $p{schema_name},
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
		      cardinality => [ 'n', 1 ],
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

    delete @p{ 'schema_name', 'rdbms' };
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

    return $p{column}->name
	if $p{type} eq 'lookup_columns';

    return $p{column}->name if $p{type} eq 'lookup_columns';

    return $p{parent} ? 'parent' : 'children'
	if $p{type} eq 'self_relation';

    die "unknown type in call to naming sub: $p{type}\n";
}

sub my_PL
{
    return shift() . 's';
}

{
    package Alzabo::MM::Test::Table::Location;
    sub pre_insert
    {
	my $self = shift;
	my $p = shift;
	Alzabo::Exception->throw( error => "PRE INSERT TEST" ) if $p->{values}->{location} eq 'pre_die';

	$p->{values}->{location} = 'insert tweaked' if $p->{values}->{location} eq 'insert tweak me';
    }

    sub post_insert
    {
	my $self = shift;
	my $p = shift;
	Alzabo::Exception->throw( error => "POST INSERT TEST" ) if $p->{row}->select('location') eq 'post_die';
    }
}

{
    package Alzabo::MM::Test::Row::Location;
    sub pre_update
    {
	my $self = shift;
	my $p = shift;
	Alzabo::Exception->throw( error => "PRE UPDATE TEST" ) if $p->{location} && $p->{location} eq 'pre_die';

	$p->{location} = 'update tweaked' if $p->{location} && $p->{location} eq 'update tweak me';
    }

    sub post_update
    {
	my $self = shift;
	my $p = shift;
	Alzabo::Exception->throw( error => "POST UPDATE TEST" ) if $p->{location} && $p->{location} eq 'post_die';
    }

    sub pre_select
    {
	my $self = shift;
	my $cols = shift;

	Alzabo::Exception->throw( error => "PRE SELECT TEST" ) if grep { $_ eq 'pre_sel_die' } @$cols;
    }

    sub post_select
    {
	my $self = shift;
	my $data = shift;

	Alzabo::Exception->throw( error => "POST SELECT TEST" ) if exists $data->{location} && $data->{location} eq 'post_sel_die';

	$data->{location} = 'select tweaked' if exists $data->{location} && $data->{location} eq 'select tweak me';
    }

    sub pre_delete
    {
	my $self = shift;
	Alzabo::Exception->throw( error => "PRE DELETE TEST" ) if $self->select('location') eq 'pre_del_die';
    }

    sub post_delete
    {
	my $self = shift;
#	Alzabo::Exception->throw( error => "POST DELETE TEST" );
    }
}

1;
