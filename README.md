Neo4j::Driver
=============

This software is an unofficial Perl community driver for the
Neo4j graph database server. It is designed to follow the
[Neo4j Driver API][], allowing clients to interact with a Neo4j
server using the same classes and method calls as the official
Neo4j drivers do. This extends the uniformity across languages,
which is a stated goal of the Neo4j Driver API, to [Perl][].

For networking, HTTP (Jolt / JSON) and Bolt are supported by
this driver. Use of the Bolt protocol requires the XS module
[Neo4j::Bolt][] to be installed as well.

This driver targets the [Neo4j community edition][],
version 2.0 and newer (including Neo4j 5).
Other Neo4j editions are only supported as far as practical,
but issue reports and patches about them are welcome.

See [TODO.pod][] for known issues and planned improvements.

[Perl]: https://www.perl.org/
[Neo4j Driver API]: https://neo4j.com/docs/driver-manual/4.1/session-api/
[Neo4j community edition]: https://neo4j.com/download-center/#community
[Neo4j::Bolt]: https://metacpan.org/release/Neo4j-Bolt
[TODO.pod]: https://github.com/johannessen/neo4j-driver-perl/blob/master/TODO.pod


Installation
------------

Released versions of [Neo4j::Driver][] may be installed via [CPAN][]:

	cpanm Neo4j::Driver

[![CPAN distribution](https://badge.fury.io/pl/Neo4j-Driver.svg)](https://badge.fury.io/pl/Neo4j-Driver)

To install a development version from this repository, run the following steps:

```sh
git clone https://github.com/johannessen/neo4j-driver-perl && cd neo4j-driver-perl
cpanm Dist::Zilla::PluginBundle::Author::AJNN
dzil install

dzil release   # upload a new version to CPAN
```

[![Build and Test Status](https://github.com/johannessen/neo4j-driver-perl/actions/workflows/build-and-test.yml/badge.svg)](https://github.com/johannessen/neo4j-driver-perl/actions/workflows/build-and-test.yml)

This is a “Pure Perl” distribution, which means you don’t need
[Dist::Zilla][] to contribute patches. You can simply clone
the repository and run the test suite using `prove` instead.

[CPAN]: https://www.cpan.org/modules/INSTALL.html
[Neo4j::Driver]: https://metacpan.org/release/Neo4j-Driver
[Dist::Zilla]: https://metacpan.org/release/Dist-Zilla
