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


# The following tests all look into deprecated, but still available
# functionality. If the behaviour of such functionality changes, we
# want it to be a conscious decision, hence we test for it.

use Test::More 0.96 tests => 1 + 1;
use Test::Exception;
use Test::Warnings qw(warning);


my ($w);


subtest 'close()' => sub {
	plan tests => 4;
	# close() always was a no-op, so we only check the deprecation warning
	$w = '';
	lives_ok { $w = warning { $driver->close; }; } 'Driver close()';
	(like $w, qr/\bdeprecate/, 'Driver close deprecated') or diag 'got warning(s): ', explain($w);
	$w = '';
	lives_ok { $w = warning { $s->close; }; } 'Session close()';
	(like $w, qr/\bdeprecate/, 'Session close deprecated') or diag 'got warning(s): ', explain($w);
};


done_testing;
