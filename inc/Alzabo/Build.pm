package Alzabo::Build;

use strict;

use base 'Module::Build';

use Cwd;
use Data::Dumper;
use File::Path;
use File::Spec;

sub ACTION_build
{
    my $self = shift;

    $self->SUPER::ACTION_build(@_);

    $self->ACTION_pod_merge;
}

sub ACTION_pod_merge
{
    my $self = shift;

    my $script = File::Spec->catfile( 'install_helpers', 'pod_merge.pl' );

    my $blib = File::Spec->catdir( qw( blib lib ) );
    $self->run_perl_script( $script, '', "lib $blib" );
}

sub ACTION_test
{
    my $self = shift;

    my $dumped = Dumper $self->{args}{tests} || [];
    $dumped =~ s/\$VAR1 =//;

    $ENV{ALZABO_TEST_CONFIG} = $dumped;

    # Checked in the Sync::IPC module
    $ENV{ALZABO_TESTING} = 1;

    $self->SUPER::ACTION_test(@_);

    $self->add_to_cleanup( File::Spec->catdir( 't', 'objectcache' ),
			   File::Spec->catdir( 't', 'schemas' ),
			   File::Spec->catfile( 't', 'SDBM_File.lock' ),
			   ( glob('log.*') ),
			   ( glob('*.share') ),
			 );
}

sub ACTION_install
{
    my $self = shift;

    $self->SUPER::ACTION_install(@_);

    $self->ACTION_install_extras;
}

sub ACTION_install_extras
{
    my $self = shift;

    if( defined $self->{args}{root_dir} )
    {
        my $schema_dir =
            File::Spec->catdir( $self->{args}{root_dir}, 'schemas' );

        unless ( -d $schema_dir )
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

        mkpath( $schema_dir, 1, 0755 );
    }

    $self->_install_mason_schema_tool
        if $self->{args}{mason_schema};

    $self->_install_mason_browser_tool
        if $self->{args}{mason_browser};
}

sub _install_mason_schema_tool
{
    my $self = shift;

    $self->_make_mason_dirs( 'schema', 'common' );

    $self->_copy_common_mason_files;

    require Alzabo::Config;
    my $base = Alzabo::Config::mason_web_dir();
    my $count = $self->_copy_dir( [ cwd(), 'interfaces', 'mason' ],
                                  [ $base, 'schema' ] );
    if ($count)
    {
	warn <<'EOF';

Finished installing mason based schema creation interface

EOF
    }
    else
    {
	warn <<'EOF';

No changes in mason based schema creation interface components.  No
files copied.

EOF
    }
}

sub _install_mason_browser_tool { } # tool is currently defunct

sub _make_mason_dirs
{
    my $self = shift;

    $self->_get_uid_gid;

    require Alzabo::Config;
    my $base = Alzabo::Config::mason_web_dir();

    foreach (@_)
    {
        my $dir = File::Spec->catdir( $base, $_ );
	unless ( -d $dir )
	{
	    mkpath( $dir, 1, 0755 )
		or die "Can't make $dir dir: $!\n";
	    warn "chown $dir to $self->{Alzabo}{user}/$self->{Alzabo}{group}\n";
	    chown $self->{Alzabo}{uid}, $self->{Alzabo}{gid}, $dir
		or die "Can't chown $dir to $self->{Alzabo}{user}/$self->{Alzabo}{group}: $!\n?";
	}
    }
}

sub _copy_common_mason_files
{
    my $self = shift;

    require Alzabo::Config;
    my $base = Alzabo::Config::mason_web_dir();
    return if $self->{Alzabo}{common_is_copied};

    my $count = $self->_copy_dir( [ cwd(), 'mason', 'common' ],
                                  [ $base, 'common' ] );

    if ($count)
    {
	warn "\nFinished installing mason shared components\n\n";
    }
    else
    {
	warn "\nNo changes in mason shared components.  No files copied.\n\n";
    }

    $self->{Alzabo}{common_is_copied} = 1;
}

sub _copy_dir
{
    my ( $self, $f, $t ) = @_;

    $self->_get_uid_gid;

    my $dh = do { local $^W = 0; local *DH; local *DH; };

    my $from = File::Spec->catdir(@$f);
    my $to   = File::Spec->catdir(@$t);

    opendir $dh, $from
	or die "Can't read $from dir: $!\n";

    my $count = 0;
    foreach my $from_f ( grep { ( ! /~\Z/ ) &&
                                -f File::Spec->catfile( $from, $_ ) }
                         readdir $dh )
    {
        my $target =
            $self->copy_if_modified( File::Spec->catfile( $from, $from_f ),
                                     $to,
                                     'flatten',
                                   );

        # was up to date
        next unless $target;

        $count++;

	chown $self->{Alzabo}{uid}, $self->{Alzabo}{gid}, $target
	    or die "Can't chown $target to $self->{Alzabo}{user}/$self->{Alzabo}{group}: $!\n?";
    }

    closedir $dh;

    return $count;
}

sub _get_uid_gid
{
    my $self = shift;

    return if ( exists $self->{Alzabo}{uid} &&
                exists $self->{Alzabo}{gid} );

    $self->{Alzabo}{user} =
        $self->prompt( <<'EOF',

What user would you like to own the directories and files used for the
Mason components as well as the components themselves?
EOF
                       $self->_possible_web_user );

    $self->{Alzabo}{group} =
        $self->prompt( <<'EOF',

What group would you like to own the directories and files used for
the Mason components as well as the components themselves?
EOF
                       $self->_possible_web_group );

    $self->{Alzabo}{uid} = (getpwnam( $self->{Alzabo}{user} ))[2] || $<;
    $self->{Alzabo}{gid} = (getgrnam( $self->{Alzabo}{group} ))[2] || $(;
}

sub _possible_web_user
{
    foreach ( qw( www-data web apache daemon nobody root ) )
    {
	return $_ if getpwnam($_);
    }

    return (getpwuid( $< ))[0];
}

sub _possible_web_group
{
    foreach ( qw( www-data web apache nobody nogroup daemon root ) )
    {
	return $_ if getpwnam($_);
    }

    return (getgrgid( $( ))[0];
}


1;
