Neo4j::Driver
=============

This is an unofficial Perl implementation of the [Neo4j Driver API][]. It
enables interacting with a Neo4j database server using more or less the same
classes and method calls as the official Neo4j drivers do. Responses from the
Neo4j server are passed through to the client as-is.

This driver extends the uniformity across languages, which is a stated goal of
the Neo4j Driver API, to Perl. The downside is that this driver doesn't offer
fully-fledged object bindings like the [REST::Neo4p][] module does.
Nor does it offer any DBI integration. However, it avoids the legacy `cypher`
endpoint, assuring compatibility with future Neo4j versions.

**This software has pre-release quality. There is no schedule for further
development. The interface is not yet stable.**

See the [TODO][] document and Github for known issues and planned
improvements. Please report new issues and other feedback on Github.

[Neo4j Driver API]: https://neo4j.com/docs/developer-manual/3.3/drivers/
[REST::Neo4p]: https://metacpan.org/release/REST-Neo4p
[TODO]: https://github.com/johannessen/neo4j-driver-perl/blob/master/TODO.pod
[known issues]: https://github.com/johannessen/neo4j-driver-perl/issues


Installation
------------

Released versions of [Neo4j::Driver][] may be installed via CPAN:

	cpanm Neo4j::Driver

To install a development version from this repository, run the following steps:

 1. `git clone https://github.com/johannessen/neo4j-driver-perl && cd neo4j-driver-perl`
 1. `dzil build` (requires [Dist::Zilla][])
 1. `cpanm <archive>.tar.gz`

[![Build Status](https://travis-ci.org/johannessen/neo4j-driver-perl.svg?branch=master)](https://travis-ci.org/johannessen/neo4j-driver-perl)

[Neo4j::Driver]: https://metacpan.org/release/Neo4j-Driver
[Dist::Zilla]: https://metacpan.org/release/Dist-Zilla
