package Alzabo::RDBMSRules::MySQL;

use strict;
use vars qw($VERSION);

use Alzabo::RDBMSRules;

use base qw(Alzabo::RDBMSRules);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.51 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    return bless {}, $class;
}

sub validate_schema_name
{
    my $self = shift;
    my $name = shift->name;

    Alzabo::Exception::RDBMSRules->throw( error => "Schema name must at least one character long" )
	unless length $name;

    # These are characters that are illegal in a dir name.  I'm trying
    # to accomodate both Win32 and UNIX here.
    foreach my $c ( qw( : \ / ) )
    {
	Alzabo::Exception::RDBMSRules->throw( error => "Schema name contains an illegal character ($c)" )
	    if index($name, $c) != -1;
    }
}

# Note: These rules are valid for MySQL 3.22.x.  MySQL 3.23.x is
# actually less restrictive but this should be enough freedom.

sub validate_table_name
{
    my $self = shift;
    my $name = shift->name;

    Alzabo::Exception::RDBMSRules->throw( error => "Table name must at least one character long" )
	unless length $name;
    Alzabo::Exception::RDBMSRules->throw( error => "Table name is too long.  Names must be 64 characters or less." )
	if length $name >= 64;
    Alzabo::Exception::RDBMSRules->throw( error => "Table name must only contain alphanumerics or underscore(_)." )
	if $name =~ /\W/;
}

sub validate_column_name
{
    my $self = shift;
    my $name = shift->name;

    Alzabo::Exception::RDBMSRules->throw( error => "Column name must at least one character long" )
	unless length $name;
    Alzabo::Exception::RDBMSRules->throw( error => 'Name is too long.  Names must be 64 characters or less.' )
	if length $name >= 64;
    Alzabo::Exception::RDBMSRules->throw( error =>
					  'Name contains characters that are not alphanumeric or the dollar sign ($).' )
	if $name =~ /[^\w\$]/;
    Alzabo::Exception::RDBMSRules->throw( error =>
					  'Name contains only digits.  Names must contain at least one alpha character.' )
	unless $name =~ /[^\W\d]/;
}

sub validate_column_type
{
    my $self = shift;
    my $type = shift;

    $type = 'INTEGER' if uc $type eq 'INT';

    # Columns which take no modifiers.
    my %simple_types = map {$_ => 1} ( qw( DATE
					   DATETIME
					   TIME
					   TINYBLOB
					   TINYTEXT
					   BLOB
					   TEXT
					   MEDIUMBLOB
					   MEDIUMTEXT
					   LONGBLOB
					   LONGTEXT
					   INTEGER
					   TINYINT
					   SMALLINT
					   MEDIUMINT
					   BIGINT
					   FLOAT
					   DOUBLE
					   REAL
					   DECIMAL
					   NUMERIC
					   TIMESTAMP
					   CHAR
					   VARCHAR
					   YEAR
					 ),
				     );

    return uc $type if $simple_types{uc $type};

    return 'DOUBLE' if $type =~ /DOUBLE\s+PRECISION/i;

    return 'CHAR' if $type =~ /\A(?:NATIONAL\s+)?CHAR(?:ACTER)?/i;
    return 'VARCHAR' if $type =~ /\A(?:NATIONAL\s+)?(?:VARCHAR|CHARACTER VARYING)/i;

    my $t = $self->_capitalize_type($type);
    return $t if $t;

    Alzabo::Exception::RDBMSRules->throw( error => "Unrecognized type: $type" );
}

sub _capitalize_type
{
    my $self = shift;
    my $type = shift;

    if ( uc substr($type, 0, 4) eq 'ENUM' )
    {
	return 'ENUM' . substr($type, 4);
    }
    elsif ( uc substr($type, 0, 3) eq 'SET' )
    {
	return 'SET' . substr($type, 3);
    }
    else
    {
	return uc $type;
    }
}

