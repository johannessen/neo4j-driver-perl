use v5.14;
use warnings;

package Neo4j::Driver::Session;
# ABSTRACT: Context of work for database interactions


use Carp qw(croak);
our @CARP_NOT = qw(
	Neo4j::Driver
);
use Feature::Compat::Try;
use List::Util qw(min);
use Scalar::Util qw(blessed);
use Time::HiRes ();
use URI 1.25;

use Neo4j::Driver::Net::Bolt;
use Neo4j::Driver::Net::HTTP;
use Neo4j::Driver::Transaction;
use Neo4j::Error;


sub new {
	# uncoverable pod (private method)
	my ($class, $driver) = @_;
	
	return Neo4j::Driver::Session::Bolt->new($driver) if $driver->config('uri')->scheme eq 'bolt';
	return Neo4j::Driver::Session::HTTP->new($driver);
}


# Connect and get ServerInfo (via Bolt HELLO or HTTP Discovery API),
# then determine the default database name for Neo4j >= 4.
sub _connect {
	my ($self, $database) = @_;
	
	my $neo4j_version = $self->server->agent;  # ensure contact with the server has been made
	$self->{cypher_params_v2} = 0 if $neo4j_version =~ m{^Neo4j/2\.};  # no conversion required
	
	$database //= $self->server->_default_database($self->{driver});
	$self->{net}->_set_database($database);
	return $self;
}


sub begin_transaction {
	my ($self) = @_;
	
	return $self->new_tx->_begin;
}


sub run {
	my ($self, $query, @parameters) = @_;
	
	return $self->new_tx->_run_autocommit($query, @parameters);
}


