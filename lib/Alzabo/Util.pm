package Alzabo::Util;

use strict;
use vars qw($VERSION);

use Config;

use Alzabo::Exceptions;

$VERSION = sprintf '%2d.%02d', q$Revision: 1.6 $ =~ /(\d+)\.(\d+)/;

1;

sub subclasses
{
    my $base = shift;

    $base =~ s,::,/,g;

    $base = $Config{installsitelib} . "/$base";

    opendir DIR, $base
	or Alzabo::Exception::System->throw( error => "Cannot open directory $base: $!" );

    my @packages = map { substr($_, 0, length($_) - 3) } grep { substr($_, -3) eq '.pm' && -f "$base/$_" } readdir DIR;

    closedir DIR
	or Alzabo::Exception::System->throw( error => "Cannot close directory $base: $!" );

    return @packages;
}

__END__

=head1 NAME

Alzabo::Util - Utility functions for Alzabo

=head1 SYNOPSIS

  use Alzabo::Util;

=head1 DESCRIPTION

My dumping grounds for things that need to be shared among multiple
unrelated classes.

=head1 FUNCTIONS

=head2 subclasses ($package_name)

Given a package name, finds the available subclasses for that package.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
