package Alzabo::RDBMSRules::MySQL;

use strict;
use vars qw($VERSION);

use Alzabo::RDBMSRules;

use base qw(Alzabo::RDBMSRules);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.25 $ =~ /(\d+)\.(\d+)/;

1;

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    my $self = bless {}, $class;

    return $self;
}

sub validate_schema_name
{
    my $self = shift;
    my $schema = shift;
    my $name = $schema->name;

    # These are characters that are illegal in a dir name.  I'm trying
    # to accomodate both Win32 and UNIX here.
    foreach my $c ( qw( : \ / ) )
    {
	AlzaboRDBMSRulesException->throw( error => "Schema name contains an illegal character ($c)" )
	    if index($name, $c) != -1;
    }
}

# Note: These rules are valid for MySQL 3.22.x.  MySQL 3.23.x is
# actually less restrictive but this should be enough freedom.

sub validate_table_name
{
    my $self = shift;
    my $table = shift;
    my $name = $table->name;

    AlzaboRDBMSRulesException->throw( error => "Name is too long.  Names must be 64 characters or less." )
	if length $name >= 64;
    AlzaboRDBMSRulesException->throw( error => "Name must only contain alphanumerics or underscore(_)." )
	if $name =~ /[^\w]/;
}

sub validate_column_name
{
    my $self = shift;
    my $column = shift;
    my $name = $column->name;

    # Note: Right now this does not respect non Latin-1 charsets.
    AlzaboRDBMSRulesException->throw( error => 'Name is too long.  Names must be 64 characters or less.' )
	if length $name >= 64;
    AlzaboRDBMSRulesException->throw( error =>
				      'Name contains only digits.  Names must contain at least one alpha character.' )
	unless $name =~ /[a-zA-Z]/;
    AlzaboRDBMSRulesException->throw( error =>
				      'Name contains characters that are not alphanumeric or the dollar sign ($).' )
	if $name =~ /[^\w\$]/;
}

