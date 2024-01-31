use 5.010;
use strict;
use warnings;

package Neo4j::Driver::Type::Temporal;
# ABSTRACT: DEPRECATED (use DateTime / Duration instead)


1;

__END__

=head1 SYNOPSIS

 package Neo4j::Driver::Type::DateTime;
 use parent 'Neo4j::Driver::Type::Temporal';
 
 package Neo4j::Driver::Type::Duration;
 use parent 'Neo4j::Driver::Type::Temporal';

=head1 DESCRIPTION

The Neo4j::Driver::Type::Temporal module was created to
mark temporal values returned from the Neo4j server.
However, beyond that, it was never implemented, and the
documentation has always carried the warning:

E<nbsp> The package name C<Neo4j::Driver::Type::Temporal> may change
in future.

Since the L<Neo4j::Types> model doesn't have a shared super-type
for temporal instants and temporal durations, this module is
no longer required.

B<Any use of C<Neo4j::Driver::Type::Temporal> is deprecated.>

This module will be removed in a future version of this driver.

=head1 SEE ALSO

=over

=item * L<Neo4j::Driver::Types>

=back
