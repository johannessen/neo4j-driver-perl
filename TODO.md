### Driver

- Write tests.

- HTTPS support.

- The current `close` method is a no-op. It should either be removed completely or behave like the session `close` method; see below.

- Consider if the 6 second timeout is too long. It should in fact be as short as reasonably possible.



### Session

- Support for persistent connections would be nice.

- Two different sessions should use two different TCP connections (at the moment, every session uses the same `REST::Client` instance).

- Sessions should offer a `close` method that automatically rolls back and terminates all currently open transactions. The current `close` method is a no-op, which needs to be fixed.

- Sessions of some of the official drivers can have at most one transaction running at a time. This restriction is not necessary for this Perl driver because `REST::Client` works fine without it. Perhaps we should implement it anyway for consistency; however, the Python driver docs explicitly say that a "Session is a logical container for one or more transactional units of work".



### Transaction

- Bugfix: query prep should fail on unblessed references with own error message (see test `bogus reference query`).

- The option to send multiple statements at once should no longer be exposed to the client. It should only be used internally for running statements lazily. The method structure should be refactored such that this becomes obvious.

- Using the `meta` data (which is automatically returned since version 3.0 (or possibly 3.1/3.2/3.3) and cannot be explicitly requested in `resultDataContents`), it should be possible to parse out the IDs and stuff from any reply and bless the entities in the JSON hashes accordingly. However, we'd need to investigate how the official drivers handle multiple requests for the same entities: We'd rather avoid the hassle of keeping a central object store like Neo4p does. `rest` can always be requested in `resultDataContents`, but just returns some info for the deprecated API. It should work on old server versions where `meta` is not available. However, the internal structure is different (actually `rest` looks easier to parse than `meta` at first glance).

- Profile the performance penalty of blessing the entities in the JSON hashes (see using the `meta` data). If the penalty turns out to be low, blessing should probably be done by default.

- An alternative to using `$client->{_res}->status_line` (to get the HTTP error message) might be to call `$client->getUseragent->add_handler(response_header => sub { $status_line = shift->status_line })`. However, this is probably slower and would likely need to be run for each and every POST including those with 2xx status codes, which might not be acceptable.

- Disabling `die_on_error` probably makes errors harder to find, but has no clear advantages. In particular, errors are often missing the proper header fields for the commit URL etc., so it's likely the failed request doesn't produce useful return values and the next request will fail anyway with a misleading error message due to the URLs being corrupted. This feature is not present in the official drivers anyway; it was inspired by Neo4p and should probably be removed completely.

- Consider supporting re-using `Record` objects for query parameters in `run`. The Java and C# drivers do this.

- Profile whether `Tie::IxHash` or sorting `JSON:PP` is quicker and adjust the code accordingly.

- Investigate which JSON module is the best. While `Cpanel::JSON::XS` may have some advantages in terms of correctness (I think?), maybe `JSON::MaybeXS` is more compatible.

- Run statements lazily: Just like with the official drivers, statements passed to `run` should be gathered until their results are actually accessed. Then, and only then, all statements gathered so far should be sent to the server using a single request. Challenges of this approach include that notifications are not associated with a single statement, so there must be an option to disable this behaviour; indeed, disabled should probably be the default when stats are requested. Additionally, there are some bugs with multiple statements (see tests `non-arrayref individual statement` and `include empty statement`). If stats end up being requested by default due to profiling, this item would mean investing time in developing an optimisation feature that is almost never used. Since the server is often run on localhost anyway where latency is very close to zero, this item should not have high priority.



### StatementResult

- Add `keys` method, returning a simple list of strings. (Looks like we're stuck with a private method for the `ResultColumns` object, but this is something different.)

- Consider whether to implement iterator semantics for StatementResult.



### Record

- Bugfix: `get` should croak if the call is ambiguous (i. e., there's more than one field but the field to get is not specified by argument). Note, though, that the Python driver intentionally does deliver the first field only in this exact scenario (though its method is called `value` instead of `get`).

- Implement a method that returns the entire record as a hashref. Most of the official drivers offer this; they use the method names `asMap`, `toObject`, `data`.

- Bugfix: The `get` method behaves unpredictably for queries that have fields with conflicting indexes and keys such as `RETURN 1, 0`. It would technically be possible to distinguish between a key and an index by inspecting the scalar's FLAGS (namely, `POK`/`IOK`; see <https://metacpan.org/pod/Devel::Peek#EXAMPLES> and `JSON::PP`'s `_looks_like_number`). Then `get(0)` would mean _index_ `0` and `get('0')` would mean _key_ `0`. Not sure if this is the best approach though.

- Consider whether to implement methods to query the list of fields for this record (`keys`, `has`, `size`) and/or a mapping function for all fields (`map`/`forEach`). Given that this data should easily be available through the StatementResult object, these seem slightly superfluous though.

- Implement `graph`; see <https://github.com/neo4j/neo4j-python-driver/wiki/1.6-changelog#160a1>.



### ResultSummary

- Consider moving the `ServerInfo` over to `Session` to completely avoid the security issue described in the comments.

- `ServerInfo` should use host_port so that IPv6 addresses are returned correctly.

- Profile the server-side performance penalty of requesting stats for various kinds of queries. If the penalty turns out to be low, stats should probably be requested by default.

- The ResultSummary is currently only available via `summary` after explicitly requesting stats before `run`, while the `ResultSummary` object is created regardless. Profile the performance impact of this (questionable) design and investigate possible improvements. One option might be to always provide the summary, but to provide the counters only if requested before running the statement.



### SummaryCounters

- Report `relationships_deleted` issue to Neo4j.

- `use Class::Accessor::Fast 0.34;`

