use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::Session;
# ABSTRACT: Context of work for database interactions


use Cpanel::JSON::XS 3.0201 qw(decode_json);
use URI 1.25;

use Neo4j::Driver::Transaction;


sub new {
	my ($class, $transport) = @_;
	
	my $session = {
#		driver => $driver,
#		uri => $driver->{uri}->clone,
		transport => $transport,
	};
	
	return bless $session, $class;
}


sub begin_transaction {
	my ($self) = @_;
	
	my $t = Neo4j::Driver::Transaction->new($self);
	return $t->_explicit;
}


sub run {
	my ($self, $query, @parameters) = @_;
	
	my $t = Neo4j::Driver::Transaction->new($self);
	return $t->_autocommit->run($query, @parameters);
}


sub close {
	warnings::warnif deprecated => __PACKAGE__ . "->close() is deprecated";
}


sub server {
	my ($self) = @_;
	
	return $self->{transport}->server_info;
}


1;

__END__

=head1 SYNOPSIS

 use Neo4j::Driver;
 $session = Neo4j::Driver->new->basic_auth(...)->session;
 
 # explicit transaction
 $transaction = $session->begin_transaction;
 
 # autocommit transaction
 $result = $session->run('MATCH (m:Movie) RETURN m.name, m.year');

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

Only one open transaction per session at a time is supported. To
work with multiple concurrent transactions (also known as "nested
transactions"), simply use more than one session.

=head1 METHODS

L<Neo4j::Driver::Session> implements the following methods.

=head2 begin_transaction

 $transaction = $session->begin_transaction;

Begin a new explicit L<Transaction|Neo4j::Driver::Transaction>.

=head2 run

 $result = $session->run('...');

Run and commit a statement using an autocommit transaction and return
the L<StatementResult|Neo4j::Driver::StatementResult>.

This method is semantically exactly equivalent to the following code,
but is faster because it doesn't require an extra server roundtrip to
commit the transaction.

 $transaction = $session->begin_transaction;
 $result = $transaction->run('...');
 $transaction->commit;

=head1 EXPERIMENTAL FEATURES

L<Neo4j::Driver::Session> implements the following experimental
features. These are subject to unannounced modification or removal
in future versions. Expect your code to break if you depend upon
these features.

=head2 Calling in list context

 @records = $session->run('...');
 @results = $session->run([...]);

The C<run> method tries to Do What You Mean if called in list
context.

=head2 ServerInfo

 $host_port = $session->server->address;
 $version_string = $session->server->version;
 say "Contacting $version_string at $host_port.";

For security reasons, L<ResultSummary|Neo4j::Driver::ResultSummary>
cannot provide C<ServerInfo>. Therefore, C<ServerInfo> is available
from the L<Session|Neo4j::Driver::Session> instead.

In future, an extra server round-trip I<just> to obtain the Neo4j
version number might be a way to get around this restriction and
offer the C<ServerInfo> strings through
L<ResultSummary|Neo4j::Driver::ResultSummary> after all. However,
I'm really not sure if the ensuing performance penalty is worth it.

=head2 Concurrent explicit transactions

 $session = Neo4j::Driver->new('http://...')->basic_auth(...)->session;
 $tx1 = $session->begin_transaction;
 $tx2 = $session->begin_transaction;

Since HTTP is a stateless protocol, the Neo4j HTTP API effectively
allows multiple concurrently open transactions without special
client-side considerations. This driver exposes this feature to the
client and will continue to do so, but the interface is not yet
finalised.

The Bolt protocol does not support concurrent explicit transactions.

=head2 Concurrent autocommit transactions

 $tx1 = $session->begin_transaction;
 $tx2 = $session->run(...);

Sessions support autocommit transactions while an explicit
transaction is open. Since it is not clear to me if this is
intended behaviour when the Bolt protocol is used, this feature
is listed as experimental.

=head1 SECURITY CONSIDERATIONS

Both L<Session|Neo4j::Driver::Session> as well as
L<Transaction|Neo4j::Driver::Transaction> objects internally hold
references to the authentication credentials used to contact the
Neo4j server. Objects of these classes should therefore not be
passed to untrusted modules. However, objects of the
L<StatementResult|Neo4j::Driver::StatementResult> class do not
contain a reference to these credentials and are safe in this
regard.

=head1 SEE ALSO

=over

=item * L<Neo4j::Driver>

=item * L<Neo4j::Driver::B<Transaction>>,
L<Neo4j::Driver::B<StatementResult>>

=item * Equivalent documentation for the official Neo4j drivers:
L<Session (Java)|https://neo4j.com/docs/api/java-driver/current/index.html?org/neo4j/driver/Session.html>,
L<Session (JavaScript)|https://neo4j.com/docs/api/javascript-driver/current/class/src/session.js~Session.html>,
L<ISession (.NET)|https://neo4j.com/docs/api/dotnet-driver/4.0/html/6bcf5d8c-98e7-b521-03e7-210cd6155850.htm>

=back

=cut
