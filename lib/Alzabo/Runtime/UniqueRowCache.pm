package Alzabo::Runtime::UniqueRowCache;

use strict;

use Alzabo::Runtime::Table;
use Alzabo::Runtime::RowState::InCache;

my %CACHE;

BEGIN
{
    my $real_make_row = \&Alzabo::Runtime::Table::_make_row;

    local $^W = 0;
    *Alzabo::Runtime::Table::_make_row =
        sub { my $self = shift;
              my %p = @_;

              my $id =
                  Alzabo::Runtime::Row->id_as_string_ext
                      ( pk    => $p{pk},
                        table => $p{table},
                      );

              my $table_name = $p{table}->name;
              return $CACHE{$table_name}{$id} if exists $CACHE{$table_name}{$id};

	      my $row =
		  $self->$real_make_row( %p,
					 state => 'Alzabo::Runtime::RowState::InCache',
				       );

	      Alzabo::Runtime::UniqueRowCache->write_to_cache($row);

              return $row;
          };
}

sub clear { %CACHE = () };

sub clear_table { delete $CACHE{ $_[1]->name } }

sub row_in_cache { return $CACHE{ $_[1] }{ $_[2] } }

sub delete_from_cache { delete $CACHE{ $_[1] }{ $_[2] } }

sub write_to_cache { $CACHE{ $_[1]->table->name }{ $_[1]->id_as_string } = $_[1] }

1;

__END__

# doesn't work across Storable without patch I sent to p5p
