use 5.014;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::SummaryCounters;
# ABSTRACT: Statement statistics


use Carp qw(croak);


sub new {
	my ($self, $result) = @_;
	
	croak 'Result missing stats' unless $result && $result->{stats};
	return bless $result->{stats}, $self;
}


my @counters = qw(
	constraints_added
	constraints_removed
	contains_updates
	indexes_added
	indexes_removed
	labels_added
	labels_removed
	nodes_created
	nodes_deleted
	properties_set
	relationships_created
);
no strict 'refs';  ##no critic (ProhibitNoStrict)
for my $c (@counters) { *$c = sub { shift->{$c} } }

# relationships_deleted is not provided by the Neo4j server versions 2.3.3, 3.3.5, 3.4.1
# (a relationship_deleted [!] counter is provided, but always returns zero)


1;
