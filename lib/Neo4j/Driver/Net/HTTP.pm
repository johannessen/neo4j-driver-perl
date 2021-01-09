use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::Net::HTTP;
# ABSTRACT: Networking delegate for Neo4j HTTP


use Carp qw(croak);
our @CARP_NOT = qw(Neo4j::Driver::Transaction Neo4j::Driver::Transaction::HTTP);

use URI 1.31;

use Neo4j::Driver::Net::HTTP::REST;
use Neo4j::Driver::Result::JSON;
use Neo4j::Driver::Result::Text;
use Neo4j::Driver::ServerInfo;


my $DISCOVERY_ENDPOINT = '/';
my $COMMIT_ENDPOINT = 'commit';

my @RESULT_MODULES = qw( Neo4j::Driver::Result::JSON );
my $RESULT_FALLBACK = 'Neo4j::Driver::Result::Text';


sub new {
	my ($class, $driver) = @_;
	
	my $net_module = $driver->{net_module} // 'Neo4j::Driver::Net::HTTP::REST';
	
	my $self = bless {
		die_on_error => $driver->{die_on_error},
		cypher_types => $driver->{cypher_types},
		http_agent => $net_module->new($driver),
		active_tx => {},
	}, $class;
	
	return $self;
}


# Use Neo4j Discovery API to obtain both ServerInfo and the
# transaction endpoint templates.
sub _server {
	my ($self) = @_;
	
	return $self->{server_info} if exists $self->{server_info};
	
	my ($neo4j_version, $tx_endpoint);
	my @discovery_queue = ($DISCOVERY_ENDPOINT);
	while (@discovery_queue) {
		my $tx = { transaction_endpoint => shift @discovery_queue };
		my $service = $self->_request($tx, 'GET')->_json;
		
		$neo4j_version = $service->{neo4j_version};
		$tx_endpoint = $service->{transaction};
		last if $neo4j_version && $tx_endpoint;
		
		# a different discovery endpoint existed in Neo4j < 4.0
		if ($service->{data}) {
			push @discovery_queue, URI->new( $service->{data} )->path;
		}
	}
	
	croak "Neo4j server not found (ServerInfo discovery failed)" unless $neo4j_version;
	
	$self->{server_info} = Neo4j::Driver::ServerInfo->new({
		uri => $self->{http_agent}->uri,
		version => "Neo4j/$neo4j_version",
		protocol => $self->{http_agent}->protocol,
	});
	
	$self->{endpoints} = {
		new_transaction => "$tx_endpoint",
		new_commit => "$tx_endpoint/$COMMIT_ENDPOINT",
	} if $tx_endpoint;
	
	return $self->{server_info};
}


# Update requested database name based on transaction endpoint templates.
sub _set_database {
	my ($self, $database) = @_;
	
	return unless defined $database;
	$database = URI::Escape::uri_escape_utf8 $database;
	$self->{endpoints}->{new_transaction} =~ s/\{databaseName}/$database/;
	$self->{endpoints}->{new_commit} =~ s/\{databaseName}/$database/;
}


# Send statements to the Neo4j server and return a list of all results.
sub _run {
	my ($self, $tx, @statements) = @_;
	
	my $json = { statements => \@statements };
	return $self->_request($tx, 'POST', $json)->_results;
}


# Determine the Accept HTTP header that is appropriate for the specified
# request method. Accept headers are cached in $self->{accept_for}.
sub _accept_for {
	my ($self, $method) = @_;
	
	# GET requests may fail if Neo4j sees clients that support Jolt, see neo4j #12644
	my @accept = map { $_->_accept_header( $self->{want_jolt}, $method ) } @RESULT_MODULES;
	return $self->{accept_for}->{$method} = join ', ', @accept;
}


# Determine a result handler module that is appropriate for the specified
# media type. Result handlers are cached in $self->{result_module_for}.
sub _result_module_for {
	my ($self, $content_type) = @_;
	
	foreach my $module (@RESULT_MODULES) {
		if ($module->_acceptable($content_type)) {
			return $self->{result_module_for}->{$content_type} = $module;
		}
	}
	return $RESULT_FALLBACK;
}


# Send a HTTP request to the Neo4j server and return a representation
# of the response.
sub _request {
	my ($self, $tx, $method, $json) = @_;
	
	if (! defined $tx->{transaction_endpoint}) {
		$tx->{transaction_endpoint} = URI->new( $self->{endpoints}->{new_transaction} )->path;
	}
	my $tx_endpoint = "$tx->{transaction_endpoint}";
	my $accept = $self->{accept_for}->{$method}
	             // $self->_accept_for($method);
	
	$self->{http_agent}->request($method, $tx_endpoint, $json, $accept);
	
	my $header = $self->{http_agent}->http_header;
	$tx->{closed} = $header->{success};  # see _parse_tx_status() and neo4j #12651
	my $result_module = $self->{result_module_for}->{ $header->{content_type} }
	                    // $self->_result_module_for( $header->{content_type} );
	
	my $result = $result_module->new({
		http_agent => $self->{http_agent},
		http_method => $method,
		http_path => $tx_endpoint,
		http_header => $header,
		die_on_error => $self->{die_on_error},
		cypher_types => $self->{cypher_types},
		server_info => $self->{server_info},
		statements => $json ? $json->{statements} : [],
	});
	
	$self->_parse_tx_status($tx, $header, $result->_info);
	return $result;
}


# Update list of active transactions and update transaction endpoints.
sub _parse_tx_status {
	my ($self, $tx, $header, $info) = @_;
	
	$self->{unused} = 0;
	$tx->{closed} = ! $info->{commit} || ! $info->{transaction};
	
	if ( $tx->{closed} ) {
		my $old_endpoint = $tx->{transaction_endpoint};
		$old_endpoint =~ s|/$COMMIT_ENDPOINT$||;  # both endpoints may be set to /commit (for autocommit), so we need to remove that here
		delete $self->{active_tx}->{ $old_endpoint };
	}
	elsif ($header->{location} && $header->{status} eq '201') {  # Created
		my $new_commit = URI->new( $info->{commit} )->path_query;
		my $new_endpoint = URI->new( $header->{location} )->path_query;
		$tx->{commit_endpoint} = $new_commit;
		$tx->{transaction_endpoint} = $new_endpoint;
		$self->{active_tx}->{ $new_endpoint } = 1;
	}
}


# Query list of active transactions.
sub _is_active_tx {
	my ($self, $tx) = @_;
	
	my $tx_endpoint = $tx->{transaction_endpoint};
	$tx_endpoint =~ s|/$COMMIT_ENDPOINT$||;  # for tx in the (auto)commit state, both endpoints are set to commit
	return exists $self->{active_tx}->{ $tx_endpoint };
}



1;

__END__

=head1 DESCRIPTION

The L<Neo4j::Driver::Net::HTTP> package is not part of the
public L<Neo4j::Driver> API.

=cut
