#!/usr/bin/perl -w

use strict;

use File::Spec;

use lib '.', File::Spec->catdir( File::Spec->curdir, 't', 'lib' );

use Alzabo::Test::Utils;

use Test::More;


use Alzabo::Create;
use Alzabo::Config;
use Alzabo::Runtime::UniqueRowCache;
use Alzabo::Runtime;

use Storable ();


my @rdbms_names = Alzabo::Test::Utils->rdbms_names;

unless (@rdbms_names)
{
    plan skip_all => 'no test config provided';
    exit;
}

plan tests => 10;


Alzabo::Test::Utils->remove_all_schemas;


# doesn't matter which RDBMS is used
my $rdbms = $rdbms_names[0];

Alzabo::Test::Utils->make_schema($rdbms);

my $config = Alzabo::Test::Utils->test_config_for($rdbms);

my $s = Alzabo::Runtime::Schema->load_from_file( name => $config->{schema_name} );

$s->connect( Alzabo::Test::Utils->connect_params_for($rdbms)  );

{
    my $dep1 = $s->table('department')->insert( values => { name => 'dep1' } );
    my $dep1_copy =
        $s->table('department')->row_by_pk( pk => $dep1->select('department_id') );

    is( "$dep1", "$dep1_copy",
        "There should only be one reference for a given row" );

    $dep1->delete;
    ok( $dep1->is_deleted, 'copy is deleted' );
    ok( $dep1_copy->is_deleted, 'copy is deleted' );
}

{
    my $dep2 = $s->table('department')->insert( values => { name => 'dep2' } );
    my $dep2_copy =
        $s->table('department')->row_by_pk( pk => $dep2->select('department_id') );

    $dep2->update( name => 'foo' );
    is( $dep2_copy->select('name'), 'foo', 'name in copy is foo' );

    $s->driver->do( sql  => 'UPDATE department SET name = ? WHERE department_id = ?',
                    bind => [ 'bar', $dep2->select('department_id') ],
                  );

    $dep2->refresh;

    is( $dep2->select('name'), 'bar', 'refresh works for cached rows' );
    is( $dep2_copy->select('name'), 'bar', 'refresh works for cached rows' );

   TODO:
    {
        local $TODO = "Needs a custom Storable patch (for now)";

        my $clone = Storable::thaw( Storable::nfreeze($dep2) );

        is( "$clone", "$dep2",
            'Storable freeze & thaw should still not create new object' );

        my $clone2 = Storable::dclone($dep2);

        is( "$clone2", "$dep2", 'Storable dclone should still not create new object' );
    }

    my $old_id = $dep2->id_as_string;
    $dep2->update( department_id => 1000 );

    ok( Alzabo::Runtime::UniqueRowCache->row_in_cache
            ( $dep2->table->name, $dep2->id_as_string ),
        'row is still in cache after updating primary key' );

    ok( ! Alzabo::Runtime::UniqueRowCache->row_in_cache( $dep2->table->name, $old_id ),
        'old id is not in cache' );
}
