package Neo4j::Sim;
use strict;
use warnings;

use Carp qw(croak);
use Cpanel::JSON::XS;
use Digest::MD5;
use File::Basename qw(dirname);
use File::Slurp;
use URI;
use Neo4j::Driver::Transport::HTTP;
use Neo4j::Test;

my $path = (dirname dirname dirname __FILE__) . "/simulator";
my $hash_url = 1;  # not 100% sure if 0 would produce correct results, but it might increase maintainability ... and it _looks_ okay!


sub new {
	my ($class, $options) = @_;
	my $self = bless {
		auth => $options->{auth} // 1,
	}, $class;
	$self->{_res} = bless \($self), $class."::Response";
	return $self;
}


sub factory {
	shift;
	my %options = (@_);
	sub {
		return Neo4j::Sim->new(\%options);
	}
}


sub request {
	my ($self, $method, $url, $content, $headers) = @_;
	
	return $self->not_authenticated() unless $self->{auth};
	if ($method eq 'DELETE') {
		$self->{status} = 204;  # HTTP: No Content
		return $self;
	}
	return $self->not_implemented($method, $url) unless $method eq 'POST';
	return $self->not_found($url) if $url !~ m/^$Neo4j::Driver::Transport::HTTP::SERVICE_ROOT_ENDPOINT/;
	
	my $hash = request_hash($url, $content);
	my $file = "$path/$hash.json";
	if (! -f $file || ! -r $file) {
		return $self->not_implemented($method, $url, $file);
	}
	$self->{json} = File::Slurp::read_file $file;
	$self->{status} = 201;  # HTTP: Created
	# always use 201 so that the Location header is picked up by the Transaction
	return $self;
}


sub GET {
	my ($self, $url, $headers) = @_;
	if ($url ne $Neo4j::Driver::Transport::HTTP::SERVICE_ROOT_ENDPOINT) {
		return $self->not_implemented('GET', $url);
	}
	$self->{json} = '{"neo4j_version":"0.0.0 (Neo4j::Sim)"}';
	$self->{status} = 200;  # HTTP: OK
	return $self;
}


sub not_found {
	my ($self, $url) = @_;
	$self->{json} = "{\"error\":\"$url not found in Neo4j simulator.\"}";
	$self->{status} = 404;  # HTTP: Not Found
	return $self;
}


sub not_authenticated {
	my ($self, $method, $url, $file) = @_;
	$self->{json} = "{\"error\":\"Neo4j simulator unauthenticated.\"}";
	$self->{status} = 401;  # HTTP: Unauthorized
	return $self;
}


sub not_implemented {
	my ($self, $method, $url, $file) = @_;
	$self->{json} = "{\"error\":\"$method to $url not implemented in Neo4j simulator.\"}";
	$self->{json} = "{\"error\":\"Query not implemented (file '$file' not found).\"}" if $file;
	$self->{status} = 501;  # HTTP: Not Implemented
	return $self;
}


sub responseContent {
	my ($self) = @_;
	return $self->{json};
}


sub responseHeader {
	my ($self, $header) = @_;
	if ($header eq 'Content-Type') {
		return 'application/json';
	}
	elsif ($header eq 'Location') {
		my $loc = '';
		eval { $loc = decode_json($self->{json})->{commit} // '' };
		$loc =~ s|/commit$||;
		return $loc;
	}
	else {
		croak "responseHeader '$header' not implemented in Neo4j simulator";
	}
}


sub responseCode {
	my ($self) = @_;
	return $self->{status};
}


sub getHost {
	return "http://" . Neo4j::Test->server_address;
}


sub store {
	my (undef, $url, $request, $response, $write_txt) = @_;
	return if $Neo4j::Test::sim;  # don't overwrite the files while we're reading from them
	
	my $hash = request_hash($url, $request);
	$response //= '';
	$response =~ s/{"expires":"[A-Za-z0-9 :,+-]+"}/{"expires":"Thu, 01 Jan 1970 00:00:00 +0000"}/;
	File::Slurp::write_file "$path/$hash.json", $response;
	File::Slurp::write_file "$path/$hash.txt", "$url\n\n\n$request" if $write_txt;
}


sub request_hash ($$) {
	my ($url, $content) = @_;
	return Digest::MD5::md5_hex $url . ($content // '') if $hash_url;
	return Digest::MD5::md5_hex $content // '';
}


package Neo4j::Sim::Response;

sub status_line {
	my $status = ${ shift() }->{status};
	return "401 Unauthorized" if $status == 401;
	return "404 Not Found" if $status == 404;
	return "501 Not Implemented";
}


1;

__END__

This module implements enough parts of the REST::Client interface that it can
be used to simulate an active transactional HTTP connection to a Neo4j server.
To do so, it replays canned copies of earlier real responses from a live Neo4j
server that have been stored in a repository.

To populate the repository of canned responses used by the simulator,
insert these lines of code:

	use lib qw(./t/lib);
	use Neo4j::Sim;
	Neo4j::Sim->store("$tx_endpoint", $content, $client->responseContent()) if $method eq 'POST';

into the method:

	Neo4j::Driver::Transport::HTTP->_request

after the call to:

	$client->request(...)


The simulator operates most efficiently when repeated identical queries are
reused for multiple _autocommit_ transactions. The tests should be tailored
accordingly.

When writing tests, care must be taken to not repeat identical queries
on _explicit_ transactions. While some of these cases are handled by the
simulator when the $hash_url option is turned on, frequently the wrong
response is returned by mistake, which leads to test failures being reported
that can be difficult to debug.