sub validate_column_type
{
    my $self = shift;
    my $type = uc shift;

    $type =~ s/\A\s+//;
    $type =~ s/\s+\z//;

    # Columns which take no modifiers.
    my %simple_type = map {$_ => 1} qw( DATE
					DATETIME
					TIME
					TINYBLOB
					TINYTEXT
					BLOB
					TEXT
					MEDIUMBLOB
					MEDIUMTEXT
					LONGBLOB
					LONGTEXT );
    return if $simple_type{$type};

    # More complicated type specs.
    my $max_display = qr{\((\d+)\)};
    my $floating = qr{\((\d+),\s*(\d+)\)};

    if ( $type =~ /\A(?:(?:(?:TINY|SMALL|MEDIUM|BIG)?INT)|INTEGER)\s*$max_display?\z/o )
    {
	AlzaboRDBMSRulesException->throw( error => "Max display value is too long.  Maximum allowed value is 255." )
	    if defined $1 && $1 > 255;
	return;
    }

    if ( $type =~ /\A(?:FLOAT|DOUBLE(?:\s+PRECISION)?|REAL)\s*$floating?\z/o )
    {
	if (defined $1)
	{
	    AlzaboRDBMSRulesException->throw( error => "Max display value is too long.  Maximum allowed value is 255." )
		if $1 > 255;

	    AlzaboRDBMSRulesException->throw( error => "Max display value specified without floating point precision." )
		if ! defined $2;

	    AlzaboRDBMSRulesException->throw( error =>
					      "Floating point precision is too high.  The maximum value is " .
					      "30 or the maximum display size - 2, whichever is smaller." )
		if $2 > 30 || $2 > ($1 - 2);
	}

	return;
    }

    if ( $type =~ /\A(?:DECIMAL|NUMERIC)
                    (?:                   # Optional 1 ...
                       \s*                # space
                       \(                 # opening paren
                         (\d+)            # A digit
                         (?:              # Optional 2 ...
                            ,\s*(\d+)     # comma followed by optional space followed by a digit
                         )?               # end 2
                       \)                 # closing paren
                    )?                    # end 1
                  \z/x )
    {
	AlzaboRDBMSRulesException->throw( error => "Max display value is too long.  Maximum allowed value is 255." )
	    if defined $1 && $1 > 255;
	AlzaboRDBMSRulesException->throw( error => 
					  "Floating point precision is too high.  The maximum value is " .
					  "30 or the maximum display size - 2, whichever is smaller." )
	    if defined $2 && ($2 > 30 || $2 > ($1 - 2) );
	return;
    }

    if ( $type =~ /\ATIMESTAMP\s*$max_display?\z/o )
    {
	AlzaboRDBMSRulesException->throw( error => "Max display value is too long.  Maximum allowed value is 14." )
	    if defined $1 && $1 > 14;
	return;
    }

    if ( $type =~ /\A(?:(?:NATIONAL\s+)?VAR)?CHAR\s*$max_display?\z/o )
    {
	AlzaboRDBMSRulesException->throw( error => "Max display value is too long.  Maximum allowed value is 255." )
	    if defined $1 && $1 > 255;
	return;
    }

    if ($type =~ /\AYEAR\s*$max_display?\z/)
    {
	AlzaboRDBMSRulesException->throw( error => "Valid values for the digit specification are 2 or 4." )
	    if defined $1 && ($1 ne '2' && $1 ne '4');
	return;
    }

    my $list_val = qr{(['"]).*?\1};
    my $comma_sep_list = qr{\($list_val(?:\s*,\s*$list_val)+?\)};

    return if $type =~ /\A(?:ENUM|SET)\s*$comma_sep_list\z/o;

    AlzaboRDBMSRulesException->throw( error => "Unrecognized type: $type" );
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

    return if $a eq 'NULL';
    return if $a =~ /\ANOT\s+NULL\z/;
    return if $a =~ /\APRIMARY\s+KEY\z/;

    return if $a =~ /\ADEFAULT\s+(?:\d+|(['"]).+\1)\z/;

    if ( $a eq 'AUTO_INCREMENT' || $a eq 'UNSIGNED' || $a eq 'ZEROFILL' )
    {
	AlzaboRDBMSRulesException->throw( error => "$a attribute can only be applied to numeric columns" )
	    unless $self->_is_numeric($type);
	return;
    }

    if ($a eq 'BINARY')
    {
	AlzaboRDBMSRulesException->throw( error => "$a attribute can only be applied to character columns" )
	    unless $self->_is_character($type);
	return;
    }

    my $index_col_name = qr{ \w+ # A word
			     # optionally followed by ...
	                     (?:
                               \s*  # 0 or more space chars and ...
                               \(\s*\d+\s*\) # open paren, a number, close paren
                               \s*
                             )?
                           }x;

    my $comma_sep_list = qr{ \(
                               $index_col_name # see above
			       (?:
                                 \s*
                                 ,    # a comma and ...
                                 \s*
                                 $index_col_name # see above
                                 \s*
                               )*
                             \)
                           }x;

    my $ref_option = qr{(?:RESTRICT|CASCADE|SET NULL|NO ACTION|SET DEFAULT)};

    return if $a =~ /\A REFERENCES\s+\w+
		       (?: \s+$comma_sep_list )?
		       (?: \s+MATCH\s+ (?:FULL|PARTIAL) )?
		       (?: \s+ON\s+DELETE\s+$ref_option )?
		       (?: \s+ON\s+UPDATE\s+$ref_option )?
                   \z/xo;

    AlzaboRDBMSRulesException->throw( error => "Unrecognized attribute: $a" );
}

sub validate_primary_key
{
    my $self = shift;
    my $col = shift;

    AlzaboRDBMSRulesException->throw( error => 'Blob columns cannot be part of a primary key' )
	if $col->type =~ /\A(?:TINY|MEDIUM|LONG)?(?:BLOB|TEXT)\z/i;
}

sub validate_sequenced_attribute
{
    my $self = shift;
    my $col = shift;

    AlzaboRDBMSRulesException->throw( error => 'Non-numeric columns cannot be sequenced' )
	unless $self->_is_numeric( $col->type );
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
	    AlzaboRDBMSRulesException->throw( error => "Invalid prefix specification ('$prefix')" )
		unless $prefix =~ /\d+/ && $prefix > 0;

	    AlzaboRDBMSRulesException->throw( error => 'Non-character/blob columns cannot have an index prefix' )
		unless $self->_is_blob( $c->type ) || $self->_is_character( $c->type );
	}

	if ( $self->_is_blob( $c->type ) )
	{
	    AlzaboRDBMSRulesException->throw( error => 'Blob columns must have an index prefix' )
		unless $prefix;
	}
    }
}

sub _is_numeric
{
    my $self = shift;
    my $type = uc shift;

    return 1 if $type =~ /\A(?:
                            (?:TINY|SMALL|MEDIUM|BIG)?
                            INT|INTEGER
                            )
                           |
                           FLOAT|DOUBLE|REAL
                         /x;
}

sub _is_character
{
    my $self = shift;
    my $type = uc shift;

    return 1 if $type =~ /\A(?:(?:NATIONAL\s+)?VAR)?CHAR/;
}

sub _is_blob
{
    my $self = shift;
    my $type = uc shift;

    return 1 if $type =~ /(?:TEXT|BLOB)\z/;
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
				     ($col->null ? 'NULL' : 'NOT NULL'),
				     ($col->sequenced ? 'AUTO_INCREMENT' : () ) );

    my $sql .= join '  ', ( $col->name,
			    $col->type,
			    sort values %attr );

    return $sql;
}

sub index_sql
{
    my $self = shift;
    my $index = shift;

    my @cols = $index->columns;

    my $index_name = $index->id;

    my $sql = 'CREATE';
    $sql .= ' UNIQUE' if $index->unique;
    $sql .= " INDEX $index_name ON " . $index->table->name . ' ( ';

    $sql .= join ', ', ( map { my $sql = $_->name;
			       $sql .= '(' . $index->prefix($_) . ')' if $index->prefix($_);
			       $sql; } @cols );

    $sql .= ' )';

    return $sql;
}

sub foreign_key_sql
{
    return;
}

sub drop_table_sql
{
    my $self = shift;

    return 'DROP TABLE ' . shift->name;
}

sub drop_column_sql
{
    my $self = shift;
    my $col = shift;

    return 'ALTER TABLE ' . $col->table->name . ' DROP COLUMN ' . $col->name;
}

sub drop_index_sql
{
    my $self = shift;
    my $index = shift;

    return 'DROP INDEX ' . $index->id . ' ON ' . $index->table->name;
}

sub drop_foreign_key_sql
{
    return;
}

sub column_sql_add
{
    my $self = shift;
    my $col = shift;

    return 'ALTER TABLE ' . $col->table->name . ' ADD COLUMN ' . $self->column_sql($col);
}

sub column_sql_diff
{
    my $self = shift;
    my %p = @_;
    my $new = $p{new};
    my $old = $p{old};

    my $new_sql = $self->column_sql($new);

    my $sql = 'ALTER TABLE ' . $new->table->name . ' CHANGE COLUMN ' . $new->name . ' ' . $new_sql
	if $new_sql ne $self->column_sql($old);

    return $sql || ();
}

sub index_sql_diff
{
    my $self = shift;
    my %p = @_;
    my $new = $p{new};
    my $old = $p{old};

    my $new_sql = $self->index_sql($new);

    my @sql;
    if ( $new_sql ne $self->index_sql($old) )
    {
	push @sql, $self->drop_index_sql($old);
	push @sql, $new_sql;
    }

    return @sql;
}

sub foreign_key_sql_diff
{
    return;
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
	foreach my $row ( $driver->rows( sql => "DESC $table" ) )
	{
	    my ($type, @a) = split /\s+/, $row->[1];

	    if ($row->[4] && $row->[4] ne 'NULL')
	    {
		$row->[4] = "'$row->[4]'" unless $row->[4] =~ /\A\d+\z/;
		push @a, "DEFAULT $row->[4]";
	    }

	    my $seq = 0;
	    foreach my $a ( split /\s+/, $row->[5] )
	    {
		if ( lc $a eq 'auto_increment' )
		{
		    $seq = 1;
		}
		else
		{
		    push @a, $a;
		}
	    }

 	    my $c = $t->make_column( name => $row->[0],
				     type => $type,
				     null => $row->[2] eq 'YES',
				     sequenced => $seq,
				     attributes => @a ? \@a : [],
				   );
	    $t->add_primary_key($c) if $row->[3] eq 'PRI';
	}

	my %i;
	foreach my $row ( $driver->rows( sql => "SHOW INDEX FROM $table" ) )
	{
	    next if $row->[2] eq 'PRIMARY';

	    $i{ $row->[2] }[ $row->[3] - 1 ]{column} = $t->column( $row->[4] );
	    $i{ $row->[2] }[ $row->[3] - 1 ]{prefix} = $row->[7]
		if defined $row->[7];
	}

	foreach my $index (keys %i)
	{
	    $t->make_index( columns => $i{$index} );
	}
    }
}   



__END__

=head1 NAME

Alzabo::RDBMSRules::MySQL - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Alzabo::RDBMSRules::MySQL;

=head1 DESCRIPTION

This module implements all the methods descibed in Alzabo::RDBMSRules
for the MySQL database.  The syntax rules follow the more restrictive
rules of version 3.22.

=head1 AUTHOR

Dave Rolsky, <dave@urth.org>

=cut
