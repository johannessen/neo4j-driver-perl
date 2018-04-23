Neo4j::Driver
=============

This is an unofficial Perl implementation of the [Neo4j Driver API][]. It
enables interacting with a Neo4j database server using more or less the same
classes and method calls as the official Neo4j drivers do. In contrast to
[REST::Neo4p][], it does not offer object bindings or DBI integration.

This software has pre-release quality. There is little documentation and no
schedule for further development.

[Neo4j Driver API]: https://neo4j.com/docs/developer-manual/3.3/drivers/
[REST::Neo4p]: https://metacpan.org/release/REST-Neo4p


Installation
------------

 1. `git clone https://github.com/johannessen/neo4j-driver-perl && cd neo4j-driver-perl`
 1. `dzil build` (requires [Dist::Zilla][])
 1. `cpanm <archive>.tar.gz`

[Dist::Zilla]: https://metacpan.org/release/Dist-Zilla
