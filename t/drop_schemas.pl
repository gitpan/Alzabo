sub mysql_drop_schema
{
    my %p = @_;

    my $cs = Alzabo::Create::Schema->load_from_file( name => $p{schema_name} );
    $cs->delete;

    delete @p{ 'schema_name', 'rdbms' };
    eval { $cs->drop(%p); };
    warn $@ if $@;
    $cs->driver->disconnect;
}

sub pg_drop_schema
{
    my %p = @_;

    my $cs = Alzabo::Create::Schema->load_from_file( name => $p{schema_name} );
    $cs->delete;

    delete @p{ 'schema_name', 'rdbms' };

    if ( $pid = fork )
    {
	wait;
	return;
    }
    else
    {
	Test::Builder->no_ending(1);

	my $x = 0;
	while ($x++ <= 10)
	{
	    eval { $cs->drop(%p); };
	    last unless $@;
	    sleep 1;
	}
	warn $@ if $@;
	$cs->driver->disconnect;

	exit;
    }
}

1;
