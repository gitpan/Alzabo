# This is just to test whether this stuff compiles.

use Alzabo::Config;

use Alzabo::ChangeTracker;

use Alzabo::ObjectCacheIPC;

use Alzabo;

use Alzabo::Create;

use Alzabo::Runtime;

use Alzabo::Driver;
use Alzabo::Driver::MySQL;
use Alzabo::Driver::PostgreSQL;
#use Alzabo::Driver::Oracle;

use Alzabo::RDBMSRules;
use Alzabo::RDBMSRules::MySQL;
use Alzabo::RDBMSRules::PostgreSQL;
#use Alzabo::RDBMSRules::Oracle;

use Alzabo::SQLMaker;
use Alzabo::SQLMaker::MySQL;
use Alzabo::SQLMaker::PostgreSQL;
#use Alzabo::SQLMaker::Oracle;


print "1..1\n";
print "ok 1\n";