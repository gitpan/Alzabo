use strict;

BEGIN
{
    unless ( eval { require DBD::mysql } && ! $@ )
    {
	print "1..0\n";
	exit;
    }
}

use Alzabo::Create;

use lib '.', './t';

require 'base.pl';

eval "use Test::More ( tests => 6 )";
die $@ if $@;

my $new_s;
eval_ok( sub { $new_s = Alzabo::Create::Schema->new( name => 'hello there',
						     rdbms => 'MySQL' ) },
	 "Make a new MySQL schema named 'hello there'" );

eval { Alzabo::Create::Schema->new( name => 'hello:there',
				    rdbms => 'MySQL' ); };

my_isa_ok( $@, 'Alzabo::Exception::RDBMSRules',
	"Attempting to create a MySQL schema named 'hello:there' should throw an Alzabo::Exception::RDBMSRules exception" );

my $s = eval { Alzabo::Create::Schema->load_from_file( name => 'foo_MySQL' ); };

eval { $new_s->make_table( name => 'x' x 65 ) };

my_isa_ok( $@, 'Alzabo::Exception::RDBMSRules',
	"Attempting to create a table in MySQL with a 65 character name should throw an Alzabo::Exception::RDBMSRules exception" );

$s->make_table( name => 'quux' );
my $t4 = $s->table('quux');
$t4->make_column( name => 'foo',
		  type => 'int',
		  attributes => [ 'unsigned' ],
		  null => 1,
		);

my $sql = join '', $s->rules->table_sql($t4);
like( $sql, qr/int(?:eger)\s+unsigned/i,
      "Unsigned attribute should come right after type" );

eval { $t4->make_column( name => 'foo2',
			 type => 'text',
			 length => 1,
		       ); };

my_isa_ok( $@, 'Alzabo::Exception::RDBMSRules',
	"Attempt to make 'text' column with a length parameter should throw an Alzabo::Exception::RDBMSRules exception" );

eval { $t4->make_column( name => 'var_no_len',
			 type => 'varchar' ) };

my_isa_ok( $@, 'Alzabo::Exception::RDBMSRules',
	"Attempt to make 'varchar' column with no length parameter should throw an Alzabo::Exception::RDBMSRules exception" );
