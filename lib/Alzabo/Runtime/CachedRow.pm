package Alzabo::Runtime::CachedRow;

use strict;
use vars qw($VERSION $CACHE);

use Alzabo::Runtime;

use Params::Validate qw( :all );
Params::Validate::validation_options( on_fail => sub { Alzabo::Exception::Params->throw( error => join '', @_ ) } );

use base qw(Alzabo::Runtime::Row);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.22 $ =~ /(\d+)\.(\d+)/;

1;

sub retrieve
{
    my $proto = shift;
    my $class = ref $proto || $proto;
    my %p = @_;

    if ( $CACHE && ! $p{insert} )
    {
	if ( my $row = $CACHE->fetch_object( $class->id_as_string(%p) ) )
	{
	    $row->check_cache;
	    return $row;
	}
    }
    elsif ( ! defined $CACHE )
    {
	$CACHE = Alzabo::ObjectCache->new;
    }

    if ( $p{potential_row} )
    {
	my $self = $p{potential_row};
	$self->{cache} = $CACHE;

	return bless $self, $class;
    }

    return bless { cache => $CACHE }, $class;
}

sub _init
{
    my $self = shift;
    my %p = @_;

    $self->{cache}->delete_from_cache($self)
	if $p{insert};

    if ( $p{prefetch} )
    {
	while ( my ($k, $v) = each %{ $p{prefetch} } )
	{
	    $self->{data}{$k} = $v;
	}
    }
    elsif ( my @pre = grep { ! exists $self->{data}{$_} } $self->table->prefetch )
    {
	$self->_get_data(@pre) if @pre;

	# If we're doing a fetch now then ignore time given
	delete $p{time};
    }

    $self->SUPER::_init(%p);

    $self->{cache}->store_object($self, $p{time});
    $self->{cache}->register_change($self, $p{time}) if $p{insert};
}

sub cache_id
{
    my $self = shift;

    my ($mem) = "$self" =~ /\((.*)\)$/;

    return join ' - ',  $self->table->name, $mem;
}

sub _get_data
{
    my $self = shift;
    my @cols = @_;

    my %select;
    my %data;
    foreach my $c (@cols)
    {
	foreach my $s ( $self->table->group_by_column($c) )
	{
	    if ( exists $self->{data}{$s} )
	    {
		$data{$s} = $self->{data}{$s};
	    }
	    else
	    {
		$select{$s} = 1;
	    }
	}
    }

    if (keys %select)
    {
	my %d = $self->SUPER::_get_data( keys %select );
	while ( my ($k,$v) = each %d )
	{
	    $self->{data}{$k} = $data{$k} = $v;
	}
    }

    return %data;
}

sub select
{
    my $self = shift;

    $self->check_cache;

    return $self->SUPER::select(@_);
}

sub select_hash
{
    my $self = shift;

    $self->check_cache;

    return $self->SUPER::select_hash(@_);
}

sub update
{
    my $self = shift;
    my %data = @_;

    Alzabo::Exception::Cache::Expired->throw
        ( error => "Cannot update expired object: " . $self->id_as_string )
            unless $self->check_cache;

    $self->SUPER::update(%data);

    $self->{cache}->register_change($self);

    while (my ($k, $v) = each %data)
    {
	# These can't be stored until they're fetched from the database again
	if ( defined $v && UNIVERSAL::isa( $v, 'Alzabo::SQLMaker::Function' ) )
	{
	    delete $self->{data}{$k};
	    next;
	}

	$self->{data}{$k} = $v;
    }
}

sub delete
{
    my $self = shift;

    Alzabo::Exception::Cache::Expired->throw( error => 'Cannot delete an expired object' )
	unless $self->check_cache;

    $self->SUPER::delete(@_);

    $self->{cache}->register_delete($self);
}

sub check_cache
{
    my $self = shift;

    Alzabo::Exception::Cache::Deleted->throw( error => "Object has been deleted" )
	if $self->{cache}->is_deleted($self);

    if ( $self->{cache}->is_expired($self) )
    {
	$self->{data} = {};

	while (my ($k, $v) = each %{ $self->{id} })
	{
	    $self->{data}{$k} = $v;
	}

	if (my @pre = $self->table->prefetch)
	{
	    $self->_get_data(@pre);
	}

	$self->{cache}->register_refresh($self);

	return 0;
    }

    return 1;
}

__END__

=head1 NAME

Alzabo::Runtime::CachedRow - Cached row objects

=head1 SYNOPSIS

  use Alzabo::Runtime::Row;

=head1 DESCRIPTION

This class is loaded by the
L<C<Alzabo::ObjectCache>|Alzabo::ObjectCache> module.  It subclasses
the L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> class and caches
rows and row object data.

=head1 METHODS

It has the exact same methods as
L<C<Alzabo::Runtime::Row>|Alzabo::Runtime::Row> plus:

=head2 check_cache

This checks if the row has been expired or deleted.  If the row is
deleted, an C<Alzabo::Exception::Cache::Deleted> exception is thrown.
If the row is expired, it will update itself from the RDBMS.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
