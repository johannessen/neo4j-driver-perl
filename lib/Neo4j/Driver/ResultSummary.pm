use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::ResultSummary;
# ABSTRACT: Details about the result of running a statement


use Carp qw(croak);

use Neo4j::Driver::SummaryCounters;


sub new {
	my ($class, $result, $notifications, $statement, $server_info) = @_; 
	my $self = {};
	if ($result && $result->{stats}) {
		$self->{counters} = $result->{stats};
		$self->{plan} = $result->{plan};
		$self->{notifications} = $notifications;
		$self->{statement} = $statement;
		$self->{server_info} = $server_info;
	}
	return bless $self, $class;
}


sub init {
	my ($self) = @_; 
	
	# The purpose of this method is to fail as early as possible if we don't
	# have all necessary info. This should improve the user experience.
	croak 'Result missing stats' unless $self->{statement};
	return $self;
}


sub counters {
	my ($self) = @_;
	
	return Neo4j::Driver::SummaryCounters->new( $self->{counters} );
}


sub notifications {
	my ($self) = @_;
	
	$self->{notifications} //= [];
	return @{ $self->{notifications} };
}


sub plan {
	my ($self) = @_;
	
	return $self->{plan};
}


sub statement {
	my ($self) = @_;
	
	return {
		text => $self->{statement}->{statement},
		parameters => $self->{statement}->{parameters} // {},
	};
}


sub server {
	my ($self) = @_;
	
	return $self->{server_info};
}


1;

__END__

=head1 SYNOPSIS

 use Neo4j::Driver;
 $driver = Neo4j::Driver->new->basic_auth(...);
 $result = $driver->session->run('MATCH (a)-[:KNOWS]-(b) RETURN a, b');
 
 $summary = $result->summary;
 
 # SummaryCounters
 $counters = $summary->counters;
 
 # query information
 $query  = $summary->statement->{text};
 $params = $summary->statement->{parameters};
 $plan   = $summary->plan;
 @notes  = $summary->notifications;
 
 # ServerInfo
 $address = $summary->server->address;
 $version = $summary->server->version;

=head1 DESCRIPTION

The result summary of running a statement. The result summary can be
used to investigate details about the result, like the Neo4j server
version, how many and which kinds of updates have been executed, and
query plan information if available.

=head1 METHODS

L<Neo4j::Driver::ResultSummary> implements the following methods.

=head2 counters

 $summary_counters = $summary->counters;

Returns the L<SummaryCounters|Neo4j::Driver::SummaryCounters> with
statistics counts for operations the statement triggered.

=head2 notifications

 use Data::Dumper;
 print Dumper $summary->notifications;

A list of notifications that might arise when executing the
statement. Notifications can be warnings about problematic statements
or other valuable information that can be presented in a client.
Unlike failures or errors, notifications do not affect the execution
of a statement.

At time of this writing, notifications are not supported on a Bolt
connection for this driver.

=head2 plan

 use Data::Dumper;
 print Dumper $summary->plan;

This describes how the database will execute your statement.
Available if this is the summary of a Cypher C<EXPLAIN> statement.

At time of this writing, execution plans are not supported on a Bolt
connection for this driver.

=head2 server

 $address = $summary->server->address;
 $version = $summary->server->version;

The L<ServerInfo|Neo4j::Driver::ServerInfo>, consisting of
the host, port and Neo4j version.

=head2 statement

 $query  = $summary->statement->{text};
 $params = $summary->statement->{parameters};

The statement and parameters this summary is for.

=head1 EXPERIMENTAL FEATURES

L<Neo4j::Driver::ResultSummary> implements the following experimental
features. These are subject to unannounced modification or removal
in future versions. Expect your code to break if you depend upon
these features.

=head2 Calling in scalar context

 $count = $summary->notifications;

The C<notifications()> method returns the number of notifications
if called in scalar context.

Until version 0.25, it returned an array reference instead,
or C<undef> if there were no notifications.

=head1 SEE ALSO

=over

=item * L<Neo4j::Driver>

=item * L<Neo4j::Driver::B<ServerInfo>>,
L<Neo4j::Driver::B<SummaryCounters>>

=item * Equivalent documentation for the official Neo4j drivers:
L<ResultSummary (Java)|https://neo4j.com/docs/api/java-driver/current/index.html?org/neo4j/driver/summary/ResultSummary.html>,
L<ResultSummary (JavaScript)|https://neo4j.com/docs/api/javascript-driver/current/class/src/result-summary.js~ResultSummary.html>,
L<IResultSummary (.NET)|https://neo4j.com/docs/api/dotnet-driver/4.0/html/17958e2b-d923-ab62-bb96-697556493c2e.htm>

=back

=cut
