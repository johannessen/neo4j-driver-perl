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


# The purpose of these tests is to check the behaviour of the StatementResult
# class, particularly for input that is legal, but unusual -- for example,
# due to coding errors on the client's part.

use Test::More 0.96 tests => 5;
use Test::Exception;


my $t = $s->begin_transaction;
my ($q, $r);


subtest 'inappropriate use of single()' => sub {
	plan tests => 2;
	$q = <<END;
RETURN 0 AS n UNION RETURN 1 AS n
END
	throws_ok { $t->run($q)->single; } qr/exactly one/i, 'single called with 2+ records';
	$q = <<END;
RETURN 0 LIMIT 0
END
	throws_ok { $t->run($q)->single; } qr/exactly one/i, 'single called with 0 records';
};


subtest 'result with no statement' => sub {
	plan tests => 3;
	# It is legal to run zero statements, in which case the run method,
	# which normally gives one StatementResult object each for every
	# statement run, must produce an empty StatementResult object for a
	# statement that never existed. This ensures a safe interface that
	# doesn't unexpectedly blow up in the client's face.
	lives_and { is $t->run->size, 0 } 'no query';
	lives_and { is $t->run('')->size, 0 } 'empty query';
	lives_and { is $t->run('RETURN 0 LIMIT 0')->size, 0 } 'one statement with no rows';
};


subtest 'list() repeated' => sub {
	# This test is for a detail of the statement result: A reference
	# to the array of result records can be requested more than once,
	# in which case every request returns a reference to the exact
	# same array.
	plan tests => 1;
	$r = $t->run('RETURN 42');
	is scalar($r->list), scalar($r->list), 'arrayref identical';
};


subtest 'keys()' => sub {
	plan tests => 2;
	$r = $t->run('RETURN 1 AS one, 2 AS two')->keys;
	is $r->[0], 'one', 'key 1';
	is $r->[1], 'two', 'key 2';
};


subtest 'simulate bogus data from server' => sub {
	plan tests => 2;
	$r = $t->run('RETURN 42');
	$r->{result}->{columns} = undef;
	throws_ok { $r->list; } qr/missing columns/i, 'result with no columns field';
	lives_and { is @{ scalar $r->keys }, 0; } 'empty keys list with no columns field';
};


done_testing;
