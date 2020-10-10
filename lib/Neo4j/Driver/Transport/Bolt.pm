use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::Transport::Bolt;
# ABSTRACT: Adapter for Neo4j::Bolt


use Carp qw(croak);
our @CARP_NOT = qw(Neo4j::Driver::Transaction);

use URI 1.25;
use Neo4j::Bolt;

use Neo4j::Driver::ServerInfo;
use Neo4j::Driver::StatementResult;


our $gather_results = 0;  # set to 1 to retrieve all data rows before creating the StatementResult (used for testing)


sub new {
	my ($class, $driver) = @_;
	
	my $uri = $driver->{uri};
	if ($driver->{auth}) {
		croak "Only Basic Authentication is supported" if $driver->{auth}->{scheme} ne 'basic';
		$uri = $uri->clone;
		$uri->userinfo( $driver->{auth}->{principal} . ':' . $driver->{auth}->{credentials} );
	}
	
	my $cxn;
	if ($driver->{tls}) {
		$cxn = Neo4j::Bolt->connect_tls("$uri", {
			timeout => $driver->{http_timeout},
			ca_file => $driver->{tls_ca},
		});
	}
	else {
		$cxn = Neo4j::Bolt->connect( "$uri", $driver->{http_timeout} );
	}
	unless ($cxn && $cxn->connected) {
		# Neo4j::Bolt < 0.10 didn't report human-readable error messages (perlbolt#24), so we re-create the most important ones here
		croak 'Bolt error -13: Unknown host' if ! $cxn->errmsg && $cxn->errnum == -13;
		croak 'Bolt error -14: Could not agree on a protocol version' if ! $cxn->errmsg && $cxn->errnum == -14;
		croak 'Bolt error -15: Username or password is invalid' if ! $cxn->errmsg && $cxn->errnum == -15;
		croak 'Bolt error ' . $cxn->errnum . ' ' . $cxn->errmsg;
	}
	
	return bless {
		connection => $cxn,
		server_info => Neo4j::Driver::ServerInfo->new({
			uri => $uri,
			version => $cxn->server_id,
		}),
		cypher_types => $driver->{cypher_types},
	}, $class;
}

# libneo4j-client error numbers:
# https://github.com/cleishm/libneo4j-client/blob/master/lib/src/neo4j-client.h.in


# Prepare query statement, including parameters. When multiple statements
# are to be combined in a single server communication, this method allows
# preparing each statement individually.
sub prepare {
	my ($self, $tx, $query, $parameters) = @_;
	
	my $statement = [$query, $parameters // {}];
	return $statement;
}


# Send statements to the Neo4j server and return all results.
sub run {
	my ($self, $tx, @statements) = @_;
	
	die "multiple statements not supported for Bolt" if @statements > 1;
	my ($statement) = @statements;
	
	my $statement_json = {
		statement => $statement->[0],
		parameters => $statement->[1],
	};
	
	my ($stream, $result);
	if ($statement->[0]) {
		$stream = $self->{connection}->run_query( @$statement );
		
		if (! $stream) {
			croak sprintf "Bolt error %i: %s", $self->{connection}->errnum, $self->{connection}->errmsg;
		}
		if ($stream->failure) {
			# failure() == -1 is an error condition because run_query_()
			# always calls update_errstate_rs_obj()
			croak sprintf "Bolt error %i: %s", $stream->client_errnum, $stream->client_errmsg unless $stream->server_errcode || $stream->server_errmsg;
			eval { $tx->rollback; };  # if rollback fails, too, report the primary error only
			croak sprintf "%s:\n%s\nBolt error %i: %s", $stream->server_errcode, $stream->server_errmsg, $stream->client_errnum, $stream->client_errmsg;
		}
		
		if ($gather_results) {
			$result = Neo4j::Driver::StatementResult->new({
				json => $self->_gather_results($stream),
				deep_bless => \&_deep_bless,
				statement => $statement_json,
				cypher_types => $self->{cypher_types},
				server_info => $self->{server_info},
			});
			return ($result);
		}
		
		my @names = $stream->field_names;
		$result = Neo4j::Driver::StatementResult->new({
			bolt_stream => $stream,
			bolt_connection => $self->{connection},
			json => { columns => \@names },
			deep_bless => \&_deep_bless,
			statement => $statement_json,
			cypher_types => $self->{cypher_types},
			server_info => $self->{server_info},
		});
	}
	
	return ($result);
}


sub _gather_results {
	my ($self, $stream) = @_;
	
	my @names = $stream->field_names;
	my @data = ();
	while ( my @row = $stream->fetch_next ) {
		
		croak 'next true and failure/success mismatch: ' . $stream->failure . '/' . $stream->success unless $stream->failure == -1 || $stream->success == -1 || ($stream->failure xor $stream->success);  # assertion
		croak 'next true and error: client ' . $stream->client_errnum . ' ' . $stream->client_errmsg . '; server ' . $stream->server_errcode . ' ' . $stream->server_errmsg if $stream->failure && $stream->failure != -1;
		
		push @data, { row => \@row, meta => [] };
	}
	
	croak 'next false and failure/success mismatch: ' . $stream->failure . '/' . $stream->success unless  $stream->failure == -1 || $stream->success == -1 || ($stream->failure xor $stream->success);  # assertion
	croak 'next false and error: client ' . $stream->client_errnum . ' ' . $stream->client_errmsg . '; server ' . $stream->server_errcode . ' ' . $stream->server_errmsg if $stream->failure && $stream->failure != -1;
	
	my $json = {
		columns => \@names,
		data => \@data,
		stats => $stream->update_counts(),
	};
	return $json;
}


# Declare that the specified transaction should be treated as an explicit
# transaction (i. e. it is opened at this time and will be closed by
# explicit command from the client).
sub begin {
	my ($self, $tx) = @_;
	
	$self->run( $tx, $self->prepare($tx, 'BEGIN') );
}


# Declare that the specified transaction should be treated as an autocommit
# transaction (i. e. it should automatically close successfully when the
# next statement is run).
sub autocommit {
}


# Mark the specified server transaction as successful and close it.
sub commit {
	my ($self, $tx) = @_;
	
	$self->run( $tx, $self->prepare($tx, 'COMMIT') );
}


# Mark the specified server transaction as failed and close it.
sub rollback {
	my ($self, $tx) = @_;
	
	$self->run( $tx, $self->prepare($tx, 'ROLLBACK') );
}


sub _deep_bless {
	my ($cypher_types, $data) = @_;
	
	if (ref $data eq 'Neo4j::Bolt::Node') {  # node
		my $node = $data->{properties} // {};
		bless $node, $cypher_types->{node};
		$node->{_meta} = {
			id => $data->{id},
			labels => $data->{labels},
		};
		$cypher_types->{init}->($node) if $cypher_types->{init};
		return $node;
	}
	if (ref $data eq 'Neo4j::Bolt::Relationship') {  # relationship
		my $rel = $data->{properties} // {};
		bless $rel, $cypher_types->{relationship};
		$rel->{_meta} = {
			id => $data->{id},
			start => $data->{start},
			end => $data->{end},
			type => $data->{type},
		};
		$cypher_types->{init}->($rel) if $cypher_types->{init};
		return $rel;
	}
	
	# support for Neo4j::Bolt 0.01 data structures (to be phased out)
	if (ref $data eq 'HASH' && defined $data->{_node}) {  # node
		bless $data, $cypher_types->{node};
		$data->{_meta} = {
			id => $data->{_node},
			labels => $data->{_labels},
		};
		$cypher_types->{init}->($data) if $cypher_types->{init};
		return $data;
	}
	if (ref $data eq 'HASH' && defined $data->{_relationship}) {  # relationship
		bless $data, $cypher_types->{relationship};
		$data->{_meta} = {
			id => $data->{_relationship},
			start => $data->{_start},
			end => $data->{_end},
			type => $data->{_type},
		};
		$cypher_types->{init}->($data) if $cypher_types->{init};
		return $data;
	}
	
	if (ref $data eq 'Neo4j::Bolt::Path') {  # path
		bless $data, $cypher_types->{path};
		foreach my $i ( 0 .. $#{$data} ) {
			$data->[$i] = _deep_bless($cypher_types, $data->[$i]);
		}
		return $data;
	}
	
	if (ref $data eq 'ARRAY') {  # array
		foreach my $i ( 0 .. $#{$data} ) {
			$data->[$i] = _deep_bless($cypher_types, $data->[$i]);
		}
		return $data;
	}
	if (ref $data eq 'HASH') {  # and neither node nor relationship ==> map
		foreach my $key ( keys %$data ) {
			$data->{$key} = _deep_bless($cypher_types, $data->{$key});
		}
		return $data;
	}
	
	if (ref $data eq '') {  # scalar
		return $data;
	}
	if (ref $data eq 'JSON::PP::Boolean') {  # boolean
		return $data;
	}
	
	die "Assertion failed: unexpected type: " . ref $data;
}


1;

__END__

=head1 DESCRIPTION

The L<Neo4j::Driver::Transport::Bolt> package is not part of the
public L<Neo4j::Driver> API.

=cut
