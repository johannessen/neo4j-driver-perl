use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::StatementResult;
# ABSTRACT: Result of running a Cypher statement (a stream of records)


use Carp qw(carp croak);

use Neo4j::Driver::Record;
use Neo4j::Driver::ResultColumns;
use Neo4j::Driver::ResultSummary;


sub new {
	my ($class, $result, $summary, $deep_bless) = @_;
	
	my $self = {
		attached => 1,   # all records delivered by Neo4j; summary available
		exhausted => 0,  # all records read by the client; fetch() will fail
		result => $result,
		buffer => [],
		columns => undef,
		summary => $summary,
		deep_bless => $deep_bless,
	};
	
	# HTTP JSON results can be fully buffered immediately
	if ($result && ! $result->{bolt}) {
		$self->{buffer} = $result->{data};
		$self->{columns} = Neo4j::Driver::ResultColumns->new($result);
		foreach my $record (@{ $self->{buffer} }) {
			Neo4j::Driver::Record->new($record, $self->{columns}, $deep_bless);
		}
		$self->{attached} = 0;
	}
	
	return bless $self, $class;
}


sub _column_keys {
	my ($self) = @_;
	
	$self->{columns} = Neo4j::Driver::ResultColumns->new($self->{result}) unless $self->{columns};
	return $self->{columns};
}


sub keys {
	my ($self) = @_;
	
	# Don't break encapsulation by just returning the original reference
	# because ResultColumns depends on the {columns} field being intact.
	my @keys = ();
	@keys = @{ $self->{result}->{columns} } if $self->{result}->{columns};
	return wantarray ? @keys : [@keys];
}


sub list {
	my ($self) = @_;
	
	$self->_fill_buffer;
	$self->{exhausted} = 1;
	return wantarray ? @{$self->{buffer}} : $self->{buffer};
}


sub size {
	my ($self) = @_;
	
	return scalar @{$self->list};
}


sub single {
	my ($self) = @_;
	
	croak 'There is not exactly one result record' if $self->size != 1;
	my ($record) = $self->list;
	$record->{_summary} = $self->summary if $self->{result}->{stats};
	return $record;
}


sub _fill_buffer {
	my ($self, $minimum) = @_;
	
	return 0 unless $self->{attached};
	
	$self->_column_keys if $self->{result};
	
	# try to get at least $minimum records on the buffer
	my $buffer = $self->{buffer};
	my $count = 0;
	my $next = 1;
	while ( (! $minimum || @$buffer < $minimum)
			&& ($next = $self->_fetch_next) ) {
		push @$buffer, $next;
		$count++;
	}
	
	# _fetch_next was called, but didn't return records => end of stream; detached
	$self->{attached} = 0 if ! $next;
	
	return $count;
}


sub _fetch_next {
	my ($self) = @_;
	
#	return $stream->fetch_next;
	
	# Neo4j::Bolt::ResultStream support is not yet implemented,
	# so we simulate a JSON-backed result stream
	$self->{json_cursor} //= 0;
	my $record = $self->{result}->{data}->[ $self->{json_cursor}++ ];
	return undef unless $record;
	return Neo4j::Driver::Record->new($record, $self->{columns}, $self->{deep_bless});
}


sub fetch {
	my ($self) = @_;
	
	return undef if $self->{exhausted};  # fetch() mustn't destroy a list() buffer
	$self->_fill_buffer(1);
	my $next = shift @{$self->{buffer}};
	$self->{exhausted} = ! $next;
	return $next;
}


sub peek {
	my ($self) = @_;
	
	croak "iterator is exhausted" if $self->{exhausted};
	$self->_fill_buffer(1);
	return $self->{buffer}->[0];
}


sub has_next {
	my ($self) = @_;
	
	return 0 if $self->{exhausted};
	$self->_fill_buffer(1);
	return scalar @{$self->{buffer}};
}


sub attached {
	my ($self) = @_;
	
	return $self->{attached};
}


sub detach {
	my ($self) = @_;
	
	return $self->_fill_buffer;
}


sub consume {
	my ($self) = @_;
	
	# Neo4j::Bolt doesn't offer direct access to neo4j_close_results()
	$self->{exhausted} = 1;
	return $self->summary;
}


sub summary {
	my ($self) = @_;
	
	$self->_fill_buffer;
	
	$self->{summary} //= Neo4j::Driver::ResultSummary->new;
	return $self->{summary}->init;
}


sub stats {
	my ($self) = @_;
	carp __PACKAGE__ . "->stats is deprecated; use summary instead";
	
	return $self->{result}->{stats} ? $self->summary->counters : {};
}


1;

__END__

=head1 SYNOPSIS

 use Neo4j::Driver;
 my $session = Neo4j::Driver->new->basic_auth(...)->session;
 
 # stream result records
 my $result = $session->run('MATCH (a:Actor) RETURN a.name, a.born');
 while ( my $record = $result->fetch ) {
   ...
 }
 
 # list result records
 my $result = $session->run('MATCH (m:Movie) RETURN m.name, m.year');
 my $record_count = $result->size;
 my @records = @{ $result->list };
 
 # shortcut for results with a single record only
 my $query = 'MATCH (m:Movie) WHERE id(m) = {id} RETURN m.name';
 my $name = $session->run($query, id => 12)->single->get('m.name');

=head1 DESCRIPTION

