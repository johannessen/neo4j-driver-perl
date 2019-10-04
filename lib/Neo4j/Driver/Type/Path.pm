use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::Type::Path;
# ABSTRACT: Directed sequence of relationships between two nodes



sub nodes {
	my ($self) = @_;
	
	my @nodes = grep { ref eq 'Neo4j::Driver::Type::Node' } @$self;
	return wantarray ? @nodes : [@nodes];
}


sub relationships {
	my ($self) = @_;
	
	my @rels = grep { ref eq 'Neo4j::Driver::Type::Relationship' } @$self;
	return wantarray ? @rels : [@rels];
}


sub path {
	my ($self) = @_;
	
	return [ @$self ];
}


1;

__END__

=head1 SYNOPSIS

 my $q = "MATCH p=(a:Person)-[k:KNOWS]->(b:Person) RETURN p";
 my $path = $driver->session->run($q)->list->[0]->get('p');
 
 my $node_a = $path->nodes->[0];
 my $node_b = $path->nodes->[1];
 my $relationship_k = $path->relationships->[0];

=head1 DESCRIPTION

A path is a directed sequence of relationships between two nodes.
Its direction may be separate from that of the relationships traversed.

It is allowed to be of length 0, meaning there are no relationships
in it. In this case, it contains only a single node which is both the
start and the end of the path.

=head1 METHODS

L<Neo4j::Driver::Type::Path> implements the following methods.

=head2 nodes

 my $nodes = $path->nodes;

Return all L<nodes|Neo4j::Driver::Type::Node> of this path.

The start node of this path is the first node in the array this method
returns, the end node is the last one.

 my $nodes = $path->nodes;
 my $start_node = $nodes->[0];
 my $end_node   = $nodes->[@$nodes - 1];

=head2 relationships

 my $rels = $path->relationships;

Return all L<relationships|Neo4j::Driver::Type::Relationship>
of this path.

The length of a path is defined as the number of relationships.

 my $rels = $path->relationships;
 my $length = scalar @$rels;

=head1 EXPERIMENTAL FEATURES

L<Neo4j::Driver::Type::Path> implements the following experimental
features. These are subject to unannounced modification or removal
in future versions. Expect your code to break if you depend upon
these features.

=head2 Calling in list context

 my @nodes = $node->nodes;
 my @rels  = $node->relationships;

The C<nodes()> and C<relationships()> methods try to Do What You Mean
if called in list context.

=head2 Direct data structure access

 my $start_node = $path->[0];

Currently, the paths's sequence may be directly accessed as if
the path was a simple arrayref. This is a concession to backwards
compatibility, as the data structure only started being blessed
as an object in version 0.13.

Relying on this implementation detail is deprecated.
Use the accessor methods C<nodes> and C<relationships> instead.

=head2 Path as alternating array

 my $array = $path->path;

Return the path as an array reference, alternating between nodes
and relationships in path sequence order. This is similar to
L<REST::Neo4p::Path>'s C<as_simple()> method.

=head1 BUGS

When paths are returned via HTTP, the objects accessible via
C<nodes()> and C<relationships()> lack meta data for their labels
and types. This is due to an issue in the Neo4j server.

When paths are returned via Bolt, they end up as array references
instead of L<Neo4j::Driver::Type::Path> objects. This is due to
an issue in C<Neo4j::Bolt>
(L<#11|https://github.com/majensen/perlbolt/issues/11>).

=head1 SEE ALSO

L<Neo4j::Driver>,
L<Neo4j Java Driver|https://neo4j.com/docs/api/java-driver/current/org/neo4j/driver/v1/types/Path.html>

=cut