sub validate_column_length
{
    my $self = shift;
    my $column = shift;

    # integer column
    if ( $column->type =~ /\A(?:(?:(?:TINY|SMALL|MEDIUM|BIG)?INT)|INTEGER)/i )
    {
	Alzabo::Exception::RDBMSRules->throw( error => "Max display value is too long.  Maximum allowed value is 255." )
	    if defined $column->length && $column->length > 255;

	Alzabo::Exception::RDBMSRules->throw( error => $column->type . " columns cannot have a precision." )
	    if defined $column->precision;
	return;
    }

    if ( $column->type =~ /\A(?:FLOAT|DOUBLE(?:\s+PRECISION)?|REAL)/i )
    {
	if (defined $column->length)
	{
	    Alzabo::Exception::RDBMSRules->throw( error => "Max display value is too long.  Maximum allowed value is 255." )
		if $column->length > 255;

	    Alzabo::Exception::RDBMSRules->throw( error => "Max display value specified without floating point precision." )
		unless defined $column->precision;

	    Alzabo::Exception::RDBMSRules->throw( error =>
						  "Floating point precision is too high.  The maximum value is " .
						  "30 or the maximum display size - 2, whichever is smaller." )
		if $column->precision > 30 || $column->precision > ($column->length - $column->precision);
	}

	return;
    }

    if ( $column->type =~ /\A(?:DECIMAL|NUMERIC)\z/i )
    {
	Alzabo::Exception::RDBMSRules->throw( error => "Max display value is too long.  Maximum allowed value is 255." )
	    if defined $column->length && $column->length > 255;
	Alzabo::Exception::RDBMSRules->throw( error =>
					      "Floating point precision is too high.  The maximum value is " .
					      "30 or the maximum display size - 2, whichever is smaller." )
	    if defined $column->precision && ($column->precision > 30 || $column->precision > ($column->length - 2) );
	return;
    }

    if ( uc $column->type eq 'TIMESTAMP' )
    {
	Alzabo::Exception::RDBMSRules->throw( error => "Max display value is too long.  Maximum allowed value is 14." )
	    if defined $column->length && $column->length > 14;
	Alzabo::Exception::RDBMSRules->throw( error => $column->type . " columns cannot have a precision." )
	    if defined $column->precision;
	return;
    }

    if ( $column->type =~ /\A(?:(?:NATIONAL\s+)?VAR)?CHAR/i )
    {
	Alzabo::Exception::RDBMSRules->throw( error => "CHAR and VARCHAR columns must have a length provided." )
	    unless defined $column->length && $column->length > 0;
	Alzabo::Exception::RDBMSRules->throw( error => "Max display value is too long.  Maximum allowed value is 255." )
	    if $column->length > 255;
	Alzabo::Exception::RDBMSRules->throw( error => $column->type . " columns cannot have a precision." )
	    if defined $column->precision;
	return;
    }

    if ( uc $column->type eq 'YEAR' )
    {
	Alzabo::Exception::RDBMSRules->throw( error => "Valid values for the length specification are 2 or 4." )
	    if defined $column->length && ($column->length != 2 && $column->length != 4);
	return;
    }

    Alzabo::Exception::RDBMSRules->throw( error => $column->type . " columns cannot have a length or precision." )
	if defined $column->length || defined $column->precision;
}

sub validate_column_attribute
{
    my $self = shift;
    my %p = @_;

    my $column = $p{column};
    my $type = $column->type;
    my $a = uc $p{attribute};
    $a =~ s/\A\s//;
    $a =~ s/\s\z//;

    if ( $a eq 'AUTO_INCREMENT' || $a eq 'UNSIGNED' || $a eq 'ZEROFILL' )
    {
	Alzabo::Exception::RDBMSRules->throw( error => "$a attribute can only be applied to numeric columns" )
	    unless $self->type_is_numeric($type);
	return;
    }

    if ($a eq 'BINARY')
    {
	Alzabo::Exception::RDBMSRules->throw( error => "$a attribute can only be applied to character columns" )
	    unless $self->type_is_char($type);
	return;
    }
    return if $a =~ /\AREFERENCES/i;

    Alzabo::Exception::RDBMSRules->throw( error => "Unrecognized attribute: $a" );
}

