use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::Result::Bolt;
# ABSTRACT: Bolt result handler


use parent 'Neo4j::Driver::Result';

use Carp qw(croak);


our $gather_results = 0;  # 1: detach from the stream immediately (yields JSON-style result; used for testing)


sub new {
	# uncoverable pod (private method)
	my ($class, $params) = @_;
	
	# Holding a reference to the Bolt connection is important, because
	# Neo4j::Bolt automatically closes the session upon object destruction.
	# Perl uses reference counting to control its garbage collector, so we
	# need to hold that reference {cxn} until we detach from the stream,
	# even though we never use the connection object directly.
	
	my $self = {
		attached => 1,   # 1: unbuffered records may exist on the stream
		exhausted => 0,  # 1: all records read by the client; fetch() will fail
		buffer => [],
		columns => undef,
		summary => undef,
		cypher_types => $params->{cypher_types},
		statement => $params->{statement},
		cxn => $params->{bolt_connection},  # important to avoid dereferencing the connection
		stream => $params->{bolt_stream},
		server_info => $params->{server_info},
	};
	bless $self, $class;
	
	return $self->_gather_results if $gather_results;
	
	my @names = $params->{bolt_stream}->field_names;
	$self->{result} = { columns => \@names };
	
	return $self;
}


sub _gather_results {
	my ($self) = @_;
	
	my $stream = $self->{stream};
	my @names = $stream->field_names;
	my @data = ();
	while ( my @row = $stream->fetch_next ) {
		
		croak 'next true and failure/success mismatch: ' . $stream->failure . '/' . $stream->success unless $stream->failure == -1 || $stream->success == -1 || ($stream->failure xor $stream->success);  # assertion
		croak 'next true and error: client ' . $stream->client_errnum . ' ' . $stream->client_errmsg . '; server ' . $stream->server_errcode . ' ' . $stream->server_errmsg if $stream->failure && $stream->failure != -1;
		
		push @data, { row => \@row, meta => [] };
	}
	
	croak 'next false and failure/success mismatch: ' . $stream->failure . '/' . $stream->success unless  $stream->failure == -1 || $stream->success == -1 || ($stream->failure xor $stream->success);  # assertion
	croak 'next false and error: client ' . $stream->client_errnum . ' ' . $stream->client_errmsg . '; server ' . $stream->server_errcode . ' ' . $stream->server_errmsg if $stream->failure && $stream->failure != -1;
	
	$self->{stream} = undef;
	$self->{cxn} = undef;
	$self->{result} = {
		columns => \@names,
		data => \@data,
		stats => $stream->update_counts(),
	};
	return $self->_as_fully_buffered;
}


sub _fetch_next {
	my ($self) = @_;
	
	return $self->SUPER::_fetch_next unless $self->{stream};
	
	my (@row, $record);
	@row = $self->{stream}->fetch_next;
	$record = { row => \@row } if @row;
	
	unless ($self->{stream}->success) {
		# success() == -1 is not an error condition; it simply
		# means that there are no more records on the stream
		my $stream = $self->{stream};
		croak sprintf "Bolt error %i: %s", $stream->client_errnum, $stream->client_errmsg unless $stream->server_errcode || $stream->server_errmsg;
		croak sprintf "%s:\n%s\nBolt error %i: %s", $stream->server_errcode, $stream->server_errmsg, $stream->client_errnum, $stream->client_errmsg;
	}
	
	return $self->_init_record( $record );
}


sub _init_record {
	my ($self, $record, $cypher_types) = @_;
	
	return undef unless $record;  ##no critic (ProhibitExplicitReturnUndef)
	
	$record->{column_keys} = $self->{columns};
	$self->_deep_bless( $record->{row} );
	return bless $record, 'Neo4j::Driver::Record';
}


sub _deep_bless {
	my ($self, $data) = @_;
	my $cypher_types = $self->{cypher_types};
	
	if (ref $data eq 'Neo4j::Bolt::Node') {  # node
		my $node = \( $data->{properties} // {} );
		bless $node, $cypher_types->{node};
		$$node->{_meta} = {
			id => $data->{id},
			labels => $data->{labels},
		};
		$cypher_types->{init}->($node) if $cypher_types->{init};
		return $node;
	}
	if (ref $data eq 'Neo4j::Bolt::Relationship') {  # relationship
		my $rel = \( $data->{properties} // {} );
		bless $rel, $cypher_types->{relationship};
		$$rel->{_meta} = {
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
		my $node = bless \$data, $cypher_types->{node};
		$data->{_meta} = {
			id => $data->{_node},
			labels => $data->{_labels},
		};
		$cypher_types->{init}->($node) if $cypher_types->{init};
		return $node;
	}
	if (ref $data eq 'HASH' && defined $data->{_relationship}) {  # relationship
		my $rel = bless \$data, $cypher_types->{relationship};
		$data->{_meta} = {
			id => $data->{_relationship},
			start => $data->{_start},
			end => $data->{_end},
			type => $data->{_type},
		};
		$cypher_types->{init}->($rel) if $cypher_types->{init};
		return $rel;
	}
	
	if (ref $data eq 'Neo4j::Bolt::Path') {  # path
		my $path = bless { path => $data }, $cypher_types->{path};
		foreach my $i ( 0 .. $#{$data} ) {
			$data->[$i] = $self->_deep_bless($data->[$i]);
		}
		$cypher_types->{init}->($path) if $cypher_types->{init};
		return $path;
	}
	
	if (ref $data eq 'ARRAY') {  # array
		foreach my $i ( 0 .. $#{$data} ) {
			$data->[$i] = $self->_deep_bless($data->[$i]);
		}
		return $data;
	}
	if (ref $data eq 'HASH') {  # and neither node nor relationship ==> map
		foreach my $key ( keys %$data ) {
			$data->{$key} = $self->_deep_bless($data->{$key});
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
