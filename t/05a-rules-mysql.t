use strict;

use Test::More;

BEGIN
{
    unless ( eval { require DBD::mysql } && ! $@ )
    {
        plan skip_all => 'needs DBD::mysql';
	exit;
    }
}

use Alzabo::Create;

use lib '.', File::Spec->catdir( File::Spec->curdir, 't' );

require 'base.pl';

plan tests => 6;

my $new_s;
eval_ok( sub { $new_s = Alzabo::Create::Schema->new( name => 'hello there',
						     rdbms => 'MySQL' ) },
	 "Make a new MySQL schema named 'hello there'" );

eval { Alzabo::Create::Schema->new( name => 'hello:there',
				    rdbms => 'MySQL' ); };

my $e = $@;
isa_ok( $e, 'Alzabo::Exception::RDBMSRules',
	"Exceptiont thrown from attempt to create a MySQL schema named 'hello:there'" );

my $s = eval { Alzabo::Create::Schema->load_from_file( name => 'foo_MySQL' ); };

eval { $new_s->make_table( name => 'x' x 65 ) };
$e = $@;
isa_ok( $e, 'Alzabo::Exception::RDBMSRules',
	"Exception thrown from attempt to create a table in MySQL with a 65 character name" );

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
$e = $@;
isa_ok( $e, 'Alzabo::Exception::RDBMSRules',
	"Exception thrown from attempt to make 'text' column with a length parameter" );

eval { $t4->make_column( name => 'var_no_len',
			 type => 'varchar' ) };
$e = $@;
isa_ok( $e, 'Alzabo::Exception::RDBMSRules',
	"Exception thrown from attempt to make 'varchar' column with no length parameter" );
