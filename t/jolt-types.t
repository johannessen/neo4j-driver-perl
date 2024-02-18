#!perl
use strict;
use warnings;
use lib qw(./lib t/lib);

use Test::More 0.94;
use Test::Exception;
use Test::Warnings 0.010 qw(:no_end_test);
my $no_warnings;
use if $no_warnings = $ENV{AUTHOR_TESTING} ? 1 : 0, 'Test::Warnings';

use Neo4j_Test;
use Neo4j_Test::MockHTTP;

my $mock_plugin = Neo4j_Test::MockHTTP->new;
sub response_for { $mock_plugin->response_for(undef, @_) }

sub single_column {[
	{ header => { fields => [0] } },
	(map {{ data => [$_] }} @_),
	{ summary => {} },
	{ info => {} },
]}

response_for 'property' => { jolt => single_column(
	undef,
	{ '?' => 'true' },
	{ '?' => 'false' },
	{ 'Z' => '13' },
	{ 'R' => '0.5' },
	{ 'U' => 'hello' },
	{ '#' => '466F6F' },  # hex, see neo4j#12660
)};

response_for 'property sparse' => { jolt => single_column(
	\1,
	\0,
	17,
	'world',
)};

response_for 'composite' => { jolt => single_column(
	{ '[]' => [{ Z => '23' }, { Z => '29' }] },
	{ '{}' => { a => { Z => '31' }, b => { Z => '37' } } },
	{ '[]' => [{ '{}' => { c => { Z => '41' } } }] },
	{ '{}' => { X => { '[]' => [{ U => 'Y' }, { U => 'Z' }] } } },
	{ '[]' => [] },
	{ '{}' => {} },
)};

response_for 'composite sparse' => { jolt => single_column(
	[23, 29],
	[{ '{}' => { c => { Z => '41' } } }],
	{ '{}' => { X => ['Y', 'Z'] } },
	[],
)};

response_for 'structural v1' => { jolt => single_column(
	{ '()' => [ 101, ['Test'], { p => { Z => '59'} } ] },
	{ '()' => [ 103, ['Test', 'N'], { p1 => 61, p2 => 67 } ] },
	{ '->' => [ 233, 101, 'FOO', 103, { p => { Z => '71'} } ] },
	{ '<-' => [ 239, 101, 'BAR', 103, {} ] },
	{ '<-' => [ 0, 0, 'NIL', 0, {} ] },
)};

response_for 'structural paths v1' => { jolt => single_column(
	{ '..' => [
			{ '()' => [ 311, ['Test'], { p => 59 } ] },
			{ '->' => [ 307, 311, 'TEST', 313, { p1 => { Z => '73'}, p2 => { Z => '79'} } ] },
			{ '()' => [ 313, ['Test'], {} ] },
		] },
	{ '..' => [ { '()' => [ 409, [], {} ] } ] },
)};

response_for 'structural v2' => {
	content_type => 'application/vnd.neo4j.jolt-v2+json-seq',
	jolt => single_column(
	{ '()' => [ '4:db:101', ['Test'], { p => { Z => '59'} } ] },
	{ '()' => [ '4:db:103', ['Test', 'N'], { p1 => 61, p2 => 67 } ] },
	{ '->' => [ '5:db:233', '4:db:101', 'FOO', '4:db:103', { p => { Z => '71'} } ] },
	{ '<-' => [ '5:db:239', '4:db:101', 'BAR', '4:db:103', {} ] },
	{ '<-' => [ '5:db:0', '4:db:0', 'NIL', '4:db:0', {} ] },
)};

response_for 'structural paths v2' => {
	content_type => 'application/vnd.neo4j.jolt-v2+json-seq',
	jolt => single_column(
	{ '..' => [
			{ '()' => [ '4:db:311', ['Test'], { p => 59 } ] },
			{ '->' => [ '5:db:307', '4:db:311', 'TEST', '4:db:313', { p1 => { Z => '73'}, p2 => { Z => '79'} } ] },
			{ '()' => [ '4:db:313', ['Test'], {} ] },
		] },
	{ '..' => [ { '()' => [ '4:0d66f27a-d2c3-479e-80ac-d02bd263d24c:409', [], {} ] } ] },
)};

response_for 'bool error' => { jolt => single_column(
	{ '?' => 'null' },
)};
response_for 'sigil error' => { jolt => single_column(
	{ '' => '' },
)};
response_for 'element id format version error' => {
	content_type => 'application/vnd.neo4j.jolt-v2+json-seq',
	jolt => single_column(
	{ '()' => [ '8::1:DLV', [], {} ] },
	{ '->' => [ '9::1:DLX', '8::1:DLV', 'FOO', '8::1:DLI', {} ] },
)};


