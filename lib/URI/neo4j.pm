use v5.12;
use warnings;

package URI::neo4j;


use parent 'URI::_server';

sub default_port { 7687 }

1;
