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

use Neo4j::Driver::StatementResult;


sub new {
	my ($class, $driver) = @_;
	
	my $uri = $driver->{uri};
	if ($driver->{auth}) {
		croak "Only Basic Authentication is supported" if $driver->{auth}->{scheme} ne 'basic';
		$uri = $uri->clone;
		$uri->userinfo( $driver->{auth}->{principal} . ':' . $driver->{auth}->{credentials} );
	}
	
	my $cxn = Neo4j::Bolt->connect("$uri");
	unless ($cxn && $cxn->connected) {
		# libneo4j-client seems to not always report human-readable error messages, so we re-create the most important ones here
		croak 'Bolt error -13: Unknown host' if ! $cxn->errmsg && $cxn->errnum == -13;
		croak 'Bolt error -15: Username or password is invalid' if ! $cxn->errmsg && $cxn->errnum == -15;
		croak 'Bolt error ' . $cxn->errnum . ' ' . $cxn->errmsg;
	}
	
	return bless {
		connection => $cxn,
		uri => $driver->{uri},
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
	
	# multiple statements not yet supported for Bolt
	my ($statement) = @statements;
	
	my ($stream, $json, $summary);
	if ($statement->[0]) {
		$stream = $self->{connection}->run_query( @$statement );
		
		croak 'Bolt error ' . $self->{connection}->errnum . ' ' . $self->{connection}->errmsg unless $stream;
		
		# There is some sort of strange problem passing any data structures
		# that come from the Neo4j::Bolt result stream along
		# to StatementResult. As a workaround, for now we consume the full
		# stream right here and re-create the JSON result data structure.
		# Not sure if this issue occurs outside the tests.
		my @names = $stream->field_names;
		my @data = ();
		while ( my @row = $stream->fetch_next ) {
			
			croak 'next true and failure/success mismatch: ' . $stream->failure . '/' . $stream->success unless $stream->failure == -1 || $stream->success == -1 || ($stream->failure xor $stream->success);  # assertion
			croak 'next true and error: client ' . $stream->client_errnum . ' ' . $stream->client_errmsg . '; server ' . $stream->server_errcode . ' ' . $stream->server_errmsg if $stream->failure && $stream->failure != -1;
			
			push @data, { row => \@row, meta => [] };
		}
		
		croak 'next false and failure/success mismatch: ' . $stream->failure . '/' . $stream->success unless  $stream->failure == -1 || $stream->success == -1 || ($stream->failure xor $stream->success);  # assertion
		croak 'next false and error: client ' . $stream->client_errnum . ' ' . $stream->client_errmsg . '; server ' . $stream->server_errcode . ' ' . $stream->server_errmsg if $stream->failure && $stream->failure != -1;
		
		my $stats = {};
		my @counters = qw(
			nodes_created
			nodes_deleted
			relationships_created
			properties_set
			labels_added
			labels_removed
			indexes_added
			indexes_removed
			constraints_added
			constraints_removed
		);
		for my $c (@counters) { eval {$stats->{$c} = $stream->update_counts()->{$c} } }
		eval {$stats->{relationship_deleted} = $stream->update_counts()->{relationships_deleted}};
		
		$json = {
			columns => \@names,
			data => \@data,
			stats => $stats,
		};
		my $statement_summary = {statement => shift @$statement};
		$statement_summary->{parameters} = $statement->[0];
		$summary = Neo4j::Driver::ResultSummary->new( $json, {}, $statement_summary );
	}
	
	my $result = Neo4j::Driver::StatementResult->new( $json, $summary, \&_deep_bless );
	return ($result);
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


sub server_info {
	my ($self) = @_;
	
	# That the ServerInfo is provided by the same object
	# is an implementation detail that might change in future.
	return $self;
}


# server_info->
sub address {
	my ($self) = @_;
	
	return URI->new( $self->{uri} )->host_port;
}


# server_info->
sub version {
	my ($self) = @_;
	
	...
}


sub _deep_bless {
	my ($data) = @_;
	
	if (ref $data eq 'HASH' && defined $data->{_node}) {  # node
		bless $data, 'Neo4j::Driver::Type::Node';
		$data->{_meta} = {
			id => $data->{_node},
			labels => $data->{_labels},
		};
		return $data;
	}
	if (ref $data eq 'HASH' && defined $data->{_relationship}) {  # relationship
		bless $data, 'Neo4j::Driver::Type::Relationship';
		$data->{_meta} = {
			id => $data->{_relationship},
			start => $data->{_start},
			end => $data->{_end},
			type => $data->{_type},
		};
		return $data;
	}
	
# 	if (ref $data eq 'ARRAY' && ref $rest eq 'HASH' && defined $rest->{length}) {  # path
# 		# unimplemented:
# 		# no discernible difference to array in Neo4j::Bolt
# 		bless $data, 'Neo4j::Driver::Type::Path';
# 		return;
# 	}
	
	if (ref $data eq 'ARRAY') {  # array
		foreach my $i ( 0 .. $#{$data} ) {
			$data->[$i] = _deep_bless($data->[$i]);
		}
		return $data;
	}
	if (ref $data eq 'HASH') {  # and neither node nor relationship ==> map
		foreach my $key ( keys %$data ) {
			$data->{$key} = _deep_bless($data->{$key});
		}
		return $data;
	}
	
	if (ref $data eq '') {  # scalar
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