# Confirm that the deep_bless Jolt parser correctly
# converts Neo4j values to Perl values.

use Neo4j::Driver;
use Neo4j::Types;

my ($s, $r, $v, $e);

plan tests => 1 + 10 + $no_warnings;


lives_and { ok $s = Neo4j::Driver->new('http:')
                    ->plugin($mock_plugin)
                    ->session(database => 'dummy') } 'session';

my $warned;

sub id5 {
	my $entity = shift;
	my $name = shift // 'id';
	my (undef, undef, $line) = caller;
	my $id;
	my $w = Test::Warnings::warning { $id = $entity->$name };
	if ($w !~ qr/\b\Q$name\E\b.+\bdeprecated\b.+\bNeo4j 5\b/i) {
		diag "got warning(s) at line $line: ", explain($w);
		warn 'Got unexpected warning(s)' unless $warned++;  # fail tests (but only warn once)
	}
	return $id;
}


subtest 'property types' => sub {
	plan tests => 13;
	lives_and { ok $r = $s->run('property') } 'run';
	lives_and { is $r->fetch->get(), undef } 'null';
	lives_ok { $v = undef; $v = $r->fetch->get() } 'Boolean true';
	ok !! $v, 'Boolean truthy';
	Neo4j_Test::bool_ok $v, 'true is bool';
	lives_ok { $v = undef; $v = $r->fetch->get() } 'Boolean false';
	ok ! $v, 'Boolean falsy';
	Neo4j_Test::bool_ok $v, 'false is bool';
	lives_and { is $r->fetch->get(), 13 } 'Integer';
	lives_and { is $r->fetch->get(), 0.5 } 'Float';
	lives_and { is $r->fetch->get(), 'hello' } 'String';
	lives_and { is $r->fetch->get(), 'Foo' } 'Bytes';
	lives_and { ok ! $r->has_next } 'no has_next';
};


subtest 'property types sparse' => sub {
	plan tests => 10;
	lives_and { ok $r = $s->run('property sparse') } 'run';
	lives_ok { $v = undef; $v = $r->fetch->get() } 'Boolean true';
	ok !! $v, 'Boolean truthy';
	Neo4j_Test::bool_ok $v, 'true is bool';
	lives_ok { $v = undef; $v = $r->fetch->get() } 'Boolean false';
	ok ! $v, 'Boolean falsy';
	Neo4j_Test::bool_ok $v, 'false is bool';
	lives_and { is $r->fetch->get(), 17 } 'Integer';
	lives_and { is $r->fetch->get(), 'world' } 'String';
	lives_and { ok ! $r->has_next } 'no has_next';
};


subtest 'composite types' => sub {
	plan tests => 8;
	lives_and { ok $r = $s->run('composite') } 'run';
	lives_and { is_deeply $r->fetch->get(), [23, 29] } 'list';
	lives_and { is_deeply $r->fetch->get(), {a=>31, b=>37} } 'map';
	lives_and { is_deeply $r->fetch->get(), [{c=>41}] } 'list of map';
	lives_and { is_deeply $r->fetch->get(), {X=>[qw(Y Z)]} } 'map of list';
	lives_and { is_deeply $r->fetch->get(), [] } 'list empty';
	lives_and { is_deeply $r->fetch->get(), {} } 'map empty';
	lives_and { ok ! $r->has_next } 'no has_next';
};


subtest 'composite types sparse' => sub {
	plan tests => 6;
	lives_and { ok $r = $s->run('composite sparse') } 'run';
	lives_and { is_deeply $r->fetch->get(), [23, 29] } 'list';
	lives_and { is_deeply $r->fetch->get(), [{c=>41}] } 'list of map';
	lives_and { is_deeply $r->fetch->get(), {X=>[qw(Y Z)]} } 'map of list';
	lives_and { is_deeply $r->fetch->get(), [] } 'list empty';
	lives_and { ok ! $r->has_next } 'no has_next';
};


