use Test;

BEGIN { Test::plan tests => 1; }

use Cwd;
use File::Path;

warn "Cleaning up files written during testing\n";

my $dir = cwd;

rmtree( "$dir/schemas", $Test::Harness::verbose );

ok(1);
