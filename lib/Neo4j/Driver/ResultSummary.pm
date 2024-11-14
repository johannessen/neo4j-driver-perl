use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::ResultSummary;
# ABSTRACT: Details about the result of running a statement


use Carp qw(croak);

use Neo4j::Driver::SummaryCounters;


sub new {
	# uncoverable pod (private method)
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


sub _init {
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

 $summary = $session->execute_write( sub ($transaction) {
   return $transaction->run( ... )->consume;
 });
 
 # SummaryCounters
 $counters = $summary->counters;
 
 # Query information
 $query  = $summary->statement->{text};
 $params = $summary->statement->{parameters};
 $plan   = $summary->plan;
 @notes  = $summary->notifications;
 
 # ServerInfo
 $address = $summary->server->address;
 $version = $summary->server->agent;

=head1 DESCRIPTION

The result summary of running a statement. The result summary can be
used to investigate details about the result, like the Neo4j server
version, how many and which kinds of updates have been executed, and
query plan information if available.

To obtain a result summary, call L<Neo4j::Driver::Result/"consume">.

=head1 METHODS

L<Neo4j::Driver::ResultSummary> implements the following methods.

=head2 counters

 $summary_counters = $summary->counters;

Returns the L<SummaryCounters|Neo4j::Driver::SummaryCounters> with
statistics counts for operations the statement triggered.

=head2 notifications

 use Data::Dumper;
 @notifications = $summary->notifications;
 print Dumper @notifications;

A list of notifications that might arise when executing the
statement. Notifications can be warnings about problematic statements
or other valuable information that can be presented in a client.
Unlike failures or errors, notifications do not affect the execution
of a statement.
In scalar context, return the number of notifications.

This driver only supports notifications over HTTP.

=head2 plan

 use Data::Dumper;
 print Dumper $summary->plan;

This describes how the database will execute your statement.
Available if this is the summary of a Cypher C<EXPLAIN> statement.

This driver only supports execution plans over HTTP.

=head2 server

 $address = $summary->server->address;
 $version = $summary->server->agent;

The L<ServerInfo|Neo4j::Driver::ServerInfo>, consisting of
the host, port, protocol and Neo4j version.

=head2 statement

 $query  = $summary->statement->{text};
 $params = $summary->statement->{parameters};

The statement and parameters this summary is for.

=head1 SEE ALSO

=over

=item * L<Neo4j::Driver>

=item * L<Neo4j::Driver::B<ServerInfo>>,
L<Neo4j::Driver::B<SummaryCounters>>

=item * Equivalent documentation for the official Neo4j drivers:
L<ResultSummary (Java)|https://neo4j.com/docs/api/java-driver/5.26/org.neo4j.driver/org/neo4j/driver/summary/ResultSummary.html>,
L<ResultSummary (JavaScript)|https://neo4j.com/docs/api/javascript-driver/5.26/class/lib6/result-summary.js~ResultSummary.html>,
L<IResultSummary (.NET)|https://neo4j.com/docs/api/dotnet-driver/5.26/api/Neo4j.Driver.IResultSummary.html>

=back

=cut
