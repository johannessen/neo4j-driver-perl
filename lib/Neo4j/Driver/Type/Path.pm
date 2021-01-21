use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::Type::Path;
# ABSTRACT: Directed sequence of relationships between two nodes


use parent 'Neo4j::Types::Path';
use overload '@{}' => \&_array, fallback => 1;

use Carp qw(croak);


sub nodes {
	my ($self) = @_;
	
	croak 'nodes() in scalar context not supported' unless wantarray;
	my $i = 0;
	return grep { ++$i & 1 } @{$self->{path}};
}


sub relationships {
	my ($self) = @_;
	
	croak 'relationships() in scalar context not supported' unless wantarray;
	my $i = 0;
	return grep { $i++ & 1 } @{$self->{path}};
}


sub elements {
	my ($self) = @_;
	
	croak 'elements() in scalar context not supported' unless wantarray;
	return @{$self->{path}};
}


sub path {
	my ($self) = @_;
	
	warnings::warnif deprecated => __PACKAGE__ . "->path() is deprecated; use elements()";
	return [ @{$self->{path}} ];
}


sub _array {
	my ($self) = @_;
	
	warnings::warnif deprecated => "Direct array access is deprecated; use " . __PACKAGE__ . "->elements()";
	return $self->{path};
}


# for experimental Cypher type system customisation only
sub _private {
	my ($self) = @_;
	
	$self->{private} //= {};
	return $self->{private};
}


1;

__END__

=head1 SYNOPSIS

 $q = "MATCH p=(a:Person)-[k:KNOWS]->(b:Person) RETURN p";
 $path = $driver->session->run($q)->list->[0]->get('p');
 
 ($node_a, $node_b) = $path->nodes;
 ($relationship_k)  = $path->relationships;
 
 ($a, $k, $b) = $path->elements;

=head1 DESCRIPTION

A path is a directed sequence of relationships between two nodes.
Its direction may be separate from that of the relationships traversed.

It is allowed to be of length 0, meaning there are no relationships
in it. In this case, it contains only a single node which is both the
start and the end of the path.

=head1 METHODS

L<Neo4j::Driver::Type::Path> inherits all methods from
L<Neo4j::Types::Path>.

=head2 elements

 @all = $path->elements;

See L<Neo4j::Types::Path/"elements">.

=head2 nodes

 @nodes = $path->nodes;

See L<Neo4j::Types::Path/"nodes">.

=head2 relationships

 @rels = $path->relationships;

See L<Neo4j::Types::Path/"relationships">.

=head1 EXPERIMENTAL FEATURES

L<Neo4j::Driver::Type::Path> implements the following experimental
features. These are subject to unannounced modification or removal
in future versions. Expect your code to break if you depend upon
these features.

=head2 Calling in scalar context

 $all   = $path->elements;  # fails
 $nodes = $path->nodes;  # fails
 $rels  = $path->relationships;  # fails

The C<elements()>, C<nodes()>, and C<relationships()> methods
C<die> if called in scalar context.

=head1 BUGS

When paths are returned via HTTP, the objects accessible via
C<elements()>, C<nodes()>, and C<relationships()> lack meta data for
their labels and types. This is due to an issue in the Neo4j server.

=head1 SEE ALSO

=over

=item * L<Neo4j::Driver>

=item * L<Neo4j::Types::Path>

=item * Equivalent documentation for the official Neo4j drivers:
L<Path (Java)|https://neo4j.com/docs/api/java-driver/current/index.html?org/neo4j/driver/types/Path.html>

=back

=cut
