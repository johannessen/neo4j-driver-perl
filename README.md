Neo4j::Driver
=============

[Neo4j::Driver][] is a stable unofficial Perl implementation of the
[Neo4j Driver API][]. It enables interacting with a Neo4j database server
using the same classes and method calls as the official Neo4j drivers do.

This driver extends the uniformity across languages, which is a stated goal of
the Neo4j Driver API, to Perl. The downside is that this driver doesn't offer
fully-fledged object bindings like the [REST::Neo4p][] module does.
Nor does it offer any DBI integration. However, it avoids the legacy `cypher`
endpoint, assuring compatibility with Neo4j versions 2.3, 3.x and 4.x.

See the [TODO][] document and Github for known issues and planned
improvements. Please report new issues and other feedback on Github.

There is an ongoing effort to clean up the experimental features. For each of
them, the goal is to eventually either declare it stable or deprecate it. There
is also ongoing work to further improve general reliability of this software.
However, there is no schedule for the completion of these efforts.

[Neo4j Driver API]: https://neo4j.com/docs/driver-manual/current/
[REST::Neo4p]: https://metacpan.org/release/REST-Neo4p
[TODO]: https://github.com/johannessen/neo4j-driver-perl/blob/master/TODO.pod


Installation
------------

Released versions of [Neo4j::Driver][] may be installed via CPAN:

	cpanm Neo4j::Driver

[![CPAN distribution](https://badge.fury.io/pl/Neo4j-Driver.svg)](https://badge.fury.io/pl/Neo4j-Driver)

To install a development version from this repository, run the following steps:

 1. `git clone https://github.com/johannessen/neo4j-driver-perl && cd neo4j-driver-perl`
 1. `dzil build` (requires [Dist::Zilla][])
 1. `cpanm <archive>.tar.gz`

[![Build Status](https://travis-ci.org/johannessen/neo4j-driver-perl.svg?branch=master)](https://travis-ci.org/johannessen/neo4j-driver-perl)

[Neo4j::Driver]: https://metacpan.org/release/Neo4j-Driver
[Dist::Zilla]: https://metacpan.org/release/Dist-Zilla
