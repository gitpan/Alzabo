package Alzabo::ObjectCache::IPCSync;

use strict;

use IPC::Shareable;

use vars qw($SELF $VERSION %IPC);

use base qw( Alzabo::ObjectCache::Sync );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.5 $ =~ /(\d+)\.(\d+)/;

1;

sub import
{
    shift;
    my %p = @_;

    tie %IPC, 'IPC::Shareable', ($ENV{ALZABO_TESTING} ? 'AOCT' : 'AOCI'), { create => 'yes', destroy => 'yes' }
	or die "couldn't tie to IPC segment during BEGIN block";

    %IPC = () if $p{clear_on_startup};
}

sub _init
{
    my $self = shift;
    $self->{ipc} = \%IPC;
}

sub update
{
    my $self = shift;
    my $id = shift;
    my $time = shift;
    my $overwrite = shift;

    $self->{ipc}{$id} = $time
	if ( $overwrite ||
	     ! exists $self->{ipc}{$id} ||
	     $self->{ipc}{$id} <= 0 );
}

sub sync_time
{
    my $self = shift;
    my $id = shift;

    return $self->{ipc}{$id};
}

__END__

=head1 NAME

Alzabo::ObjectCache::IPCSync - Uses a IPC file to sync object caches

=head1 SYNOPSIS

  use Alzabo::ObjectCache( store => 'Alzabo::ObjectCache::MemoryStore',
                           sync  => 'Alzabo::ObjectCache::IPCSync',
                           clear_on_startup => 1 );


=head1 DESCRIPTION

This class implements object cache syncing between multiple processes
using IPC to handle data storage.  The C<IPC::Shareable> module which
it uses handles locking issues.

In normal circumstances, the IPC segment used by this module is
deleted when the process that first loaded the module ends.  If the
program is aborted abnormally (via an external signal) then this
cleanup will probably not occur.

=head1 IMPORT PARAMETERS

=over 4

=item * clear_on_startup => $boolean

If this is true, then the IPC segment is cleared when the module is
loaded.  This is generally desirable as an existing segment may
contain spurious entries from previous executions of the program.
However, in the interests of safety, this parameter defaults to false.

=back

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
