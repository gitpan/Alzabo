use Alzabo::Create;
use Cwd;
use File::Path;

use Test::More tests => 1;

use lib '.', './t';

require 'base.pl';

require 'utils.pl';

warn "\n# Cleaning up databases created during testing\n";

ok(1);

exit unless @$Alzabo::Build::Tests;

foreach my $t ( @$Alzabo::Build::Tests )
{
    no strict 'refs';
    eval { &{ "$t->{rdbms}_clean_schema" }(%$t); };
}

1;
