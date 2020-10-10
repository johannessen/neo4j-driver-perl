#!perl
use strict;
use warnings;
use lib qw(./lib t/lib);

my $driver;
use Neo4j::Test;
BEGIN {
	unless ($driver = Neo4j::Test->driver) {
		print qq{1..0 # SKIP no connection to Neo4j server\n};
		exit;
	}
}
my $s = $driver->session;


# The following tests are for details of the Session class.

use Test::More 0.96 tests => 2;
use Test::Exception;


subtest 'ServerInfo' => sub {
	plan tests => 4;
	my $server;
	lives_ok { $server = $s->server } 'get ServerInfo';
	isa_ok $server, 'Neo4j::Driver::ServerInfo', 'isa ServerInfo';
	lives_and { my $a = $server->address; like(Neo4j::Test->server_address, qr/$a/) } 'server address';
	like $server->version, qr(^Neo4j/\d+\.\d+\.\d), 'server version syntax';
	diag $server->version if $ENV{AUTHOR_TESTING};  # give feedback about which Neo4j version is being tested
};


subtest 'error handling' => sub {
	
	# this really just tests Neo4j::Driver
	throws_ok {
		Neo4j::Test->driver_no_host->session->run('');
	} qr/\bCan't connect\b|\bUnknown host\b/i, 'no connection';
	throws_ok {
		Neo4j::Test->driver_no_auth->session->run('');
	} qr/\bUnauthorized\b|\bpassword is invalid\b/, 'Unauthorized';
};


done_testing;
