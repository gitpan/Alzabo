#!/usr/bin/perl -w

use strict;

use Alzabo::Create;
use ExtUtils::MakeMaker qw(prompt);
use Getopt::Long;

my $V = $Alzabo::VERSION;

use vars qw($name);
my $s = Alzabo::Create::Schema->load_from_file( name => $ARGV[0] );

my @eval;

push @eval, "use strict;\n\nuse Alzabo::Create::Schema;\n\n";

push @eval, "my (\$t, \$d);\n";

dump_schema($s, 'schema');

push @eval, "\$schema->save_to_file;\n";

print <<"EOF";

The code necessary to recreate $ARGV[0] schema has been created.  You
can either save it disk as a file or evaluate it in place.  Evaluating
it in place will cause your existing $ARGV[0] schema files to be
overwritten.  This is not recommended unless you have made a backup of
your files.

save or eval?

EOF

my $action = prompt( 'Save or eval?', 'save' );

if ($action =~ /^eval$/i)
{
    evaluate_schema();
}
else
{
    save_schema();
}

sub dump_schema
{
    my $s = shift;
    local $name = shift;
    my $recursed = shift;

    push @eval, "my \$$name = Alzabo::Create::Schema->new(";
    my $n = $s->name;
    $n =~ s/'/\\'/g;
    push @eval, "\tname => '$n',";

    my $rdbms;

    if ($V > 0.20)
    {
	$rdbms = $s->driver->driver_id;
    }
    else
    {
	($rdbms) = (split /::/, ref $s->driver)[2];
    }
    push @eval, "\trdbms => '$rdbms',";

    push @eval, ");\n";

    dump_table($_) foreach $s->tables;

    dump_foreign_key($_) foreach map { $_->all_foreign_keys } $s->tables;

    dump_column_ownership($_) foreach map { $_->columns } $s->tables;

    if ($s->instantiated)
    {
	push @eval, "\$$name\->set_instantiated(1);\n";
    }
    if ($s->{original} && not $recursed)
    {
	dump_schema($s->{original}, 'original', 1);
	push @eval, "\$$name\->{original} = \$original;\n";
    }
}

sub dump_table
{
    my $t = shift;

    push @eval, "\$t = \$$name\->make_table(";
    my $n = $t->name;
    $n =~ s/'/\\'/g;
    push @eval, "\tname => '$n',";
    push @eval, ");\n";

    dump_column($_) foreach $t->columns;

    foreach ($t->primary_key)
    {
	push @eval, "\$t->add_primary_key( \$t->column('" . $_->name . "') );";
    }

    dump_index($_) foreach $t->indexes;

    push @eval, "\n";
}

sub dump_column
{
    my $c = shift;

    push @eval, "\$t->make_column(";
    my $n = $c->name;
    $n =~ s/'/\\'/g;
    push @eval, "\tname => '$n',";
    push @eval, "\tsequenced => " . ($c->sequenced ? 1 : 0) . ",";

    my $method = $V < 0.20 ? 'null' : 'nullable';
    push @eval, "\tnullable => " . ($c->$method() ? 1 : 0)  . ",";

    if ($c->attributes)
    {
	my @a;
	foreach ( $c->attributes )
	{
	    if ( /default\s*(.*)/ )
	    {
		my $d = $1;
		$d =~ s/'/\\'/g;
		push @eval, "\tdefault => '$d',";
	    }
	    else
	    {
		push @a, $_;
	    }
	}

	if (@a)
	{
	    push @eval, "\tattributes => [" . (join ', ', map { s/'/\\'/g; "'$_'" } @a) . '],';
	}
    }

    if ($V >= 0.20 && defined $c->default)
    {
	my $d = $c->default;
	$d =~ s/'/\\'/g;
	push @eval, "\tdefault => '$d',";
    }

    my %p;
    $p{type} = $c->type;
    if ($p{type} !~ /enum|set/i && $p{type} =~ /(.+)\((\d+)(?:\s*,\s*(\d+))?\)$/)
    {
	$p{type} = $1;
	$p{length} = $2;
	$p{precision} = $3;
    }

    if ($V >= 0.20 && defined $c->length)
    {
	$p{length} = $c->length;
	$p{precision} = $c->precision;
    }

    while ( my ($k, $v) = each %p )
    {
	next unless defined $v;
	$v =~ s/'/\\'/g;
	push @eval, "\t$k => '$v',";
    }

    push @eval, ");\n";
}

sub dump_index
{
    my $i = shift;

    push @eval, "\$t->make_index(";
    push @eval, "\tunique => " . ($i->unique ? 1 : 0) . ",";
    push @eval, "\tcolumns => [";

    foreach ( $i->columns )
    {
	my %p;
	$p{column} = "\$t->column('" . $_->name . "')";

	if ( defined $i->prefix($_) )
	{
	    $p{prefix} = $i->prefix($_);
	}

	push @eval, "\t\t{ ";

	while ( my ($k, $v) = each %p )
	{
	    push @eval, "\t\t\t$k => $v,";
	}
	push @eval, "\t\t},";
    }

    push @eval, "] );\n";
}

my %fk;
sub dump_foreign_key
{
    my $fk = shift;

    my $id1 = join "\0", map { $fk->$_()->name } qw( column_from column_to table_from table_to );
    $id1 .= "\0";
    $id1 .= join "\0", $fk->min_max_from, $fk->min_max_to;

    my $id2 = join "\0", map { $fk->$_()->name } qw( column_to column_from table_to table_from );
    $id2 .= "\0";
    $id2 .= join "\0", $fk->min_max_to, $fk->min_max_from;

    return if $fk{$id1} || $fk{$id2};

    push @eval, "\$$name\->add_relation(";

    foreach ( qw( table_from table_to ) )
    {
	my $table = $fk->$_()->name;
	push @eval, "\t$_ => \$$name\->table('$table'),";
    }

    foreach ( qw( column_from column_to ) )
    {
	my $table = $fk->$_()->table->name;
	my $column = $fk->$_()->name;

	push @eval, "\t$_ => \$$name\->table('$table')->column('$column'),";
    }

    foreach ( qw( min_max_from min_max_to ) )
    {
	my $mm = join ', ', map { "'$_'" } $fk->$_();
	push @eval, "\t$_ => [ $mm ],";
    }

    push @eval, ");\n";

    $fk{$id1} = $fk{$id2} = 1;
}

sub dump_column_ownership
{
    my $c = shift;

    return if $c eq $c->definition->owner;

    my $table = $c->table->name;
    my $column = $c->name;
    my $owner = $c->definition->owner->name;
    my $owner_table = $c->definition->owner->table->name;
    push @eval, "\$d = \$$name\->table('$owner_table')->column('$owner')->definition;";
    push @eval, "\$$name\->table('$table')->column('$column')->set_definition( \$d );\n";
}

sub evaluate_schema
{
    eval join '', @eval;
    die $@ if $@;

    print "The converted $ARGV[0] schema has been saved\n";
}

sub save_schema
{
    my $file = prompt( "File to which schema should be written?", "$ARGV[0].schema" );

    local *S;
    open S, ">$file" or die "Cannot open file '$file': $!\n";
    unless ( print S (join "\n", @eval) ) { die "Cannot write to file '$file': $!\n"; }
    close S or die "Cannot close file '$file': $!\n";

    print <<"EOF";
The schema has been saved to $file.

To use this file, simply run:

 $^X $file

This will overwrite the existing files for the $ARGV[0] schema
EOF
}
