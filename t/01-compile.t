use strict;

# This is just to test whether this stuff compiles.

use Alzabo::Config;

use Alzabo::ChangeTracker;

require Alzabo::ObjectCache;
require Alzabo::ObjectCache::Store::LRU;
require Alzabo::ObjectCache::Store::Memory;
require Alzabo::ObjectCache::Sync::Null;

if ( eval { require IPC::Shareable } && ! $@ )
{
    require Alzabo::ObjectCache::Sync::IPC;
}

if ( eval { require DB_File } && ! $@ )
{
    require Alzabo::ObjectCache::Sync::DB_File;
}

if ( eval { require BerekeleyDB } && ! $@ )
{
    require Alzabo::ObjectCache::Sync::BerkeleyDB;
    require Alzabo::ObjectCache::Store::BerkeleyDB;
}

if ( eval { require SDBM_File } && ! $@ )
{
    require Alzabo::ObjectCache::Sync::SDBM_File;
}

use Alzabo;

use Alzabo::Create;

use Alzabo::Runtime;

use Alzabo::SQLMaker;
use Alzabo::SQLMaker::MySQL;
use Alzabo::SQLMaker::PostgreSQL;

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

require Alzabo::MethodMaker;

print "1..1\n";
print "ok 1\n";
