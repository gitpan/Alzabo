use Test;

BEGIN { Test::plan tests => 1; }

use Alzabo::Create;
use Cwd;
use File::Path;

require 't/utils.pl';

warn "Cleaning up files and databases created during testing\n";

my $dir = cwd;

rmtree( "$dir/schemas", $Test::Harness::verbose );

ok(1);

exit unless defined $ENV{ALZABO_RDBMS_TESTS};

my $tests = eval $ENV{ALZABO_RDBMS_TESTS};

foreach (@$tests)
{
    no strict 'refs';
    eval { &{ "$_->{rdbms}_clean_schema" }(%$_); };
}
