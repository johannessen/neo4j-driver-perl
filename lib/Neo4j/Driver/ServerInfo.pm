use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::ServerInfo;
# ABSTRACT: Provides Neo4j server address and version


use URI 1.25;


sub new {
	my ($class, $server_info) = @_;
	
	# don't store the full URI here - it may contain auth credentials
	$server_info->{uri} = URI->new( $server_info->{uri} )->host_port;
	
	return bless $server_info, $class;
}


sub address  { shift->{uri} }
sub agent    { shift->{version} }
sub version  { shift->{version} }


sub protocol_version {
	shift->{protocol}
}


sub protocol {
	my ($self) = @_;
	
	my $protocol = $self->{protocol_string};
	return $protocol if defined $protocol;
	my $bolt_version = $self->{protocol};
	return "Bolt/$bolt_version" if $bolt_version;
	return defined $bolt_version ? "Bolt" : "HTTP";
}


1;

__END__

=head1 SYNOPSIS

 use Neo4j::Driver;
 $session = Neo4j::Driver->new->basic_auth(...)->session;
 
 $host_port = $session->server->address;
 $version_string = $session->server->version;
 say "Contacting $version_string at $host_port.";

=head1 DESCRIPTION

Provides some basic information of the server where the result
is obtained from.

=head1 METHODS

L<Neo4j::Driver::ServerInfo> implements the following methods.

=head2 address

 $host_port = $session->server->address;

Returns the host name and port number of the server. Takes the form
of an URL authority string (for example: C<localhost:7474>).

=head2 agent

 $agent_string = $session->server->agent;

Returns the product name and version number. Takes the form of
a server agent string (for example: C<Neo4j/3.5.17>).

=head2 protocol_version

 $bolt_version = $session->server->protocol_version;

Returns the Bolt protocol version with which the remote server
communicates. Takes the form of a string C<"$major.$minor">
where the major and minor version numbers both are integers.

When the HTTP protocol is used instead of Bolt, this method
returns an undefined value.

If the Bolt protocol is used, but the version number is unknown,
an empty string is returned. This situation shouldn't occur unless
you use L<Neo4j::Bolt> S<version 0.20> or older.

=head2 version

 $agent_string = $session->server->version;

Alias for L<C<agent()>|/"agent">.

Use of C<version()> is discouraged since version 0.26.
This method may be deprecated and removed in future.

=head1 EXPERIMENTAL FEATURES

L<Neo4j::Driver::ServerInfo> implements the following experimental
features. These are subject to unannounced modification or removal
in future versions. Expect your code to break if you depend upon
these features.

=head2 protocol

 $protocol_string = $session->server->protocol;

Returns the protocol name and version number announced by the server.
Similar to an agent string, this value is formed by the protocol
name followed by a slash and the version number, usually two digits
separated by a dot (for example: C<Bolt/1.0> or C<HTTP/1.1>).

If the protocol version is unknown, just the name is returned.

=head1 SEE ALSO

=over

=item * L<Neo4j::Driver>

=item * L<Neo4j::Driver::B<Session>>,
L<Neo4j::Driver::B<ResultSummary>>

=item * Equivalent documentation for the official Neo4j drivers:
L<ServerInfo (Java)|https://neo4j.com/docs/api/java-driver/current/index.html?org/neo4j/driver/summary/ServerInfo.html>,
L<IServerInfo (.NET)|https://neo4j.com/docs/api/dotnet-driver/4.0/html/24780fbc-1b81-92a8-97f6-a484475e18dc.htm>,
L<ServerInfo (Python)|https://neo4j.com/docs/api/python-driver/current/api.html#serverinfo>

=back

=cut
