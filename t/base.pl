use Alzabo::Config;
use Cwd;
use File::Spec;

$| = 1;
$^W = 1;

my $cwd = Cwd::cwd();

foreach ( File::Spec->catdir( $cwd, 't', 'schemas' ),
	  File::Spec->catdir( $cwd, 't', 'objectcache' ) )
{
    unless (-d $_)
    {
	mkdir $_, 0755
	    or die "Can't make dir $_ for testing: $!\n";
    }
}

Alzabo::Config::root_dir( File::Spec->catdir( $cwd, 't' ) );

BEGIN
{
    require Test::More;
    push @Test::More::EXPORT, 'eval_ok';

    $^W = 0;
}

sub Test::More::eval_ok (&$)
{
    my ($code, $name) = @_;

    eval { $code->() };
    if ($@)
    {
	Test::More::ok( 0, $name );
	$@ =~ s/\n/\n\#/g;
	Test::Builder->new->diag("     got error: $@\n" );
    }
    else
    {
	Test::More::ok( 1, $name );
    }
}