subtest 'structural types v1' => sub {
	plan tests => 44;
	no warnings 'Neo4j::Types';  # Jolt v1 doesn't provide element IDs
	lives_and { ok $r = $s->run('structural v1') } 'run';
	lives_and { $v = 0; ok $v = $r->fetch->get() } 'get n101';
	lives_and { isa_ok $v, 'Neo4j::Types::Node' } 'n101 blessed';
	lives_and { is $v->element_id(), '101' } 'n101 element_id';
	lives_and { is $v->id(), 101 } 'n101 id';
	lives_and { is_deeply [$v->labels], ['Test'] } 'n101 labels';
	lives_and { is_deeply $v->properties(), {p=>59} } 'n101 properties';
	lives_and { $v = 0; ok $v = $r->fetch->get() } 'get n103';
	lives_and { isa_ok $v, 'Neo4j::Types::Node' } 'n103 blessed';
	lives_and { is $v->element_id(), '103' } 'n103 element_id';
	lives_and { is $v->id(), 103 } 'n103 id';
	lives_and { is_deeply [$v->labels], ['Test', 'N'] } 'n103 labels';
	lives_and { is_deeply $v->properties(), {p1=>61, p2=>67} } 'n103 properties';
	lives_and { $v = 0; ok $v = $r->fetch->get() } 'get r233';
	lives_and { isa_ok $v, 'Neo4j::Types::Relationship' } 'r233 blessed';
	lives_and { is $v->element_id(), '233' } 'r233 element_id';
	lives_and { is $v->id(), 233 } 'r233 id';
	lives_and { is $v->type(), 'FOO' } 'r233 type';
	lives_and { is $v->start_element_id(), '101' } 'r233 start_element_id';
	lives_and { is $v->start_id(), 101 } 'r233 start_id';
	lives_and { is $v->end_element_id(), '103' } 'r233 end_element_id';
	lives_and { is $v->end_id(), 103 } 'r233 end_id';
	lives_and { is_deeply $v->properties(), {p=>71} } 'r233 properties';
	lives_and { $v = 0; ok $v = $r->fetch->get() } 'get r239';
	lives_and { isa_ok $v, 'Neo4j::Types::Relationship' } 'r239 blessed';
	lives_and { is $v->element_id(), '239' } 'r239 element_id';
	lives_and { is $v->id(), 239 } 'r239 id';
	lives_and { is $v->type(), 'BAR' } 'r239 type';
	lives_and { is $v->start_element_id(), '103' } 'r239 start_element_id';
	lives_and { is $v->start_id(), 103 } 'r239 start_id';
	lives_and { is $v->end_element_id(), '101' } 'r239 end_element_id';
	lives_and { is $v->end_id(), 101 } 'r239 end_id';
	lives_and { is_deeply $v->properties(), {} } 'r239 properties';
	lives_and { $v = 0; ok $v = $r->fetch->get() } 'get r0';
	lives_and { isa_ok $v, 'Neo4j::Types::Relationship' } 'r0 blessed';
	lives_and { is $v->element_id(), '0' } 'r0 element_id';
	lives_and { is $v->id(), 0 } 'r0 id';
	lives_and { is $v->type(), 'NIL' } 'r0 type';
	lives_and { is $v->start_element_id(), '0' } 'r0 start_element_id';
	lives_and { is $v->start_id(), 0 } 'r0 start_id';
	lives_and { is $v->end_element_id(), '0' } 'r0 end_element_id';
	lives_and { is $v->end_id(), 0 } 'r0 end_id';
	lives_and { is_deeply $v->properties(), {} } 'r239 properties';
	lives_and { ok ! $r->has_next } 'no has_next';
};


