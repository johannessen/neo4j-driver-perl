package Neo4j::Test;
use strict;
use warnings;

use URI;
use Neo4j::Driver;
use Neo4j::Sim;

my $ok;


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
	
	my $user = $ENV{TEST_NEO4J_USERNAME} || 'neo4j';
	my $pass = $ENV{TEST_NEO4J_PASSWORD};
	$driver->basic_auth($user, $pass);
	
	return $driver;
}


# returns a driver that is known to work
sub driver {
	my $driver = driver_maybe;
	
	$bolt = $driver->{uri} && $driver->{uri}->scheme eq 'bolt';
	if (! $ENV{TEST_NEO4J_PASSWORD} && $driver && ! $bolt) {
		# the driver has no chance of connecting to a real database via
		# HTTP without a password, so we use the REST simulator instead
		$driver->{client_factory} = Neo4j::Sim->factory;
		$sim = 1;
	}
	
	# verify that the supplied credentials actually work
	eval {
		# the Neo4j HTTP API allows running empty statements
		$driver->session->run('');
	};
	return if $@;
	
	$ok = 1;
	return $driver;
}


# used for testing driver readiness
sub driver_ok { $ok }


# used for the ResultSummary/ServerInfo test
sub server_address {
	return 'localhost:7474' unless $ENV{TEST_NEO4J_SERVER};
	return '' . URI->new( $ENV{TEST_NEO4J_SERVER} )->host_port;
}


1;

__END__

These environment variables can be specified either in the shell (using
export/setenv) or in dist.ini (when using `dzil test`). At the very least,
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
