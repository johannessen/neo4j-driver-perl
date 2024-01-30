use 5.010;
use strict;
use warnings;

package URI::neo4j;


use parent 'URI::_server';

sub default_port { 7687 }

1;
