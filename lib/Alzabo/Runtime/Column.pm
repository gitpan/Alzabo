package Alzabo::Runtime::Column;

use strict;
use vars qw($VERSION);

use Alzabo::Runtime;

use base qw(Alzabo::Column);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.4 $ =~ /(\d+)\.(\d+)/;

1;

__END__

=head1 NAME

Alzabo::Runtime::Column - Column objects

=head1 SYNOPSIS

  use Alzabo::Runtime::Column;

=for pod_merge DESCRIPTION

=head1 INHERITS FROM

C<Alzabo::Column>

=for pod_merge merged

=for pod_merge METHODS

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
