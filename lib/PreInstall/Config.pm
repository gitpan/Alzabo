package Alzabo::Config;

use File::Spec;

use vars qw($VERSION %CONFIG);

use strict;

%CONFIG = ''CONFIG'';

my $curdir = File::Spec->curdir;
my $updir = File::Spec->updir;

sub root_dir
{
    $CONFIG{root_dir} = $_[0] if defined $_[0];
    return $CONFIG{root_dir};
}

sub schema_dir
{
    Alzabo::Exception->throw( error => "No Alzabo root directory defined" )
	unless defined $CONFIG{root_dir};

    return File::Spec->catdir( $CONFIG{root_dir}, 'schemas' );
}

sub available_schemas
{
    my $dirname = Alzabo::Config::schema_dir;

    local *DIR;
    opendir DIR, $dirname
        or Alzabo::Exception::System->throw( error =>  "can't open $dirname: $!\n" );

    my @s;
    foreach my $e (readdir DIR)
    {
        next if $e eq $curdir || $e eq $updir;
        push @s, $e if -d File::Spec->catdir( $dirname, $e ) && -r _;
    }

    closedir DIR
        or Alzabo::Exception::System->throw( error =>  "can't close $dirname: $!\n" );

    return @s;
}

sub mason_web_dir
{
    $CONFIG{mason_web_dir} = $_[0] if defined $_[0];
    return $CONFIG{mason_web_dir};
}

sub mason_extension
{
    $CONFIG{mason_extension} = $_[0] if defined $_[0];
    return $CONFIG{mason_extension};
}

__END__

=head1 NAME

Alzabo::Config - Alzabo configuration information

=head1 SYNOPSIS

  use Alzabo::Config

  print Alzabo::Config::schema_dir;

=head1 DESCRIPTION

This module contains functions related to Alzabo configuration
information.

=head1 FUNCTIONS

=head2 root_dir ($root)

If a value is passed to this method then the root is temporarily
changed.  This change lasts as long as your application remains in
memory.  However, since changes are not written to disk it will have
to be changed again.

=head3 Returns

The root directory for your Alzabo installation.

=head2 schema_dir

If no root_dir is defined, this function throws an exception.

=head3 Returns

The directory under which Alzabo schema objects are stored in
serialized form.

=head2 available_schemas

If no root_dir is defined, this function throws an exception.

=head3 Returns

A list containing the names of the available schemas.  There will be
one directory for each schema under the directory returned.
Directories which cannot be read will not be included in the list.

=head3 Throws

Alzabo::Exception::System

=head2 mason_web_dir ($web_dir)

If a value is passed to this method then the Mason component directory
is temporarily changed.  This change lasts as long as your application
remains in memory.  However, since changes are not written to disk it
will have to be changed again.

=head3 Returns

The path to the root directory for the Alzabo Mason components.

=head2 mason_extension

If a value is passed to this method then the Mason extenstion is
temporarily changed.  This change lasts as long as your application
remains in memory.  However, since changes are not written to disk it
will have to be changed again.

=head3 Returns

The file extension used by the Alzabo Mason components.

=cut
