use Alzabo::Config;
use Cwd;

$Alzabo::Config::CONFIG{root_dir} = Cwd::cwd;

$| = 1;

use vars qw( $COUNT );

sub ok
{
    my $ok = !!shift;
    print $ok ? 'ok ': 'not ok ';
    print ++$COUNT, "\n";
    print "@_\n" if ! $ok;
}
