use strict;

use Alzabo::Create;
use Alzabo::Config;
use Cwd;

my $count = 0;
$| = 1;
print "1..6\n";

my $cwd = Cwd::cwd;
$Alzabo::Config::CONFIG{root_dir} = $cwd;

my $new_s = eval { Alzabo::Create::Schema->new( name => 'hello there',
						rdbms => 'MySQL' ); };

ok( $new_s && ! $@,
    "Unable to create a schema named 'hello there': $@" );

eval { Alzabo::Create::Schema->new( name => 'hello:there',
				    rdbms => 'MySQL' ); };

ok( $@,
    "Attempting to create a schema named 'hello:there' should have caused an error" );

my $s = eval { Alzabo::Create::Schema->load_from_file( name => 'foo' ); };

eval { $new_s->make_table( name => 'x' x 65 ) };

ok( $@,
    "Attempting to create a table with a 65 character name should cause an error" );

$s->make_table( name => 'quux' );
my $t4 = $s->table('quux');
$t4->make_column( name => 'foo',
		  type => 'int',
		  attributes => [ 'unsigned' ],
		  null => 1,
		);

my $sql = $s->rules->table_sql($t4);
ok( $sql =~ /int\s+unsigned\s+.*default 1/i,
    "Unsigned attribute should come right after type" );

eval { $t4->make_column( name => 'foo2',
			 type => 'text',
			 length => 1,
		       ); };

ok( $@,
    "Attempt to make 'text' column with a length parameter succeeded" );
ok( $@->isa('Alzabo::Exception::RDBMSRules'),
    "Attempt to make 'text' column with a length parameter failed with unexpected exception: $@" );




sub ok
{
    my $ok = !!shift;
    print $ok ? 'ok ': 'not ok ';
    print ++$count, "\n";
    print "@_\n" if ! $ok;
}
