package Alzabo::Runtime::Column;

use strict;
use vars qw($VERSION);

use Alzabo::Runtime;
use Params::Validate qw( :all );
Params::Validate::validation_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

use base qw(Alzabo::Column);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.5 $ =~ /(\d+)\.(\d+)/;

sub alias_clone
{
    my $self = shift;

    my %p = validate( @_, { table => { isa => 'Alzabo::Runtime::Table' },
			  } );

    my $clone;

    %$clone = %$self;
    $clone->{table} = $p{table};

    bless $clone, ref $self;

    return $clone;
}

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
