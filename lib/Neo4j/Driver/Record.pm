use 5.014;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::Record;
# ABSTRACT: container for Cypher result values


use Carp qw(croak);
use JSON::PP;


sub get {
	my ($self, $field) = @_;
	
	return $self->{row}->[0] if ! defined $field;
	my $key = $self->{column_keys}->key($field);
	croak "Field '$field' not present in query result" if ! defined $key;
	return $self->{row}->[$key];
}


sub get_bool {
	my ($self, $field) = @_;
	
	my $value = $self->get($field);
	return $value if ! ref $value;
	return $value if $value != JSON::PP::false;
	return undef;
}


sub stats {
	my ($self) = @_;
	
	return $self->{_stats};
}


1;

__END__
