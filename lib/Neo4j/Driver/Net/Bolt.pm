use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::Net::Bolt;
# ABSTRACT: Networking delegate for Neo4j Bolt


use Carp qw(croak);
our @CARP_NOT = qw(Neo4j::Driver::Transaction Neo4j::Driver::Transaction::Bolt);

use URI 1.25;

use Neo4j::Driver::Result::Bolt;
use Neo4j::Driver::ServerInfo;


# Neo4j::Bolt < 0.10 didn't report human-readable error messages
# (perlbolt#24), so we re-create the most common ones here
my %BOLT_ERROR = (
	 61 => "Connection refused",
	-13 => "Unknown host",
	-14 => "Could not agree on a protocol version",
	-15 => "Username or password is invalid",
	-22 => "Statement evaluation failed",
);


sub new {
	my ($class, $driver) = @_;
	
	my $uri = $driver->{uri};
	if ($driver->{auth}) {
		croak "Only Basic Authentication is supported" if $driver->{auth}->{scheme} ne 'basic';
		$uri = $uri->clone;
		$uri->userinfo( $driver->{auth}->{principal} . ':' . $driver->{auth}->{credentials} );
	}
	
	my $net_module = $driver->{net_module} // 'Neo4j::Bolt';
	if ($net_module eq 'Neo4j::Bolt') {
		croak $@ . "URI scheme 'bolt' requires Neo4j::Bolt"
			unless eval { require Neo4j::Bolt; 1 };
	}
	
	my $cxn;
	if ($driver->{tls}) {
		$cxn = $net_module->connect_tls("$uri", {
			timeout => $driver->{http_timeout},
			ca_file => $driver->{tls_ca},
		});
	}
	else {
		$cxn = $net_module->connect( "$uri", $driver->{http_timeout} );
	}
	croak $class->_bolt_error($cxn) unless $cxn->connected;
	
	return bless {
		connection => $cxn,
		server_info => Neo4j::Driver::ServerInfo->new({
			uri => $uri,
			version => $cxn->server_id,
		}),
		cypher_types => $driver->{cypher_types},
		active_tx => 0,
	}, $class;
}


sub _bolt_error {
	my (undef, $ref) = @_;
	
	my ($errnum, $errmsg);
	($errnum, $errmsg) = ($ref->errnum, $ref->errmsg) if $ref->can('errnum');
	($errnum, $errmsg) = ($ref->client_errnum, $ref->client_errmsg) if $ref->can('client_errnum');
	
	$errmsg //= $BOLT_ERROR{$errnum};
	return "Bolt error $errnum: $errmsg" if $errmsg;
	return "Bolt error $errnum";
}


sub _server {
	my ($self) = @_;
	return $self->{server_info};
}


# Update requested database name.
sub _set_database {
	my ($self, $database) = @_;
	
	$self->{database} = $database;
}


# Send statements to the Neo4j server and return a list of all results.
sub _run {
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
			$tx->{closed} = 1;
			$self->{active_tx} = 0;
			croak $self->_bolt_error( $self->{connection} );
		}
		if ($stream->failure) {
			# failure() == -1 is an error condition because run_query_()
			# always calls update_errstate_rs_obj()
			
			if ( ! $stream->server_errcode && ! $stream->server_errmsg ) {
				$tx->{closed} = 1;
				$self->{active_tx} = 0;
				croak $self->_bolt_error( $stream );
			}
			
			# <https://neo4j.com/docs/status-codes/4.2/> suggests that
			# transactions should already have been rolled back and
			# closed automatically at this point due to the server error.
			# This is usually what happens on HTTP (but see neo4j#12651).
			# However, on Bolt, the transaction tends to remain open
			# (albeit marked as failed, thus uncommittable). Just
			# attempting an explicit rollback whenever the Neo4j server
			# reports any errors should fix that. If there are additional
			# errors during the rollback, those can be ignored.
			eval { $tx->rollback };
			$tx->{closed} = 1;
			$self->{active_tx} = 0;
			
			croak sprintf "%s:\n%s\n%s", $stream->server_errcode, $stream->server_errmsg, $self->_bolt_error( $stream );
		}
		
		$result = Neo4j::Driver::Result::Bolt->new({
			bolt_stream => $stream,
			bolt_connection => $self->{connection},
			statement => $statement_json,
			cypher_types => $self->{cypher_types},
			server_info => $self->{server_info},
		});
	}
	
	return ($result);
}


1;

__END__

=head1 DESCRIPTION

The L<Neo4j::Driver::Net::Bolt> package is not part of the
public L<Neo4j::Driver> API.

=cut