subtest 'structural types v2' => sub {
	plan tests => 44;
	lives_and { ok $r = $s->run('structural v2') } 'run';
	lives_and { $v = 0; ok $v = $r->fetch->get() } 'get n101';
	lives_and { isa_ok $v, 'Neo4j::Types::Node' } 'n101 blessed';
	lives_and { is $v->element_id(), '4:db:101' } 'n101 element_id';
	lives_and { is id5($v), 101 } 'n101 id';
	lives_and { is_deeply [$v->labels], ['Test'] } 'n101 labels';
	lives_and { is_deeply $v->properties(), {p=>59} } 'n101 properties';
	lives_and { $v = 0; ok $v = $r->fetch->get() } 'get n103';
	lives_and { isa_ok $v, 'Neo4j::Types::Node' } 'n103 blessed';
	lives_and { is $v->element_id(), '4:db:103' } 'n103 element_id';
	lives_and { is id5($v), 103 } 'n103 id';
	lives_and { is_deeply [$v->labels], ['Test', 'N'] } 'n103 labels';
	lives_and { is_deeply $v->properties(), {p1=>61, p2=>67} } 'n103 properties';
	lives_and { $v = 0; ok $v = $r->fetch->get() } 'get r233';
	lives_and { isa_ok $v, 'Neo4j::Types::Relationship' } 'r233 blessed';
	lives_and { is $v->element_id(), '5:db:233' } 'r233 element_id';
	lives_and { is id5($v), 233 } 'r233 id';
	lives_and { is $v->type(), 'FOO' } 'r233 type';
	lives_and { is $v->start_element_id(), '4:db:101' } 'r233 start_element_id';
	lives_and { is id5($v, 'start_id'), 101 } 'r233 start_id';
	lives_and { is $v->end_element_id(), '4:db:103' } 'r233 end_element_id';
	lives_and { is id5($v, 'end_id'), 103 } 'r233 end_id';
	lives_and { is_deeply $v->properties(), {p=>71} } 'r233 properties';
	lives_and { $v = 0; ok $v = $r->fetch->get() } 'get r239';
	lives_and { isa_ok $v, 'Neo4j::Types::Relationship' } 'r239 blessed';
	lives_and { is $v->element_id(), '5:db:239' } 'r239 element_id';
	lives_and { is id5($v), 239 } 'r239 id';
	lives_and { is $v->type(), 'BAR' } 'r239 type';
	lives_and { is $v->start_element_id(), '4:db:103' } 'r239 start_element_id';
	lives_and { is id5($v, 'start_id'), 103 } 'r239 start_id';
	lives_and { is $v->end_element_id(), '4:db:101' } 'r239 end_element_id';
	lives_and { is id5($v, 'end_id'), 101 } 'r239 end_id';
	lives_and { is_deeply $v->properties(), {} } 'r239 properties';
	lives_and { $v = 0; ok $v = $r->fetch->get() } 'get r0';
	lives_and { isa_ok $v, 'Neo4j::Types::Relationship' } 'r0 blessed';
	lives_and { is $v->element_id(), '5:db:0' } 'r0 element_id';
	lives_and { is id5($v), 0 } 'r0 id';
	lives_and { is $v->type(), 'NIL' } 'r0 type';
	lives_and { is $v->start_element_id(), '4:db:0' } 'r0 start_element_id';
	lives_and { is id5($v, 'start_id'), 0 } 'r0 start_id';
	lives_and { is $v->end_element_id(), '4:db:0' } 'r0 end_element_id';
	lives_and { is id5($v, 'end_id'), 0 } 'r0 end_id';
	lives_and { is_deeply $v->properties(), {} } 'r239 properties';
	lives_and { ok ! $r->has_next } 'no has_next';
};


subtest 'structural types paths v1' => sub {
	plan tests => 30;
	no warnings 'Neo4j::Types';  # Jolt v1 doesn't provide element IDs
	lives_and { ok $r = $s->run('structural paths v1') } 'run';
	lives_and { $v = 0; ok $v = $r->fetch->get() } 'get path1';
	lives_and { isa_ok $v, 'Neo4j::Types::Path' } 'path1 blessed';
	lives_and { is scalar(@{[$v->nodes]}), 2 } 'path1 nodes';
	lives_and { is scalar(@{[$v->relationships]}), 1 } 'path1 relationships';
	lives_and { $e = 0; ok $e = ($v->nodes)[0] } 'get n311';
	lives_and { is $e->element_id(), '311' } 'n311 element_id';
	lives_and { is $e->id(), 311 } 'n311 id';
	lives_and { is_deeply [$e->labels], ['Test'] } 'n311 labels';
	lives_and { is_deeply $e->properties(), {p=>59} } 'n311 properties';
	lives_and { $e = 0; ok $e = ($v->relationships)[0] } 'get r307';
	lives_and { is $e->element_id(), '307' } 'r307 element_id';
	lives_and { is $e->id(), 307 } 'r307 id';
	lives_and { is $e->type(), 'TEST' } 'r307 type';
	lives_and { is $e->start_element_id(), '311' } 'r307 start_element_id';
	lives_and { is $e->start_id(), 311 } 'r307 start_id';
	lives_and { is $e->end_element_id(), '313' } 'r307 end_element_id';
	lives_and { is $e->end_id(), 313 } 'r307 end_id';
	lives_and { is_deeply $e->properties(), {p1=>73,p2=>79} } 'r307 properties';
	lives_and { $e = 0; ok $e = ($v->nodes)[1] } 'get n313';
	lives_and { is $e->element_id(), '313' } 'n313 element_id';
	lives_and { is $e->id, 313 } 'n313 id';
	lives_and { $v = 0; ok $v = $r->fetch->get() } 'get path2';
	lives_and { $e = 0; ok $e = [$v->elements] } 'path2 elements';
	lives_and { is scalar(@$e), 1 } 'path2 length';
	lives_and { is $e->[0]->element_id(), '409' } 'n409 element_id';
	lives_and { is $e->[0]->id(), 409 } 'n409 id';
	lives_and { is_deeply [$e->[0]->labels], [] } 'n409 labels';
	lives_and { is_deeply $e->[0]->properties(), {} } 'n409 properties';
	lives_and { ok ! $r->has_next } 'no has_next';
};


