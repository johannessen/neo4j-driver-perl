use 5.014;
use strict;
use warnings;
use utf8;

package Neo4j::Record;


sub get {
	my ($self, $field) = @_;
	
	return $self->{row}->[0] if ! defined $field;
	return $self->{row}->[ $self->{column_keys}->key($field) ];
}


1;

__END__
