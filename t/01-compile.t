use strict;

# This is just to test whether this stuff compiles.

use Alzabo::Config;

use Alzabo::ChangeTracker;

require Alzabo::ObjectCache;
require Alzabo::ObjectCache::MemoryStore;
require Alzabo::ObjectCache::NullSync;

if ( eval { require IPC::Shareable } && ! $@ )
{
    require Alzabo::ObjectCache::IPCSync;
}

if ( eval { require DB_File } && ! $@ )
{
    require Alzabo::ObjectCache::DBMSync;
}

use Alzabo;

use Alzabo::Create;

use Alzabo::Runtime;

use Alzabo::SQLMaker;
use Alzabo::SQLMaker::MySQL;
use Alzabo::SQLMaker::PostgreSQL;
#use Alzabo::SQLMaker::Oracle;

use Alzabo::Driver;
use Alzabo::RDBMSRules;

if ( eval { require DBD::mysql } && ! $@ )
{
    require Alzabo::Driver::MySQL;
    require Alzabo::RDBMSRules::MySQL;
}

if ( eval { require DBD::Pg } && ! $@ )
{
    require Alzabo::Driver::PostgreSQL;
    require Alzabo::RDBMSRules::PostgreSQL;
}


print "1..1\n";
print "ok 1\n";
