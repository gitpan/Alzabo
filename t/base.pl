use Alzabo::Config;
use Cwd;

Alzabo::Config::root_dir( Cwd::cwd );

$| = 1;
$^W = 1;

use vars qw( $COUNT );

sub ok
{
    my $ok = !!shift;
    print $ok ? 'ok ': 'not ok ';
    print ++$COUNT, ! $ok ? " - @_\n" : "\n";
}