sub validate_primary_key
{
    my $self = shift;
    my $col = shift;

    Alzabo::Exception::RDBMSRules->throw( error => 'Blob columns cannot be part of a primary key' )
	if $col->type =~ /\A(?:TINY|MEDIUM|LONG)?(?:BLOB|TEXT)\z/i;
}

sub validate_sequenced_attribute
{
    my $self = shift;
    my $col = shift;

    Alzabo::Exception::RDBMSRules->throw( error => 'Non-numeric columns cannot be sequenced' )
	unless $self->type_is_numeric( $col->type );

    Alzabo::Exception::RDBMSRules->throw( error => 'Only one sequenced column per table is allowed.' )
	if grep { $_ ne $col && $_->sequenced } $col->table->columns;
}

sub validate_index
{
    my $self = shift;
    my $index = shift;

    foreach my $c ( $index->columns )
    {
	my $prefix = $index->prefix($c);
	if (defined $prefix)
	{
	    Alzabo::Exception::RDBMSRules->throw( error => "Invalid prefix specification ('$prefix')" )
		unless $prefix =~ /\d+/ && $prefix > 0;

	    Alzabo::Exception::RDBMSRules->throw( error => 'Non-character/blob columns cannot have an index prefix' )
		unless $self->type_is_blob( $c->type ) || $self->type_is_char( $c->type );
	}

	if ( $c->is_blob )
	{
	    Alzabo::Exception::RDBMSRules->throw( error => 'Blob columns must have an index prefix' )
		unless $prefix;
	}

	if ( $index->fulltext )
	{
	    Alzabo::Exception::RDBMSRules->throw( error => 'A fulltext index can only include text or char columns' )
		unless $c->is_character || $c->type =~ /\A(?:TINY|MEDIUM|LONG)?TEXT\z/i;
	}
    }

    Alzabo::Exception::RDBMSRules->throw( error => 'An fulltext index cannot be unique' )
	if $index->unique && $index->fulltext;

}

sub type_is_numeric
{
    my $self = shift;
    my $type = uc shift;

    return 1 if $type =~ /\A(?:
                            (?:TINY|SMALL|MEDIUM|BIG)?
                            INT|INTEGER
                            )
                           |
                           FLOAT|DOUBLE|REAL
                          \z
                         /x;
}

sub type_is_char
{
    my $self = shift;
    my $type = uc shift;

    return 1 if $type =~ /\A(?:(?:NATIONAL\s+)?VAR)?CHAR\z/;
}

sub type_is_blob
{
    my $self = shift;
    my $type = uc shift;

    return 1 if $type =~ /\A(?:TINY|MEDIUM|LONG)?(?:TEXT|BLOB)\z/;
}

sub blob_type { return 'BLOB' }

sub column_types
{
    return qw( TINYINT
	       SMALLINT
	       MEDIUMINT
	       INTEGER
	       BIGINT

	       FLOAT
	       DOUBLE
	       DECIMAL
	       NUMERIC

	       CHAR
	       VARCHAR

	       DATE
	       DATETIME
	       TIME
	       TIMESTAMP
	       YEAR

	       TINYTEXT
	       TEXT
	       MEDIUMTEXT
	       LONGTEXT

	       TINYBLOB
	       BLOB
	       MEDIUMBLOB
	       LONGBLOB
	     );
}

my %features = map { $_ => 1 } qw ( extended_column_types
				    index_prefix
				    fulltext_index
				  );
sub feature
{
    shift;
    return $features{+shift};
}

sub schema_sql
{
    my $self = shift;
    my $schema = shift;

    my @sql;

    foreach my $t ( $schema->tables )
    {
	push @sql, $self->table_sql($t);
    }

    return @sql;
}

