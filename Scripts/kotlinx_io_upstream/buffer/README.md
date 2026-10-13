# Segmented Buffer contract preparation (KUU-1729)

This is an author-prepared proposal, not a candidate validation result. The
baseline is Kotlin 2.3.10 and kotlinx-io 0.9.1 commit
`362bdc35e159bad6da1e08101c8321792d762281`. All 218 API ledger rows keep their
original states: 208 unverified and 10 missing. No row is marked VERIFIED.

Three official internal context values currently appear as object classifiers
in Main. The proposal restores internal immutable properties with the exact
interface types, `UnsafeIoApi`, `PublishedApi`, and getter `JvmSynthetic`
annotations. Each computed getter returns a private implementation singleton.
The implementations and all their method bodies retain the existing logic and
identity. This preserves the official property/getter contract without relying
on a stored top-level initializer crossing an artifact boundary. Upstream uses
an anonymous object stored in a val; this proposal uses a computed getter to a
named private object as an explicit implementation choice.

Kotlin 2.3.10's optional common `kotlin.jvm.JvmSynthetic` annotation declaration
is added because it is absent from Main. Its official target list and optional
expectation are retained, with the same ExperimentalMultiplatform opt-in used
by the existing JsName resource. The common declaration has no explicit
retention. The JVM actual's SOURCE retention is not assigned to the common
expect declaration. This records source/common metadata intent; it does not
establish JVM `ACC_SYNTHETIC` flags or Java interoperability.

`Buffer.hintEmit` keeps its existing official `InternalIoApi` marker. No Buffer,
Segment, pool or unsafe context operation body is changed. Native SegmentPool
is officially a no-op pool, so no JVM-style recycling implementation is added.

Core checks prepare the thirty public Buffer function shapes, the Long operator
get contract, size, formal names/effective default masks, and the three property/getter
shapes. Six isolated unsuppressed internal/private-value negatives cover Source
and actual current stdlib artifacts. Source properties cannot remain object
classifiers; library properties require real getter links and no setter.
Private backing implementations cannot be exported as public/internal API.
The JSON retains declared default flags separately from effective Sema flags:
Buffer ByteArray overrides inherit Source/Sink start/end defaults. String uses
the compiler string-struct encoding; named classes use their normal class names.
Negative checks require one error and one unbound source occurrence; exact
diagnostic code/location classification still needs the fresh gate.

The direct public boundary fixture has one distinct JVM oracle, 61 rows and
1704 bytes, compile/run exits0 and empty runtime stderr. It observes lengths
0/1/8191/8192/8193/16385, Long operator versus get, copy/snapshot non-consumption,
shared append/consume, head/tail reuse, same-buffer copy, movement after sharing,
ByteArray default/named ranges and partial writes, EOF consumption, thrown root
identity, invalid Long positions/ranges, search across segments, and identity
of all three public unsafe context values. Producer and consumer sources were
compiled together for this JVM oracle; no separate JVM producer/consumer result
is claimed. Its expected output remains raw and byte exact.

The two original test files and MockSink keep their upstream bodies, preceded
only by the existing test-only invisible-access suppression prefix. Forty-four
CommonBufferTest IDs plus AlwaysSharedCopyTrackerTest.stateTransition preserve
their exact constructors, test bodies and existing driver blocks. The needed
five util functions are copied with exact bodies; unused filesystem/POSIX and
UTF-8 helper functions are excluded, without adding substitute implementations.
This is a scoped helper closure, not a full copy of util.kt. Test-only invisible
suppression emulates friend access; public boundary consumers contain no such
suppression, and Core separately rejects unsuppressed accesses.

Existing upstream JVM/Linux Native references passed these 45 IDs. No original
suite is rerun here. The original driver expected stdout is derived from those
per-ID results and preserved BEGIN/PASS lines; it is labelled derived evidence,
not a new raw reference execution. The original driver catches exceptions, so
process exit0 alone is insufficient: exact90-line output rejects missing,
reordered, failed, duplicate or skipped IDs. Supplementary boundary output does
not count as original upstream execution.

Both original45 and boundary61 scopes have Source/current-library O0/O2 plus
real producer-library/independent-consumer O0/O2 lanes. The producer compiles
five original test/helper/driver files or the one boundary producer; consumers
compile only their own source with the actual artifact search path. Public
producer entry exports are inspected. Current stdlib manifest hash, language
version, module, all artifact hashes, input hashes, executable hash, exact entry
FQName, actual exit and raw stdout/stderr are required. No old artifact fallback
is allowed.

After an independent review and Root application, run a fresh build and focused
tests serially, without skip-build or concurrent SwiftPM operations:

```sh
bash Scripts/swift_test.sh --no-parallel --filter IOBufferContractTests
bash Scripts/swift_test.sh --no-parallel --filter IOBufferContractsExecutionTests
```

Intended Core count: 3 methods/16 parameter cases. Intended Backend count:
4 methods/12 cases (6 original and6 boundary). Total7 methods/28 cases/2 suites.
Report actual Swift Testing counts. Suggested initial finite budgets are build
300s, Core1800s/test phase1500s, Backend3600s/test phase3300s; native program
timeout is30s. Compilation progress and per-case CPU need observation. First
failure stops dependent gates, and the gate owner must reap all descendants
before edits. The helper API does not expose timeout raw bytes/final exit or
process-group identity, so it records unknown rather than fabricating evidence.

Successful generated UUID-owned artifacts are cleaned only after exact output,
source/artifact immutability and all hashes are saved outside the UUID tree.
Nonzero native results retain raw String-to-UTF8 stdout/stderr, argv and exit
before the original error is rethrown; invalid original UTF8 may already have
been replaced by CommandRunner. Timeout/launch errors retain their formatted
diagnostic and mark unavailable data unknown. Compilation failures and all
generated failure directories are retained. No shared cache is cleaned.

The nine missing internal property/getter ledger views receive a prepared fix,
not a validation mark. The JVM Buffer.asByteChannel row
`jvm-ad4ebd5c3ae69d32` remains missing and is shared with KUU-1762 for platform
interop disposition. It is neither deleted nor marked target-out. All93 JVM
ABI rows require separate evidence or routing; common Native behavior does not
prove Java descriptors. The issue still cannot be Ready from this proposal.

Historical KUU-1727 frontier17 diagnostics belong to compiler/platform families
(1771 inherited/fallback, 1772 imported const,1773 mutable local, files/POSIX).
This proposal adds no IO-specific inference or no-op workaround. Current
prerequisite gates and all KUU-1729 candidate cases are still execution evidence
to obtain. Full1188 candidate execution and parent's general paired PASS remain
unclaimed. IO Buffer/snapshot evidence does not inherit ByteString namespace
verification from KUU-1760.
