use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver;
# ABSTRACT: Neo4j community graph database driver for Bolt and HTTP


use Carp qw(croak);

use URI 1.25;
use Neo4j::Driver::Events;
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
	auth => 'auth',
	ca_file => 'tls_ca',
	cypher_filter => 'cypher_filter',
	cypher_params => 'cypher_params_v2',
	cypher_types => 'cypher_types',
	encrypted => 'tls',
	jolt => 'jolt',
	concurrent_tx => 'concurrent_tx',
	net_module => 'net_module',
	timeout => 'timeout',
	tls => 'tls',
	tls_ca => 'tls_ca',
	trust_ca => 'tls_ca',
	uri => 'uri',
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
	my ($class, $config, @extra) = @_;
	
	my $self = bless { %DEFAULTS }, $class;
	$self->{plugins} = Neo4j::Driver::Events->new;
	
	croak __PACKAGE__ . "->new() with multiple arguments unsupported" if @extra;
	$config = { uri => $config } if ref $config ne 'HASH';
	$config->{uri} //= '';  # force config() to call _check_uri()
	return $self->config($config);
}


sub _check_uri {
	my ($self) = @_;
	
	my $uri = $self->{uri};
	
	if ($uri) {
		$uri = "[$uri]" if $uri =~ m{^[0-9a-f:]*::|^(?:[0-9a-f]+:){6}}i;
		$uri =~ s|^|http://| if $uri !~ m{:|/} || $uri =~ m{^\[.+\]$};
		$uri =~ s|^|http:| if $uri =~ m{^//};
		$uri = URI->new($uri);
		
		if ( ! $uri->scheme ) {
			croak sprintf "Failed to parse URI '%s'", $uri;
		}
		if ( $uri->scheme !~ m/^https?$|^bolt$/ ) {
			croak sprintf "URI scheme '%s' unsupported; use 'http' or 'bolt'", $uri->scheme // "";
		}
		
		if (my $userinfo = $uri->userinfo(undef)) {
			my @userinfo = $userinfo =~ m/^([^:]*):?(.*)/;
			@userinfo = map { URI::Escape::uri_unescape $_ } @userinfo;
			utf8::decode $_ for @userinfo;
			$self->basic_auth(@userinfo);
		}
		$uri->host('localhost') unless $uri->host;
		$uri->path('') if $uri->path_query eq '/';
		$uri->fragment(undef);
	}
	else {
		$uri = URI->new("http://localhost");
	}
	$uri->port( $NEO4J_DEFAULT_PORT{ $uri->scheme } ) if ! $uri->_port;
	
	$self->{uri} = $uri;
}


sub basic_auth {
	my ($self, $username, $password) = @_;
	
	warnings::warnif deprecated => "Deprecated sequence: call basic_auth() before session()" if $self->{server_info};
	
	$self->{auth} = {
		scheme => 'basic',
		principal => $username,
		credentials => $password,
	};
	
	return $self;
}


sub config {
	my ($self, @options) = @_;
	
	@options = %{$options[0]} if @options == 1 && ref $options[0] eq 'HASH';
	croak "config() without options unsupported" unless @options;
	
	if (@options < 2) {
		# get config option
		my $key = $options[0];
		croak "Unsupported config option: $key" unless grep m/^$key$/, keys %OPTIONS;
		return $self->{$OPTIONS{$key}};
	}
	
	croak "Unsupported sequence: call config() before session()" if $self->{server_info};
	my %options = $self->_parse_options('config', [keys %OPTIONS], @options);
	
	# set config option
	my @keys = reverse sort keys %options;  # auth should take precedence over uri
	foreach my $key (@keys) {
		$self->{$OPTIONS{$key}} = $options{$key};
		$self->_check_uri if $OPTIONS{$key} eq 'uri';
	}
	return $self;
}


sub session {
	my ($self, @options) = @_;
	
	$self->{plugins}->{die_on_error} = $self->{die_on_error};
	warnings::warnif deprecated => __PACKAGE__ . "->{die_on_error} is deprecated" unless $self->{die_on_error};
	warnings::warnif deprecated => __PACKAGE__ . "->{http_timeout} is deprecated; use config()" if defined $self->{http_timeout};
	$self->{timeout} //= $self->{http_timeout};
	
	@options = %{$options[0]} if @options == 1 && ref $options[0] eq 'HASH';
	my %options = $self->_parse_options('session', ['database'], @options);
	
	my $session = Neo4j::Driver::Session->new($self);
	return $session->_connect($options{database});
}


sub _parse_options {
	my (undef, $context, $supported, @options) = @_;
	
	croak "Odd number of elements in $context options hash" if @options & 1;
	my %options = @options;
	
	warnings::warnif deprecated => "Config option ca_file is deprecated; use trust_ca" if $options{ca_file};
	warnings::warnif deprecated => "Config option cypher_types is deprecated" if $options{cypher_types};
	if ($options{cypher_params}) {
		croak "Unimplemented cypher params filter '$options{cypher_params}'" if $options{cypher_params} ne v2;
	}
	elsif ($options{cypher_filter}) {
		warnings::warnif deprecated => "Config option cypher_filter is deprecated; use cypher_params";
		croak "Unimplemented cypher filter '$options{cypher_filter}'" if $options{cypher_filter} ne 'params';
		$options{cypher_params} = v2;
	}
	warnings::warnif deprecated => "Config option jolt is deprecated: Jolt is now enabled by default" if defined $options{jolt};
	warnings::warnif deprecated => "Config option net_module is deprecated; use plug-in interface" if defined $options{net_module};
	
	my @unsupported = ();
	foreach my $key (keys %options) {
		push @unsupported, $key unless grep m/^$key$/, @$supported;
	}
	croak "Unsupported $context option: " . join ", ", sort @unsupported if @unsupported;
	
	return %options;
}


sub plugin {
	# uncoverable pod (experimental feature)
	my ($self, $package, @extra) = @_;
	
	croak "plugin() with more than one argument is unsupported" if @extra;
	$self->{plugins}->_register_plugin($package);
	return $self;
}


sub close {
	# uncoverable pod (see Deprecations.pod)
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

This software is a community driver for the
L<Neo4j|https://neo4j.com/> graph database server.
It is designed to follow the Neo4j Driver API, allowing
clients to interact with a Neo4j server using the same
classes and method calls as the official Neo4j drivers do.
This extends the uniformity across languages, which is a
stated goal of the Neo4j Driver API, to Perl.

This driver targets the Neo4j community edition,
version 2.x, 3.x, 4.x, and 5.x. The Neo4j enterprise edition
and AuraDB are only supported as far as practical,
but patches will be accepted.

Two different network protocols exist for connecting to Neo4j.
By default, Neo4j servers offer both, but this can be changed
in F<neo4j.conf> for each server; see
L<"Configure connectors" in the Neo4j Operations Manual|https://neo4j.com/docs/operations-manual/current/configuration/connectors/>.

=over

=item Bolt

Bolt is a Neo4j proprietary, binary protocol, available with
S<Neo4j 3.0> and newer. Bolt communication may be encrypted or
unencrypted. Because Bolt is faster than HTTP, it is generally
the recommended protocol. However, Perl support for it may be
lagging after major updates to Neo4j.

This driver supports Bolt, but doesn't bundle the necessary XS
packages. You will need to install L<Neo4j::Bolt> separately
to enable Bolt for this driver.

=item HTTP / HTTPS

Support for HTTP is built into this driver, so it is always
available. HTTP is still fast enough for many use cases and
works even in a "Pure Perl" environment. It may also be
quicker than Bolt to add support for future changes in Neo4j.

HTTP connections will use B<Jolt> (JSON Bolt) when offered by the server.
For older Neo4j servers (before S<version 4.2>), the driver
will automatically fall back to slower REST-style JSON.

The driver also supports encrypted communication using HTTPS,
but doesn't bundle the necessary packages. You will need to
install L<LWP::Protocol::https> separately to enable HTTPS.

=back

The protocol is automatically chosen based on the URI scheme.
See L</"uri"> for details.

B<This driver's development is not yet considered finalised.>

As of version 0.31, the major open items are:

=over

=item *

Support for the C<neo4j:> URI scheme in some fashion.
(No implementation of Bolt routing is currently planned.)

=item *

Managed transactions through transaction functions.

=back

Once the above items are implemented, this driver will
move to S<version 1.00,> removing L<deprecated
functionality|Neo4j::Driver::Deprecations>.
There is an ongoing effort to work on these and other
items, but there is no schedule for their completion.

=head1 METHODS

L<Neo4j::Driver> implements the following methods.

=head2 basic_auth

 $driver->basic_auth('neo4j', 'password');

Set basic auth credentials with a given user and password. This
method returns the modified L<Neo4j::Driver> object, so that method
chaining is possible.

 $session = $driver->basic_auth('neo4j', 'password')->session;

=head2 config

 $driver->config({ option1 => 'foo', option2 => 'bar' });

Sets the specified configuration options on a L<Neo4j::Driver>
object. The options may be given as a hash or as a hash reference.
This method returns the modified object, so that method chaining
is possible.

 $session = $driver->config(timeout => 60)->session;

See L</"CONFIGURATION OPTIONS"> for a list of supported options.
Setting configuration options on a driver is only allowed before
creating the driver's first session.

Calling this method with just a single string parameter will return
the current value of the config option named by the parameter.

 $timeout = $driver->config('timeout');

=head2 new

 $driver = Neo4j::Driver->new({ uri => 'http://localhost' });

Construct a new L<Neo4j::Driver> object. This object holds the
details required to establish connections with a Neo4j database,
including server URIs, credentials and other configuration.

The C<new()> method accepts one or more configuration options given
as a hash reference. See L</"CONFIGURATION OPTIONS"> below for a
list of supported options. Alternatively, instead of the hash
reference, the Neo4j server URI may be given as a scalar string.

 $driver = Neo4j::Driver->new('http://localhost');

If C<new()> is called with no arguments, a default configuration
will be used for the driver.

=head2 session

 $session = $driver->session;

Creates and returns a new L<Session|Neo4j::Driver::Session>,
initiating a network connection with the Neo4j server.

Each session connects to a single database, which may be specified
using the C<database> option in a hash or hash reference passed
to this method. If no defined value is given for this
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

=head2 Plug-in modules

 $driver->plugin(  Local::MyPlugin->new );

The driver offers a simple plug-in interface. Plug-ins are modules
providing handlers for events that may be triggered by the driver.
Plug-ins are loaded by calling the C<plugin()> method with the
the blessed instance of a plug-in as parameter.

Details on the implementation of plug-ins including descriptions of
individual events are provided in L<Neo4j::Driver::Plugin>.

This feature is experimental because some parts of the plug-in
API are still evolving.

=head2 Concurrent transactions in HTTP sessions

 $session = Neo4j::Driver->new({
   concurrent_tx => 1,
   uri => 'http://...',
 })->session;
 $tx1 = $session->begin_transaction;
 $tx2 = $session->begin_transaction;
 $tx3 = $session->run(...);

The Neo4j Driver API officially doesn't allow multiple concurrent
transactions (sometimes called "nested transactions") to be open
within the same session. The standard way to work with multiple
concurrent transactions is to simply use multiple sessions. However,
since HTTP is a stateless protocol, concurrent transactions are
still possible on connections which use the C<http:> or C<https:>
protocol scheme.

This driver allows concurrent transactions on HTTP when the
C<concurrent_tx> config option is enabled. Trying to enable this
option on a Bolt connection is a fatal error.

The default for HTTP connections is currently to enable concurrent
transactions, but this will likely change in a future version.
The driver will currently give warnings on a best-effort basis
when using concurrent transactions on HTTP I<without> enabling this
option, but these warnings may become fatal errors in future.

When using HTTP, you should consider making a conscious choice
regarding whether or not to use concurrent transactions, and
configuring your driver accordingly. This can help to avoid
surprising behaviour in case you switch to Bolt at a later point
in time.

This config option is experimental because its name and semantics
are still evolving.

=head1 CONFIGURATION OPTIONS

L<Neo4j::Driver> implements the following configuration options.

=head2 auth

 $driver->config(auth => {
   scheme      => 'basic',
   principal   => $user_id,   # 'neo4j' by default
   credentials => $password,
 });

Specifies the authentication details for the Neo4j server.
The authentication details are provided as a Perl reference
that is made available to the network adapter. Typically,
this is an unblessed hash reference with the authentication
scheme declared in the hash entry C<scheme>.

The Neo4j server uses the auth scheme C<'basic'> by default,
which must be configured with a user id in the hash entry
C<principal> and a password in the entry C<credentials>,
as shown above. Alternatively, the method L</"basic_auth">
can be used as a shortcut, or the basic auth details can be
specified as userinfo in the URI.

The C<auth> config option defaults to the value C<undef>,
which disables authentication.

=head2 cypher_params

 $driver->config( cypher_params => v2 );
 $foo = $driver->session->run('RETURN {bar}', bar => 'foo');

Enables conversion of the old Cypher parameter syntax C<{param}>
supported by Neo4j S<version 2> to the modern syntax C<$param>
supported by Neo4j S<version 3> and newer. The only allowed value
for this config option is the unquoted literal
L<v-string|perldata/"Version Strings"> C<v2>.

Cypher's modern C<$> parameter syntax unfortunately may cause string
interpolations in Perl, which decreases database performance because
Neo4j can re-use query plans less often. It is also a potential
security risk (Cypher injection attacks). Using this config option
enables your code to use the safer C<{}> parameter syntax instead.

=head2 encrypted

 $driver->config(encrypted => 1);

Specifies whether to use secure communication using TLS. This
L<implies|IO::Socket::SSL/"Essential Information About SSL/TLS">
not just encryption, but also verification of the server's identity.

By default, a trust store on the local system will be used to verify
the server's identity. This will fail unless your Neo4j installation
uses a key pair that is trusted and verifiable through the global
CA infrastructure. If that's not the case, you may need to
additionally use the C<trust_ca> option.

This option defaults to C<0> (no encryption). This is generally what
you want if you connect to a server on C<localhost>.

This option is only useful for Bolt connections. For HTTP
connections, the use of TLS encryption is governed by the chosen
URI scheme (C<http> / C<https>).

Before version 0.27, this option was named C<tls>. Use of the
former name is now discouraged.

=head2 timeout

 $driver->config(timeout => 60);  # seconds

Specifies the connection timeout. The semantics of this config
option vary by network library. Its default value is therefore
not defined here and is subject to change.

For details, see L<LWP::UserAgent/"timeout"> when using HTTP or
L<select(2)> when using Bolt.

=head2 trust_ca

 $driver->config(trust_ca => 'neo4j/certificates/neo4j.cert');

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

Before version 0.27, this option was named C<tls_ca>. Use of the
former name is now discouraged.

=head2 uri

 $driver->config(uri => 'http://localhost:7474');

Specifies the Neo4j server connection URI. The URI scheme determines
the type of driver created. Supported schemes are C<bolt>, C<http>,
and C<https>.
Use of C<bolt> URIs requires L<Neo4j::Bolt> to be installed; use
of C<https> URIs requires L<LWP::Protocol::https> to be installed.

If a part of the URI or even the entire URI is missing, suitable
default values will be substituted. In particular, the host name
C<localhost> and the protocol C<http> will be used as defaults;
if no port is specified, the protocol's default port will be used.

 # all of these are semantically equal
 $driver->config(uri =>  undef );
 $driver->config(uri => 'http:');
 $driver->config(uri => 'localhost');
 $driver->config(uri => 'http://localhost');
 $driver->config(uri => 'http://localhost:7474/');

The C<neo4j> URI scheme is not yet implemented. Once it is added
to a future version of this driver, the default URI scheme will
likely change to C<neo4j>.

Note that there sometimes are issues with IPv4/IPv6 dual-stack
hostnames such as C<localhost> when using HTTP. The connection may
appear to "hang". Literal IP addresses like C<127.0.0.1> are not
affected. See L<Neo4j::Driver::Net/"IPv6 / dual-stack support">
for further discussion.

=head1 ENVIRONMENT

This software requires at least Perl 5.10, though you should consider
using Perl 5.26 or newer if you can.

=head1 DIAGNOSTICS

Neo4j::Driver triggers an "error" event as soon as an error
condition is discovered. If unhandled, this event will cause
the driver to die with an error string.
See L<Neo4j::Driver::Transaction/"ERROR HANDLING"> for
further information.

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

=head1 SEE ALSO

=over

=item * L<Neo4j::Driver::B<Session>>

=item * Official API documentation:
L<Neo4j Driver API Specification|https://github.com/neo4j/docs-bolt/blob/main/modules/ROOT/pages/driver-api/index.adoc>,
L<Neo4j Drivers Manual|https://neo4j.com/docs/java-manual/5/>,
L<Neo4j HTTP API Docs|https://neo4j.com/docs/http-api/5/>

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
driver I<certainly> would be in much worse shape than it is today.

=cut
