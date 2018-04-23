use 5.014;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::StatementResult;
# ABSTRACT: result of running a Cypher statement (a list of records)


use Carp qw(croak);

use Neo4j::Driver::Record;
use Neo4j::Driver::ResultColumns;


sub new {
	my ($class, $result) = @_;
	
	return bless { blessed => 0, result => $result }, $class;
}


sub _column_keys {
	my ($self) = @_;
	
	return undef if ! keys %{$self->{result}};
	return Neo4j::Driver::ResultColumns->new($self->{result});
}


#sub _columns {
#	return shift->_column_keys(@_);
#}


sub list {
	my ($self) = @_;
	
	my $l = $self->{result}->{data};
	if ( ! $self->{blessed} ) {
		my $column_keys = $self->_column_keys;
		foreach my $a (@$l) {
			bless $a, 'Neo4j::Driver::Record';
			$a->{column_keys} = $column_keys;
		}
		$self->{blessed} = 1;
	}
	
	return wantarray ? @$l : $l;
}


sub size {
	my ($self) = @_;
	
	return scalar @{$self->{result}->{data}};
}


sub single {
	my ($self) = @_;
	
	return undef if $self->size != 1;  # original Neo4j driver API raises an exception here
	my $record = bless $self->{result}->{data}->[0], 'Neo4j::Driver::Record';
	$record->{column_keys} = $self->_column_keys;
	$record->{_stats} = $self->stats;
	return $record;
	
	# can this be better implemented like this?
	#my ($record) = $self->list;  return $record;
}


sub stats {
	my ($self) = @_;
	
	return $self->{result}->{stats} // {};
}


sub consume {
	my ($self) = @_;
	
	croak 'not implemented';
}



1;

__END__
