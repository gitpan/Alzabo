package Alzabo::ObjectCache::Store::Memory;

use vars qw($SELF $VERSION);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.7 $ =~ /(\d+)\.(\d+)/;

1;

sub import {}

sub new
{
    return $SELF if $SELF;

    my $proto = shift;
    my $class = ref $proto || $proto;
    my %p = @_;

    $SELF = bless {}, $class;
    return $SELF;
}

sub clear
{
    my $self = shift;

    %{ $self->{cache} } = ();
}

sub fetch_object
{
    my $self = shift;
    my $id = shift;

    # avoid auto-viv
    return $self->{cache}{$id} if exists $self->{cache}{$id};
}

sub store_object
{
    my $self = shift;
    my $obj = shift;

    my $id = $obj->id_as_string;

    return if exists $self->{cache}{$id};

    $self->{cache}{$id} = $obj;
}

sub delete_from_cache
{
    my $self = shift;

    delete $self->{cache}{ shift() };
}

__END__

=head1 NAME

Alzabo::ObjectCache::Store::Memory - Cache objects in memory

=head1 SYNOPSIS

  use Alzabo::ObjectCache( store => 'Alzabo::ObjectCache::Store::Memory',
                           sync  => 'Alzabo::ObjectCache::Sync::Null' );

=head1 DESCRIPTION

This class simply stores cached objects in memory.  This means that a
given object should never have to be created twice.

By default, this module has no upper limit on how many objects it will
store.  If you are operating in a persistent environment such as
mod_perl, these will have a tendency to eat up memory over time.  Use
the lru_size parameter to Alzabo::ObjectCache to make this module act
as an LRU.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