sub _execute {
	my ($self, $mode, $func) = @_;
	
	croak sprintf "%s->execute_%s() requires subroutine ref", __PACKAGE__, lc $mode unless ref $func eq 'CODE';
	
	$self->{retry_sleep} //= 1;
	my (@r, $r);
	my $time_stop = Time::HiRes::time
		+ ($self->{driver}->config('max_transaction_retry_time') // 30);  # seconds
	my $tries = 0;
	while () {
		my $tx = $self->new_tx($mode);
		$tx->{error_handler} = sub { die shift };
		
		try {
			$tx->_begin;
			$tx->{managed} = 1;  # Disallow commit() in $func
			wantarray ? @r = $func->($tx) : $r = $func->($tx);
			$tx->{managed} = 0;
			$tx->commit;
			
			return unless defined wantarray;
			$r = $r[0] if wantarray;
			warnings::warnif closure => "Result object may not be valid outside the transaction function"
				if blessed $r && $r->isa('Neo4j::Driver::Result');
			
			return wantarray ? @r : $r;
		}
		catch ($e) {
			# The tx may or may not already be closed; we need to make sure
			$tx->{managed} = 0;
			try { $tx->rollback } catch ($f) {}
			
			# Never retry non-Neo4j errors
			croak $e unless blessed $e && $e->isa('Neo4j::Error');
			
			if (! $e->is_retryable || Time::HiRes::time >= $time_stop) {
				$self->{driver}->{plugins}->trigger( error => $e );
				return;  # in case the event handler doesn't die
			}
		}
		
		Time::HiRes::sleep min
			$self->{retry_sleep} * (1 << $tries++),
			$time_stop - Time::HiRes::time;
	}
}


sub execute_read {
	my ($self, $func) = @_;
	
	return $self->_execute( READ => $func );
}


sub execute_write {
	my ($self, $func) = @_;
	
	return $self->_execute( WRITE => $func );
}


sub server {
	my ($self) = @_;
	
	my $server_info = $self->{driver}->{server_info};
	return $server_info if defined $server_info;
	return $self->{driver}->{server_info} = $self->{net}->_server;
}




package # private
        Neo4j::Driver::Session::Bolt;
use parent -norequire => 'Neo4j::Driver::Session';


sub new {
	my ($class, $driver) = @_;
	
	return bless {
		cypher_params_v2 => $driver->config('cypher_params'),
		driver => $driver,
		net => Neo4j::Driver::Net::Bolt->new($driver),
	}, $class;
}


sub new_tx {
	return Neo4j::Driver::Transaction::Bolt->new(@_);
}




package # private
        Neo4j::Driver::Session::HTTP;
use parent -norequire => 'Neo4j::Driver::Session';


sub new {
	my ($class, $driver) = @_;
	
	return bless {
		cypher_params_v2 => $driver->config('cypher_params'),
		driver => $driver,
		net => Neo4j::Driver::Net::HTTP->new($driver),
	}, $class;
}


sub new_tx {
	return Neo4j::Driver::Transaction::HTTP->new(@_);
}


1;

__END__

=encoding utf8

=head1 SYNOPSIS

 $session = Neo4j::Driver->new(...)->session;
 
 # Managed transaction function
 @records = $session->execute_read( sub ($transaction) {
   $transaction->run( ... )->list;
 });
 
 # Unmanaged explicit transaction
 $transaction = $session->begin_transaction;
 
 # Autocommit transaction
 $result = $session->run( ... );

=head1 DESCRIPTION

Provides a context of work for database interactions.

A Session is a logical container hosting a series of
L<transactions|Neo4j::Driver::Transaction> carried out against
a database. Transactions can be either managed, unmanaged, or
auto-commit transactions:

=over

=item Managed transaction functions

A transaction function bundles an atomic unit of work that is
either automatically committed when the function (subroutine)
returns, or rolled back if an exception is thrown during query
execution or by the user code. This means you don't have to
think much about steps like begin or commit – the driver will
do it all for you.

However, transaction functions must always be idempotent,
because they might be retried (re-executed) multiple times
in certain error conditions, for example if the connection
breaks down during execution. See L</"execute_read"> and
L</"execute_write"> below.

=item Unmanaged explicit transactions

Instead of using transaction functions, you can choose to
handle begin, commit, rollback, and failures entirely yourself
in an I<unmanaged> transaction. This gives you more freedom
in your interactions with the transaction, but it's also
a bit more cumbersome. See L</"begin_transaction">.

=item Auto-commit transactions

For simple one-off queries where you don't want to deal with
explicit transactions at all, there is also a way to run
queries directly on a session. Opening a transaction before
and committing it afterwards happens implicitly on the server.
However, unlike a managed transaction function, auto-commit
queries will never be retried. See L</"run"> below.

=back

Only one open transaction per session at a time is supported. To
work with multiple concurrent transactions, simply use more than
one session.

To create a new session, call L<Neo4j::Driver/"session">.

=head1 METHODS

L<Neo4j::Driver::Session> implements the following methods.

=head2 begin_transaction

 $transaction = $session->begin_transaction;

Begin a new explicit L<Transaction|Neo4j::Driver::Transaction>.

=head2 execute_read

 @records = $session->execute_read( sub ($tx) {
   $tx->run('...')->list;
 });

Exactly like C<execute_write()>, except that it tries to route
the request to a read-only server if one is available. This is a
performance optimisation only and does not imply access control.

The effect of using this method to run queries that modify the
database is unspecified.

=head2 execute_write

 @records = $session->execute_write( sub ($tx) {
   $tx->run('...')->list;
 });

Execute a unit of work as a single, managed transaction with
retry behaviour. The transaction allows for one or more queries
to be run.

The driver will automatically commit the transaction when the
provided subroutine finishes execution. Any error raised during
execution will result in a rollback attempt. For certain kinds
of errors, the given subroutine will be retried with exponential
backoff until L<Neo4j::Driver::Config/"max_transaction_retry_time">
(see L<Neo4j::Error/"is_retryable"> for the complete list).
Because of this, the given subroutine needs to be B<idempotent>
(S<i. e.>, have the same effect regardless of how many times
it is executed).

Note that L<Neo4j::Driver::Result> objects may not be valid
outside of the given subroutine. If the driver detects that
you return such an object, it will issue a warning in the
category C<closure>. A better approach would be
to return the list of records from the subroutine instead,
which is always safe to do.

=head2 run

 $result = $session->run('...');

Run and commit a query using an auto-commit transaction and return
the L<Result|Neo4j::Driver::Result>.

This method is semantically exactly equivalent to the following code,
but is faster because it doesn't require an extra server roundtrip to
commit the transaction.

 $transaction = $session->begin_transaction;
 $result = $transaction->run('...');
 $transaction->commit;

=head2 server

 $address = $session->server->address;
 $version = $session->server->agent;

Obtain the L<ServerInfo|Neo4j::Driver::ServerInfo>, consisting of
the host, port, protocol and Neo4j version.

=head1 SECURITY CONSIDERATIONS

Both L<Session|Neo4j::Driver::Session> as well as
L<Transaction|Neo4j::Driver::Transaction> objects internally hold
references to the authentication credentials used to contact the
Neo4j server. Objects of these classes should therefore not be
passed to untrusted modules. However, objects of the
L<ServerInfo|Neo4j::Driver::ServerInfo> class and the
L<Result|Neo4j::Driver::Result> class (if detached) do not
contain a reference to these credentials and are safe in this
regard.

=head1 SEE ALSO

=over

=item * L<Neo4j::Driver>

=item * L<Neo4j::Driver::B<Transaction>>,
L<Neo4j::Driver::B<ServerInfo>>,
L<Neo4j::Driver::B<Result>>

=item * Equivalent documentation for the official Neo4j drivers:
L<Session (Java)|https://neo4j.com/docs/api/java-driver/5.26/org.neo4j.driver/org/neo4j/driver/Session.html>,
L<Session (JavaScript)|https://neo4j.com/docs/api/javascript-driver/5.26/class/lib6/session.js~Session.html>,
L<ISession (.NET)|https://neo4j.com/docs/api/dotnet-driver/5.13/html/6bcf5d8c-98e7-b521-03e7-210cd6155850.htm>

=back

=cut
