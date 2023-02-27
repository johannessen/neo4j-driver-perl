#!perl
use strict;
use warnings;
use lib qw(./lib t/lib);

use Test::More 0.88;
use Test::Exception;
use Test::Warnings;

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
	{ 'T' => '2002-04-16T12:34:56' },
	{ '@' => 'POINT (30 10)' },
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

my ($s, $r, $v, $e);

plan tests => 1 + 9 + 1;


lives_and { ok $s = Neo4j::Driver->new('http:')
                    ->plugin($mock_plugin)
                    ->session(database => 'dummy') } 'session';

sub id5 {
	my $entity = shift;
	my $name = shift // 'id';
	my (undef, undef, $line) = caller;
	my $id;
	my $w = Test::Warnings::warning { $id = $entity->$name };
	if ($w !~ qr/\b\Q$name\E\b.+\bdeprecated\b.+\bNeo4j 5\b/i) {
		diag "got warning(s) at line $line: ", explain($w);
		warn 'Got unexpected warning(s)' unless CORE::state $warned++;  # fail tests
	}
	return $id;
}


subtest 'property types' => sub {
	plan tests => 15;
	lives_and { ok $r = $s->run('property') } 'run';
	lives_and { is $r->fetch->get(), undef } 'null';
	lives_ok { $v = undef; $v = $r->fetch->get() } 'Boolean true';
	ok !! $v, 'Boolean truthy';
	isnt ref($v), '', 'ref true';
	lives_ok { $v = undef; $v = $r->fetch->get() } 'Boolean false';
	ok ! $v, 'Boolean falsy';
	isnt ref($v), '', 'ref false';
	lives_and { is $r->fetch->get(), 13 } 'Integer';
	lives_and { is $r->fetch->get(), 0.5 } 'Float';
	lives_and { is $r->fetch->get(), 'hello' } 'String';
	lives_and { is ref($r->fetch->get), 'Neo4j::Driver::Type::Temporal' } 'Date';
	lives_and { is ref($r->fetch->get), 'Neo4j::Driver::Type::Point' } 'Point';
	lives_and { is $r->fetch->get(), 'Foo' } 'Bytes';
	lives_and { ok ! $r->has_next } 'no has_next';
};


subtest 'property types sparse' => sub {
	plan tests => 10;
	lives_and { ok $r = $s->run('property sparse') } 'run';
	lives_ok { $v = undef; $v = $r->fetch->get() } 'Boolean true';
	ok !! $v, 'Boolean truthy';
	isnt ref($v), '', 'ref true';
	lives_ok { $v = undef; $v = $r->fetch->get() } 'Boolean false';
	ok ! $v, 'Boolean falsy';
	isnt ref($v), '', 'ref false';
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


done_testing;
