use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::Record;
# ABSTRACT: Container for Cypher result values


use Carp qw(croak);
use JSON::MaybeXS 1.003003 qw(is_bool);

use Neo4j::Driver::ResultSummary;


# Based on _looks_like_number() in JSON:PP 4.05, originally by HAARG.
# Modified on 2020 OCT 13 to detect only integers (column index).
sub _looks_like_int {
	my $value = shift;
	# if the utf8 flag is on, it almost certainly started as a string
	return if utf8::is_utf8($value);
	# detect numbers
	# string & "" -> ""
	# number & "" -> 0 (with warning)
	# nan and inf can detect as numbers, so check with * 0
	no warnings 'numeric';
	return unless length((my $dummy = "") & $value);
	return unless $value eq int $value;
	return unless $value * 0 == 0;
	return 1;
}


sub get {
	my ($self, $field) = @_;
	
	if ( ! defined $field ) {
		warnings::warnif ambiguous => "Ambiguous get() on " . __PACKAGE__ . " with multiple fields" if @{$self->{row}} > 1;
		return $self->{row}->[0];
	}
	
	if ( _looks_like_int $field ) {
		croak "Field $field not present in query result" if $field < 0 || $field >= @{$self->{row}};
		return $self->{row}->[$field];
	}
	
	my $key = $self->{column_keys}->key($field);
	croak "Field '$field' not present in query result" if ! defined $key;
	return $self->{row}->[$key];
}


# The various JSON modules for Perl tend to represent a boolean false value
# using a blessed scalar overloaded to evaluate to false in Perl expressions.
# This almost always works perfectly fine. However, some tests might not expect
# a non-truthy value to be blessed, which can result in wrong interpretation of
# query results. The get_bool method was meant to ensure boolean results would
# evaluate correctly in such cases. Given that such cases are rare and that no
# specific examples for such cases are currently known, this method now seems
# superfluous.
sub get_bool {
	my ($self, $field) = @_;
	warnings::warnif deprecated => __PACKAGE__ . "->get_bool is deprecated";
	
	my $value = $self->get($field);
	return $value if ! is_bool $value;
	return $value if !! $value;
	return undef;  ##no critic (ProhibitExplicitReturnUndef)
}


sub data {
	my ($self) = @_;
	
	my %data = ();
	foreach my $key (keys %{ $self->{column_keys} }) {
		$data{$key} = $self->{row}->[ $self->{column_keys}->key($key) ];
	}
	return \%data;
}


sub summary {
	my ($self) = @_;
	
	$self->{_summary} //= Neo4j::Driver::ResultSummary->new;
	return $self->{_summary}->init;
}


sub stats {
	my ($self) = @_;
	warnings::warnif deprecated => __PACKAGE__ . "->stats is deprecated; use summary instead";
	
	return $self->{_summary} ? $self->{_summary}->counters : {};
}


1;

__END__

=head1 SYNOPSIS

 use Neo4j::Driver;
 $session = Neo4j::Driver->new->basic_auth(...)->session;
 
 $query = 'MATCH (m:Movie) RETURN m.name, m.year';
 $records = $session->run($query)->list;
 foreach $record ( @$records ) {
   say $record->get('m.name');
 }
 
 $query .= ' ORDER BY m.year LIMIT 1';
 $record = $session->run($query)->single;
 say 'Year of oldest movie: ', $record->get(1);

=head1 DESCRIPTION

Container for Cypher result values. Records are returned from Cypher
statement execution, contained within a Result. A record is
a form of ordered map and, as such, contained values can be accessed
by either positional index or textual key.

=head1 METHODS

L<Neo4j::Driver::Record> implements the following methods.

=head2 get

 $value1 = $record->get('field_key');
 $value2 = $record->get(2);

Get a value from this record, either by field key or by zero-based
index.

When called without parameters, C<get()> will return the first
field. If there is more than a single field, a warning in the
category C<ambiguous> will be issued.

 $value = $session->run('RETURN "It works!"')->single->get;
 $value = $session->run('RETURN "warning", "ambiguous"')->single->get;

When retrieving values from records, Neo4j types are converted to Perl
types as shown in the following table.

 Neo4j type      resulting Perl type
 ----------      -------------------
 Number          scalar
 String          scalar
 Boolean         JSON::PP::true or JSON::PP::false
 null            undef
 
 Node            Neo4j::Driver::Type::Node
 Relationship    Neo4j::Driver::Type::Relationship
 Path            Neo4j::Driver::Type::Path
 
 List            array reference
 Map             hash reference

Boolean values are returned as JSON types; use C<!!> to force-convert
to a plain Perl boolean value if necessary.

Note that early versions of this class returned nodes, relationships
and paths as hashrefs or arrayrefs rather than blessed objects. This
was a bug. The underlying data structure of nodes and relationships
is an implementation detail that should not be relied upon. If you
try to treat L<Neo4j::Driver::Type::Node>,
L<Neo4j::Driver::Type::Relationship> or L<Neo4j::Driver::Type::Path>
objects as hashrefs or arrayrefs, your code will eventually fail
with a future version of this driver.

=head2 data

 $hashref = $record->data;
 $value = $hashref->{field_key};

Return the keys and values of this record as a hash reference.

=head1 EXPERIMENTAL FEATURES

L<Neo4j::Driver::Record> implements the following experimental
features. These are subject to unannounced modification or removal
in future versions. Expect your code to break if you depend upon
these features.

=head2 C<graph>

 $nodes = $record->{graph}->{nodes};
 $rels  = $record->{graph}->{relationships};

Allows accessing the graph response the Neo4j server can deliver via
HTTP. Requires the C<return_graph> field to be set on the
L<Transaction|Neo4j::Driver::Transaction>
before the statement is executed.

=head1 SEE ALSO

=over

=item * L<Neo4j::Driver>

=item * L<Neo4j::Driver::Type::B<Node>>,
L<Neo4j::Driver::Type::B<Relationship>>,
L<Neo4j::Driver::Type::B<Path>>

=item * Equivalent documentation for the official Neo4j drivers:
L<Record (Java)|https://neo4j.com/docs/api/java-driver/current/index.html?org/neo4j/driver/Record.html>,
L<Record (JavaScript)|https://neo4j.com/docs/api/javascript-driver/current/class/src/record.js~Record.html>,
L<IRecord (.NET)|https://neo4j.com/docs/api/dotnet-driver/4.0/html/ca4ccbd1-2925-945d-fd4c-a5635f3e4b23.htm>

=back

=cut
