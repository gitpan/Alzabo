use strict;

use 5.005;

use Cwd;
use Data::Dumper;
use File::Spec;

use lib 'inc';

use Alzabo::Build;

use Getopt::Long;
my %opts;
GetOptions( \%opts, 'dist' );

{
    my ( $config, $prereq );
    unless ( $opts{dist} )
    {
        ( $config, $prereq ) = config();
        write_config_module($config);
    }
    else
    {
        $prereq = dist_prereq();
        $config = {};
    }

    my $build =
        Alzabo::Build->new( module_name => 'Alzabo',
                            license => 'perl',
                            %$prereq,
                            args => $config,
                          );

    $build->add_to_cleanup( File::Spec->catfile( 'lib', 'Alzabo', 'Config.pm' ) );
    $build->create_build_script;
}

sub config
{
    # try to see if there is an existing Alzabo installation
    eval { require Alzabo; };
    eval { require Alzabo::Config; };

    if ( ! $@ &&
         %Alzabo::Config::CONFIG &&
         defined Alzabo::Config::root_dir() &&
         length Alzabo::Config::root_dir() &&
         -d Alzabo::Config::root_dir() &&
         Alzabo::Config::available_schemas() && $Alzabo::VERSION < 0.55 )
    {
        print <<'EOF';

You appear to have schemas created with an older version of Alzabo.
If you want to continue to use these, you may need to run the
convert.pl script in the eg/ directory _before_ installing this
version of Alzabo.

For newer versions, starting with the transition from 0.64 to 0.65,
Alzabo automatically converts schemas as needed.

EOF

        exit unless Module::Build->y_n( '  Continue?', 'no' );
    }

    my %config;

    $config{root_dir} = root_dir();

    my ( $prereq, $tests, $tools ) = features();

    %config = ( %config, %$tools );

    my $test_config = test_config($tests);

    $config{tests} = $test_config;

    return \%config, $prereq;
}

sub root_dir
{
    print <<'EOF';

Please select a root directory for Alzabo (schema files will be stored
under this root.
EOF

    my $root_dir = Alzabo::Config::root_dir() if %Alzabo::Config::CONFIG;
    return Module::Build->prompt( '  Alzabo root?', $root_dir || find_possible_root() );
}

sub find_possible_root
{
    my @dirs;

    if ( $^O =~ /win/i )
    {
	# A bit too thorough?
	foreach ('C'..'Z')
	{
	    unshift @dirs, "$_:\\Program Files";
	}
    }
    else
    {
	@dirs = qw( /usr/local );
    }

    unshift @dirs, '/opt' if $^O =~ /solaris/i;

    foreach (@dirs)
    {
	$_ .= '/alzabo';

	return $_ if -e $_;
    }

    return '';
}

sub features
{
    # These are always needed
    my %prereq = default_prereq();

    my ( %tests, %tools );

    # extra prereqs for certain features
    my @features =
        ( { phrase   => 'to use the MySQL driver',
            requires => { 'DBD::mysql' => 2.1017 },
            test     => 'mysql',
          },

          { phrase     => 'to use the PostgreSQL driver',
            requires   => { 'DBD::Pg' => 1.13 },
            recommends => { 'MIME::Base64' => 0 },
            test   => 'pg',
          },

#           { phrase => 'to use Oracle driver',
#             requires => { 'DBD::Oracle' => 0 },
#             test   => 'oracle',
#           },

          { phrase => 'to use IPC for cache syncing',
            requires => { 'IPC::Shareable' => 0.54 },
          },

          { phrase => 'to use DB_File 1.x for cache syncing',
            requires => { 'DB_File' => 1.76 },
          },

          { phrase => 'to use BerkeleyDB for caching',
            requires => { 'BerkeleyDB' => 0.15 },
          },

          { phrase => 'to use SDBM_File for cache syncing',
            requires => { 'SDBM_File' => 0 },
          },

          { phrase => 'to use Cache::Mmap for cache syncing',
            requires => { 'Cache::Mmap' => 0.04 },
          },

          { phrase => 'to use the HTML::Mason based schema creation interface',
            requires => { 'HTML::Mason' => 0.896,
                          'HTTP::BrowserDetect' => 0,
                        },
            tool   => 'mason_schema',
          },

#           { phrase => 'to use the HTML::Mason based data browser',
#             requires => { 'HTML::Mason' => 0.896,
#                           'HTTP::BrowserDetect' => 0,
#                         },
#             tool   => 'mason_browser',
#           },

          { phrase => 'to view graphs of your schema in the schema creator',
            recommends => { GraphViz => 1.4 },
            only_if => { tool => 'mason_schema' },
          },
        );

    print <<'EOF';

The following questions pertain to optional features of Alzabo.  These
questions help the installer determine what additional system checks
to perform.

EOF

    foreach my $feature (@features)
    {
        if ( exists $feature->{only_if} )
        {
            if ( $feature->{only_if}{tool} )
            {
                next unless $tools{ $feature->{only_if}{tool} };
            }
        }

	print "\n";

	my $has = 1;
        my $mods = '';
        foreach my $type ( qw( requires recommends ) )
        {
            if ( $feature->{$type} )
            {
                my $text = "$type";
                while ( my ( $mod, $ver ) = each %{ $feature->{$type} } )
                {
                    $text .= " $mod";
                    $text .= " ($ver)" if $ver;

                    $has = 0
                        unless Module::Build->check_installed_version( $mod, $ver );
                }

                $mods .= ' and ' if $mods;
                $mods .= $text;
            }
        }

	print "\u$feature->{phrase} $mods.\n";

	my $wanted =
            Module::Build->y_n( "  Do you want $feature->{phrase}?", $has ? 'yes' : 'no' );

	if ($wanted)
	{
            foreach my $type ( qw( requires recommends ) )
            {
                $prereq{$type} =
                    { %{ $prereq{$type} },
                      %{ $feature->{$type} },
                    }
                        if $feature->{$type};
            }

	    $tests{ $feature->{test} } = 1 if exists $feature->{test};
	    $tools{ $feature->{tool} } = 1 if exists $feature->{tool};
	}
    }

    if ( $tools{mason_schema} || $tools{mason_browser} )
    {
	my $default = $Alzabo::Config::CONFIG{mason_web_dir};
	$default =~ s,/alzabo\Z,, if $default;

	do
	{
	    print "\n *** The directory you selected does not exist ***\n"
		if defined $tools{mason_web_dir};

	    print <<'EOF';

Where would you like to install the mason components for this
interface (this must be under your component root)?  NOTE: The
installer will create an 'alzabo' subdirectory under the directory
given.
EOF

	    $tools{mason_web_dir} =
                Module::Build->prompt( '  Mason directory?', $default || '' );
	} while ( ! -d $tools{mason_web_dir} );

	$tools{mason_web_dir} = File::Spec->catdir( $tools{mason_web_dir}, 'alzabo' );

	print <<'EOF';

You can pick a custom file extension for the mason components.  Only
components called as top level components will be given this
extension.  Components intended only for use by other components have
no extension at all
EOF


	$tools{mason_extension} =
            Module::Build->prompt( '  Mason component file extension?',
                                   $Alzabo::Config::CONFIG{mason_extension} || '.mhtml' );
    }

    return \%prereq, \%tests, \%tools;
}

sub default_prereq
{
    return
        ( requires =>
          { 'DBI' => minimum_dbi_version(),
            'Storable' => 0.7,
            'Tie::IxHash' => 0,
            'Exception::Class' => 0.97,
            'Time::HiRes' => 0,
            'Params::Validate' => 0.58,
            'Test::Simple' => 0.47,
            'Test::Harness' => 1.26,
            'Class::Factory::Util' => 1.3,
          },
          recommends => {},
          build_requires => { 'Pod::Man' => 1.14 },
        );
}

sub dist_prereq
{
    my %prereq = default_prereq();

    $prereq{requires}{DBI} = 1.21;

    $prereq{recommends}{'DBD::mysql'} = 2.1017;
    $prereq{recommends}{'DBD::Pg'} = 1.13;

    return \%prereq;
}

sub minimum_dbi_version
{
    if ( eval { require DBI } && $DBI::VERSION == 1.24 )
    {
        warn <<'EOF';
You appear to have DBI version 1.24 installed.  This version has a bug
which causes major problems with Alzabo.  Please upgrade or downgrade.
EOF
        return 1.25;
    }

    return 1.21;
}

sub write_config_module
{
    my $config = shift;

    # config items that the config module cares about
    my @keys =
        qw( mason_web_dir mason_extension root_dir );

    my $file = File::Spec->catfile( 'inc', 'Alzabo', 'Config.pm.tmpl' );
    local *MOD;
    open MOD, "<$file"
	or die "can't open $file: $!\n";
    my $mod = join '', <MOD>;
    close MOD
	or die "can't close $file: $!\n";

    my $c = "(\n";
    foreach my $k (@keys)
    {
	my $val;
	if ( length $config->{$k} )
	{
	    $val = "'$config->{$k}'";
	}
	else
	{
	    $val = "undef";
	}

	$c .= "'$k' => $val,\n";
    }
    $c .= ")";

    $mod =~ s/"'CONFIG'"/$c/;

    my $config = File::Spec->catfile( 'lib', 'Alzabo', 'Config.pm' );
    open MOD, ">$config"
	or die "can't write to $config: $!\n";
    print MOD $mod
	or die "can't write to $config: $!\n";
    close MOD
	or die "can't close $config: $!\n";
}

sub test_config
{
    my $tests = shift;

    my @config;

    my %names = ( mysql => 'Mysql',
		  pg => 'Postgres',
		  oracle => 'Oracle' );

    foreach my $t ( keys %$tests )
    {
	my $name = $names{$t};

	print <<'EOF';

The information from the following questions are used solely for
testing the pieces of Alzabo that require a real database for proper
testing.
EOF

	my $do = Module::Build->prompt( "  Do tests with $name RDBMS?", 'yes' );
	next unless $do =~ /^y/i;

	print <<'EOF';

Please provide a username that can be used to connect to the $name
RDBMS?  This user must have the ability to create a new
database/schema.
EOF

	my $user = Module::Build->prompt( '  Username?' );
	my $password;
	if ($user)
	{
	    $password = Module::Build->prompt( "  Password for $user?" );
	}

	print <<"EOF";

What host is the $name RDBMS located on.  Press enter to skip this if
the database server is located on the localhost or can be determined
in another way (for example, Oracle can use TNS to find the database).
EOF

	my $host = Module::Build->prompt( '  Host?' );

	print <<"EOF";

What port is the $name RDBMS located on.  Press enter to skip this.
EOF

	my $port = Module::Build->prompt( '  Port?' );

	print <<'EOF';

Please provide a database name that can be used for testing.  A
database/schema with this name will be created and dropped during the
testing process.
EOF

	my $db_name = Module::Build->prompt( '  Database name?', "test_alzabo_$t" );

        push @config,
        { rdbms    => $t,
          user     => $user,
          password => $password,
          host     => $host,
          port     => $port,
          schema_name => $db_name,
        };
    }

    return \@config;
}
