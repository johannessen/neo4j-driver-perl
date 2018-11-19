use 5.014;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::ResultSummary;
# ABSTRACT: Details about the result of running a statement


use Carp qw(croak);
use Cpanel::JSON::XS 3.0201 qw(decode_json);
use URI;

use Neo4j::Driver::SummaryCounters;


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
