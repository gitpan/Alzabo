#!/usr/bin/perl -w

use strict;

use Alzabo::Config;
use Cwd;
use ExtUtils::MakeMaker qw( prompt );
use File::Copy;
use Getopt::Long;

print <<"EOF";

Currently, Alzabo only comes with one schema creation interface.  This
is a web application that uses HTML::Mason (0.896 or greater) and
requires mod_perl to function.  Modifying the code to not require
mod_perl would be fairly trivial (just modify the file
'./mason/common/redirect').

EOF

my %opts;
GetOptions( \%opts,
	    'root_dir=s',
	    'install=s%',
	    'extension:s',
	  );

$opts{extension} ||= '';

if( defined $opts{root_dir} )
{
    unless (-e $opts{root_dir} && -e "$opts{root_dir}/schemas")
    {
	my $user = getpwuid($>);
	warn <<'EOF';

I am making some directories which Alzabo will use to store
information such as schema objects.  This will be owned by the current
user ($user).  If you plan to run the schema creation interface as
another user you may need to change the ownership and/or permissions
of these directories.
EOF
    }

    unless (-e $opts{root_dir})
    {
	warn "\nMaking Alzabo root install directory $opts{root_dir}\n";
	mkdir "$opts{root_dir}", 0755
	    or die "can't make dir $opts{root_dir}: $!";
    }

    unless (-e "$opts{root_dir}/schemas")
    {
	warn "Making Alzabo schema storage directory $opts{root_dir}/schemas\n";
	mkdir "$opts{root_dir}/schemas", 0755
	    or die "can't make dir $opts{root_dir}: $!";
    }
}

mason_schema() if $opts{install}{mason_schema};
mason_browser() if $opts{install}{mason_browser};

sub mason_schema
{
    make_mason_dirs( 'schema', 'common' );

    copy_common();

    my $base = Alzabo::Config::mason_web_dir;
    my $count = copy_dir( cwd() . '/interfaces/mason', "$base/schema" );
    if ($count)
    {
	warn "\nFinished installing mason based schema creation interface\n\n";
    }
    else
    {
	warn "\nNo changes in mason based schema creation interface components.  No files copied.\n\n";
    }
}

sub mason_browser
{
    make_mason_dirs( 'browser', 'common' );

    copy_common();

    my $base = Alzabo::Config::mason_web_dir;
    my $count = copy_dir( cwd() . '/utilities/data_browser', "$base/browser" );
    if ($count)
    {
	warn "\nFinished installing mason based data browser\n\n";
    }
    else
    {
	warn "\nNo changes in mason based data browser components.  No files copied\n\n";
    }
}

sub make_mason_dirs
{
    $main::user = prompt( "\nWhat user would you like to own the directories and files used for the
Mason components as well as the components themselves?", possible_web_user() );

    $main::group = prompt( "\nWhat group would you like to own the directories and files used for the
Mason components as well as the components themselves?", possible_web_group() );

    my $base = Alzabo::Config::mason_web_dir;

    $main::uid = (getpwnam($main::user))[2] || $<;
    $main::gid = (getgrnam($main::group))[2] || $(;

    unless ( -d $base )
    {
	warn "\n";
	warn "Making directory $base\n";
	mkdir $base, 0755
	    or die "Can't make $base dir: $!\n";
	warn "chown $base to $main::user/$main::group\n";
	chown $main::uid, $main::gid, "$base"
	    or die "Can't chown $base to $main::user/$main::group: $!\n?";
    }

    foreach (@_)
    {
	unless ( -d "$base/$_" )
	{
	    warn "\n";
	    warn "Making directory $base/$_\n";
	    mkdir "$base/$_", 0755
		or die "Can't make $base/$_ dir: $!\n";
	    warn "chown $base/$_ to $main::user/$main::group\n";
	    chown $main::uid, $main::gid, "$base/$_"
		or die "Can't chown $base/$_ to $main::user/$main::group: $!\n?";
	}
    }
}

sub copy_common
{
    my $base = Alzabo::Config::mason_web_dir;
    return if $main::common_done;

    my $count = copy_dir( cwd() . '/mason/common', "$base/common" );
    if ($count)
    {
	warn "\nFinished installing mason shared components\n\n";
    }
    else
    {
	warn "\nNo changes in mason shared components.  No files copied.\n\n";
    }

    $main::common_done = 1;
}

sub copy_dir
{
    my ($from, $to) = @_;

    my $dh = do { local $^W = 0; local *DH; local *DH; };

    opendir $dh, $from
	or die "Can't read $from dir: $!\n";

    my $count = 0;
    foreach my $from_f ( grep { ( ! /~\Z/ ) && -f "$from/$_" } readdir $dh )
    {
	my $to_f = $from_f;
	if ($to_f =~ /\.mhtml\Z/)
	{
	    $to_f =~ s/\.mhtml/$opts{extension}/;
	}

	if ( -e "$to/$to_f" )
	{
	    next unless (stat(_))[9] < (stat("$from/$from_f"))[9];
	}

	warn "\nCopying files ...\n" unless $count++;

	warn "$from/$from_f ... $to/$to_f\n";
	copy( "$from/$from_f", "$to/$to_f" )
	    or die "Can't copy $from/$from_f to $to/$to_f: $!\n";
	warn "chown $to/$to_f to $main::user/$main::group\n";
	chown $main::uid, $main::gid, "$to/$to_f"
	    or die "Can't chown $to/$to_f to $main::user/$main::group: $!\n?";
    }

    closedir $dh;

    return $count;
}

sub possible_web_user
{
    foreach ( qw( nobody web daemon apache root ) )
    {
	return $_ if getpwnam($_);
    }

    return (getpwuid($<))[0];
}

sub possible_web_group
{
    foreach ( qw( nobody nogroup web daemon apache root ) )
    {
	return $_ if getpwnam($_);
    }

    return (getgrgid($())[0];
}
