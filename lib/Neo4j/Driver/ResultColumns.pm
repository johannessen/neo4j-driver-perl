use 5.014;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::ResultColumns;
# ABSTRACT: structure definition of Cypher result values


use Carp qw(croak);


sub new {
	my ($class, $result) = @_;
	
	croak 'Result missing columns' unless $result && $result->{columns};
	my $columns = $result->{columns};
	my $column_keys = {};
	for (my $f = scalar(@$columns) - 1; $f >= 0; $f--) {
		$column_keys->{$columns->[$f]} = $f;
		$column_keys->{$f} = $f;
	}
	
	return bless $column_keys, $class;
}


sub key {
	my ($self, $key) = @_;
	
	return $self->{$key};
}


sub add {
	my ($self, $column) = @_;
	
	my $index = $self->count;
	$self->{$column} = $self->{$index} = $index;
	return $index;
}


sub count {
	my ($self) = @_;
	
	my $column_count = (scalar keys %$self) >> 1;  # each column has two hash entries (numeric and by name)
	return $column_count;
}


1;

__END__
