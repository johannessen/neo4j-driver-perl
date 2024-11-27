use v5.12;
use warnings;

package Neo4j::Driver::Type::Node;
# ABSTRACT: Describes a node from a Neo4j graph


# For documentation, see Neo4j::Driver::Types.


use parent 'Neo4j::Types::Node';
use overload '%{}' => \&_hash, fallback => 1;

use Carp qw(croak);


sub get {
	my ($self, $property) = @_;
	
	return $$self->{$property};
}


sub labels {
	my ($self) = @_;
	
	$$self->{_meta}->{labels} //= [];
	return @{ $$self->{_meta}->{labels} };
}


sub properties {
	my ($self) = @_;
	
	my $properties = { %$$self };
	delete $properties->{_meta};
	return $properties;
}


sub element_id {
	my ($self) = @_;
	
	return $$self->{_meta}->{element_id} if defined $$self->{_meta}->{element_id};
	warnings::warnif 'Neo4j::Types', 'element_id unavailable';
	return $$self->{_meta}->{id};
}


sub id {
	my ($self) = @_;
	
	return $$self->{_meta}->{id} if defined $$self->{_meta}->{id};
	
	warnings::warnif deprecated => "Node->id() is deprecated since Neo4j 5; use element_id()";
	my ($id) = $$self->{_meta}->{element_id} =~ m/^4:[^:]*:([0-9]+)/;
	$id = 0 + $id if defined $id;
	return $id;
}
# Unlike Bolt v5, the Jolt v2 format regrettably removes the legacy
# numeric ID from the response entirely. Therefore we generate it
# here using the algorithm from Neo4j's DefaultElementIdMapperV1;
# the final part of the element ID is identical to the legacy ID
# according to CypherFunctions in Neo4j 5.3. This may break with
# future Neo4j versions.
# https://github.com/neo4j/neo4j/blob/0c092b70cc/community/kernel/src/main/java/org/neo4j/kernel/api/DefaultElementIdMapperV1.java#L62-L68
# https://github.com/neo4j/neo4j/blob/0c092b70cc/community/cypher/runtime-util/src/main/java/org/neo4j/cypher/operations/CypherFunctions.java#L771-L802


sub _hash {
	croak 'Use properties() to access Neo4j node properties';
}


1;
