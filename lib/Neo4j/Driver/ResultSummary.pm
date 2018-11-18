use 5.014;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::ResultSummary;
# ABSTRACT: Details about the result of running a statement


use parent qw(Neo4j::Driver::SummaryCounters);


sub counters {
	my ($self) = @_;
	
	# That ResultSummary and SummaryCounters are provided by the same object
	# is an implementation detail that might change in the future.
	return $self;
}


1;