subtest 'structural types paths v2' => sub {
	plan tests => 30;
	lives_and { ok $r = $s->run('structural paths v2') } 'run';
	lives_and { $v = 0; ok $v = $r->fetch->get() } 'get path1';
	lives_and { isa_ok $v, 'Neo4j::Types::Path' } 'path1 blessed';
	lives_and { is scalar(@{[$v->nodes]}), 2 } 'path1 nodes';
	lives_and { is scalar(@{[$v->relationships]}), 1 } 'path1 relationships';
	lives_and { $e = 0; ok $e = ($v->nodes)[0] } 'get n311';
	lives_and { is $e->element_id(), '4:db:311' } 'n311 element_id';
	lives_and { is id5($e), 311 } 'n311 id';
	lives_and { is_deeply [$e->labels], ['Test'] } 'n311 labels';
	lives_and { is_deeply $e->properties(), {p=>59} } 'n311 properties';
	lives_and { $e = 0; ok $e = ($v->relationships)[0] } 'get r307';
	lives_and { is $e->element_id(), '5:db:307' } 'r307 element_id';
	lives_and { is id5($e), 307 } 'r307 id';
	lives_and { is $e->type(), 'TEST' } 'r307 type';
	lives_and { is $e->start_element_id(), '4:db:311' } 'r307 start_element_id';
	lives_and { is id5($e, 'start_id'), 311 } 'r307 start_id';
	lives_and { is $e->end_element_id(), '4:db:313' } 'r307 end_element_id';
	lives_and { is id5($e, 'end_id'), 313 } 'r307 end_id';
	lives_and { is_deeply $e->properties(), {p1=>73,p2=>79} } 'r307 properties';
	lives_and { $e = 0; ok $e = ($v->nodes)[1] } 'get n313';
	lives_and { is $e->element_id(), '4:db:313' } 'n313 element_id';
	lives_and { is id5($e), 313 } 'n313 id';
	lives_and { $v = 0; ok $v = $r->fetch->get() } 'get path2';
	lives_and { $e = 0; ok $e = [$v->elements] } 'path2 elements';
	lives_and { is scalar(@$e), 1 } 'path2 length';
	lives_and { is $e->[0]->element_id(), '4:0d66f27a-d2c3-479e-80ac-d02bd263d24c:409' } 'n409 element_id';
	lives_and { is id5($e->[0]), 409 } 'n409 id';
	lives_and { is_deeply [$e->[0]->labels], [] } 'n409 labels';
	lives_and { is_deeply $e->[0]->properties(), {} } 'n409 properties';
	lives_and { ok ! $r->has_next } 'no has_next';
};


subtest 'type errors' => sub {
	plan tests => 2 + 12;
	throws_ok { $s->run('bool error') } qr/\bAssertion failed: unexpected bool value\b/i, 'bool';
	throws_ok { $s->run('sigil error') } qr/\bAssertion failed: unexpected sigil\b/i, 'sigil';
	# legacy numeric ids can only be derived from element id format version 1
	lives_and { ok $r = $s->run('element id format version error') } 'run';
	lives_and { $v = 0; ok $v = $r->fetch->get() } 'get nDLV';
	lives_and { is $v->element_id(), '8::1:DLV' } 'nDLV element_id';
	lives_and { is id5($v), undef } 'nDLV id';
	lives_and { $v = 0; ok $v = $r->fetch->get() } 'get rDLX';
	lives_and { is $v->element_id(), '9::1:DLX' } 'rDLX element_id';
	lives_and { is id5($v), undef } 'rDLX id';
	lives_and { is $v->start_element_id(), '8::1:DLV' } 'rDLX start_element_id';
	lives_and { is id5($v, 'start_id'), undef } 'rDLX start_id';
	lives_and { is id5($v, 'end_id'), undef } 'rDLX end_id';
	lives_and { is $v->end_element_id(), '8::1:DLI' } 'rDLX end_element_id';
	lives_and { ok ! $r->has_next } 'no has_next';
};


