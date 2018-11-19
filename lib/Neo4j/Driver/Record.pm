use 5.014;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::Record;
# ABSTRACT: container for Cypher result values


use Carp qw(carp croak);
use JSON::PP;

use Neo4j::Driver::ResultSummary;


sub get {
	my ($self, $field) = @_;
	
	return $self->{row}->[0] if ! defined $field;
	my $key = $self->{column_keys}->key($field);
	croak "Field '$field' not present in query result" if ! defined $key;
	return $self->{row}->[$key];
}


# The various JSON modules for Perl tend to represent a boolean false value
# using a blessed scalar overloaded to evaluate to false in Perl expressions.
# This almost always works perfectly fine. However, some tests might not expect
# a non-truthy value to be blessed, which can result in wrong interpretation of
# query results. The get_bool method was meant to ensure boolean results would
# evaluate correctly in such cases. Given that such cases are rare and that no
# specific examples for such cases are currently known, this method now seems
# superfluous.
sub get_bool {
	my ($self, $field) = @_;
	carp __PACKAGE__ . "->get_bool is deprecated";
	
	my $value = $self->get($field);
	return $value if ! ref $value;
	return $value if $value != JSON::PP::false;
	return undef;  ##no critic (ProhibitExplicitReturnUndef)
}


sub summary {
	my ($self) = @_;
	
	$self->{_summary} //= Neo4j::Driver::ResultSummary->new;
	return $self->{_summary}->init;
}


sub stats {
	my ($self) = @_;
	carp __PACKAGE__ . "->stats is deprecated; use summary instead";
	
	return $self->{_summary} ? $self->{_summary}->counters : {};
}


1;

__END__
