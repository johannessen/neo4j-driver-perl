use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::PluginManager;
# ABSTRACT: Plug-in manager for Neo4j::Driver


# This package is not part of the public Neo4j::Driver API.


use Carp qw(croak);
our @CARP_NOT = qw(Neo4j::Driver);


sub new {
	# uncoverable pod
	my ($class) = @_;
	
	return bless {}, $class;
}


sub add_event_handler {
	# uncoverable pod (see Plugins.pod)
	my ($self, $event, $handler, @extra) = @_;
	
	croak "add_event_handler() with more than one handler unsupported" if @extra;
	
	push @{$self->{handlers}->{$event}}, $handler;
}


sub trigger_event {
	# uncoverable pod (see Plugins.pod)
	my ($self, $event, @params) = @_;
	
	my $default_handler = $self->{default_handlers}->{$event};
	my $handlers = $self->{handlers}->{$event}
		or $default_handler and return $default_handler->()
		or return;
	
	my @callbacks;
	for my $handler ( reverse @$handlers ) {
		my $continue = $callbacks[$#callbacks] // $default_handler // sub {};
		push @callbacks, sub { $handler->($continue, @params) };
	}
	return $callbacks[$#callbacks]->();
	
	# Right now, ALL events get a continuation callback.
	# But this will almost certainly change eventually.
}


# Tell a new plugin to register itself using this manager.
sub _register_plugin {
	my ($self, $plugin) = @_;
	
	croak "Can't locate object method new() via package $plugin (perhaps you forgot to load \"$plugin\"?)" unless $plugin->can('new');
	croak "Method register() not implemented by package $plugin (is this a Neo4j::Driver plug-in?)" unless $plugin->can('register');
	
	$plugin->new->register($self);
}


1;
