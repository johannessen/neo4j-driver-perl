use 5.014;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::StatementResult;
# ABSTRACT: result of running a Cypher statement (a list of records)


use Carp qw(carp croak);

use Neo4j::Driver::Record;
use Neo4j::Driver::ResultColumns;
use Neo4j::Driver::ResultSummary;


sub new {
	my ($class, $result) = @_;
	
	return bless { blessed => 0, result => $result }, $class;
}


sub _column_keys {
	my ($self) = @_;
	
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
	
	return 0 unless $self->{result};
	return scalar @{$self->{result}->{data}};
}


sub single {
	my ($self) = @_;
	
	croak 'There is not exactly one result record' if $self->size != 1;
	my ($record) = $self->list;
	$record->{_stats} = $self->summary if $self->{result}->{stats};
	return $record;
}


sub summary {
	my ($self) = @_;
	
	return Neo4j::Driver::ResultSummary->new( $self->{result} );
}


sub stats {
	my ($self) = @_;
	carp __PACKAGE__ . "->stats is deprecated; use summary instead";
	
	return $self->{result}->{stats} ? $self->summary->counters : {};
}


sub consume {
	my ($self) = @_;
	
	croak 'not implemented';
}



1;

__END__
