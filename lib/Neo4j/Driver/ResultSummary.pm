use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::ResultSummary;
# ABSTRACT: Details about the result of running a statement


use Carp qw(croak);

use Neo4j::Driver::SummaryCounters;


sub new {
	my ($class, $result, $response, $statement) = @_; 
	my $self = {};
	if ($result && $result->{stats}) {
		$self->{counters} = $result->{stats};
		$self->{plan} = $result->{plan};
		$self->{notifications} = $response->{notifications};
		$self->{statement} = $statement;
	}
	return bless $self, $class;
}


sub init {
	my ($self) = @_; 
	
	# The purpose of this method is to fail as early as possible if we don't
	# have all necessary info. This should improve the user experience.
	croak 'Result missing stats' unless $self->{statement};
	return $self;
}


sub counters {
	my ($self) = @_;
	
	return Neo4j::Driver::SummaryCounters->new( $self->{counters} );
}


sub notifications {
	my ($self) = @_;
	
	return $self->{notifications} ? @{$self->{notifications}} : () if wantarray;
	return $self->{notifications};
}


sub plan {
	my ($self) = @_;
	
	return $self->{plan};
}


sub statement {
	my ($self) = @_;
	
	return {
		text => $self->{statement}->{statement},
		parameters => $self->{statement}->{parameters} // {},
	};
}


sub server {
	my ($self) = @_;
	
	# The HTTP-based driver does not provide the ServerInfo in the
	# ResultSummary for security reasons: Determining the server version
	# requires an additional server request, which requires the server's
	# login credentials. If ResultSummary had access to those, it would
	# not be safe to pass statement results to untrusted parties.
	croak "Unimplemented (use Session->server instead)";
}


1;

__END__

=head1 SYNOPSIS

 use Neo4j::Driver;
 my $driver = Neo4j::Driver->new->basic_auth(...);
 my $result = $driver->session->run('MATCH (a)-[:KNOWS]-(b) RETURN a, b');
 
 my $summary = $result->summary;
 
 # SummaryCounters
 my $counters = $summary->counters;
 
 # query information
 my $query  = $summary->statement->{text};
 my $params = $summary->statement->{parameters};
 my $plan   = $summary->plan;
 my @notes  = @{ $summary->notifications };

=head1 DESCRIPTION

The result summary of running a statement. The result summary can be
used to investigate details about the result, like the Neo4j server
version, how many and which kinds of updates have been executed, and
query plan information if available.

The Perl driver does not currently provide C<ServerInfo> as part of
the result summary. Use L<Neo4j::Driver::Session> to obtain this
information instead.

=head1 METHODS

L<Neo4j::Driver::ResultSummary> implements the following methods.

=head2 counters

 my $summary_counters = $summary->counters;

Returns the L<SummaryCounters|Neo4j::Driver::SummaryCounters> with
statistics counts for operations the statement triggered.

=head2 notifications

 use Data::Dumper;
 print Dumper $summary->notifications;

A list of notifications that might arise when executing the
statement. Notifications can be warnings about problematic statements
or other valuable information that can be presented in a client.
Unlike failures or errors, notifications do not affect the execution
of a statement.

=head2 plan

 use Data::Dumper;
 print Dumper $summary->plan;

This describes how the database will execute your statement.
Available if this is the summary of a Cypher C<EXPLAIN> statement.

=head2 statement

 my $query  = $summary->statement->{text};
 my $params = $summary->statement->{parameters};

The statement and parameters this summary is for.

=head1 EXPERIMENTAL FEATURES

L<Neo4j::Driver::ResultSummary> implements the following experimental
features. These are subject to unannounced modification or removal
in future versions. Expect your code to break if you depend upon
these features.

=head2 Calling in list context

 my @notifications = $summary->notifications;

The C<notifications> method tries to Do What You Mean if called in
list context.

=head1 SEE ALSO

L<Neo4j::Driver>,
L<Neo4j::Driver::Session>,
L<Neo4j::Driver::SummaryCounters>,
L<Neo4j Java Driver|https://neo4j.com/docs/api/java-driver/current/index.html?org/neo4j/driver/v1/summary/ResultSummary.html>,
L<Neo4j JavaScript Driver|https://neo4j.com/docs/api/javascript-driver/current/class/src/v1/result-summary.js~ResultSummary.html>,
L<Neo4j .NET Driver|https://neo4j.com/docs/api/dotnet-driver/current/html/859dfa7c-80b8-f754-c0d3-359a0df5d33b.htm>

=cut
