use Alzabo::Create;
use Cwd;
use File::Path;

use lib '.', './t';

require 'base.pl';

require 'utils.pl';

warn "Cleaning up files and databases created during testing\n";

my $dir = cwd;

$Test::Harness::verbose = $Test::Harness::verbose;
rmtree( "$dir/schemas", $Test::Harness::verbose );
unlink 't/dbmsynctest.dbm';

print "1..1\n";
print "ok 1\n";

exit unless defined $ENV{ALZABO_RDBMS_TESTS};

my $tests = eval $ENV{ALZABO_RDBMS_TESTS};

foreach (@$tests)
{
    no strict 'refs';
    eval { &{ "$_->{rdbms}_clean_schema" }(%$_); };
}
