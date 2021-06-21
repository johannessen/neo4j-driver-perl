use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver;
# ABSTRACT: Neo4j community graph database driver for Bolt and HTTP


use Carp qw(croak);

use URI 1.25;
use Neo4j::Driver::Session;

use Neo4j::Driver::Type::Node;
use Neo4j::Driver::Type::Relationship;
use Neo4j::Driver::Type::Path;
use Neo4j::Driver::Type::Point;
use Neo4j::Driver::Type::Temporal;


my %NEO4J_DEFAULT_PORT = (
	bolt => 7687,
	http => 7474,
	https => 7473,
);

my %OPTIONS = (
	ca_file => 'tls_ca',
	cypher_filter => 'cypher_filter',
	cypher_types => 'cypher_types',
	jolt => 'jolt',
	net_module => 'net_module',
	timeout => 'http_timeout',
	tls => 'tls',
	tls_ca => 'tls_ca',
);

my %DEFAULTS = (
	cypher_types => {
		node => 'Neo4j::Driver::Type::Node',
		relationship => 'Neo4j::Driver::Type::Relationship',
		path => 'Neo4j::Driver::Type::Path',
		point => 'Neo4j::Driver::Type::Point',
		temporal => 'Neo4j::Driver::Type::Temporal',
	},
	die_on_error => 1,
);


