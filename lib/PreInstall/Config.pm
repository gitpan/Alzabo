package Alzabo::Config;

use vars qw($VERSION %CONFIG);

use strict;

%CONFIG = ''CONFIG'';

sub schema_dir
{
    return $CONFIG{root_dir} . '/schemas';
}

sub available_schemas
{
    # Scan for schema directories
    my $dirname = Alzabo::Config::schema_dir;
    opendir DIR, $dirname
        or FileSystemException->throw( error =>  "can't open $dirname: $!\n" );

    my @s;
    foreach my $e (readdir DIR)
    {
        next if $e eq '.' || $e eq '..';
        push @s, $e if -d "$dirname/$e" && -r _;
    }

    closedir DIR
        or FileSystemException->throw( error =>  "can't close $dirname: $!\n" );

    return @s;
}

sub mason_web_dir
{
    return $CONFIG{mason_web_dir};
}

sub mason_url_path
{
    return $CONFIG{mason_url_path};
}

sub mason_extension
{
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

=over 4

=item * schema_dir

Returns a string containing the directory under which Alzabo schema
objects are stored in serialized form.  There will be one directory
per schema under the directory returned.

=item * available_schemas

Returns a list of strings containing the names of the available
schemas.

Exceptions:

FileSystemException - an error occurred trying to open or close a
directory.

=item * mason_web_dir

Returns the path to the root directory for the Alzabo Mason
components.

=item * mason_url_path

Returns the relative path to the Alzabo Mason components.

=item * mason_extension

Returns the used by the Alzabo Mason components.

=cut
