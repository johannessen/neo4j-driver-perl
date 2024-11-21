use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::Type::Bytes;
# ABSTRACT: Represents a Neo4j byte array


# For documentation, see Neo4j::Driver::Types.


use parent -norequire, 'Neo4j::Types::ByteArray';
use overload '""' => \&_overload_stringify, fallback => 1;

use Carp ();


sub as_string {
	return ${+shift};
}


sub _overload_stringify {
	Carp::croak 'Use as_string() to access byte array values';
}


package # Compatibility with Neo4j::Types v1
        Neo4j::Types::ByteArray;


1;
