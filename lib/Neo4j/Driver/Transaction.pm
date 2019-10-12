use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::Transaction;
# ABSTRACT: Logical container for an atomic unit of work


use Carp qw(croak);
our @CARP_NOT = qw(Neo4j::Driver::Session Neo4j::Driver);
use Scalar::Util qw(blessed);

use Neo4j::Driver::StatementResult;


sub new {
	my ($class, $session) = @_;
	
	my $transaction = {
		transport => $session->{transport},
		open => 1,
		return_graph => 0,
		return_stats => 1,
	};
	
	return bless $transaction, $class;
}


sub run {
	my ($self, $query, @parameters) = @_;
	
	croak 'Transaction already closed' unless $self->is_open;
	
	my @statements;
	if (ref $query eq 'ARRAY') {
		foreach my $args (@$query) {
			push @statements, $self->_prepare(@$args);
		}
	}
	elsif ($query) {
		@statements = ( $self->_prepare($query, @parameters) );
	}
	else {
		@statements = ();
	}
	
	my @results = $self->{transport}->run($self, @statements);
	
	if (scalar @statements <= 1) {
		my $result = $results[0] // Neo4j::Driver::StatementResult->new;
		return wantarray ? $result->list : $result;
	}
	return wantarray ? @results : \@results;
}


sub _prepare {
	my ($self, $query, @parameters) = @_;
	
	croak 'Query cannot be unblessed reference' if ref $query && ! blessed $query;
	if ($query->isa('REST::Neo4p::Query')) {
		# REST::Neo4p::Query->query is not part of the documented API
		$query = '' . $query->query;
	}
	
	my $params;
	if (ref $parameters[0] eq 'HASH') {
		$params = $parameters[0];
	}
	elsif (@parameters) {
		croak 'Query parameters must be given as hash or hashref' if ref $parameters[0];
		croak 'Odd number of elements in query parameter hash' if scalar @parameters % 2 != 0;
		$params = {@parameters};
	}
	
	$self->{transport}->{return_graph} = $self->{return_graph};
	$self->{transport}->{return_stats} = $self->{return_stats};
	return $self->{transport}->prepare($self, $query, $params);
}


sub _explicit {
	my ($self) = @_;
	
	$self->{transport}->begin($self);
	return $self;
}


sub _autocommit {
	my ($self) = @_;
	
	$self->{transport}->autocommit($self);
	return $self;
}


sub commit {
	my ($self) = @_;
	
	croak 'Transaction already closed' unless $self->is_open;
	
	$self->{transport}->commit($self);
	$self->{open} = 0;
}


sub rollback {
	my ($self) = @_;
	
	croak 'Transaction already closed' unless $self->is_open;
	
	$self->{transport}->rollback($self);
	$self->{open} = 0;
}


sub is_open {
	my ($self) = @_;
	
	return $self->{open};
}


1;

__END__

=head1 SYNOPSIS

 use Neo4j::Driver;
 my $session = Neo4j::Driver->new->basic_auth(...)->session;
 
 # Commit
 my $tx = $session->begin_transaction;
 my $node_id = $tx->run(
   'CREATE (p:Person) RETURN id(p)'
 )->single->get;
 $tx->run(
   'MATCH (p) WHERE id(p) = {id} SET p.name = {name}',
   {id => $node_id, name => 'Douglas'}
 );
 $tx->commit;
 
 # Rollback
 my $tx = $session->begin_transaction;
 my $tx->run('CREATE (a:Universal:Answer {value:42})');
 $tx->rollback;

=head1 DESCRIPTION

Logical container for an atomic unit of work that is either committed
in its entirety or is rolled back on failure. A driver Transaction
object corresponds to a server transaction.

Statements may be run lazily. Most of the time, you will not notice
this, because the driver automatically waits for statements to
complete at specific points to fulfill its contracts. If you require
execution of a statement to have completed, you need to use the
L<result|Neo4j::Driver::StatementResult>, for example by calling
one of the methods C<fetch()>, C<list()> or C<summary()>.

Transactions are often wrapped in a C<try> (or C<eval>) block to
ensure that C<commit> and C<rollback> occur correctly. Note that the
server will automatically roll back the transaction if any database
errors occur while executing statements.

 use Try::Tiny;
 try {
   $result = $tx->run($query, \%parameters);
   $tx->commit;
 }
 catch {
   say "Database error: $_";
   say "Transaction closed by server." if ! $tx->is_open;
 };

After C<commit> or C<rollback>, the transaction is automatically
closed by the server and can no longer be used. The C<is_open> method
can be used to determine the server-side transaction status.

=head1 METHODS

L<Neo4j::Driver::Transaction> implements the following methods.

=head2 commit

 $transaction->commit;

Commits the transaction and returns the result.

After committing the transaction is closed and can no longer be used.

=head2 is_open

 my $bool = $transaction->is_open;

Detect whether this transaction is still open, which means commit
or rollback did not happen.

