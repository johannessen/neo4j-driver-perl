use v5.12;
use warnings;

package Neo4j::Driver::Type::Path;
# ABSTRACT: Directed sequence of relationships between two nodes


# For documentation, see Neo4j::Driver::Types.


use parent 'Neo4j::Types::Path';
use overload '@{}' => \&_array, fallback => 1;

use Carp qw(croak);


sub nodes {
	my ($self) = @_;
	
	my $i = 0;
	return grep { ++$i & 1 } @{$self->{path}};
}


sub relationships {
	my ($self) = @_;
	
	my $i = 0;
	return grep { $i++ & 1 } @{$self->{path}};
}


sub elements {
	my ($self) = @_;
	
	return @{$self->{path}};
}


sub _array {
	croak 'Use elements() to access Neo4j path elements';
}


1;
