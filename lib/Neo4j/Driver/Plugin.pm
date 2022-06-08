use 5.010;
use strict;
use warnings;

package Neo4j::Driver::Plugin;
# ABSTRACT: Plug-in interface for Neo4j::Driver


1;

=encoding utf8

=head1 SYNPOSIS

 package Local::MyNeo4jPlugin;
 use parent 'Neo4j::Driver::Plugin';
 
 sub new {
   my ($class) = @_;
   return bless {}, $class;
 }
 
 sub register {
   my ($self, $manager) = @_;
   $manager->add_event_handler(
     http_adapter_factory => sub {
       Local::MyNeo4jLWPAdapter->new();
     },
   );
 }
 
 package Local::MyNeo4jLWPAdapter;
 use parent 'Neo4j::Driver::Net::HTTP::LWP';
 ...;
 
 package main;
 use Neo4j::Driver 0.31;
 
 $driver = Neo4j::Driver->new();
 $driver->plugin('Local::MyNeo4jPlugin');

=head1 WARNING: EXPERIMENTAL

The design of the plug-in API is not finalised.
You should probably let me know if you already are writing
plug-ins, so that I can try to accommodate your use case
and give you advance notice of changes.

B<The entire plug-in API is currently highly experimental.>

The driver's C<plugins()> method is
L<experimental|Neo4j::Driver/"Plug-in modules"> as well.

=head1 OVERVIEW

Plug-ins can be used to extend and customise L<Neo4j::Driver>
to a significant degree. Upon being loaded, a plug-in will be
asked to register event handlers with the driver. Handlers
are references to custom subroutines defined by the plug-in.
They will be invoked when the event they were registered for
is triggered.

Events triggered by the driver are specified in this document;
see L</"EVENTS"> below. Plug-ins can also define custom events.

Event handlers may receive a code reference for continuing with
the next handler registered for that event. When provided, this
callback should be treated as the default driver action for that
event. Depending on what a plug-in's purpose is, it may be useful
to either invoke this callback and work with the results, or to
ignore it entirely and handle the event independently.

In some cases, handling an event or not handling an event can
have side effects. In some cases, an event can only be handled a
single time, with any additional handlers being ignored. In some
cases, the return value of an event handler may be significant.
All of these API details are still evolving.

Plug-ins must inherit from C<Neo4j::Driver::Plugin>. They must
also implement the methods described in L</"METHODS"> below.

I'm grateful for any feedback you I<(yes, you!)> might have on
this driver's plug-in API. Please open a GitHub issue or get in
touch via email (make sure you mention Neo4j in the subject to
beat the spam filters).

I<The plug-in interface as described in this document is available
since version 0.31.>

=head1 EVENTS

This version of L<Neo4j::Driver> can trigger the following events.
Future versions may introduce new events or remove existing ones.

=over

=item http_adapter_factory

 $manager->add_event_handler(
   http_adapter_factory => sub {
     my ($continue, $driver) = @_;
     my $adapter;
     ...
     return $adapter // $continue->();
   },
 );

This event is triggered when a new HTTP adapter instance is
needed during session creation. Parameters given are a code
reference for continuing with the next handler registered for
this event and the driver.

A handler for this event must return the blessed instance of
an HTTP adapter module (formerly known as "networking module")
to be used instead of the default adapter built into the driver.
See L<Neo4j::Driver::Net/"API of an HTTP networking module">.

=back

More events may be added in future versions. If you have a need
for a specific event, let me know and I'll see if I can add it
easily.

If your plug-in defines custom events of its own, it must only
use event names that beginn with C<x_>. All other event names
are reserved for use by the driver itself.

Note that future versions of the driver may trigger events with
different arguments based on their name. In particular, you
should for the time being avoid using custom event names that
start with C<x_after_> and C<x_before_>, but other event names
may also be affected.

=head1 METHODS

The plug-in itself must implement the following methods.

=over

=item new

 sub new {
   my ($class) = @_;
   ...
 }

Plug-in constructor. Returns a blessed reference. Parameters
given are the plug-in package name.

=item register

 sub register {
   my ($self, $manager) = @_;
   ...
 }

Called by the driver when a plug-in is loaded. Parameters given
are the plug-in and a plug-in manager.

This method is expected to attach this plug-in's event handlers
by calling the plug-in manager's L</"add_event_handler"> method.
See L</"EVENTS"> for a list of events supported by this version
of the driver.

=back

=head1 THE PLUG-IN MANAGER

The job of the plug-in manager is to invoke the appropriate
event handlers when events are triggered. It also allows clients
to modify the list of registered handlers. A reference to the
plug-in manager is provided to your plug-in when it is loaded;
see L</"register">.

The plug-in manager implements the following methods.

=over

=item add_event_handler

 $manager->add_event_handler( event_name => sub {
   ...
 });

Registers the given handler for the named event. When that event
is triggered, the handler will be invoked (unless another plug-in's
handler for the same event prevents this). Handlers will not be
invoked in any particular defined order.

Note that future updates to the driver may change existing events
to provide additional arguments. Because subroutine signatures
perform strict checks of the number of arguments, they are not
recommended for event handlers.

=item trigger_event

 $manager->trigger_event( 'event_name', @parameters );

Called by the driver to trigger an event and invoke any registered
handlers for it. May be given an arbitrary number of parameters,
all of which will be passed through to the event handler.

Most plug-ins won't need to call this method. But plug-ins may
choose to trigger and handle custom events. These must have names
that begin with C<x_>. Plug-ins should not trigger events with
other names, as these are reserved for internal use by the driver
itself.

Events that are triggered, but not handled, are currently silently
ignored. This will likely change in a future version of the driver.

Calling this method in list context is discouraged, because doing
so might be treated specially by a future version of the driver.
Use C<scalar> to be safe.

=back
