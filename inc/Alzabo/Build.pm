package Alzabo::Build;

use strict;

use lib './lib', './blib';

use Module::Build 0.20;
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

sub ACTION_install
{
    my $self = shift;

    $self->SUPER::ACTION_install(@_);
}

1;
