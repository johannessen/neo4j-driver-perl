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
		consumed => 0,   # all records delivered by Neo4j; summary available
		exhausted => 0,  # all records read by the client; fetch() will fail
		result => $result,
		json_cursor => 0,
		buffer => [],
		columns => undef,
		summary => $summary,
		deep_bless => $deep_bless,
	};
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
	$self->{consumed} = 1 if ! $next;
	
	return $count;
}


sub _fetch_next {
	my ($self) = @_;
	
#	return $stream->fetch_next;
	
	return undef unless $self->{result};
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


sub _attached {
	my ($self) = @_;
	
	return ! $self->{consumed};
}


sub _detach {
	my ($self) = @_;
	
	return $self->_fill_buffer;
}


sub _consume {
	my ($self) = @_;
	
	$self->{exhausted} = 1;
	die "Unimplemented";
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
to yield records one at a time, or retrieved in its entirety using
C<list()> to yield an array of all records.

Result streams received over HTTP are valid indefinitely.

Result streams running on Bolt are valid until the next statement
is run on the same session or (if the result was retrieved within
an explicit transaction) until the transaction is closed, whichever
comes first. When a result stream has become invalid I<before> it
was fully consumed, calling any methods in this class may fail.
Exhausting a result stream always fully consumes it.

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
fully consumes the result stream.

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

=head2 Look ahead in the result stream

 say "Next record: ", $result->peek->get(...) if $result->has_next;

Using C<has_next()> and C<peek()>, it is possible to retrieve the
same record the next call to C<fetch()> would retrieve without
actually navigating to it. This may change the internal stream
buffer and consume the result, but will never exhaust the result.

=head1 SEE ALSO

L<Neo4j::Driver>,
L<Neo4j::Driver::Record>,
L<Neo4j::Driver::ResultSummary>,
L<Neo4j Java Driver|https://neo4j.com/docs/api/java-driver/current/index.html?org/neo4j/driver/v1/StatementResult.html>,
L<Neo4j Python Driver|https://neo4j.com/docs/api/python-driver/current/results.html>,
L<Neo4j JavaScript Driver|https://neo4j.com/docs/api/javascript-driver/current/class/src/v1/result.js~Result.html>,
L<Neo4j .NET Driver|https://neo4j.com/docs/api/dotnet-driver/current/html/1ddb9dbe-f40f-26a3-e6f0-7be417980044.htm>

=cut
