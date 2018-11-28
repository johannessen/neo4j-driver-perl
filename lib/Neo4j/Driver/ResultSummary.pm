use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::ResultSummary;
# ABSTRACT: Details about the result of running a statement


use Carp qw(croak);
use Cpanel::JSON::XS 3.0201 qw(decode_json);
use URI 1.25;

use Neo4j::Driver::SummaryCounters;


# https://neo4j.com/docs/rest-docs/current/#rest-api-service-root
our $SERVICE_ROOT_ENDPOINT = '/db/data/';


sub new {
	my ($class, $result, $response, $statement, $tx) = @_; 
	my $self = {};
	if ($result && $result->{stats}) {
		$self->{counters} = $result->{stats};
		$self->{plan} = $result->{plan};
		$self->{notifications} = $response->{notifications};
		$self->{statement} = $statement;
		$self->{client} = $tx->{client};
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
	
	return $self->{notifications} ? @{$self->{notifications}} : () if wantarray;
	return $self->{notifications};
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
	
	# That the ServerInfo is provided by the same object as ResultSummary
	# is an implementation detail that might change in future.
	return $self;
}


# server->
sub address {
	my ($self) = @_;
	
	my $uri = URI->new( $self->{client}->getHost() );
	return $uri->host . ':' . $uri->port;
}


# server->
sub version {
	my ($self) = @_;
	
	# Security issue: Passing this ResultSummary/ServerInfo object to untrusted
	# parties leaks login credentials through REST::Client internals; the same
	# is true for StatementResult objects that include stats.
	# Options:
	# - always make an extra roundtrip at session creation time just for the version number
	# - don't make the server version available at all
	# - document this minor issue for our users and either ignore it or make the behaviour user-selectable
	# - use a different API
	my $json = $self->{client}->GET( $SERVICE_ROOT_ENDPOINT )->responseContent();
	my $neo4j_version = decode_json($json)->{neo4j_version};
	return "Neo4j/$neo4j_version";
}


1;

__END__

=head1 SYNOPSIS

 use Neo4j::Driver;
 my $driver = Neo4j::Driver->new->basic_auth(...);
 
 my $transaction = $driver->session->begin_transaction;
 $transaction->{return_stats} = 1;
 my $result = $transaction->run('MATCH (a)-[:KNOWS]-(b) RETURN a, b');
 my $summary = $result->summary;
 
 # SummaryCounters
 my $counters = $summary->counters;
 
 # query information
 my $query  = $summary->statement->{text};
 my $params = $summary->statement->{parameters};
 my $plan   = $summary->plan;
 my @notes  = @{ $summary->notifications };
 
 # ServerInfo
 my $host_port = $summary->server->address;
 my $version_string = $summary->server->version;
 say "Result from $version_string at $host_port.";

=head1 DESCRIPTION

The result summary of running a statement. The result summary can be
used to investigate details about the result, like the Neo4j server
version, how many and which kinds of updates have been executed, and
query plan information if available.

=head1 METHODS

L<Neo4j::Driver::ResultSummary> implements the following methods.

=head2 counters

 my $summary_counters = $summary->counters;

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

=head2 plan

 use Data::Dumper;
 print Dumper $summary->plan;

This describes how the database will execute your statement.
Available if this is the summary of a Cypher C<EXPLAIN> statement.

=head2 server->address

 my $host_port = $summary->server->address;

The address of the server the query was executed on.

=head2 server->version

 my $version_string = $summary->server->version;

A string telling which version of the server the query was executed on.

=head2 statement

 my $query  = $summary->statement->{text};
 my $params = $summary->statement->{parameters};

The statement and parameters this summary is for.

=head1 EXPERIMENTAL FEATURES

L<Neo4j::Driver::ResultSummary> implements the following experimental
features. These are subject to unannounced modification or removal
in future versions. Expect your code to break if you depend upon
these features.

=head2 Calling in list context

 my @notifications = $summary->notifications;

The C<notifications> method tries to Do What You Mean if called in
list context.

=head1 SEE ALSO

L<Neo4j::Driver>,
L<Neo4j Java Driver|https://neo4j.com/docs/api/java-driver/current/index.html?org/neo4j/driver/v1/summary/ResultSummary.html>,
L<Neo4j JavaScript Driver|https://neo4j.com/docs/api/javascript-driver/current/class/src/v1/result-summary.js~ResultSummary.html>,
L<Neo4j .NET Driver|https://neo4j.com/docs/api/dotnet-driver/current/html/859dfa7c-80b8-f754-c0d3-359a0df5d33b.htm>

=cut
