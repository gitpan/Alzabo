use strict;

use Test::More;

use Alzabo::ObjectCache ( store => 'Alzabo::ObjectCache::Store::Memory',
			  sync => 'Alzabo::ObjectCache::Sync::Null',
			  lru_size => 2 );
use Alzabo::Runtime;

use lib '.', File::Spec->catdir( File::Spec->curdir, 't' );

require 'base.pl';

unless ( @$Alzabo::Build::Tests )
{
    plan skip_all => 'no test config provided';
    exit;
}

require 'make_schemas.pl';

plan tests => 3;

my $tests = $Alzabo::Build::Tests;

my $t = pop @$tests;
{
    no strict 'refs';
    &{ "$t->{rdbms}_make_schema" }(%$t);
}

my $s = Alzabo::Runtime::Schema->load_from_file( name => $t->{schema_name} );

foreach ( qw( user password host port ) )
{
    my $m = "set_$_";
    $s->$m( $t->{$_} );
}
$s->connect;

my @rows;
push @rows, $s->table('department')->insert( values => { name => 'a' } );
push @rows, $s->table('department')->insert( values => { name => 'b' } );
push @rows, $s->table('department')->insert( values => { name => 'c' } );
push @rows, $s->table('department')->insert( values => { name => 'd' } );
push @rows, $s->table('department')->insert( values => { name => 'e' } );

my $cache = Alzabo::ObjectCache->new;

my @keys = sort keys %{ $cache->{store}{cache} };

my @last_rows = sort map { $_->id_as_string } @rows[-1, -2];

is( scalar @keys, 2,
    "There should only be 2 keys in the cache" );

is( $keys[0], $last_rows[0],
    "The second to last row in the cache should match the second to last row inserted" );

is( $keys[1], $last_rows[1],
    "The last row in the cache should match the last row inserted" );
