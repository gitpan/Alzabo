use ExtUtils::MakeMaker qw( prompt WriteMakefile );
use Text::Wrap;

use 5.005;
use strict;

use Data::Dumper;

my %config;
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

# extra prereqs for certain features
my %extra_prereq = ( 'the MySQL driver' => [ { 'Digest::MD5' => 0,
					       'DBD::mysql' => 0 },
					     'mysql' ],
		     'the Oracle driver' => [ { 'DBD::Oracle' => 0 },
					      'oracle' ],
		     'the PostgreSQL driver' => [ { 'DBD::Pg' => 0 },
						  'pg' ]
		   );

print <<'EOF';
The following questions pertain to optional features of Alzabo.
These questions help the installer determine what additional
system checks to perform.
EOF

my %prereq;
foreach my $k ( keys %extra_prereq )
{
    my $yesno = prompt( "\nDo you plan to use $k?", 'no' );
    if ( $yesno && $yesno !~ /\A[Nn]/)
    {
	%prereq = ( %prereq, %{ $extra_prereq{$k}[0] } );
	$main::test{ $extra_prereq{$k}[1] } = 1;
    }
}

eval { require Alzabo::Config; };

use vars qw(%extra);

$extra{mason_schema} = prompt( "\nDo you plan to install the HTML::Mason based schema creation interface?", 'no' ) =~ /\Ay/i;
$extra{mason_browser} = prompt( "\nDo you plan to install the HTML::Mason based data browser?", 'no' ) =~ /\Ay/i;

if ( $extra{mason_schema} || $extra{mason_browser} )
{
    $prereq{'HTML::Mason'} = 0.87;

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

if ( keys %Alazabo::Config::CONFIG )
{
    while (my ($k, $v) = each %Alzabo::Config::CONFIG)
    {
	$config{$k} ||= $v;
    }
}

write_config_module(%config);

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

WriteMakefile( 'NAME'	=> 'Alzabo',
	       'VERSION_FROM' => 'lib/Alzabo.pm',
	       PREREQ_PM => {
			     'DBI' => 0,
			     'Storable' => 0,
			     'Tie::IxHash' => 0,
			     'Class::Fields' => 0,
			     'Exception::Class' => 0,
			     'Tie::Cache' => 0,
			     'IPC::Shareable' => 0,
			     %prereq,
			    },

	       realclean => { FILES => './lib/Alzabo/Config.pm' },

	       AUTHOR => 'Dave Rolsky <autarch@urth.org>',
	       ABSTRACT => 'Perl data modelling tool',
	     );

package MY;

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
	$install =~ s/(install :: all pure_install doc_install)/$1 extras_install/;

	$install .= "\nextras_install : $extras\n";
    }

    return $install;
}

sub test
{
    my $self = shift;

    my $test = $self->SUPER::test(@_);

    my @t;
    my %names = ( mysql => 'Mysql',
		  pg => 'Postgres',
		  oracle => 'Oracle' );

    foreach (keys %main::test)
    {
	my $name = $names{$_};
	my $user = ExtUtils::MakeMaker::prompt( qq[
What username should be used to connect to the $name RDBMS
(must have the ability to create a new database/schema)? ] );
	my $password;
	if ($user)
	{
	    $password = ExtUtils::MakeMaker::prompt( qq[
What password should be used with the $user username? ] );
	}
	my $host = ExtUtils::MakeMaker::prompt( qq[
What host is the $name RDBMS located on (skip this if its localhost)? ] );

	push @t, { rdbms => $_, user => $user, password => $password, host => $host };
    }
    $Data::Dumper::Indent = 0;
    my $t = Data::Dumper->Dump( [\@t], [''] );
    $t =~ s/\$ = //;
    $t =~ s/'/"/g;
    $test =~ s/(runtests \@ARGV;)/\$\$ENV{ALZABO_RDBMS_TESTS} = q^$t^; $1/;

    return $test;
}
