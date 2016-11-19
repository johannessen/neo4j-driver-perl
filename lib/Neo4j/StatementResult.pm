use 5.014;
use strict;
use warnings;
use utf8;

package Neo4j::StatementResult;

use Carp qw(croak);

use Neo4j::Record;
use Neo4j::ResultColumns;


sub new {
	my ($class, $result) = @_;
	
	return bless { blessed => 0, result => $result }, $class;
}


sub _column_keys {
	my ($self) = @_;
	
	return Neo4j::ResultColumns->new($self->{result});
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
			bless $a, 'Neo4j::Record';
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
	my $record = bless $self->{result}->{data}->[0], 'Neo4j::Record';
	$record->{column_keys} = $self->_column_keys;
	return $record;
	
	# can this be better implemented like this?
	#my ($record) = $self->list;  return $record;
}


sub consume {
	my ($self) = @_;
	
	croak 'not implemented';
}



1;

__END__
