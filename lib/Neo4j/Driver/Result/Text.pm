use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::Result::Text;
# ABSTRACT: Fallback handler for result errors


use parent 'Neo4j::Driver::Result';

use Carp qw(carp croak);
our @CARP_NOT = qw(Neo4j::Driver::Net::HTTP);


#our $ACCEPT_HEADER = "text/*; q=0.1";


sub new {
	# uncoverable pod (private method)
	my ($class, $params) = @_;
	
	my $header = $params->{http_header};
	my @errors = ();
	
	if (! $header->{success}) {
		my $reason_phrase = $params->{http_agent}->http_reason;
		push @errors, "HTTP error: $header->{status} $reason_phrase on $params->{http_method} to $params->{http_path}";
	}
	
	my $content_type = $header->{content_type};
	if ($content_type =~ m|^text/plain|) {
		push @errors, $params->{http_agent}->fetch_all;
	}
	else {
		push @errors, "Received " . ($content_type ? $content_type : "empty") . " content from database server; skipping result parsing";
	}
	
	croak join "\n", @errors if $params->{die_on_error};
	carp join "\n", @errors;
	
	return bless {}, $class;
}


sub _info { {} }  # no transaction status info => treat as closed


sub _results { () }  # no actual results provided here


# sub _accept_header { () }
# 
# 
# sub _acceptable {
# 	my ($class, $content_type) = @_;
# 	
# 	return $_[1] =~ m|^text/|i;
# }


1;
