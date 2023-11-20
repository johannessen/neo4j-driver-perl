use 5.010;
use strict;
use warnings;
use utf8;

package Neo4j::Driver::Type::Temporal;
# ABSTRACT: Represents a Neo4j temporal value


# may not be supported by Bolt

1;

__END__

=head1 DESCRIPTION

Represents a date, time or duration value in Neo4j.

Temporal types are only supported in Neo4j version 3.4 and above.

I<B<Note:> This module documentation will soon be replaced entirely
by L<Neo4j::Driver::Types>.>

=head1 BUGS

L<Neo4j::Driver::Type::Temporal> is not yet implemented.

The package name C<Neo4j::Driver::Type::Temporal> may change in future.

Temporal types may not work over a Bolt connection, because they
are not yet supported by C<libneo4j-client>
(L<#36|https://github.com/cleishm/libneo4j-client/issues/36>),
which L<Neo4j::Bolt> depends on internally. Use HTTP instead.

=head1 SEE ALSO

=over

=item * L<Neo4j::Driver::Types>

=item * L<Neo4j::Types::DateTime>

=item * L<Neo4j::Types::Duration>

=item * L<"Temporal values" in Neo4j Cypher Manual|https://neo4j.com/docs/cypher-manual/5/syntax/temporal/>

=back

=cut
