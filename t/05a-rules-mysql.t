#!/usr/bin/perl -w

use strict;

use File::Spec;

use lib '.', File::Spec->catdir( File::Spec->curdir, 't', 'lib' );

use Alzabo::Test::Utils;

use Test::More;


use Alzabo::Create;


unless ( eval { require DBD::mysql } && ! $@ )
{
    plan skip_all => 'needs DBD::mysql';
    exit;
}

plan tests => 11;


my $new_schema;
eval_ok( sub { $new_schema = Alzabo::Create::Schema->new( name => 'hello there',
                                                          rdbms => 'MySQL' ) },
	 "Make a new MySQL schema named 'hello there'" );

{
    eval { Alzabo::Create::Schema->new( name => 'hello:there',
                                        rdbms => 'MySQL' ); };

    my $e = $@;
    isa_ok( $e, 'Alzabo::Exception::RDBMSRules',
            "Exceptiont thrown from attempt to create a MySQL schema named 'hello:there'" );
}

{
    eval { $new_schema->make_table( name => 'x' x 65 ) };
    my $e = $@;
    isa_ok( $e, 'Alzabo::Exception::RDBMSRules',
            "Exception thrown from attempt to create a table in MySQL with a 65 character name" );
}

my $table;
{
    $table = $new_schema->make_table( name => 'quux' );
    $table->make_column( name => 'foo',
                         type => 'int',
                         attributes => [ 'unsigned' ],
                         null => 1,
                       );

    my $sql = join '', $new_schema->rules->table_sql($table);
    like( $sql, qr/int(?:eger)\s+unsigned/i,
          "Unsigned attribute should come right after type" );
}

{
    eval { $table->make_column( name => 'foo2',
                                type => 'text',
                                length => 1,
                              ); };
    my $e = $@;
    isa_ok( $e, 'Alzabo::Exception::RDBMSRules',
            "Exception thrown from attempt to make 'text' column with a length parameter" );
}

{
    eval { $table->make_column( name => 'var_no_len',
                                type => 'varchar' ) };
    my $e = $@;
    isa_ok( $e, 'Alzabo::Exception::RDBMSRules',
            "Exception thrown from attempt to make 'varchar' column with no length parameter" );
}

{
    foreach my $type ( qw( DATE DATETIME TIMESTAMP ) )
    {
        my $col = $table->make_column( name => "col_$type",
                                       type => $type,
                                     );

        ok( $col->is_date, "$type is date" );
    };
}

{
    foreach my $type ( qw( DATETIME TIMESTAMP ) )
    {
        my $col = $table->make_column( name => "col2_$type",
                                       type => $type,
                                     );

        ok( $col->is_datetime, "$type is date" );
    };
}