response_for 'no labels' => { jolt => single_column(
	{ '()' => [ 1, undef, {} ] },
)};
response_for 'zero labels' => { jolt => single_column(
	{ '()' => [ 1, [], {} ] },
)};
response_for 'one label' => { jolt => single_column(
	{ '()' => [ 1, ['foobar'], {} ] },
)};
response_for 'two labels' => { jolt => single_column(
	{ '()' => [ 1, ['foo', 'baz'], {} ] },
)};
response_for 'no labels' => { jolt => single_column(
	{ '()' => [ 1, [], {} ] },
)};
response_for 'one label' => { jolt => single_column(
	{ '()' => [ 1, ['foobar'], {} ] },
)};
response_for 'path zero' => { jolt => single_column( { '..' => [
	{ '()' => [ 11, [], {} ] },
]})};
response_for 'path one' => { jolt => single_column( { '..' => [
	{ '()' => [ 2, [], {} ] },
	{ '->' => [ 3, 2, 'TEST', 4, {} ] },
	{ '()' => [ 4, [], {} ] },
]})};
response_for 'path two' => { jolt => single_column( { '..' => [
	{ '()' => [ 5, [], {} ] },
	{ '->' => [ 6, 5, 'TEST', 7, {} ] },
	{ '()' => [ 7, [], {} ] },
	{ '->' => [ 8, 7, 'TEST', 9, {} ] },
	{ '()' => [ 9, [], {} ] },
]})};
subtest 'types node/path wantarray' => sub {
	plan tests => 4*3 + 3*7;
	
	lives_and { $r = 0; ok $r = $s->run('no labels')->single->get } 'run no labels';
	lives_and { is_deeply [$r->labels], [] } 'labels undef';
	lives_and { is scalar($r->labels), 0 } 'labels undef scalar context';
	lives_and { $r = 0; ok $r = $s->run('zero labels')->single->get } 'run zero labels';
	lives_and { is_deeply [$r->labels], [] } '0 labels';
	lives_and { is scalar($r->labels), 0 } '0 labels scalar context';
	lives_and { $r = 0; ok $r = $s->run('one label')->single->get } 'run one label';
	lives_and { is_deeply [$r->labels], ['foobar'] } '1 label';
	lives_and { is scalar($r->labels), 1 } '1 label scalar context';
	lives_and { $r = 0; ok $r = $s->run('two labels')->single->get } 'run two labels';
	lives_and { is_deeply [$r->labels], ['foo','baz'] } '2 labels';
	lives_and { is scalar($r->labels), 2 } '2 labels scalar context';
	
	lives_and { $r = 0; ok $r = $s->run('path zero')->single->get } 'run path zero';
	lives_and { is_deeply [map {$_->id} $r->elements], [11] } '1 element';
	lives_and { is_deeply [map {$_->id} $r->nodes], [11] } '1 node';
	lives_and { is_deeply [map {$_->id} $r->relationships], [] } '0 rels';
	lives_and { is scalar($r->elements), 1 } '1 element scalar context';
	lives_and { is scalar($r->nodes), 1 } '1 node scalar context';
	lives_and { is scalar($r->relationships), 0 } '0 rels scalar context';
	
	lives_and { $r = 0; ok $r = $s->run('path one')->single->get } 'run path one';
	lives_and { is_deeply [map {$_->id} $r->elements], [2,3,4] } '3 elements';
	lives_and { is_deeply [map {$_->id} $r->nodes], [2,4] } '2 nodes';
	lives_and { is_deeply [map {$_->id} $r->relationships], [3] } '1 rel';
	lives_and { is scalar($r->elements), 3 } '3 elements scalar context';
	lives_and { is scalar($r->nodes), 2 } '2 nodes scalar context';
	lives_and { is scalar($r->relationships), 1 } '1 rel scalar context';
	
	lives_and { $r = 0; ok $r = $s->run('path two')->single->get } 'run path two';
	lives_and { is_deeply [map {$_->id} $r->elements], [5,6,7,8,9] } '5 elements';
	lives_and { is_deeply [map {$_->id} $r->nodes], [5,7,9] } '3 nodes';
	lives_and { is_deeply [map {$_->id} $r->relationships], [6,8] } '2 rels';
	lives_and { is scalar($r->elements), 5 } '5 elements scalar context';
	lives_and { is scalar($r->nodes), 3 } '3 nodes scalar context';
	lives_and { is scalar($r->relationships), 2 } '2 rels scalar context';
};


done_testing;
