use Alzabo::Create;
use Cwd;
use File::Path;
use File::Spec;

use lib '.', './t';

require 'base.pl';

require 'utils.pl';

warn "\n# Cleaning up files and databases created during testing\n";

my $dir = cwd;

rmtree( File::Spec->catdir( $dir, 't', 'schemas' ), $Test::Harness::verbose );
rmtree( File::Spec->catdir( $dir, 't', 'objectcache' ), $Test::Harness::verbose );

print "1..1\n";
print "ok 1\n";

exit unless defined $ENV{ALZABO_RDBMS_TESTS};

my $tests = eval $ENV{ALZABO_RDBMS_TESTS};

foreach (@$tests)
{
    no strict 'refs';
    eval { &{ "$_->{rdbms}_clean_schema" }(%$_); };
}
