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


# These tests are about the REST and transaction implementation.

use Test::More 0.96 tests => 4 + 2;
use Test::Exception;
my $undo_id;


my ($q, $r);


subtest 'param syntax' => sub {
	plan tests => 9;
	my ($a, $b) = (17, 19);
	$q = <<END;
RETURN {a} AS a, {b} AS b
END
	lives_and { ok $r = $s->run( $q, {a => $a, b => $b} )->single } 'param hashref';
	is $r->get('a') * $r->get('b'), $a * $b, 'param values hashref';
	lives_and { ok $r = $s->run( $q,  a => $a, b => $b  )->single } 'param list';
	is $r->get('a') * $r->get('b'), $a * $b, 'param values list';
	throws_ok {
		$r = $s->run($q, a => $a, b => $b, c => );
	} qr/Odd number of elements .* parameter hash/i, 'param list uneven';
	throws_ok {
		$r = $s->run($q, a => $a);
	} qr/ParameterMissing.* b /si, 'missing param';
	throws_ok {
		$r = $s->run($q, [a => $a, b => $b]);
	} qr/parameters must be .* hash or hashref/i, 'param arrayref';
	throws_ok {
		$r = $s->run( $q, sub { return {a => $a, b => $b} } );
	} qr/parameters must be .* hash or hashref/i, 'sub returning param hashref';
	throws_ok {
		$r = $s->run( $q, sub { return (a => $a, b => $b) } );
	} qr/parameters must be .* hash or hashref/i, 'sub returning param list';
};


subtest 'error handling' => sub {
	plan tests => 6;
	throws_ok { $s->run('iced manifolds.'); } qr/syntax/i, 'cypher syntax error';
	my $q = 'RETURN 42';
	TODO: {
		local $TODO = 'query prep should fail on unblessed references with own error message';
		eval { $s->run(\$q); };
		unlike $@, qr/method "isa" on unblessed reference/i, 'bogus reference query';
	}
	throws_ok { $s->run( bless \$q, 'Neo4j::Test' ); } qr/syntax/i, 'bogus blessed query';
	my $t = $s->begin_transaction;
	$t->{transaction} = '/qwertyasdfghzxcvbn';
	throws_ok { $t->run; } qr/\b404\b/, 'HTTP 404';
	dies_ok {
		Neo4j::Driver->new('http://none.invalid')->session->begin_transaction->run;
		# gives a 500 response with text/plain body that is generated by LWP
	} 'no connection';
	
	# this really just tests Neo4j::Driver
	throws_ok {
		Neo4j::Test->driver_maybe->basic_auth('nobody', '')->session->begin_transaction->run;
	} qr/\b401\b/, 'HTTP 401';
};


subtest 'commit/rollback: edge cases' => sub {
	plan tests => 11;
	my $t = $s->begin_transaction;
	lives_and { ok $t->is_open; } 'beginning open';
	lives_ok { $t->rollback; } 'immediate rollback';
	lives_and { ok ! $t->is_open; } 'immediate rollback closes';
	throws_ok { $t->run; } qr/\bclosed\b/, 'run after rollback';
	throws_ok { $t->rollback; } qr/\bclosed\b/, 'rollback after rollback';
	throws_ok { $t->commit; } qr/\bclosed\b/, 'commit after rollback';
	$t = $s->begin_transaction;
	lives_ok { $t->commit; } 'immediate commit';
	lives_and { ok ! $t->is_open; } 'immediate commit closes';
	throws_ok { $t->run; } qr/\bclosed\b/, 'run after commit';
	throws_ok { $t->commit; } qr/\bclosed\b/, 'commit after commit';
	throws_ok { $t->rollback; } qr/\bclosed\b/, 'rollback after commit';
};


subtest 'commit/rollback: modify database' => sub {
	plan tests => 4 + 9;
	my $entropy = [ time, $$, srand, int 2**31 * rand ];  # some unique numbers
	my $t = $s->begin_transaction;
	
	# make change, commit, check that change has been made
	$q = <<END;
CREATE (n {entropy: {entropy}}) RETURN id(n) AS node_id
END
	lives_and { ok $r = $t->run( $q, entropy => $entropy )->single } 'create node';
	my $node_id = $r->get('node_id');
	$q = <<END;
MATCH (n) WHERE id(n) = {node_id} RETURN n.entropy
END
	lives_and { ok $r = $t->run( $q, node_id => 0 + $node_id ) } 'get node data';
	my $commit_unsafe = @$entropy + (defined $node_id ? 0 : 1);  # `defined` because node id 0 exists in Neo4j
	lives_ok { foreach my $i (0..3) {  # (keys @$entropy)
		$commit_unsafe-- if $r->single->get->[$i] == $entropy->[$i];
	} } 'verify node data';
	ok ! $commit_unsafe, 'commit safe';
	SKIP: {
		skip 'commit: deemed unsafe; something went seriously wrong', 11 if $commit_unsafe;
		$undo_id = $node_id;
		lives_ok { $t->commit; } 'commit';
		$t = $s->begin_transaction;
		$q = <<END;
MATCH (n) WHERE id(n) = {node_id} RETURN n.entropy
END
		lives_and { ok $r = $t->run( $q, node_id => 0 + $node_id ) } 'get committed data';
		my $commit_error = @$entropy;
		lives_ok { foreach my $i (0..3) {  # (keys @$entropy)
			$commit_error-- if $r->single->get->[$i] == $entropy->[$i];
		} } 'verify committed data';
		ok ! $commit_error, 'commit successful';
		
		# make change, rollback, check that change has NOT been made
		$q = <<END;
MATCH (n) WHERE id(n) = {node_id} DELETE n
END
		lives_ok { $t->run( $q, node_id => 0 + $node_id ) } 'try deleting node';
		lives_ok { $t->rollback; } 'rollback';
		$t = $s->begin_transaction;
		$q = <<END;
MATCH (n) WHERE id(n) = {node_id} RETURN n.entropy
END
		lives_and { ok $r = $t->run( $q, node_id => 0 + $node_id ) } 'get data after rollback';
		my $rollback_error = @$entropy;
		lives_ok { foreach my $i (0..3) {  # (keys @$entropy)
			$rollback_error-- if $r->single->get->[$i] == $entropy->[$i];
		} } 'verify data after rollback';
		ok ! $rollback_error, 'rollback successful';
	}
};


CLEANUP: {
	SKIP: {
		skip 'undo: nothing to undo', 2 unless defined $undo_id;  # `defined` because node id 0 exists in Neo4j
		my $t = $driver->session->begin_transaction;
		$t->{return_stats} = 1;
		$q = <<END;
MATCH (n) WHERE id(n) = {node_id} DELETE n
END
		lives_ok { $r = $t->run( $q, node_id => 0 + $undo_id ) } "undo commit [id $undo_id]";
		lives_and { ok $r->summary->counters->nodes_deleted } 'undo commit verified';
	}
}