The result of running a Cypher statement, conceptually a stream of
records. The result stream can be navigated through using C<fetch()>
to consume records one at a time, or be consumed in its entirety
using C<list()> to get an array of all records.

Result streams typically are initially attached to the active
session. As records are retrieved from the stream, they may be
buffered locally in the driver. Once I<all> data on the result stream
has been retrieved from the server and buffered locally, the stream
becomes B<detached.>

Results received over HTTP always contain the complete list of
records, which is kept buffered in the driver. HTTP result streams
are thus immediately detached and valid indefinitely.

Result streams received on Bolt are valid until the next statement
is run on the same session or (if the result was retrieved within
an explicit transaction) until the transaction is closed, whichever
comes first. When a result stream has become invalid I<before> it
was detached, calling any methods in this class may fail.

=head1 METHODS

L<Neo4j::Driver::StatementResult> implements the following methods.

=head2 fetch

 while (my $record = $result->fetch) {
   ...
 }

Navigate to and retrieve the next L<Record|Neo4j::Driver::Record> in
this result.

When a record is fetched, that record is removed from the result
stream. Once all records have been fetched, the result stream is
exhausted and C<fetch()> returns C<undef>.

=head2 has_next

 while (my $record = $result->fetch) {
   print $record->get('field');
   print ', ' if $result->has_next;
 }

Whether the next call to C<fetch()> will return a record.

Calling this method may change the internal stream buffer and
detach the result, but will never exhaust it.

=head2 keys

 my @keys = @{ $result->keys };

Retrieve the column names of the records this result contains.

=head2 list

 my @records = @{ $result->list };

Return the entire list of all L<Record|Neo4j::Driver::Record>s that
remain in the result stream. Calling this method exhausts the result
stream.

The list is internally buffered by this class. Calling this method
multiple times returns the buffered list.

Future versions of this driver may provide a performance advantage
of C<fetch()> over C<list()> for queries with a very large number
of result rows. The current version does not.

=head2 single

 my $name = $session->run('... LIMIT 1')->single->get('name');

Return the single L<Record|Neo4j::Driver::Record> left in the result
stream, failing if there is not exactly one record left. Calling this
method exhausts the result stream.

The returned record is internally buffered by this class. Calling this
method multiple times returns the buffered record.

=head2 size

 my $record_count = $result->size;

Return the count of records that calling C<list()> would yield.

Calling this method exhausts the result stream and buffers all records
for use by C<list()>.

=head2 summary

 my $result_summary = $result->summary;

Return a L<Neo4j::Driver::ResultSummary> object. Calling this method
detaches the result stream, but does I<not> exhaust it.

As a special case, L<Record|Neo4j::Driver::Record>s returned by the
C<single> method also have a C<summary> method that works the same
way.

 my $record = $transaction->run('...')->single;
 my $result_summary = $record->summary;

=head1 EXPERIMENTAL FEATURES

L<Neo4j::Driver::StatementResult> implements the following
experimental features. These are subject to unannounced modification
or removal in future versions. Expect your code to break if you
depend upon these features.

=head2 Calling in list context

 my @keys = $result->keys;
 my @records = $result->list;

The C<keys> and C<list> methods try to Do What You Mean if called in
list context.

=head2 Control result stream attachment

 my $buffered = $result->attached;  # boolean
 my $count = $result->detach;  # number of records fetched

If necessary, C<detach()> can force the entire result stream to
be buffered locally, so that it will be available to C<fetch()>
indefinitely, irrespective of other statements run on the same
session. Essentially, the outcome is the same as calling C<list()>,
except that C<fetch()> can continue to be used because the result
is not exhausted.

Most of the official drivers do not offer these methods. Their
usefulness is doubtful. They may be removed in future versions.

=head2 Discarding the result stream

 $result->consume;

Discarding the entire result may be useful as a cheap way to signal
to the Bolt networking layer that any resources held by the result
may be released. The actual result records are silently discarded
without any effort to buffer the results. Calling this method
exhausts the result stream.

As a side effect, discarding the result yields a summary of it.

 my $result_summary = $result->consume;

All of the official drivers offer this method, but it doesn't appear
to be necessary here, since L<Neo4j::Bolt::ResultStream> reliably
calls C<neo4j_close_results()> in its C<DESTROY()> method. It may
be removed in future versions.

=head2 Look ahead in the result stream

 say "Next record: ", $result->peek->get(...) if $result->has_next;

Using C<peek()>, it is possible to retrieve the
same record the next call to C<fetch()> would retrieve without
actually navigating to it. This may change the internal stream
buffer and detach the result, but will never exhaust it.

=head1 SEE ALSO

L<Neo4j::Driver>,
L<Neo4j::Driver::Record>,
L<Neo4j::Driver::ResultSummary>,
L<Neo4j Java Driver|https://neo4j.com/docs/api/java-driver/current/index.html?org/neo4j/driver/v1/StatementResult.html>,
L<Neo4j Python Driver|https://neo4j.com/docs/api/python-driver/current/results.html>,
L<Neo4j JavaScript Driver|https://neo4j.com/docs/api/javascript-driver/current/class/src/v1/result.js~Result.html>,
L<Neo4j .NET Driver|https://neo4j.com/docs/api/dotnet-driver/current/html/1ddb9dbe-f40f-26a3-e6f0-7be417980044.htm>

=cut