sub new {
	my ($class, $uri) = @_;
	
	if ($uri) {
		$uri =~ s|^|http://| if $uri !~ m{:|/};
		$uri =~ s|^|http:| if $uri =~ m{^//};
		$uri = URI->new($uri);
		
		if (! $uri->scheme || $uri->scheme !~ m/^https?|bolt$/) {
			croak sprintf "URI scheme '%s' unsupported; use 'http' or 'bolt'", $uri->scheme // "";
		}
		
		$uri->host('localhost') unless $uri->host;
		$uri->path('') if $uri->path_query eq '/';
		$uri->fragment(undef);
	}
	else {
		$uri = URI->new("http://localhost");
	}
	$uri->port( $NEO4J_DEFAULT_PORT{ $uri->scheme } ) if ! $uri->_port;
	
	return bless { uri => $uri, %DEFAULTS }, $class;
}


sub basic_auth {
	my ($self, $username, $password) = @_;
	
	warnings::warnif deprecated => "Deprecated sequence: call basic_auth() before session()" if $self->{session};
	
	$self->{auth} = {
		scheme => 'basic',
		principal => $username,
		credentials => $password,
	};
	
	return $self;
}


sub config {
	my ($self, @options) = @_;
	
	if (@options < 2) {
		# get config option
		my $key = $options[0] // '';
		croak "Unsupported config option: $key" unless grep m/^$key$/, keys %OPTIONS;
		return $self->{$OPTIONS{$key}};
	}
	
	croak "Unsupported sequence: call config() before session()" if $self->{session};
	my %options = $self->_parse_options('config', [keys %OPTIONS], @options);
	
	# set config option
	foreach my $key (keys %options) {
		$self->{$OPTIONS{$key}} = $options{$key};
	}
	return $self;
}


sub session {
	my ($self, @options) = @_;
	
	warnings::warnif deprecated => __PACKAGE__ . "->{die_on_error} is deprecated" unless $self->{die_on_error};
	my %options = $self->_parse_options('session', ['database'], @options);
	
	$self->{session} = 1;
	
	my $session = Neo4j::Driver::Session->new($self);
	return $session->_connect($options{database});
}


sub _parse_options {
	my (undef, $context, $supported, @options) = @_;
	
	croak "Odd number of elements in $context options hash" if @options & 1;
	my %options = @options;
	
	my @unsupported = ();
	foreach my $key (keys %options) {
		push @unsupported, $key unless grep m/^$key$/, @$supported;
	}
	croak "Unsupported $context option: " . join ", ", sort @unsupported if @unsupported;
	
	return %options;
}


sub close {
	warnings::warnif deprecated => __PACKAGE__ . "->close() is deprecated";
}




package # private
        URI::bolt;

use parent 'URI::_server';

# The server methods need to be available for bolt: URI instances
# even when the Neo4j-Bolt distribution is not installed.

 
1;

__END__

=head1 SYNOPSIS

 use Neo4j::Driver;
 $uri = 'bolt://localhost';  # requires Neo4j::Bolt
 $uri = 'http://localhost';
 $driver = Neo4j::Driver->new($uri)->basic_auth('neo4j', 'password');
 
 sub say_friends_of {
   $query = 'MATCH (a:Person)-[:KNOWS]->(f) '
             . 'WHERE a.name = {name} RETURN f.name';
   $records = $driver->session->run($query, name => shift)->list;
   foreach $record ( @$records ) {
     say $record->get('f.name');
   }
 }
 
 say_friends_of 'Alice';

=head1 DESCRIPTION

This is an unofficial Perl implementation of the
L<Neo4j Driver API|https://neo4j.com/docs/driver-manual/current/>.
It enables interacting with a Neo4j database server using the
same classes and method calls as the official Neo4j drivers do.

This driver extends the uniformity across languages, which is a
stated goal of the Neo4j Driver API, to Perl. The downside is that
this driver doesn't offer fully-fledged object bindings like the
existing L<REST::Neo4p> module does. Nor does it offer any L<DBI>
integration. However, it avoids the legacy C<cypher> endpoint,
assuring compatibility with Neo4j versions 2.3, 3.x and 4.x.

Two different network protocols exist for connecting to Neo4j.
By default, Neo4j servers offer both, but this can be changed
in F<neo4j.conf> for each server; see
L<"Configure connectors" in the Neo4j Operations Manual|https://neo4j.com/docs/operations-manual/current/configuration/connectors/>.

=over

=item Bolt

Bolt is a Neo4j proprietary, binary protocol, available with
S<Neo4j 3.0> and newer. Bolt communication may be encrypted or
unencrypted. Because Bolt is faster than HTTP, it is generally
the recommended protocol. However, support for it may be
lagging after major updates to Neo4j.

This driver supports Bolt, but doesn't bundle the necessary XS
packages. You will need to install L<Neo4j::Bolt> separately
to enable Bolt.

=item HTTP / HTTPS

Support for HTTP is built into this driver, so it is always
available. HTTP is still fast enough for many use cases and
works even in a "Pure Perl" environment. It may also be
quicker than Bolt to add support for future changes in Neo4j.

The driver also supports encrypted communication using HTTPS,
but doesn't bundle the necessary packages. You will need to
install L<LWP::Protocol::https> separately to enable HTTPS.

=back

The protocol is automatically chosen based on the URI scheme.
See L</"new"> for details.

B<As of version 0.13, the interface of this software may be
considered stable.>

However, bugs may still exist. Also, experimental features may be
changed or deprecated at any time. If you find yourself reliant on
an experimental feature, please file a new issue requesting that it
be made stable.

There is an ongoing effort to clean up the experimental features.
For each of them, the goal is to eventually either declare it stable
or deprecate it. There is also ongoing work to further improve
general stability and reliability of this software. However, there
is no schedule for the completion of these efforts.

=head1 METHODS

L<Neo4j::Driver> implements the following methods.

=head2 basic_auth

 $driver->basic_auth('neo4j', 'password');

Set basic auth credentials with a given user and password. This
method returns the modified L<Neo4j::Driver> object, so that method
chaining is possible.

 $session = $driver->basic_auth('neo4j', 'password')->session;

=head2 config

 $driver->config( option1 => 'foo', option2 => 'bar' );

Sets the specified configuration option or options on a
L<Neo4j::Driver> object. The options are given in hash syntax.
This method returns the modified object, so that method chaining
is possible.

 $session = $driver->config(timeout => 60)->session;

See below for an explanation of
L<all supported configuration options|/"CONFIGURATION OPTIONS">.
Setting configuration options on a driver is only allowed before
creating the driver's first session.

Calling this method with just a single parameter will return the
current value of the config option named by the parameter.

 $timeout = $driver->config('timeout');

=head2 new

 $driver = Neo4j::Driver->new('http://localhost');

Construct a new L<Neo4j::Driver> object. This object holds the
details required to establish connections with a Neo4j database,
including server URIs, credentials and other configuration.

The URI passed to this method determines the type of driver created. 
The C<http>, C<https>, and C<bolt> URI schemes are supported.
Use of C<bolt> URIs requires L<Neo4j::Bolt> to be installed; use
of C<https> URIs requires L<LWP::Protocol::https> to be installed.

If a part of the URI or even the entire URI is missing, suitable
default values will be substituted. In particular, the host name
C<localhost> and the protocol C<http> will be used as defaults;
if no port is specified, the protocol's default port will be used.

 # all of these are semantically equal
 $driver = Neo4j::Driver->new;
 $driver = Neo4j::Driver->new('http:');
 $driver = Neo4j::Driver->new('localhost');
 $driver = Neo4j::Driver->new('http://localhost');
 $driver = Neo4j::Driver->new('http://localhost:7474');

=head2 session

 $session = $driver->session;

Creates and returns a new L<Session|Neo4j::Driver::Session>,
initiating a network connection with the Neo4j server.

Each session connects to a single database, which may be specified
using the C<database> option. If no defined value is given for this
option, the driver will select the default database configured
in F<neo4j.conf>.

 $session = $driver->session( database => 'system' );

The C<database> option is silently ignored when used with Neo4j
S<versions 2> S<and 3>, which only support a single database.

=head1 EXPERIMENTAL FEATURES

L<Neo4j::Driver> implements the following experimental features.
These are subject to unannounced modification or removal in future
versions. Expect your code to break if you depend upon these
features.

=head2 Bolt version 3 and 4

There is now experimental support for Bolt protocol versions newer
S<than 1> using L<Neo4j::Bolt> S<version 0.40> or newer. This allows
connecting to S<Neo4j 4> using Bolt.

This feature is currently undergoing testing. Until it becomes
stable, please continue to use HTTP with S<Neo4j 4> in production
environments.

=head2 Jolt

 $d->config(jolt => undef);  # prefer Jolt (the default)
 $d->config(jolt => 0);      # accept only JSON
 $d->config(jolt => 1);      # accept only Jolt

The L<Jolt|https://neo4j.com/docs/http-api/4.3/actions/result-format/#_jolt>
response format (JSON Bolt) is preferred for HTTP connections
because the older JSON response format has several known issues
and is much slower than Jolt.

The Jolt format can be enforced or disabled as shown above.
If you use the scalars C<'sparse'>, C<'strict'> or C<'ndjson'>
instead of just C<1>, the driver will request that particular
Jolt mode from the server. However, there is generally no
advantage to enforcing Jolt or to manually selecting one
of these modes. This feature is for testing purposes only.

=head2 Custom networking modules

 use Local::MyNetworkAgent;
 $driver->config(net_module => 'Local::MyNetworkAgent');

The module to be used for network communication may be specified
using the C<net_module> config option. The specified module must
implement the API described in L<Neo4j::Driver::Net/"EXTENSIONS">.
Your code must C<use> or C<require> the module it specifies here.

By default, the driver will try to auto-detect a suitable module.
This will currently always result in the driver's built-in modules
being used. Alternatively, you may specify the empty string to ask
for the built-in modules explicitly, which will disable
auto-detection.

 $driver->config(net_module => undef);  # auto-detect (the default)
 $driver->config(net_module => '');     # use the built-in modules

This config option is experimental because the API for custom
networking modules is still evolving. See L<Neo4j::Driver::Net>
for details.

=head2 Parameter syntax conversion

 $driver->config(cypher_filter => 'params');

When this option is set, the driver automatically uses a regular
expression to convert the old Cypher parameter syntax C<{param}>
supported by Neo4j S<versions 2 and 3> to the new syntax C<$param>
supported by Neo4j S<versions 3 and 4>.

=head2 Type system customisation

 $driver->config(cypher_types => {
   node => 'Local::Node',
   relationship => 'Local::Relationship',
   path => 'Local::Path',
   point => 'Local::Point',
   temporal => 'Local::Temporal',
   init => sub { my $object = shift; ... },
 });

The package names used for C<bless>ing objects in query results can be
modified. This allows clients to add their own methods to such objects.

Clients must make sure their custom type packages are subtypes of the
base type packages that this module provides (S<e. g.> using C<@ISA>):

=over

=item * L<Neo4j::Driver::Type::Node>

=item * L<Neo4j::Driver::Type::Relationship>

=item * L<Neo4j::Driver::Type::Path>

=item * L<Neo4j::Driver::Type::Point>

=item * L<Neo4j::Driver::Type::Temporal>

=back

Clients may only use the documented API to access the data in the base
type. As an exception, clients may store private data by calling the
C<_private()> method, which returns a hashref. Within that hashref,
clients may make free use of any hash keys that begin with two
underscores (C<__>). All other hash keys are reserved for use by
Neo4j::Driver. Reading or modifying their values is unsupported
and discouraged because it makes your code prone to fail when any
internals change in the implementation of Neo4j::Driver.

The C<cypher_types> config option will soon be deprecated and
eventually be removed. The C<net_module> option offers the same
functionality and more (albeit somewhat less conveniently).

=head1 CONFIGURATION OPTIONS

L<Neo4j::Driver> implements the following configuration options.

=head2 timeout

 $driver->config(timeout => 60);  # seconds

Specifies the connection timeout. The semantics of this config
option vary by network library. Its default value is therefore
not defined here and is subject to change.

For details, see L<LWP::UserAgent/"timeout"> when using HTTP or
L<select(2)> when using Bolt.

The old C<< $driver->{http_timeout} >> syntax remains supported
for the time being in order to ensure backwards compatibility,
but its use is discouraged and it may be deprecated in future.

=head2 tls

 $driver->config(tls => 1);

Specifies whether to use secure communication using TLS. This
L<implies|IO::Socket::SSL/"Essential Information About SSL/TLS">
not just encryption, but also verification of the server's identity.

By default, the local system's trust store will be used to verify
the server's identity. This will fail unless your Neo4j installation
uses a key pair that is trusted and verifiable through the global
CA infrastructure. If that's not the case, you may need to
additionally use the C<tls_ca> option.

This option defaults to C<0> (no encryption). This is generally what
you want if you connect to a server on C<localhost>.

This option is only useful for Bolt connections. For HTTP
connections, the use of TLS encryption is governed by the chosen
URI scheme (C<http> / C<https>).

=head2 tls_ca

 $driver->config(tls_ca => 'neo4j/certificates/neo4j.cert');

Specifies the path to a file containing one or more trusted TLS
certificates. When this option is given, encrypted connections will
only be accepted if the server's identity can be verified using the
certificates provided.

The certificates in the file must be PEM encoded. They are expected
to be "root" certificates, S<i. e.> the S<"CA bit"> needs to be set
and the certificate presented by the server must be signed by one of
the certificates in this file (or by an intermediary).

Self-signed certificates (such as those automatically provided by
some Neo4j versions) should also work if their S<"CA bit"> is set.

=head1 ENVIRONMENT

This software currently targets Neo4j versions 2.3, 3.x and 4.x.

This software requires at least Perl 5.10, though you should consider
using Perl 5.16 or newer if you can.

=head1 DIAGNOSTICS

Neo4j::Driver currently dies as soon as an error condition is
discovered. Use C<eval>, L<Try::Tiny> or similar to catch this.

Warnings are given when deprecated or ambiguous method calls are used.
These warnings may be disabled if desired.

 no warnings 'deprecated';
 no warnings 'ambiguous';

=head1 BUGS

See the F<TODO> document and Github for known issues and planned
improvements. Please report new issues and other feedback on Github.

Just like the official Neo4j drivers, this driver has been designed to strike
a balance between an idiomatic API for Perl and a uniform surface across all
languages. Differences between this driver and the official Neo4j drivers in
either the API or the behaviour are generally to be regarded as bugs unless
there is a compelling reason for a different approach in Perl.

Due to lack of resources, only the Neo4j community edition is targeted by this
driver at present.

=head1 SEE ALSO

=over

=item * L<Neo4j::Driver::B<Session>>

=item * Official API documentation:
L<Neo4j Drivers Manual|https://neo4j.com/docs/driver-manual/current/>,
L<Neo4j HTTP API Docs|https://neo4j.com/docs/http-api/current/>

=item * Other modules for working with Neo4j:
L<DBD::Neo4p>,
L<Neo4j::Bolt>,
L<Neo4j::Cypher::Abstract>,
L<REST::Cypher>,
L<REST::Neo4p>

=back

=head1 ACKNOWLEDGEMENT

Special thanks go to Mark A. Jensen (MAJENSEN). Without the
inspiration of his L<REST::Neo4p>, this driver project I<probably>
would never have been even gotten started. And without Mark's
tremendous work on L<Neo4j::Bolt> and libneo4j-client, this
driver I<certainly> would be a far cry from what it is today.

=cut
