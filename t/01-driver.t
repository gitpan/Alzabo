#!/usr/bin/perl -w

use strict;

use File::Spec;

use lib '.', File::Spec->catdir( File::Spec->curdir, 't', 'lib' );

use Alzabo::Test::Utils;

use Test::More;


use Alzabo::Driver;


my @rdbms_names = Alzabo::Test::Utils->rdbms_names;

unless (@rdbms_names)
{
    plan skip_all => 'no test config provided';
    exit;
}


my $tests_per_run = 1;

plan tests => $tests_per_run * @rdbms_names;


my %rdbms = ( mysql => 'MySQL',
              pg    => 'PostgreSQL' );

foreach my $rdbms (@rdbms_names)
{
    my $config = Alzabo::Test::Utils->test_config_for($rdbms);

    my $driver = Alzabo::Driver->new( rdbms => $rdbms{ $config->{rdbms} } );

    my @p = ( 'user', 'password', 'host', 'port' );

    my %connect = map { $_ => $config->{$_} } grep { exists $rdbms{$_} } @p;

    eval_ok( sub { $driver->schemas(%connect) },
             "Schema method for $rdbms{ $config->{rdbms} }" );
}
