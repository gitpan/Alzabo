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
    my $dirname = Alzabo::Config::schema_dir;
    local *DIR;
    opendir DIR, $dirname
        or Alzabo::Exception::System->throw( error =>  "can't open $dirname: $!\n" );

    my @s;
    foreach my $e (readdir DIR)
    {
        next if $e eq '.' || $e eq '..';
        push @s, $e if -d "$dirname/$e" && -r _;
    }

    closedir DIR
        or Alzabo::Exception::System->throw( error =>  "can't close $dirname: $!\n" );

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

=head2 schema_dir

=head3 Returns

The directory under which Alzabo schema objects are stored in
serialized form.

=head2 available_schemas

=head3 Returns

A list containing the names of the available schemas.  There will be
one directory for each schema under the directory returned.
Directories which cannot be read will not be included in the list.

=head3 Throws

Alzabo::Exception::System

=head2 mason_web_dir

=head3 Returns

The path to the root directory for the Alzabo Mason components.

=head2 mason_url_path

=head3 Returns

The relative url path to the Alzabo Mason components.  This is only
really useful inside the Mason components themselves.

=head2 mason_extension

=head3 Returns

The file extenstion used by the Alzabo Mason components.

=cut
