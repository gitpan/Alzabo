package Alzabo::ColumnDefinition;

use strict;
use vars qw($VERSION);

use Alzabo;

use fields qw( owner type );

$VERSION = sprintf '%2d.%02d', q$Revision: 1.7 $ =~ /(\d+)\.(\d+)/;

1;

sub type
{
    my Alzabo::ColumnDefinition $self = shift;

    return $self->{type};
}

sub owner
{
    my Alzabo::ColumnDefinition $self = shift;

    return $self->{owner};
}

__END__

=head1 NAME

Alzabo::ColumnDefinition - Holds the type attribute for a column

=head1 SYNOPSIS

  my $def = $column->definition;

  print $def->type;

=head1 DESCRIPTION

This object holds information on a column that might need to be shared
with another column.  The idea is that if a column is a key in two or
more tables, then some of the information related to that column
should change automatically for all tables (and all columns) whenever
it changes at all.  Right now this is only type ('VARCHAR', 'NUMBER',
etc) information.  This object also has an 'owner', which is the
column which created it.

=head1 METHODS

=over 4

=item * type

Returns the object's type.

=item * owner

Returns the Column object that owns this definitions (the object that
created it).

=back

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
