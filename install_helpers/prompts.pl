use strict;

eval { require Alzabo::Config; };
eval { require Alzabo; };

if ( ! $@ && defined Alzabo::Config::root_dir() &&
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
    exit unless prompt( '  Continue?', 'no' ) =~ /^y/i;
}

{
    print <<'EOF';

Please select a root directory for Alzabo (schema files will be stored
under this root.
EOF

    my $root_dir = Alzabo::Config::root_dir() if %Alzabo::Config::CONFIG;
    $config{root_dir} = prompt( '  Alzabo root?', $root_dir || find_possible_root() );
}

{
    # extra prereqs for certain features
    my @extra_prereq = ( [ 'to use the MySQL driver', [ [ 'DBD::mysql' => 2.1017 ] ], 'mysql' ],
			 [ 'to use the PostgreSQL driver', [ [ 'DBD::Pg' => 1.13 ], [ 'MIME::Base64' => 0 ] ], 'pg' ],
#			 [ 'to use Oracle driver', [ [ 'DBD::Oracle' => 0 ] ], 'oracle' ],
			 [ 'to use IPC for cache syncing', [ [ 'IPC::Shareable' => 0.54 ] ] ],
			 [ 'to use DB_File 1.x for cache syncing', [ [ 'DB_File' => 1.76 ] ] ],
			 [ 'to use BerkeleyDB 2.x/3.x for cache syncing', [ [ 'BerkeleyDB' => 0.15 ] ] ],
			 [ 'to use SDBM_File for cache syncing', [ [ 'SDBM_File' => 0 ] ] ],
			 [ 'to use Cache::Mmap for cache syncing', [ [ 'Cache::Mmap' => 0.04 ] ] ],
			 [ 'to use the HTML::Mason based schema creation interface', [ [ 'HTML::Mason' => 0.896 ],
										       [ 'HTTP::BrowserDetect' => 0 ], ],
			   undef, 'mason_schema' ],
#			 [ 'to use the HTML::Mason based data browser', , [ [ 'HTML::Mason' => 0.896 ],
#									    [ 'HTTP::BrowserDetect' => 0 ], ],
#			   undef, 'mason_browser' ],
			 [ 'to view graphs of your schema in the schema creator',
			   [ [ GraphViz => 1.4 ] ] ],
		       );

    print <<'EOF';

The following questions pertain to optional features of Alzabo.
These questions help the installer determine what additional
system checks to perform.
EOF

    foreach my $p ( @extra_prereq )
    {
	print "\n";
	my $requires = '';
	$requires .= join ', ', map { my $x = $_->[0]; $x .= $_->[1] ? " ($_->[1])": ''; $x } @{ $p->[1] };
	print "\u$p->[0] requires: $requires.\n";
	my $has = ( grep { has_module(@$_) } @{ $p->[1] } ) == @{ $p->[1] };
	my $yesno = prompt( "  Do you want $p->[0]?", $has ? 'yes' : 'no' );
	if ( $yesno && $yesno !~ /\A[Nn]/)
	{
	    foreach ( @{ $p->[1] } )
	    {
		$prereq{ $_->[0] } = $_->[1];
	    }
	    $test{ $p->[2] } = 1 if $p->[2];
	    $extra{ $p->[3] } = 1 if $p->[3];
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

my $dbi_version = 1.21;
if ( eval { require DBI } && $DBI::VERSION == 1.24 )
{
    warn "You appear to have DBI version 1.24 installed.  This version has a bug which causes major problems with Alzabo.  Please upgrade or downgrade.\n";
    $dbi_version = 1.25;
}

%prereq = ( 'DBI' => $dbi_version,
	    'Storable' => 0.7,
	    'Tie::IxHash' => 0,
	    'Exception::Class' => 0.97,
	    'Time::HiRes' => 0,
	    'Pod::Man' => 1.14,
	    'Params::Validate' => 0.24,
	    'Test::Simple' => 0.44,
	    'Test::Harness' => 1.26,
	    'Class::Factory::Util' => 1.2,
	    %prereq );

check_prereq(\%prereq);


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

sub write_config_module
{
    my %config = @_;

    my $preinstall = File::Spec->catfile( 'lib', 'PreInstall', 'Config.pm' );
    open MOD, "<$preinstall"
	or die "can't open $preinstall: $!\n";
    my $mod = join '', <MOD>;
    close MOD
	or die "can't close $preinstall: $!\n";

    my $c = "(\n";
    foreach my $k (sort keys %config)
    {
	my $val;
	if ( length $config{$k} )
	{
	    $val = "'$config{$k}'";
	}
	else
	{
	    $val = "undef";
	}

	$c .= "'$k' => $val,\n";
    }
    $c .= ")";

    $mod =~ s/''CONFIG''/$c/;

    my $config = File::Spec->catfile( 'lib', 'Alzabo', 'Config.pm' );
    open MOD, ">$config"
	or die "can't write to $config: $!\n";
    print MOD $mod
	or die "can't write to $config: $!\n";
    close MOD
	or die "can't close $config: $!\n";
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

	print <<"EOF";

What port is the $name RDBMS located on.  Press enter to skip this.
EOF

	my $port = prompt( '  Port?' );

	print <<'EOF';

Please provide a database name that can be used for testing.  A
database/schema with this name will be created and dropped during the
testing process.
EOF

	my $db_name = prompt( '  Database name?', "test_alzabo_$_" );

	push @TESTS, { rdbms => $_, user => $user, password => $password, host => $host, port => $port, schema_name => $db_name };
    }
}

1;
