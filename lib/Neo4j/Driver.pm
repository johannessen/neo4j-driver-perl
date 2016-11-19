use 5.014;
use strict;
use warnings;
use utf8;

package Neo4j::Driver;

our $VERSION = 0.01;

use Carp qw(croak);

use URI;
use REST::Client 134;
use Neo4j::Session;


=pod

=head1 NAME

Neo4j::Driver - Perl implementation of a Neo4j REST driver.

=head1 SYNOPSIS

 my $d = Neo4j::Driver->new("localhost")->basic_auth("neo4j", "neo4j");
 my $s = $d->session;
 my $t = $s->begin_transaction;
 my $r = $t->run("MATCH p:Person WHERE p.name = {n} RETURN p", {n => "Jane Doe"});
 #my $l = $t->list;
 foreach my $p (@$r) {
     print $p->get('name'), " ", $p->get('born');
 }
 $t->commit;
 #$t->rollback;
 $s->close;
 $d->close;

=head1 DESCRIPTION

This is an unofficial Perl implementation of the Neo4j Driver API. It enables
interacting with a Neo4j database server using more or less the same classes
and method calls as the official Neo4j drivers do. Responses from the Neo4j
server are passed through to the client as-is.

See L<http://neo4j.com/docs/developer-manual/3.0/drivers/#driver-use-the-driver>
for the official driver API documentation.

This driver extends the uniformity across languages, which is a stated goal of
the Neo4j Driver API, to Perl at least to a limited extent (work in progress).
The downside is that this driver doesn't offer sleek object bindings like the
existing L<REST::Neo4p> module does. Nor does it offer any DBI integration.

=cut


our $CONTENT_TYPE = 'application/json; charset=UTF-8';


sub new {
	my ($class, $uri) = @_;
	
	if ($uri) {
		$uri =~ s|^|http://| if $uri !~ m{:|/};
		$uri = URI->new($uri);
#		croak "Only the REST interface is supported [$uri]" if $uri->scheme eq 'bolt';
		croak "Only the 'http' URI scheme is supported [$uri]" if $uri->scheme ne 'http';
		croak "Hostname is required [$uri]" if ! $uri->host;
		$uri->port(7474) if ! $uri->port;
	}
	else {
		$uri = URI->new("http://localhost:7474");
	}
	
	return bless { uri => $uri, die_on_error => 1 }, $class;
}


sub basic_auth {
	my ($self, $username, $password) = @_;
	
	$self->{auth} = {
		scheme => 'basic',
		principal => $username,
		credentials => $password,
	};
	$self->{client} = undef;  # ensure the next call to _client picks up the new credentials
	
	return $self;
}


sub _client {
	my ($self) = @_;
	
	# lazy initialisation
	if ( ! $self->{client} ) {
		my $uri = $self->{uri};
		if ($self->{auth}) {
			croak "Only HTTP Basic Authentication is supported" if $self->{auth}->{scheme} ne 'basic';
			$uri = $uri->clone;
			$uri->userinfo( $self->{auth}->{principal} . ':' . $self->{auth}->{credentials} );
		}
		
		$self->{client} = REST::Client->new({
			host => "$uri",
			timeout => 60,
			follow => 1,
		});
		$self->{client}->addHeader('Accept', $CONTENT_TYPE);
		$self->{client}->addHeader('Content-Type', $CONTENT_TYPE);
		$self->{client}->addHeader('X-Stream', 'true');
	}
	
	return $self->{client};
}


sub session {
	my ($self) = @_;
	
	return Neo4j::Session->new($self);
}


sub run {
	my ($self, $query, @parameters) = @_;
	
	return $self->session->run($query, @parameters);
}


sub close {
}



1;

__END__

=pod

=head1 ENVIRONMENT

It is unknown whether this class works with Neo4j 1.x or 3.x.
It has only been tested with Neo4j 2.3.

=head1 BUGS

This software has pre-release quality. There is little documentation and no
schedule for further development. The interface is not yet stable.

This driver does not support the Bolt protocol of Neo4j version 3 and there are
no plans of supporting Bolt in the future. The Transactional HTTP API is used
for communicating with the server instead. However, this should be of little
concern to clients as the API is the same and the speed difference isn't
particularly large anyway as far as I can see.

HTTPS support is planned.

=head1 COPYRIGHT

Copyright (c) 2016 Arne Johannessen
All rights reserved.

=cut