Note that this method does not request the transaction status from
the Neo4j server. Instead, it uses the status information the server
provided along with its previous response, which may be outdated. In
particular, a transaction can timeout on the server due to
inactivity, in which case it may in fact be closed even though
this method returns a true value. The Neo4j server default
C<dbms.transaction_timeout> is 60 seconds.

=head2 rollback

 $transaction->rollback;

Rollbacks the transaction.

After rolling back the transaction is closed and can no longer be
used.

=head2 run

 my $result = $transaction->run($query, %params);

Run a statement and return the L<StatementResult|Neo4j::Driver::StatementResult>.
This method takes an optional set of parameters that will be injected
into the Cypher statement by Neo4j. Using parameters is highly
encouraged: It helps avoid dangerous Cypher injection attacks and
improves database performance as Neo4j can re-use query plans more
often.

Parameters are given as Perl hashref. Alternatively, they may be
given as a hash / balanced list.

 # all of these are semantically equal
 my $result = $transaction->run('...', {key => 'value'});
 my $result = $transaction->run('...',  key => 'value' );
 my %hash = (key => 'value');
 my $result = $transaction->run('...', \%hash);
 my $result = $transaction->run('...',  %hash);

When used as parameters, Perl values are converted to Neo4j types as
shown in the following example:

 my $parameters = {
   number =>  0 + $scalar,
   string => '' . $scalar,
   true   => \1,
   false  => \0,
   null   => undef,
   list   => [ ],
   map    => { },
 };

A Perl scalar may internally be represented as a number or a string
(see L<perldata/Scalar values>). Perl usually auto-converts one into
the other based on the context in which the scalar is used. However,
Perl cannot know the context of a Neo4j query parameter, because
queries are just opaque strings to Perl. Most often your scalars will
already have the correct internal flavour. A typical example for a
situation in which this is I<not> the case are numbers parsed out
of strings using regular expressions. If necessary, you can force
conversion of such values into the correct type using unary coercions
as shown in the example above.

Running empty queries is supported. Such queries establish a
connection with the Neo4j server, which returns a result with zero
records. This feature may be used to reset the transaction timeout
or test the connection to the server.

 my $result = $transaction->run;

Queries are usually strings, but may also be L<REST::Neo4p::Query> or
L<Neo4j::Cypher::Abstract> objects. Such objects are automatically
converted to strings before they are sent to the Neo4j server.

 $transaction->run( REST::Neo4p::Query->new('RETURN 42') );
 $transaction->run( Neo4j::Cypher::Abstract->new->return(42) );

=head1 EXPERIMENTAL FEATURES

L<Neo4j::Driver::Transaction> implements the following experimental
features. These are subject to unannounced modification or removal
in future versions. Expect your code to break if you depend upon
these features.

=head2 Calling in list context

 my @records = $transaction->run('...');
 my @results = $transaction->run([...]);

The C<run> method tries to Do What You Mean if called in list
context.

=head2 Execute multiple statements at once

 my $statements = [
   [ 'RETURN 42' ],
   [ 'RETURN {value}', value => 'forty-two' ],
 ];
 my $results = $transaction->run($statements);
 foreach my $result ( @$results ) {
   say $result->single->get;
 }

The Neo4j HTTP API supports executing multiple statements within a
single HTTP request. This driver exposes this feature to the client.

This feature is likely to be removed from this driver in favour of
lazy execution, similar to the official Neo4j drivers.

=head2 Disable obtaining query statistics

 my $transaction = $session->begin_transaction;
 $transaction->{return_stats} = 0;
 my $result = $transaction->run('...');

Since version 0.13, this driver requests query statistics from the
Neo4j server by default. When using HTTP, this behaviour can be
disabled. Doing so might provide a very minor performance increase.

The ability to disable the statistics may be removed in future.

=head2 Return results in graph format

 my $transaction = $session->begin_transaction;
 $transaction->{return_graph} = 1;
 my $records = $transaction->run('...')->list;
 for $record ( @$records ) {
   my $graph_data = $record->{graph};
   ...
 }

The Neo4j HTTP API supports a "graph" results data format. This driver
exposes this feature to the client and will continue to do so, but
the interface is not yet finalised.

=head1 SEE ALSO

L<Neo4j::Driver>,
L<Neo4j::Driver::StatementResult>,
L<Neo4j Java Driver|https://neo4j.com/docs/api/java-driver/current/index.html?org/neo4j/driver/v1/Transaction.html>,
L<Neo4j JavaScript Driver|https://neo4j.com/docs/api/javascript-driver/current/class/src/v1/transaction.js~Transaction.html>,
L<Neo4j .NET Driver|https://neo4j.com/docs/api/dotnet-driver/current/html/ec1f5ba3-57f9-bdc6-9121-f595def04a00.htm>,
L<Neo4j Python Driver|https://neo4j.com/docs/api/python-driver/current/transactions.html>,
L<Neo4j Transactional Cypher HTTP API|https://neo4j.com/docs/developer-manual/3.0/http-api/>

=cut
