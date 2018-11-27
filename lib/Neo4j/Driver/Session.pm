use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::Session;
# ABSTRACT: context of work for database interactions


use Neo4j::Driver::Transaction;


sub new {
	my ($class, $driver) = @_;
	
	# this method might initiate the HTTP connection, but doesn't as of yet
	
	my $session = {
#		driver => $driver,
#		uri => $driver->{uri}->clone,
		client => $driver->_client,
		die_on_error => $driver->{die_on_error},
	};
	
	return bless $session, $class;
}


sub begin_transaction {
	my ($self) = @_;
	
	# this method might initiate the HTTP connection, but doesn't as of yet
	return Neo4j::Driver::Transaction->new($self);
}


sub run {
	my ($self, $query, @parameters) = @_;
	
	my $t = $self->begin_transaction();
	return $t->_commit($query, @parameters);
}


sub close {
}


1;

__END__

=head1 SYNOPSIS

 use Neo4j::Driver;
 my $session = Neo4j::Driver->new->basic_auth(...)->session;
 
 # explicit transaction
 my $transaction = $session->begin_transaction;
 
 # autocommit transaction
 my $result = $session->run('MATCH (m:Movie) RETURN m.name, m.year');

=head1 DESCRIPTION

Provides a context of work for database interactions.

A Session hosts a series of transactions carried out against a
database. Within the database, all statements are carried out within
a transaction. Within application code, however, it is not always
necessary to explicitly begin a transaction. If a statement is run
directly against a Session, the server will automatically C<BEGIN>
and C<COMMIT> that statement within its own transaction. This type
of transaction is known as an I<autocommit transaction>.

I<Explicit transactions> allow multiple statements to be committed
as part of a single atomic operation and can be rolled back if
necessary.

=head1 METHODS

L<Neo4j::Driver::Session> implements the following methods.

=head2 begin_transaction

 my $transaction = $session->begin_transaction;

Begin a new explicit L<Transaction|Neo4j::Driver::Transaction>.

=head2 run

 my $result = $session->run('...');

Run and commit a statement using an autocommit transaction and return
the result.

This method is semantically exactly equivalent to the following code,
but is faster because it doesn't require an extra server roundtrip to
commit the transaction.

 my $transaction = $session->begin_transaction;
 my $result = $transaction->run('...');
 $transaction->commit;

=head1 EXPERIMENTAL FEATURES

L<Neo4j::Driver::Session> implements the following experimental
features. These are subject to unannounced modification or removal
in future versions. Expect your code to break if you depend upon
these features.

=head2 Calling in list context

 my @records = $session->run('...');
 my @results = $session->run([...]);

The C<run> method tries to Do What You Mean if called in list
context.

=head2 Close method

C<close> is currently a no-op in this class.

=head1 BUGS

The implementation of sessions in this driver is incomplete. In
particular, some of the official drivers implement restrictions on
the count of transactions that can be used per session and offer
additional methods to manage transactions.

See the F<TODO> document and Github for details.

=head1 SEE ALSO

L<Neo4j::Driver>,
L<Neo4j Java Driver|https://neo4j.com/docs/api/java-driver/current/index.html?org/neo4j/driver/v1/Session.html>,
L<Neo4j JavaScript Driver|https://neo4j.com/docs/api/javascript-driver/current/class/src/v1/session.js~Session.html>,
L<Neo4j .NET Driver|https://neo4j.com/docs/api/dotnet-driver/current/html/bd812bce-8d2c-f29e-6c2a-cf93bd3d85d7.htm>

=cut
