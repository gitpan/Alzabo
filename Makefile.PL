use ExtUtils::MakeMaker qw( prompt WriteMakefile );
use Text::Wrap;

use 5.005;
use strict;

use Cwd;
use Data::Dumper;

use vars qw(%extra %config %test @TESTS);

goto MAKEFILE if $ARGV[0] eq '--dist';

{
    $config{root_dir} = prompt( q[
Please select a root directory for Alzabo (schema files will be 
stored under this root.
], find_possible_root() );

    unless (-e $config{root_dir})
    {
	mkdir "$config{root_dir}", 0755
	    or die "can't make dir $config{root_dir}: $!";
    }
    unless (-e "$config{root_dir}/schemas")
    {
	mkdir "$config{root_dir}/schemas", 0755
	    or die "can't make dir $config{root_dir}: $!";
    }
}

my %prereq;

{
    # extra prereqs for certain features
    my %extra_prereq = ( 'the MySQL driver' => [ { 'Digest::MD5' => 0,
						   'DBD::mysql' => 0 },
						 'mysql' ],
			 'the PostgreSQL driver' => [ { 'DBD::Pg' => 0 },
						      'pg' ]
			 #'the Oracle driver' => [ { 'DBD::Oracle' => 0 },
			 #			      'oracle' ],
		       );

    print <<'EOF';

The following questions pertain to optional features of Alzabo.
These questions help the installer determine what additional
system checks to perform.
EOF

    foreach my $k ( keys %extra_prereq )
    {
	my $yesno = prompt( "\nDo you plan to use $k?", 'no' );
	if ( $yesno && $yesno !~ /\A[Nn]/)
	{
	    %prereq = ( %prereq, %{ $extra_prereq{$k}[0] } );
	    $test{ $extra_prereq{$k}[1] } = 1;
	}
    }
}

{
    eval { require Alzabo::Config; };

    $extra{mason_schema} = prompt( "\nDo you plan to install the HTML::Mason based schema creation interface?", 'no' ) =~ /\Ay/i;
    $extra{mason_browser} = prompt( "\nDo you plan to install the HTML::Mason based data browser?", 'no' ) =~ /\Ay/i;

    if ( $extra{mason_schema} || $extra{mason_browser} )
    {
	$prereq{'HTML::Mason'} = 0.895;

	my $default = $Alzabo::Config::CONFIG{mason_web_dir};
	$default =~ s,/alzabo\Z,,;

	do
	{
	    print "\n *** The directory you selected does not exist ***\n"
		if $config{mason_web_dir};

	    $config{mason_web_dir} = prompt('
Where would you like to install the mason components for
this interface (this must be under your component root)?
NOTE: The installer will create an \'alzabo\'
subdirectory under the directory given.
', $default || '' );
	} while ( ! -e $config{mason_web_dir} );

	$default = $Alzabo::Config::CONFIG{mason_url_path};
	$default =~ s,/alzabo\Z,,;

	do
	{
	    $config{mason_url_path} = prompt("
This directory ($config{mason_web_dir}) translates to what absolute
path on your web server (Do not include the server name here)?
", $default || '' );
	} while ( ! defined $config{mason_url_path} );

	foreach ( qw( mason_web_dir mason_url_path ) )
	{
	    $config{$_} =~ s,/\Z,,;
	}

	$config{mason_web_dir} .= '/alzabo';
	$config{mason_url_path} .= '/alzabo';

	$extra{mason_extension} = prompt( "
What extension would you like to use for the mason components?
", $Alzabo::Config::CONFIG{mason_extension} || '.mhtml' );
	$config{mason_extension} = $extra{mason_extension};
    }
}

if ( keys %Alazabo::Config::CONFIG )
{
    while (my ($k, $v) = each %Alzabo::Config::CONFIG)
    {
	$config{$k} ||= $v;
    }
}

write_config_module(%config);
get_test_setup();

%prereq = ( 'DBI' => 0,
	    'Storable' => 0,
	    'Tie::IxHash' => 0,
	    'Exception::Class' => 0.8,
	    'Tie::Cache' => 0,
	    'IPC::Shareable' => 0,
	    %prereq );

check_prereq(\%prereq);

MAKEFILE:

WriteMakefile( 'NAME'	=> 'Alzabo',
	       'VERSION_FROM' => 'lib/Alzabo.pm',
	       PREREQ_PM => \%prereq,

	       realclean => { FILES => './lib/Alzabo/Config.pm schemas' },

	       AUTHOR => 'Dave Rolsky <autarch@urth.org>',
	       ABSTRACT => 'Perl data modelling tool',
	     );

sub check_prereq
{
    my $pre = shift;

    while ( my ($k, $v) = each %$pre )
    {
	install_module($k, $v, $pre) unless has_module($k, $v);
    }
}

sub has_module
{
    my ($module, $version) = @_;

    my $string = "package Foo; use $module";
    $string .= " $version" if $version;

    eval $string;
    return ! $@;
}

sub install_module
{
    my ($module, $version, $pre) = @_;

    print "\n";
    my $prompt = "Prerequisite $module ";
    $prompt .= "(version $version) " if $version;
    $prompt .= "not found.
I can try to install this using the CPAN module but it
may require me to be running as root.  Install?";

    return unless prompt( $prompt, 'y' ) =~ /^y/i;

    my $cwd = cwd();

    require CPAN;
    CPAN::Shell->install(shift);

    # prevents bug where WriteMakeFile says it can't find the module
    # that was just installed.
    delete $pre->{$module};

    chdir $cwd or die "Can't change dir to '$cwd': $!";
}

sub find_possible_root
{
    my @dirs;

    if ($^O =~ /win/i)
    {
	# A bit too thorough?
	foreach ('C'..'Z')
	{
	    unshift @dirs, "$_:\Program Files";
	}
    }
    else
    {
	@dirs = qw( /usr/local
		    /usr/local/bin );
    }
    unshift @dirs, '/opt' if $^O =~ /solaris/i;

    foreach (@dirs)
    {
	$_ .= '/alzabo';
	# Ok, this won't work for Mac and what else?  VMS?  BeOS?
	# Help is appreciated.
	if ($^O !~ /win/)
	{
	    return $_ if (stat($_))[4] == 0;
	}
	else
	{
	    return $_ if -e $_;
	}
    }

    return '';
}

sub write_config_module
{
    my %config = @_;

    open MOD, './lib/PreInstall/Config.pm'
	or die "can't open ./lib/PreInstall/Config.pm: $!\n";
    my $mod = join '', <MOD>;
    close MOD
	or die "can't close ./lib/PreInstall/Config.pm: $!\n";

    my $c = "(\n";
    foreach my $k (sort keys %config)
    {
	$c .= "'$k' => '$config{$k}',\n";
    }
    $c .= ")";

    $mod =~ s/''CONFIG''/$c/;

    open MOD, '>./lib/Alzabo/Config.pm'
	or die "can't write to ./lib/Alzabo/Config.pm: $!\n";
    print MOD $mod
	or die "can't write to ./lib/Alzabo/Config.pm: $!\n";
    close MOD
	or die "can't close ./lib/Alzabo/Config.pm: $!\n";
}


sub get_test_setup
{

    my %names = ( mysql => 'Mysql',
		  pg => 'Postgres',
		  oracle => 'Oracle' );

    foreach (keys %test)
    {
	my $name = $names{$_};

	print qq[
The information from the following questions are used solely for
testing the pieces of Alzabo that require a real database for proper
testing.
];

	my $do = prompt( qq[
Do tests with $name RDBMS?
], 'yes' );
	next unless $do =~ /^y/i;

	my $user = prompt( qq[
Please provide a username that can be used to connect to the $name
RDBMS?  This user must have the ability to create a new
database/schema.  Username?
] );
	my $password;
	if ($user)
	{
	    $password = prompt( qq[
What password should be used with the $user username?
] );
	}

	my $host = prompt( qq[
What host is the $name RDBMS located on (skip this if its localhost)?
] );

	my $db_name = prompt( qq[
Please provide database name should be used for testing.  A
database/schema with this name will be created and dropped during the
testing process.  Database name?
], 'test_alzabo' );

	push @TESTS, { rdbms => $_, user => $user, password => $password, host => $host, db_name => $db_name };
    }
}

package MY;

sub top_targets
{
    my $self = shift;

    my $tt = $self->SUPER::top_targets;

    $tt =~ s/all :: pure_all manifypods/all :: pure_all pod_merge manifypods/;

    $tt .= "\npod_merge :\n\t\$(PERL) pod_merge.pl lib \$(INST_LIB)";

    return $tt;
}

sub install
{
    my $self = shift;

    my $install = $self->SUPER::install(@_);

    my $extras = '';
    my @args;
    push @args, '--install=mason_schema' if $main::extra{mason_schema};
    push @args, '--install=mason_browser' if $main::extra{mason_browser};
    push @args, "--extension=$main::extra{mason_extension}";

    $extras .= "\n\t\$(PERL) install_extras.pl @args";

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
    $test =~ s/(runtests \@ARGV;)/\$\$ENV{ALZABO_RDBMS_TESTS} = q^$t^; $1/;

    return $test;
}

sub libscan
{
    my $self = shift;
    my $file = shift;

    return $file =~ /\.pl$|\.old$|PreInstall/ ? 0 : $self->SUPER::libscan($file);
}
