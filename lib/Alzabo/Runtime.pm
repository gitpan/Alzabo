package Alzabo::Runtime;

use strict;

use Alzabo;

use Alzabo::Runtime::Column;
use Alzabo::Runtime::ColumnDefinition;
use Alzabo::Runtime::ForeignKey;
use Alzabo::Runtime::Index;
use Alzabo::Runtime::JoinCursor;
use Alzabo::Runtime::OuterJoinCursor;
use Alzabo::Runtime::Row;
use Alzabo::Runtime::RowCursor;
use Alzabo::Runtime::Schema;
use Alzabo::Runtime::Table;

use vars qw($VERSION);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.19 $ =~ /(\d+)\.(\d+)/;

1;

sub import
{
    shift;

    # ignore errors and let them be handled later in the app when it
    # tries to access the schema.
    eval { Alzabo::Runtime::Schema->load_from_file( name => $_ ); } foreach @_;
}

sub process_where_clause
{
    my ($sql, $where, $has_conditions) = @_;

    $where = [ $where ] unless UNIVERSAL::isa( $where->[0], 'ARRAY' );

    my $x = 0;
    my $needs_op = 1;
    foreach my $clause (@$where)
    {
	if (ref $clause)
	{
	    if ($needs_op)
	    {
		my $op = $x || $has_conditions ? 'and' : 'where';
		$sql->$op();
	    }
	    $sql->condition(@$clause);
	    $needs_op = 1;
	}
	elsif ($clause eq 'and' || $clause eq 'or')
	{
	    $sql->$clause();
	    $needs_op = 0;
	    next;
	}
	elsif ($clause eq '(')
	{
	    if ($needs_op)
	    {
		my $op = $x || $has_conditions ? 'and' : 'where';
		$sql->$op();
	    }
	    $sql->subgroup_start;
	    $needs_op = 0;
	}
	elsif ($clause eq ')')
	{
	    $sql->subgroup_end;
	    $needs_op = 1;
	}
	else
	{
	    Alzabo::Exception::Params->throw( error => "Invalid where clause specification: $clause" );
	}
	$x++;
    }
}

sub process_order_by_clause
{
    _process_by_clause(@_, 'order');
}

sub process_group_by_clause
{
    _process_by_clause(@_, 'group');
}

sub _process_by_clause
{
    my ($sql, $by, $type) = @_;

    my @c;
    my $s;
    if ( UNIVERSAL::isa( $by, 'Alzabo::Column' ) )
    {
	@c = $by;
    }
    elsif ( UNIVERSAL::isa( $by, 'ARRAY' ) )
    {
	@c = @{ $by };
    }
    else
    {
	Alzabo::Exception::Params->throw( error => "No columns provided for order by" )
		unless $by->{columns};

	@c = ( UNIVERSAL::isa( $by->{columns}, 'ARRAY' ) ?
	       @{ $by->{columns} } :
	       $by->{columns} );

	$s = lc $by->{sort} if exists $by->{sort};
    }

    my $method = "${type}_by";
    $sql->$method(@c);
    $sql->$s() if $s;
}



__END__

=head1 NAME

Alzabo::Runtime - Loads all Alzabo::Runtime::* classes

=head1 SYNOPSIS

  use Alzabo::Runtime qw( schema_name );

=head1 DESCRIPTION

Using this module loads Alzabo::Runtime::* modules.

These modules are what an end user of Alzabo uses to instantiate
objects representing data in a given schema.

=head1 import METHOD

This method is called when you C<use> this class.  You can pass an
array of strings to the module via the C<use> function.  These strings
are assumed to be the names of schema objects that you want to load.
This can be useful if you are running under a mod_perl (or similar)
environment and has the potential to save some memory by preloading
the objects before a fork, hopefully increasing shared memory.

This method explicitly ignores errors that may occur when trying to
load a particular schema.  This means that later attempts to retrieve
that schema will probably also fail.  This is done so that the
application that wants a particular schema can explicitly handle the
failure later on.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut

