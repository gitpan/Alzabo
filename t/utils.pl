sub mysql_clean_schema
{
    my %p = @_;

    print "\n# Removing MySQL database $p{schema_name}\n";

    my $s = Alzabo::Create::Schema->new( name => $p{schema_name},
					 rdbms => 'MySQL' );

    delete @p{ 'schema_name', 'rdbms' };
    $s->drop(%p);
}

sub pg_clean_schema
{
    my %p = @_;

    my $s = Alzabo::Create::Schema->new( name => $p{schema_name},
					 rdbms => 'PostgreSQL' );

    print "\n# Removing PostgreSQL database $p{schema_name}\n";

    delete @p{ 'schema_name', 'rdbms' };
    $s->drop(%p);
}

1;
