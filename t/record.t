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


# The following tests are for details of the Record class.

use Test::More 0.96 tests => 2 + 1;
use Test::Exception;
use Test::Warnings qw(warnings);


my ($q, $r);


subtest 'wrong/ambiguous field names for get()' => sub {
	plan tests => 3 + 6 + 6;
	lives_ok { $r = 0; $r = $s->run('RETURN 2, 1 AS NaN, 0')->single; } 'query lives';
	TODO: {
		local $TODO = 'fix to not simply return the first field';
		throws_ok {
			warnings { $r->get; }
		} qr/\bambiguous\b.*\bget\b.*\bfield/i, 'ambiguous get without field';
	}
	lives_and { is $r->get( 1.0 ), 1 } 'get(1.0)';
	# index/key collisions
	is $r->get( 0 ), 2, 'get( 0 )';
	is $r->get("0"), 0, 'get("0")';
	is $r->get( 2 ), 0, 'get( 2 )';
	is $r->get("2"), 2, 'get("2")';
	dies_ok { $r->get("1"); } 'get("1") dies';
	is $r->get(0+"NaN"), 1, 'get(NaN)';
	$q = 'RETURN 1 AS a';
	lives_and { is $s->run($q)->single->get(), 1 } 'unambiguous get without field';
	dies_ok { $s->run($q)->single->get({}); } 'non-scalar field';
	dies_ok { $s->run($q)->single->get(1); } 'index out of bounds';
	dies_ok { $s->run($q)->single->get(-1); } 'index negative';
	dies_ok { $s->run($q)->single->get(.1); } 'index not integer';
	dies_ok { $s->run($q)->single->get("\N{U+0100}"); } 'field not present';
};


subtest 'hashref' => sub {
	plan tests => 2 + 3;
	my $fields = {
		first  => 17,
		second => 19,
		third  => 23,
	};
	$q = 'RETURN {first} AS first, {second} AS second, {third} AS third';
	lives_ok { $r = $s->run($q, $fields)->single->data; } 'get hashref';
	is ref $r, 'HASH', '$r is HASH ref';
	foreach my $key ( sort keys %$fields ) {
		is $r->{$key}, $fields->{$key}, "hashref key $key";
	}
};


done_testing;
