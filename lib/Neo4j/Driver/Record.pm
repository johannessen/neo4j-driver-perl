use v5.12;
use warnings;

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
		warnings::warnif ambiguous =>
			sprintf "Ambiguous get() on %s with multiple fields", __PACKAGE__
			if @{$self->{row}} > 1;
		return $self->{row}->[0];
	}
	
	croak "Field '' not present in query result" if ! length $field;
	
	my $unambiguous_key = $self->{column_keys}->{$field};
	return $self->{row}->[$unambiguous_key] if defined $unambiguous_key;
	
	if ( _looks_like_int $field ) {
		croak sprintf "Field %i not present in query result", $field
			unless $field >= 0 && $field < @{$self->{row}};
		return $self->{row}->[$field];
	}
	
	my $key = $self->_field_index( $field );
	croak sprintf "Field '%s' not present in query result", $field
		unless defined $key;
	return $self->{row}->[$key];
}


sub data {
	my ($self) = @_;
	
	my %data = ();
	foreach my $key (keys %{ $self->{column_keys} }) {
		$data{$key} = $self->{row}->[ $self->_field_index( $key ) ];
	}
	return \%data;
}


# Return the index of the given column in the result record array
sub _field_index {
	my ($self, $name) = @_;
	
	my $cache = $self->{column_keys};
	return $cache->{$name} if length $name && exists $cache->{$name};
	return $cache->{''}->{$name} if exists $cache->{''};
	return undef;
}


# Parse the field names (result column keys) provided by the server and
# return them as a hash ref for fast index lookups
sub _field_names_cache {
	my ($result) = @_;
	
	croak 'Result missing columns' unless $result && $result->{columns};
	my $columns = $result->{columns};
	my $cache = {};
	for my $index (0 .. $#$columns) {
		my $name = $columns->[$index];
		
		# Create lookup cache for both index and field name to the index.
		# Move ambiguous index/name pairs to the '' sub-hash.
		
		if ( exists $cache->{$name} ) {
			delete $cache->{$name};
			$cache->{''}->{$name} = $index;
		}
		else {
			$cache->{$name} = $index;
		}
		
		if ( exists $cache->{$index} ) {
			$cache->{''}->{$index} = delete $cache->{$index};
		}
		else {
			$cache->{$index} = $index;
		}
	}
	
	return $cache;
}

# The field names (column keys / ex ResultColumns) are stored in a hash ref.
# For each field, there are entries with keys for the name and the column index
# in the result record array. The value is always the column index.
# For example, for `RETURN 1 AS foo`, it would look like this:
#   $cache = { 'foo' => 0, '0' => 0 };

# Exceptionally, index/name collisions can occur (see record-ambiguous.t).
# The field names lookup cache is limited to cases where no ambiguity exists.
# Any field name which would also be a valid index is moved to a sub-hash
# stored in the entry '' (empty string). Neo4j doesn't allow zero-length
# field names, so '' itself is never ambiguous.


sub summary {
	# uncoverable pod (see consume)
	my ($self) = @_;
	warnings::warnif deprecated => "summary() in Neo4j::Driver::Record is deprecated; use consume() in Neo4j::Driver::Result instead";
	
	$self->{_summary} //= Neo4j::Driver::ResultSummary->new;
	return $self->{_summary}->_init;
}


1;

__END__

=head1 SYNOPSIS

 $record = $session->execute_write( sub ($transaction) {
   return $transaction->run( ... )->fetch;
 });
 
 $value = $record->get('name');  # field key
 $value = $record->get(0);       # field index
 
 # Shortcut for records with just a single key
 $value = $record->get;

=head1 DESCRIPTION

Container for Cypher result values. Records are returned from Cypher
query execution, contained within a Result. A record is
a form of ordered map and, as such, contained values can be accessed
by either positional index or textual key.

To obtain a record, call L<Neo4j::Driver::Result/"fetch">.

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

Values are returned from Neo4j as L<Neo4j::Types> objects and
as simple Perl references / scalars. For details and for known
issues with type mapping see L<Neo4j::Driver::Types>.

=head2 data

 $hashref = $record->data;
 $value = $hashref->{field_key};

Return the keys and values of this record as a hash reference.

=head1 SEE ALSO

=over

=item * L<Neo4j::Driver>

=item * L<Neo4j::Driver::Types>

=item * Equivalent documentation for the official Neo4j drivers:
L<Record (Java)|https://neo4j.com/docs/api/java-driver/5.26/org.neo4j.driver/org/neo4j/driver/Record.html>,
L<Record (JavaScript)|https://neo4j.com/docs/api/javascript-driver/5.26/class/lib6/record.js~Record.html>,
L<IRecord (.NET)|https://neo4j.com/docs/api/dotnet-driver/5.26/api/Neo4j.Driver.IRecord.html>

=back

=cut
