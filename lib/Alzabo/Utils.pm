package Alzabo::Utils;

use strict;

use Scalar::Util qw( blessed );


sub safe_can
{
    return blessed( $_[0] ) && $_[0]->can( $_[1] );
}

sub safe_isa
{
    return blessed( $_[0] ) && $_[0]->isa( $_[1] );
}


1;

__END__

=head1 NAME

Alzabo::SQLMaker - Utility functions for other Alzabo modules

=head1 SYNOPSIS

  use Alzabo::Utils;

  if ( Alzabo::Utils::safe_can( $maybe_obj, 'method' ) { }

  if ( Alzabo::Utils::safe_isa( $maybe_obj, 'Class' ) { }

=head1 DESCRIPTION

This module contains a few utility functions for the use of other
Alzabo modules.

=head1 AUTHOR

Dave Rolsky, <dave@urth.org>

=cut
