use Alzabo::Create;
use Cwd;
use File::Path;

use lib '.', './t';

require 'base.pl';

require 'utils.pl';

warn "\n# Cleaning up databases created during testing\n";

print "1..1\n";
print "ok 1\n";

exit unless defined $ENV{ALZABO_RDBMS_TESTS};

my $tests = eval $ENV{ALZABO_RDBMS_TESTS};

foreach (@$tests)
{
    no strict 'refs';
    eval { &{ "$_->{rdbms}_clean_schema" }(%$_); };
}
