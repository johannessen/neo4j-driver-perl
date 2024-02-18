#!perl
use strict;
use warnings;
use lib qw(./lib t/lib);

my $driver;
use Neo4j_Test;
BEGIN {
	unless ( $driver = Neo4j_Test->driver() ) {
		print qq{1..0 # SKIP no connection to Neo4j server\n};
		exit;
	}
}
my $s = $driver->session;  # only for autocommit transactions


# These tests are for the result summary and statistics.

use Test::More 0.94;
use Test::Exception;
use Test::Warnings 0.010 qw(:no_end_test);
my $no_warnings;
use if $no_warnings = $ENV{AUTHOR_TESTING} ? 1 : 0, 'Test::Warnings';

use Neo4j::Driver;
use Neo4j_Test::MockHTTP;

plan tests => 8 + 1 + $no_warnings;

my $transaction = $driver->session->begin_transaction;


my ($q, $r, $c);


subtest 'result stream interface: consume' => sub {
	plan tests => 7;
	$r = $s->run('RETURN 7 AS n UNION RETURN 11 AS n');
	lives_ok { $c = $r->consume } 'consume()';
	isa_ok $c, 'Neo4j::Driver::ResultSummary', 'summary from consume()';
	ok ! $r->{stream}, 'stream dereferenced';
	ok ! $r->{attached}, 'stream detached';
	ok $r->{exhausted}, 'stream exhausted';
	lives_and { ok ! $r->has_next } 'no has next';
	lives_and { ok ! $r->size } 'no size';
};


subtest 'result stream interface: summary' => sub {
	plan tests => 6;
	$r = $s->run('RETURN 7 AS n UNION RETURN 11 AS n');
	lives_ok { $r->summary } 'summary()';
	ok ! $r->{stream}, 'stream dereferenced';
	ok ! $r->{attached}, 'stream detached';
	ok ! $r->{exhausted}, 'stream not exhausted';
	lives_and { ok $r->has_next } 'has next';
	lives_and { ok $r->size } 'has size';
};


subtest 'ResultSummary' => sub {
	plan tests => 11;
	$q = <<END;
RETURN {fortytwo}
END
	my @params = (fortytwo => 42);
	lives_ok { $r = $s->run($q, @params)->consume; } 'get summary';
	isa_ok $r, 'Neo4j::Driver::ResultSummary', 'ResultSummary';
	isa_ok $r->server, 'Neo4j::Driver::ServerInfo', 'ServerInfo';
	my $param_start = $s->{cypher_params_v2} ? '\$' : '\{';
	lives_and { like $r->statement->{text}, qr/RETURN ${param_start}fortytwo\b/ } 'statement text';
	lives_and { is_deeply $r->statement->{parameters}, {@params} } 'statement params';
	lives_and { ok ! $r->plan; } 'no plan';
	lives_and { is_deeply [$r->notifications], []; } 'no notification';
#	diag explain $r;
	SKIP: { skip 'EXPLAIN unsupported by Neo4j::Bolt', 4 if $Neo4j_Test::bolt;
	$q = <<END;
EXPLAIN MATCH (n), (m) RETURN n, m
END
	lives_ok { $r = $s->run($q)->consume; } 'get summary with plan';
	lives_and { is_deeply $r->statement->{parameters}, {} } 'no params';
	my ($plan, @notifications);
	lives_and { ok $plan = $r->plan; } 'get plan';
	lives_and { ok @notifications = $r->notifications; } 'get notifications';
	# NB: the server is a bit unreliable in providing notifications; if there are problems with this test, restarting the server usually helps
	}
};


my $mock_plugin = Neo4j_Test::MockHTTP->new;
{
no warnings 'qw';
$mock_plugin->response_for(undef, 'zero notes' => { jolt => [qw(
	{"header":{}} {"summary":{"stats":{}}} {"info":{}}
)]});
$mock_plugin->response_for(undef, 'one note' => { jolt => [qw(
	{"header":{}} {"summary":{"stats":{}}} {"info":{"notifications":["foobaz"]}}
)]});
$mock_plugin->response_for(undef, 'two notes' => { jolt => [qw(
	{"header":{}} {"summary":{"stats":{}}} {"info":{"notifications":["foo","bar"]}}
)]});
}
subtest 'summary notifications() wantarray' => sub {
	plan tests => 1 + 3*3;
	my $d = Neo4j::Driver->new('http:');
	$d->plugin($mock_plugin);
	my $sx;
	lives_and { ok $sx = $d->session(database => 'dummy') } 'session';
	lives_and { $r = 0; ok $r = $sx->run('zero notes')->summary } 'run 0';
	lives_and { is_deeply [$r->notifications], [] } '0 notifications';
	lives_and { is scalar($r->notifications), 0 } '0 notifications scalar context';
	lives_and { $r = 0; ok $r = $sx->run('one note')->summary } 'run 1';
	lives_and { is_deeply [$r->notifications], ['foobaz'] } '1 notification';
	lives_and { is scalar($r->notifications), 1 } '1 notification scalar context';
	lives_and { $r = 0; ok $r = $sx->run('two notes')->summary } 'run 2';
	lives_and { is_deeply [$r->notifications], ['foo','bar'] } '2 notifications';
	lives_and { is scalar($r->notifications), 2 } '2 notifications scalar context';
};


subtest 'SummaryCounters: from result' => sub {
	plan tests => 4;
	$q = <<END;
RETURN 42
END
	lives_ok { $r = $s->run($q); } 'run query';
	lives_ok { $c = $r->summary->counters; } 'get counters';
	isa_ok $c, 'Neo4j::Driver::SummaryCounters', 'summary counters';
	lives_and { ok ! $c->contains_updates } 'contains_updates counter';
};


subtest 'SummaryCounters: from single' => sub {
	plan tests => 4;
	$q = <<END;
RETURN 42
END
	lives_ok { $r = $s->run($q)->single; } 'run query';
	lives_ok { $c = $r->summary->counters; } 'get counters';
	isa_ok $c, 'Neo4j::Driver::SummaryCounters', 'summary counters';
	lives_and { ok ! $c->contains_updates } 'contains_updates counter';
};


subtest 'SummaryCounters: updates, properties, labels' => sub {
	plan tests => 4;
	$q = <<END;
CREATE (n)
SET n:Universal:Answer
SET n.value = 42, n.origin = 'Deep Thought'
REMOVE n:Answer
SET n = {}
END
	$c = $transaction->run($q)->summary->counters;
	ok $c->contains_updates, 'contains_updates counter';
	is $c->properties_set, 4, 'properties_set counter';
	is $c->labels_added, 2, 'labels_added counter';
	is $c->labels_removed, 1, 'labels_removed counter';
};


subtest 'SummaryCounters: nodes, relationships' => sub {
	plan tests => 4;
	$q = <<END;
CREATE (d:DeepThought)-[r1:GIVES]->(a:UniversalAnswer)
CREATE (a)-[r2:ORIGIN]->(d)
CREATE (a)-[:ANSWERS]->(q:UniversalQuestion)
DELETE r1, r2, d
END
	$c = $transaction->run($q)->summary->counters;
	is $c->nodes_created, 3, 'nodes_created counter';
	is $c->nodes_deleted, 1, 'nodes_deleted counter';
	is $c->relationships_created, 3, 'relationships_created counter';
	is $c->relationships_deleted, 2, 'relationships_deleted counter';
};


#subtest 'SummaryCounters: constraints, indexes' => sub {
#};


CLEANUP: {
	lives_ok { $transaction->rollback } 'rollback';
}

done_testing;
