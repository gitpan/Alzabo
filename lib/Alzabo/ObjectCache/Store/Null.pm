package Alzabo::ObjectCache::Store::Null;

use vars qw($SELF $VERSION);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.2 $ =~ /(\d+)\.(\d+)/;

1;

sub import {}

sub new
{
    return $SELF if $SELF;

    my $proto = shift;
    my $class = ref $proto || $proto;

    $SELF = bless {}, $class;
    return $SELF;
}

sub clear
{
    1;
}

sub fetch_object
{
    0;
}

sub store_object
{
    0;
}

sub delete_from_cache
{
    0;
}

__END__

=head1 NAME

Alzabo::ObjectCache::Store::Null - Doesn't really store anything

=head1 SYNOPSIS

  use Alzabo::ObjectCache( store => 'Alzabo::ObjectCache::Store::Null',
                           sync  => 'Alzabo::ObjectCache::Sync::BerkeleyDB',
                           sync_dbm_file => 'somefilename.db',
                         );

=head1 DESCRIPTION

This class fakes the object storage mechanism.  It is useful if you
want to use the syncing part of the cache to signal changes between
multiple processes to in memory objects without storing the objects in
memory and thus causing some bloat.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
