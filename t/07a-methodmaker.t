use strict;

use File::Spec;

use Alzabo::ObjectCache( store => 'Alzabo::ObjectCache::Store::Memory',
			 sync  => 'Alzabo::ObjectCache::Sync::Null' );

use lib '.', File::Spec->catdir( File::Spec->curdir, 't' );

require 'methodmaker.pl';
