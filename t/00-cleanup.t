use strict;

use Alzabo::Create;
use Cwd;
use File::Path;

use Test::More (tests => 1);

require 't/utils.pl';

my $dir = cwd;

rmtree( File::Spec->catdir( $dir, 't', 'schemas' ), $Test::Harness::verbose );
rmtree( File::Spec->catdir( $dir, 't', 'objectcache' ), $Test::Harness::verbose );

ok(1);

exit unless defined $ENV{ALZABO_RDBMS_TESTS};

my $tests = eval $ENV{ALZABO_RDBMS_TESTS};

foreach (@$tests)
{
    no strict 'refs';
    eval { &{ "$_->{rdbms}_clean_schema" }(%$_); };
}
