package Neo4j::Test;
use strict;
use warnings;

use URI;
use Neo4j::Driver;
use Neo4j::Driver::Net::HTTP::REST;
use Neo4j::Sim;


our $error = '';

# may be used for conditional testing
our $bolt;
our $sim;


# returns a driver that might or might not work
sub driver_maybe {
	
	my $driver;
	eval {
		# a default URI (localhost) is built into the driver
		$driver = Neo4j::Driver->new( $ENV{TEST_NEO4J_SERVER} );
	};
	return unless $driver;
	
	my $user = $ENV{TEST_NEO4J_USERNAME} // 'neo4j';
	my $pass = $ENV{TEST_NEO4J_PASSWORD} // '';
	$driver->basic_auth($user, $pass);
	$driver->config(timeout => 2);  # 2 seconds timeout may speed up testing
	$driver->config(cypher_filter => 'params') if ($ENV{NEO4J} // 0) =~ m/^4\b/;
	
	$bolt = $driver->{uri} && $driver->{uri}->scheme eq 'bolt';
	if (! $ENV{TEST_NEO4J_PASSWORD} && ! $bolt) {
		# without a password, we use the REST simulator instead
		$driver->config(net_module => 'Neo4j::Driver::Net::HTTP::REST');
		$driver->{client_factory} = Neo4j::Sim->factory;
		$driver->config(cypher_filter => 'params');  # sim uses modern param syntax
		$sim = 1;
	}
	
	return $driver;
}


# returns a driver that is known to work
sub driver {
	my $driver = driver_maybe;
	
	# verify that the supplied credentials actually work
	eval {
		# the Neo4j HTTP API allows running empty statements
		$driver->session->run('');
	};
	if ($@) {
		$error = $@;
		return;
	}
	
	return $driver;
}


# returns a driver that is expected to fail (no connection)
sub driver_no_connect {
	# NXDOMAIN via DNS is slow; Port 14 is unassigned and should be closed
	driver_maybe;  # init $bolt
	my $driver = Neo4j::Driver->new(($bolt ? 'bolt' : 'http') . '://localhost:14');
	return $driver;
}


# returns a driver that is expected to fail (unauthorized)
sub driver_no_auth {
	my $driver = driver_maybe;
	$driver->{auth} = { scheme => 'basic', principal => "no\tuser", credentials => "no\tpass" };
	$driver->{client_factory} = Neo4j::Sim->factory(auth => 0) if $sim;
	return $driver;
}


# returns a transaction not connected to a server
# (convenience for unit tests)
sub transaction_unconnected {
	my (undef, $driver) = @_;
	
	$driver //= Neo4j::Driver->new;
	my $session = Neo4j::Driver::Session::HTTP->new( $driver );
	my $transaction = Neo4j::Driver::Transaction::HTTP->new( $session );
	return $transaction;
}


# used for the ResultSummary/ServerInfo test
sub server_address {
	return 'localhost:7474' unless $ENV{TEST_NEO4J_SERVER};
	return 'localhost:7687' if $ENV{TEST_NEO4J_SERVER} =~ m{^bolt:(?://(?:localhost\b)?)?}i;
	return '' . (URI->new( $ENV{TEST_NEO4J_SERVER} )->host_port // '');
}


1;

__END__

These environment variables can be specified either in the shell (using
export/setenv) or in dist.ini (when using `dzil test`). The driver
does support connecting to a Neo4j server with authentication disabled.
However, without a password, these tests will never attempt a server
connection, instead relying on the REST simulator (Neo4j::Sim).
To execute these tests on a real Neo4j server, at the very least
the password is required. If the password is the only available setting,
default values will be used for the server URI and user name.

Examples:


#! bash

export TEST_NEO4J_SERVER=http://127.0.0.1:7474
export TEST_NEO4J_USERNAME=neo4j
export TEST_NEO4J_PASSWORD=neo4j


#! csh

setenv TEST_NEO4J_SERVER http://127.0.0.1:7474
setenv TEST_NEO4J_USERNAME neo4j
setenv TEST_NEO4J_PASSWORD neo4j
