use strict;

use Alzabo::ObjectCache( store => 'Alzabo::ObjectCache::Store::Memory',
			 sync  => 'Alzabo::ObjectCache::Sync::Null' );

use lib '.', './t';

require 'methodmaker.pl';
