use v5.14;
use warnings;

package Neo4j::Driver::ServerInfo;
# ABSTRACT: Provides Neo4j server address and version


use Carp qw(croak);
our @CARP_NOT = qw(Neo4j::Driver::Session);
use Feature::Compat::Try;
use URI 1.25;


sub new {
	# uncoverable pod (private method)
	my ($class, $server_info) = @_;
	
	# don't store the full URI here - it may contain auth credentials
	$server_info->{uri} = URI->new( $server_info->{uri} )->host_port;
	
	return bless $server_info, $class;
}


sub address  { shift->{uri} }
sub agent    { shift->{version} }


sub protocol_version {
	shift->{protocol}
}


sub version {
	# uncoverable pod (see agent)
	warnings::warnif deprecated => "version() in Neo4j::Driver::ServerInfo is deprecated; use agent() instead";
	&agent;
}


# discover default database on Neo4j >= 4 using the given driver config
sub _default_database {
	my ($self, $driver) = @_;
	
	my $database = $self->{default_database};
	return $database if defined $database;
	
	return if $self->{version} =~ m{^Neo4j/[123]\.};
	try {
		my $sys = $driver->session(database => 'system');
		$database = $sys->run('SHOW DEFAULT DATABASE')->single->get('name');
	}
	catch ($e) {
		croak sprintf
			"%sSession creation failed because the default database of %s at %s could not be determined",
			$e, $self->{version}, $self->{uri};
	}
	return $self->{default_database} = $database;
}


1;

__END__

=head1 SYNOPSIS

 $server_info = $session->server;
 $server_info = $result_summary->server;
 
 $host_port     = $server_info->address;
 $neo4j_version = $server_info->agent;
 $bolt_version  = $server_info->protocol_version;

=head1 DESCRIPTION

Provides some basic information of the server where the result
is obtained from.

To obtain server info, call L<Neo4j::Driver::Session/"server">.

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

Before driver S<version 0.26>, the agent string was retrieved with
the C<version()> method. That method has since been deprecated,
matching a corresponding change in S<Neo4j 4.3>.

=head2 protocol_version

 $bolt_version = $session->server->protocol_version;

Returns the Bolt protocol version with which the remote server
communicates. Takes the form of a string C<"$major.$minor">
where the major and minor version numbers both are integers.

When the HTTP protocol is used instead of Bolt, this method
returns an undefined value.

=head1 SEE ALSO

=over

=item * L<Neo4j::Driver>

=item * L<Neo4j::Driver::B<Session>>,
L<Neo4j::Driver::B<ResultSummary>>

=item * Equivalent documentation for the official Neo4j drivers:
L<ServerInfo (Java)|https://neo4j.com/docs/api/java-driver/5.26/org.neo4j.driver/org/neo4j/driver/summary/ServerInfo.html>,
L<IServerInfo (.NET)|https://neo4j.com/docs/api/dotnet-driver/5.26/api/Neo4j.Driver.IServerInfo.html>,
L<ServerInfo (Python)|https://neo4j.com/docs/api/python-driver/5.26/api.html#serverinfo>

=back

=cut
