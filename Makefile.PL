use 5.005;
use strict;
$^W = 1;

use Cwd;
use Data::Dumper;
use ExtUtils::MakeMaker qw( prompt WriteMakefile );
use Text::Wrap;

use vars qw(%extra %config %test @TESTS);

goto MAKEFILE if @ARGV && $ARGV[0] eq '--dist';

eval { require Alzabo::Config; };

if ( ! $@ && Alzabo::Config::available_schemas() )
{
    print <<'EOF';

You appear to have schemas created with an older version of Alzabo.
If you want to continue to use these, you will need to run the
convert.pl script in the eg/ directory _before_ installing this
version of Alzabo.
EOF
    exit unless prompt( '  Continue?', 'no' ) =~ /^y/i;
}

{
    print <<'EOF';

Please select a root directory for Alzabo (schema files will be stored
under this root.
EOF

    $config{root_dir} = prompt( '  Alzabo root?', find_possible_root() );

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
    my @extra_prereq = ( [ 'the MySQL driver', 'DBD::mysql' => 0, 'mysql' ],
			 [ 'the PostgreSQL driver', 'DBD::Pg' => 0, 'pg' ],
#			 [ 'the Oracle driver', 'DBD::Oracle', 0, 'oracle' ],
			 [ 'the IPC caching system', 'IPC::Shareable', 0.54 ],
			 [ 'the DBM caching system', 'DB_File', 1.76 ],
			 [ 'the HTML::Mason based schema creation interface', 'HTML::Mason', 0.896, undef, 'mason_schema' ],
			 [ 'the HTML::Mason based data browser', 'HTML::Mason', 0.896, undef, 'mason_browser' ],
		       );

    print <<'EOF';

The following questions pertain to optional features of Alzabo.
These questions help the installer determine what additional
system checks to perform.
EOF

    foreach my $p ( @extra_prereq )
    {
	print "\n";
	my $requires = $p->[1];
	$requires .= " (version $p->[2])" if $p->[2];
	print "\u$p->[0] requires $requires.\n";
	my $yesno = prompt( "  Use $p->[0]?", has_module($p->[1], $p->[2]) ? 'yes' : 'no' );
	if ( $yesno && $yesno !~ /\A[Nn]/)
	{
	    $prereq{ $p->[1] } = $p->[2];
	    $test{ $p->[3] } = 1 if $p->[3];
	    $extra{ $p->[4] } = 1 if $p->[4];
	}
    }
}

{
    if ( $prereq{'HTML::Mason'} )
    {
	my $default = $Alzabo::Config::CONFIG{mason_web_dir};
	$default =~ s,/alzabo\Z,, if $default;

	do
	{
	    print "\n *** The directory you selected does not exist ***\n"
		if $config{mason_web_dir};

	    print <<'EOF';

Where would you like to install the mason components for this
interface (this must be under your component root)?  NOTE: The
installer will create an 'alzabo' subdirectory under the directory
given.
EOF

	    $config{mason_web_dir} = prompt( '  Mason directory?', $default || '' );
	} while ( ! -d $config{mason_web_dir} );

	$config{mason_web_dir} .= '/alzabo';

	print <<'EOF';

You can pick a custom file extension for the mason components.  Only
components called as top level components will be given this
extension.  Components intended only for use by other components have
no extension at all
EOF


	$extra{mason_extension} = prompt( '  Mason component file extension?',
					  $Alzabo::Config::CONFIG{mason_extension} || '.mhtml' );
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
	    'Time::HiRes' => 0,
	    'Pod::Man' => 1.14,
	    'Params::Validate' => 0.03,
	    %prereq );

check_prereq(\%prereq);

MAKEFILE:

WriteMakefile( 'NAME'	=> 'Alzabo',
	       'VERSION_FROM' => 'lib/Alzabo.pm',
	       PREREQ_PM => \%prereq,

	       realclean => { FILES => './lib/Alzabo/Config.pm schemas t/dbmsynctest.dbm' },

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
may require me to be running as root.
";
    print $prompt;
    return unless prompt( "  Install $module?", 'y' ) =~ /^y/i;

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

	print <<'EOF';

The information from the following questions are used solely for
testing the pieces of Alzabo that require a real database for proper
testing.
EOF

	my $do = prompt( "  Do tests with $name RDBMS?", 'yes' );
	next unless $do =~ /^y/i;

	print <<'EOF';

Please provide a username that can be used to connect to the $name
RDBMS?  This user must have the ability to create a new
database/schema.
EOF

	my $user = prompt( '  Username?' );
	my $password;
	if ($user)
	{
	    $password = prompt( "  Password for $user?" );
	}

	print <<"EOF";

What host is the $name RDBMS located on.  Press enter to skip this if
the database server is located on the localhost or can be determined
in another way (for example, Oracle can use TNS to find the database).
EOF

	my $host = prompt( '  Host?' );

	print <<'EOF';

Please provide database name should be used for testing.  A
database/schema with this name will be created and dropped during the
testing process.
EOF

	my $db_name = prompt( '  Database name?', "test_alzabo_$_" );

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
    $test =~ s/(runtests \@ARGV;)/\$\$ENV{ALZABO_RDBMS_TESTS} = q^$t^; \$\$ENV{ALZABO_TESTING} = 1; $1/;

    return $test;
}

sub libscan
{
    my $self = shift;
    my $file = shift;

    return $file =~ /\.pl$|\.old$|PreInstall/ ? 0 : $self->SUPER::libscan($file);
}
