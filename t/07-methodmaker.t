# This is just to test whether this stuff compiles.

use strict;

use Alzabo::Create;
use Alzabo::Runtime;
require Alzabo::MethodMaker;

use lib '.', './t';

require 'base.pl';

my $tests = eval $ENV{ALZABO_RDBMS_TESTS};

unless ($tests)
{
    print "1..0\n";
    exit;
}

print "1..37\n";

my $t = $tests->[0];
make_schema(%$t);

$ENV{ALZABO_DEBUG}=1;
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
	"Schema object cannot do method $t_meth" );

    ok( $s->$t_meth() eq $t,
	"Results of \$s->$t_meth() is not equal to table object" );

    foreach my $c ($t->columns)
    {
	my $c_meth = $c->name . '_c';
	ok( $t->can($c_meth),
	    "Table object cannot do method $t_meth" );

	ok( $t->$c_meth() eq $c,
	    "Results of \$t->$c_meth() is not equal to column object" );
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
	"First location should not have a parent but it does" );

    my @c = $loc1->children( order_by => { columns => $s->Location_t->location_id_c } ) ->all_rows;
    ok( @c == 2,
	"First location should have 2 children" );

    ok( $c[0]->location_id == 2 && $c[1]->location_id == 3,
	"Child location ids should be 2 and 3 but that are not" );

    ok( $loc5->parent->location_id == 4,
	"Location 5's parent should be 4 but it is not" );
}

{
    eval { $s->Location_t->insert( values => { location_id => 100,
					       location => 'die' } ) };
    ok( $@->error eq 'TEST',
	"validate_insert should have thrown an exception with the error message 'TEST' but it did not" );

    my $loc100 = $s->Location_t->insert( values => { location_id => 100,
						     location => 'a'} );
    eval { $loc100->update( location => 'die' ); };
    ok( $@->error eq 'TEST',
	"validate_update should have thrown an exception with the error message 'TEST' but it did not" );

    $s->ToiletType_t->insert( values => { toilet_type_id => 1,
					  material => 'porcelain' } );
    my $t = $s->Toilet_t->insert( values => { toilet_id => 1,
					      toilet_type_id => 1 } );

    ok( $t->material eq 'porcelain',
	"New toilet's material method should be 'porcelain' but it is not" );

    $s->ToiletLocation_t->insert( values => { toilet_id => 1,
					      location_id => 100 } );

    $s->ToiletLocation_t->insert( values => { toilet_id => 1,
					      location_id => 1 } );

    my @l = $t->Locations( order_by => { columns => $s->Location_t->location_id_c } )->all_rows;

    ok( @l == 2,
	"The toilet should have two locations but it has " . scalar @l );

    ok( $l[0]->location_id == 1 && $l[1]->location_id == 100,
	"Toilet's location ids should be 1 and 100 but that are not" );

    my @tl = $t->ToiletLocations->all_rows;

    ok( @tl == 2,
	"The toilet should have two ToiletLocation rows but it has " . scalar @tl );

    ok( $tl[0]->location_id == 1 && $tl[0]->toilet_id == 1 &&
	$tl[1]->location_id == 100 && $tl[1]->toilet_id == 1,
	"The toilet location rows should be 1/1 & 100/1 but they are not" );
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
		      min_max_from => [ 0, 1 ],
		      min_max_to => [ 0, 'n' ],
		    );

    my $toi = $s->make_table( name => 'Toilet' );

    $toi->make_column( name => 'toilet_id',
		       type => 'int',
		       primary_key => 1 );

    # linking table
    $s->add_relation( table_from => $toi,
		      table_to => $loc,
		      min_max_from => [ 0, 'n' ],
		      min_max_to => [ 0, 'n' ],
		    );

    my $tt = $s->make_table( name => 'ToiletType' );

    $tt->make_column( name => 'toilet_type_id',
		      type => 'int',
		      primary_key => 1 );
    $tt->make_column( name => 'material',
		      type => 'varchar',
		      length => 50 );

    # lookup table
    $s->add_relation( table_from => $toi,
		      table_to => $tt,
		      min_max_from => [ 1, 1 ],
		      min_max_to => [ 0, 'n' ],
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

    return (grep { ! $_->is_primary_key } $p{foreign_key}->table_to->columns)[0]->name
	if $p{type} eq 'lookup_table';

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
