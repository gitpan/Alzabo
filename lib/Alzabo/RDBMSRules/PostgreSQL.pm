package Alzabo::RDBMSRules::PostgreSQL;

use strict;
use vars qw($VERSION);

use Alzabo::RDBMSRules;

use base qw(Alzabo::RDBMSRules);

$VERSION = sprintf '%2d.%02d', q$Revision: 1.8 $ =~ /(\d+)\.(\d+)/;

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

    $self->_check_name($name, 'schema');

    Alzabo::Exception::RDBMSRules->throw( error => "Schema name ($name) contains a single quote char (')" )
	if index($name, "'") != -1;
}

sub validate_table_name
{
    my $self = shift;

    $self->_check_name( shift->name, 'table' );
}

sub validate_column_name
{
    my $self = shift;

    $self->_check_name( shift->name, 'column' );
}

sub _check_name
{
    my $self = shift;
    my $name = shift;

    Alzabo::Exception::RDBMSRules->throw( error => "\u$name name name must at least one character long" )
	unless length $name;
    Alzabo::Exception::RDBMSRules->throw( error => '\u$name name ($name) is too long.  Names must be 31 characters or less.' )
	if length $name >= 31;
    Alzabo::Exception::RDBMSRules->throw( error => "\u$name name ($name) must start with an alpha or underscore(_) and must contain only alphanumerics and underscores." )
	unless $name =~ /^[^\W\d]\w/;
}

sub validate_column_type
{
    my $self = shift;
    my $type = uc shift;

    my %simple_types = map { $_ => 1 } qw( BOOL
					   BOOLEAN
					   BOX
					   CHAR
					   CHARACTER
					   CIDR
					   CIRCLE
					   DATE
					   DECIMAL
					   FLOAT
					   FLOAT4
					   FLOAT8
					   INET
					   SMALLINT
					   INT
					   INTEGER
					   INT2
					   INT4
					   INT8
					   INTERVAL
					   LINE
					   LSEG
					   MONEY
					   NUMERIC
					   OID
					   PATH
					   POINT
					   POLYGON
					   SERIAL
					   TEXT
					   TIME
					   TIMETZ
					   TIMESTAMP
					   VARCHAR );

    return if $simple_types{$type};

    return if $type =~ /CHARACTER\s+VARYING/;

    Alzabo::Exception::RDBMSRules->throw( error => "Invalid column type: $type" );
}

sub validate_column_length
{
    my $self = shift;
    my $column = shift;

    if ( defined $column->length )
    {
	Alzabo::Exception::RDBMSRules->throw( error => "Length is not supported except for char, varchar, decimal, float, numeric columns (" . $column->name . " column)" )
	    unless $column->type =~ /\A(?:(?:VAR)CHAR|CHARACTER|DECIMAL|FLOAT|NUMERIC)\z/i;
    }

    if ( defined $column->precision )
    {
	Alzabo::Exception::RDBMSRules->throw( error => "Precision is not supported except for decimal, float, numeric columns" )
	    unless $column->type =~ /\A(?:DECIMAL|FLOAT|NUMERIC)\z/i;
    }
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

    return if  $a =~ /\A(?:CHECK|CONSTRAINT|REFERENCES)/i;

    Alzabo::Exception::RDBMSRules->throw( error => "Only column constraints are supported as column attributes" )
}

sub validate_primary_key
{
    1;
}

sub validate_sequenced_attribute
{
    my $self = shift;
    my $col = shift;

    Alzabo::Exception::RDBMSRules->throw( error => 'Non-numeric columns cannot be sequenced' )
	unless $self->type_is_numeric( $col->type );
}

sub validate_index
{
    my $self = shift;
    my $index = shift;

    foreach my $c ( $index->columns )
    {
	my $prefix = $index->prefix($c);
	Alzabo::Exception::RDBMSRules->throw( error => "PostgreSQL does not support index prefixes" )
	    if defined $index->prefix($c)
    }
}

