package Alzabo::Runtime::RowState::InCache;

use strict;

use base qw(Alzabo::Runtime::RowState::Live);

BEGIN
{
    no strict 'refs';
    foreach my $meth ( qw( select select_hash delete ) )
    {
        my $super = "SUPER::$meth";
        *{__PACKAGE__ . "::$meth"} =
            sub { my $s = shift;

                  $s->refresh(@_) unless $s->_in_cache(@_);

                  $s->$super(@_);
              };
    }
}

sub update
{
    my $class = shift;
    my $row = shift;

    my $old_id = $row->id_as_string;

    $class->refresh($row) unless $class->_in_cache($row);

    $class->SUPER::update( $row, @_ );

    return if exists $row->{id_string};

    Alzabo::Runtime::UniqueRowCache->delete_from_cache( $row->table->name, $old_id );

    Alzabo::Runtime::UniqueRowCache->write_to_cache($row);
}

sub refresh
{
    my $class = shift;

    $class->SUPER::refresh(@_);

#    return if $class->_in_cache($row); #????
}

sub _in_cache
{
    return
	Alzabo::Runtime::UniqueRowCache->row_in_cache
	    ( $_[1]->table->name, $_[1]->id_as_string );
}

sub _write_to_cache
{
    Alzabo::Runtime::UniqueRowCache->write_to_cache( $_[1] );
}


1;

__END__
