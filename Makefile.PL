use 5.005;
use strict;
$^W = 1;

use Cwd;
use Data::Dumper;
use ExtUtils::MakeMaker qw( prompt WriteMakefile );
use File::Spec;

use vars qw(%prereq %extra %config %test @TESTS);

use Getopt::Long;
my %opts;
GetOptions( \%opts, 'dist' );

unless ( $opts{dist} )
{
    my $pl_file = File::Spec->catfile( 'install_helpers', 'prompts.pl' );
    require $pl_file;
}

my $realclean = join ' ', ( File::Spec->catfile( 'lib', 'Alzabo', 'Config.pm' ),
			    File::Spec->catdir( 't', 'objectcache' ),
			    File::Spec->catdir( 't', 'schemas' ),
			    File::Spec->catfile( 't', 'SDBM_File.lock' ),
			    'log.*' );

WriteMakefile( NAME         => 'Alzabo',
	       VERSION_FROM => File::Spec->catfile( 'lib', 'Alzabo.pm' ),
	       PREREQ_PM    => \%prereq,

	       realclean    => { FILES => $realclean },

	       AUTHOR       => 'Dave Rolsky <autarch@urth.org>',
	       ABSTRACT     => 'Perl data modelling tool',
	     );

package MY;

sub postamble
{
    my $pl_file = File::Spec->catfile( 'install_helpers', 'pod_merge.pl' );

    # add pod merge target
    my $make = <<"MAKE";

pure_all :: pod_merge
\t\$(NOOP)

pod_merge: pm_to_blib
\t\$(PERL) $pl_file lib \$(INST_LIB)
\t\@\$(TOUCH) \$\@

clean ::
\t\$(RM_F) pod_merge
MAKE

    return $make;
}

sub manifypods
{
    my $self = shift;

    my $make = $self->SUPER::manifypods;

    # include Alzabo::Config in list of PODs
#    my $config_pm = File::Spec->catfile( 'lib', 'Alzabo Config.pm' );
#    $make =~ s|(\t\@\$\(POD2MAN\))|$1 $config_pm \$(INST_MAN3DIR)/Alzabo::Config.\$(MAN3EXT)|;

    # use PODs from INST_LIB for man page creation
    $make =~ s/(\s)lib/$1\$(INST_LIB)/g;

    return $make;
}

sub install
{
    my $self = shift;

    my $install = $self->SUPER::install(@_);

    my $extras = '';
    my @args;
    push @args, "--root_dir=$main::config{root_dir}" if $main::config{root_dir};
    push @args, '--install=mason_schema' if $main::extra{mason_schema};
    push @args, '--install=mason_browser' if $main::extra{mason_browser};
    push @args, "--extension=$main::extra{mason_extension}"
	if $main::extra{mason_extension};

    my $pl_file = File::Spec->catfile( 'install_helpers', 'install_extras.pl' );
    $extras .= "\n\t\$(PERL) $pl_file @args";

    if ($extras)
    {
	$install =~ s/install :: all pure_install doc_install/install :: all pod_merge pure_install doc_install extras_install/;

	$install .= "\nextras_install : $extras\n";
    }

    return $install;
}

sub test
{
    my $self = shift;

    my $test = $self->SUPER::test(@_);

    return $test unless @main::TESTS;

    $Data::Dumper::Indent = 0;
    my $t = Data::Dumper->Dump( [\@main::TESTS], [''] );
    $t =~ s/\$ = //;
    $t =~ s/'/"/g;

    # works with older (pre 5.48_01 MM)
    $test =~ s/(runtests \@ARGV;)/\$\$ENV{ALZABO_RDBMS_TESTS} = q^$t^; \$\$ENV{ALZABO_TESTING} = 1; $1/;

    # works with newer MM
    $t =~ s/"/'/g;
    $test =~ s/("-MExtUtils::Command::MM" "-e" ")(test_harness\(\$\(TEST_VERBOSE\).*?\)" \$\(TEST_FILES\))/$1 \\\$\$ENV{ALZABO_RDBMS_TESTS} = q^$t^; \\\$\$ENV{ALZABO_TESTING} = 1; $2/;

    return $test;
}

sub processPL {''}

sub libscan
{
    my $self = shift;
    my $file = shift;

    return $file =~ /\.pl$|\.old$|PreInstall/ ? 0 : $self->SUPER::libscan($file);
}

sub dist_core
{
    my $self = shift;

    my $dist_core = $self->SUPER::dist_core(@_);

    $dist_core =~ s/dist : (\$\(DIST_DEFAULT\))/dist :  distcheck pause $1/;

    $dist_core .= qq|\n\npause : \n\t\@\$\(PERL\) -e'print "Press a key\\n"; <STDIN>'|;

    return $dist_core;
}