sub type_is_numeric
{
    my $self = shift;
    my $type = uc shift;

    return 1 if $type =~ /\A(?:
                             DECIMAL|
			     FLOAT(?:4|8)?|
			     INT(?:2|4|8)?|
			     SMALLINT
			     INTEGER|
			     MONEY|
			     NUMERIC|
			     OID|
			     SERIAL
			    )
                          \z
                         /x;
}

sub type_is_char
{
    my $self = shift;
    my $type = uc shift;

    return 1 if $type =~ /\A(?:(?:VAR)?CHAR|CHARACTER|TEXT)\z/;
}

sub type_is_blob
{
    return 0;
}

sub _start_sql
{
    my $self = shift;
    $self->{sql_made} = {};
}

sub _end_sql
{
    my $self = shift;
    $self->{sql_made} = {};
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

    foreach my $c ( $table->columns )
    {
	push @sql, $self->_sequence_sql($c) if $c->sequenced;
    }

    $self->{sql_made}{table_sql}{ $table->name } = 1;

    return @sql;
}

sub _sequence_sql
{
    my $self = shift;
    my $col = shift;

    my $seq_name = join '___', $col->table->name, $col->name;

    return "CREATE SEQUENCE $seq_name;\n";
}

sub column_sql
{
    my $self = shift;
    my $col = shift;

    my @default;
    if ( defined $col->default )
    {
	my $def = ( $col->is_character ?
		    do { my $d = $col->default; $d =~ s/"/""/g; qq|'$d'| } :
		    $col->default );
	@default = ( "DEFAULT $def" );
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
			    @default,
			    $col->nullable ? 'NULL' : 'NOT NULL',
			    $col->attributes );

    return $sql;
}


sub foreign_key_sql
{
    return;
}

sub drop_column_sql
{
    my $self = shift;
    my %p = @_;

    # This is a hack to prevent this SQL from being made multiple
    # times (which would be pointless)
    return () if $self->{sql_made}{table_sql}{ $p{new_table}->name };

    return ( $self->_temp_table_sql( $p{new_table} ),
	     $self->drop_table_sql( $p{old}->table ),
	     $self->table_sql( $p{new_table} ),
	     $self->_restore_table_data_sql( $p{new_table} ),
	   );
}

sub _temp_table_sql
{
    my $self = shift;
    my $table = shift;

    my $temp_name = "TEMP" . $table->name;

    my $sql = "SELECT ";
    $sql .= join ', ', map { $_->name } $table->columns;
    $sql .= "\n INTO TEMPORARY $temp_name FROM " . $table->name;

    return $sql;
}

sub _restore_table_data_sql
{
    my $self = shift;
    my $table = shift;

    my $temp_name = "TEMP" . $table->name;

    my $sql = "SELECT ";
    $sql .= join ', ', map { $_->name } $table->columns;
    $sql .= "\n INTO " . $table->name . " FROM $temp_name";

    return $sql;
}

sub drop_foreign_key_sql
{
    return;
}

sub drop_index_sql
{
    my $self = shift;
    my $index = shift;

    return 'DROP INDEX ' . $index->id;
}

sub column_sql_add
{
    my $self = shift;
    my $col = shift;

    my @sql = 'ALTER TABLE ' . $col->table->name . ' ADD COLUMN ' . $self->column_sql($col);

    my $default;
    if ( $col->default )
    {
	my $def = ( $col->is_character ?
		    do { my $d = $col->default; $d =~ s/"/""/g; qq|'$d'| } :
		    $col->default );
	$default = ( 'DEFAULT $def' );

	push @sql, ( 'ALTER TABLE ' . $col->table->name . ' ALTER COLUMN ' . $col->name . " SET $default" );
    }

    return @sql;
}

sub column_sql_diff
{
    my $self = shift;
    my %p = @_;

    return $self->drop_column_sql( new_table => $p{new}->table,
				   old => $p{old} )
	if $self->column_sql($p{new}) ne $self->column_sql($p{old});


    return;
}

sub foreign_key_sql_diff
{
    return;
}

sub alter_primary_key_sql
{
    my $self = shift;
    my %p = @_;

    my @sql;
    push @sql, 'DROP INDEX ' . $p{old}->name . '_pkey';

    if ( $p{new}->primary_key )
    {
	push @sql, ( 'CREATE INDEX ' . $p{new}->name . '_pkey (' .
		     ( join ', ', map { $_->name } $p{new}->primary_key ) . ')' );
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


	my $t_oid = $driver->one_row( sql => 'SELECT oid FROM pg_class WHERE relname = ?',
				      bind => lc $table );

	my $sql = <<'EOF';
SELECT a.oid, a.attname, a.attnotnull, t.typname, a.attnum, a.atthasdef, a.atttypmod
FROM pg_attribute a, pg_type t
WHERE a.attrelid = ?
AND a.atttypid = t.oid
AND a.attnum > 0
ORDER BY attnum
EOF

	foreach my $row ( $driver->rows( sql => $sql,
					 bind => $t_oid ) )
	{
	    my %p;
	    # has default
	    if ( $row->[5] )
	    {
		$p{default} =
		    $driver->one_row( sql => 'SELECT adsrc FROM pg_attrdef WHERE adrelid = ? AND adnum = ?',
				      bind => [ $t_oid, $row->[4] ] );
		# strip quotes Postgres added
		for ($p{default}) { s/^'//; s/'$//; }
	    }

	    if ( $row->[3] =~ /char/ )
	    {
		# The real length is the value of: a.atttypmod - ((int32) sizeof(int32))
		#
		# Sure wish I knew how to figure this out in Perl.
		# Its provided as VARHDRSZ in postgres.h but I can't
		# really get at it.  On my linux machine this is 4.  A
		# better way of doing this would be welcome.
		$p{length} = $row->[6] - 4;
	    }
	    if ( $row->[3] eq 'numeric' )
	    {
		# see comment above.
		my $num = $row->[6] - 4;
		$p{length} = ($num >> 16) & 0xffff;
		$p{precision} = $num & 0xffff;
	    }

	    $t->make_column( name => $row->[1],
			     nullable => ! $row->[2],
			     type => $row->[3],
			     %p
			   );
	}


	$sql = <<'EOF';
SELECT a.attname
FROM pg_index i, pg_attribute a, pg_class c
WHERE i.indrelid = ?
AND i.indisprimary
AND i.indexrelid = c.oid
AND c.oid = a.attrelid
AND a.attnum > 0
ORDER BY a.attnum
EOF

	foreach my $col ( $driver->column( sql => $sql,
					   bind => $t_oid ) )
	{
	    $t->add_primary_key( $t->column($col) );
	}


	$sql = <<'EOF';
SELECT c.oid, a.attname, i.indisunique
FROM pg_index i, pg_attribute a, pg_class c
WHERE i.indrelid = ?
AND NOT i.indisprimary
AND i.indexrelid = c.oid
AND c.oid = a.attrelid
AND a.attnum > 0
ORDER BY a.attnum
EOF

	my %i;
	foreach my $row ( $driver->rows( sql => $sql,
					 bind => $t_oid ) )
	{
	    push @{ $i{ $row->[0] }{cols} }, $t->column($row->[1]);
	    $i{ $row->[0] }{unique} = $row->[2];
	}

	foreach my $oid (keys %i)
	{
	    my @c = map { { column => $_ } } @{ $i{$oid}{cols} };
	    $t->make_index( columns => \@c,
			    unique => $i{$oid}{unique} );
        }
    }
}

sub rules_id
{
    return 'PostgreSQL';
}

__END__

=head1 NAME

Alzabo::RDBMSRules::PostgreSQL - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Alzabo::RDBMSRules::PostgreSQL;

=head1 DESCRIPTION

This module implements all the methods descibed in Alzabo::RDBMSRules
for the PostgreSQL database.  The syntax rules follow those of the 7.0
releases.  Older versions may work but are not supported.

=head1 AUTHOR

Dave Rolsky, <dave@urth.org>

=cut
