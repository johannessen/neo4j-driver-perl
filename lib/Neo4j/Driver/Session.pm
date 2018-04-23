use 5.014;
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
#	$t->{transaction} = $t->{commit};  # commit (= execute) the statement before even opening a transaction
	return $t->_commit($query, @parameters);
}


sub close {
}



1;

__END__