sub table_sql
{
    my $self = shift;
    my $table = shift;

    my $sql = "CREATE TABLE " . $table->name . " (\n  ";

    $sql .= join ",\n  ", map { $self->column_sql($_) } $table->columns;

    if (my @pk = $table->primary_key)
    {
	$sql .= ",\n";
	$sql .= '  PRIMARY KEY (';
	$sql .= join ', ', map {$_->name} @pk;
	$sql .= ')';
    }
    $sql .= "\n)";

    my @sql = ($sql);
    foreach my $i ( $table->indexes )
    {
	push @sql, $self->index_sql($i);
    }

    return @sql;
}

sub column_sql
{
    my $self = shift;
    my $col = shift;

    # make sure each one only happens once
    my %attr = map { uc $_ => $_ } ( $col->attributes,
				     ($col->nullable ? 'NULL' : 'NOT NULL'),
				     ($col->sequenced ? 'AUTO_INCREMENT' : () ) );

    # unsigned attribute has to come right after type declaration,
    # same with binary.  No column could have both.
    my @unsigned = $attr{UNSIGNED} ? delete $attr{UNSIGNED} : ();
    my @binary   = $attr{BINARY} ? delete $attr{BINARY} : ();

    my @default;
    if ( defined $col->default )
    {
	my $def = ( $self->type_is_numeric( $col->type ) ? $col->default :
		    do { my $d = $col->default; $d =~ s/"/""/g; $d } );
	@default = ( qq|DEFAULT "$def"| );
    }

    my $type = $col->type;
    my @length;
    if ( defined $col->length )
    {
	my $length = '(' . $col->length;
	$length .= ', ' . $col->precision if defined $col->precision;
	$length .= ')';
	$type .= $length;
    }

    my $sql .= join '  ', ( $col->name,
			    $type,
			    @unsigned,
			    @binary,
			    @default,
			    sort values %attr );

    return $sql;
}

sub index_sql
{
    my $self = shift;
    my $index = shift;

    my $index_name = $self->_make_index_name( $index->id );

    my $sql = 'CREATE';
    $sql .= ' UNIQUE' if $index->unique;
    $sql .= ' FULLTEXT' if $index->fulltext;
    $sql .= " INDEX $index_name ON " . $index->table->name . ' ( ';

    $sql .= join ', ', ( map { my $sql = $_->name;
			       $sql .= '(' . $index->prefix($_) . ')' if $index->prefix($_);
			       $sql; } $index->columns );

    $sql .= ' )';

    return $sql;
}

sub _make_index_name
{
    shift;
    return substr(shift, 0, 64);
}

sub foreign_key_sql
{
    return;
}

sub drop_column_sql
{
    my $self = shift;
    my %p = @_;

    return 'ALTER TABLE ' . $p{old}->table->name . ' DROP COLUMN ' . $p{old}->name;
}

sub drop_foreign_key_sql
{
    return;
}

sub drop_index_sql
{
    my $self = shift;
    my $index = shift;

    return 'DROP INDEX ' . $self->_make_index_name( $index->id ) . ' ON ' . $index->table->name;
}

sub column_sql_add
{
    my $self = shift;
    my $col = shift;

    my $sequenced = 0;
    if ( ($sequenced = $col->sequenced) )
    {
	$col->set_sequenced(0);
    }

    my $new_sql = $self->column_sql($col);

    if ($sequenced)
    {
	$col->set_sequenced(1);
    }

    return 'ALTER TABLE ' . $col->table->name . ' ADD COLUMN ' . $new_sql;
}

sub column_sql_diff
{
    my $self = shift;
    my %p = @_;
    my $new = $p{new};
    my $old = $p{old};

    my $sequenced = 0;
    if ( ($sequenced = $new->sequenced) && ! $old->sequenced )
    {
	$new->set_sequenced(0);
    }

    my $new_sql = $self->column_sql($new);

    if ($sequenced)
    {
	$new->set_sequenced(1);
    }

    my @sql;
    if ( $new_sql ne $self->column_sql($old) )
    {
	push @sql, 'ALTER TABLE ' . $new->table->name . ' CHANGE COLUMN ' . $new->name . ' ' . $new_sql;
    }

    return @sql;
}

sub foreign_key_sql_diff
{
    return ();
}

sub alter_primary_key_sql
{
    my $self = shift;
    my %p = @_;

    my $new = $p{new};
    my $old = $p{old};

    my @sql;
    push @sql, 'ALTER TABLE ' . $new->name . ' DROP PRIMARY KEY'
	if $old->primary_key;

    if ($new->primary_key)
    {
	my $sql = 'ALTER TABLE  ' . $new->name . ' ADD PRIMARY KEY ( ';
	$sql .= join ', ', map {$_->name} $new->primary_key;
	$sql .= ')';

	push @sql, $sql;
    }

    foreach ($new->primary_key)
    {
	if ( $_->sequenced && ! ( eval { $old->column( $_->name ) } && $old->column_is_primary_key( $_->name ) ) )
	{
	    my $sql = $self->column_sql($_);
	    push @sql, 'ALTER TABLE ' . $new->name . ' CHANGE COLUMN ' . $_->name . ' ' . $sql;
	}
    }

    return @sql;
}

sub reverse_engineer
{
    my $self = shift;
    my $schema = shift;

    my $driver = $schema->driver;

    foreach my $table ( $driver->tables )
    {
	my $t = $schema->make_table( name => $table );
	foreach my $row ( $driver->rows( sql => "DESCRIBE $table" ) )
	{
            my ($type, @a);
            if ( $row->[1] =~ /\A(?:ENUM|SET)/i )
            {
                $type = $row->[1];
            }
            else
            {
                ($type, @a) = split /\s+/, $row->[1];
            }

	    my $default = $row->[4] if $row->[4] && uc $row->[4] ne 'NULL';

	    my $seq = 0;
	    foreach my $a ( split /\s+/, $row->[5] )
	    {
		if ( uc $a eq 'AUTO_INCREMENT' )
		{
		    $seq = 1;
		}
		else
		{
		    push @a, $a;
		}
	    }

	    my %p;
	    if ($type !~ /enum|set/i && $type =~ /(.+)\((\d+)(?:\s*,\s*(\d+))?\)$/)
	    {
		$type = $1;

		# skip defaults
		unless ( $type eq 'tinyint' && $2 == 4 ||
			 $type eq 'smallint' && $2 == 6 ||
			 $type eq 'mediumint' && $2 == 6 ||
			 $type eq 'int' && $2 == 11 ||
			 $type eq 'bigint' && $2 == 21 )
		{
		    $p{length} = $2;
		    $p{precision} = $3;
		}
	    }
	    $type = 'integer' if $type eq 'int';
	    $type = $self->_capitalize_type($type);

 	    my $c = $t->make_column( name => $row->[0],
				     type => $type,
				     nullable => $row->[2] eq 'YES',
				     sequenced => $seq,
				     default => $default,
				     attributes => \@a,
				     %p,
				   );
	    $t->add_primary_key($c) if $row->[3] eq 'PRI';
	}

	my %i;
	foreach my $row ( $driver->rows( sql => "SHOW INDEX FROM $table" ) )
	{
	    next if $row->[2] eq 'PRIMARY';

	    $i{ $row->[2] }{cols}[ $row->[3] - 1 ]{column} = $t->column( $row->[4] );
	    $i{ $row->[2] }{cols}[ $row->[3] - 1 ]{prefix} = $row->[7]
		if defined $row->[7];
	    $i{ $row->[2] }{unique} = $row->[1] ? 0 : 1;
	}

	foreach my $index (keys %i)
	{
	    $t->make_index( columns => $i{$index}{cols},
			    unique  => $i{$index}{unique} );
	}
    }
}

sub rules_id
{
    return 'MySQL';
}

__END__

=head1 NAME

Alzabo::RDBMSRules::MySQL - MySQL specific database rules.

=head1 SYNOPSIS

  use Alzabo::RDBMSRules::MySQL;

=head1 DESCRIPTION

This module implements all the methods descibed in Alzabo::RDBMSRules
for the MySQL database.  The syntax rules follow the more restrictive
rules of version 3.22.

=head1 AUTHOR

Dave Rolsky, <dave@urth.org>

=cut
