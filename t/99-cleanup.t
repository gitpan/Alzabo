use strict;

use Alzabo::Create;
use Cwd;
use File::Path;
use File::Spec;

use Test::More tests => 1;

use lib '.', File::Spec->catdir( File::Spec->curdir, 't' );

require 'base.pl';

require 'utils.pl';

warn "\n# Cleaning up files and databases created during testing\n";

my $dir = cwd;

rmtree( File::Spec->catdir( $dir, 't', 'schemas' ), $Test::Harness::verbose );
rmtree( File::Spec->catdir( $dir, 't', 'objectcache' ), $Test::Harness::verbose );

ok(1);

exit unless @$Alzabo::Build::Tests;

foreach my $t ( @$Alzabo::Build::Tests )
{
    no strict 'refs';
    eval { &{ "$t->{rdbms}_clean_schema" }(%$t); };
}
