# KUU-1730 buffering contract preparation

This proposal targets Kotlin 2.3.10 and kotlinx-io 0.9.1 at immutable upstream
`362bdc35e159bad6da1e08101c8321792d762281`. The old issue text's master
`3fa5bd6` is context, not the tested source pin. Main is unchanged; this is a
scratch proposal, not a Ready claim.

The owner ledger contains 72 rows: 40 common/KLIB and 32 JVM ABI. All remain
UNVERIFIED. Core proposes four methods/eight source-library parameter cases;
Backend proposes three methods/ten cases: the original41 source/library × O0/O2
and actual producer/consumer × O0/O2 remain, with four additional Source/current
stdlib-library O0/O2 Native EOF constructor checks. Total7 methods/18 cases/2 suites. Swift syntax parsing does
not prove Swift type checking or candidate behavior.

## Production differences

Five official annotations are absent: `Source.buffer`, `Sink.buffer`, and
`Sink.hintEmit` require exact `kotlinx.io.InternalIoApi`; `Source.transferTo`
and `Sink.transferFrom` carry `kotlin.IgnorableReturnValue`. Both marker
annotations have BINARY retention and must survive a real stdlib producer.
No special IO lowering, runtime bridge, storage change, or new native ABI is
introduced. Existing convenience Sink.write overloads remain; tests select
the canonical three-parameter signature and exercise named `endIndex`.

One version-pinned diagnostic difference is explicit: Main computes the
positive number skipped in RealSource.skip's EOF message, while 0.9.1 uses
`remainingByteCount - byteCount`, producing `only -1 bytes were skipped`.
The new independently executed JVM oracle confirms that literal message.
The complete proposal restores the pinned message for byte-exact parity;
`annotations-only.patch` separately preserves the positive-count Main text
if the owner deliberately accepts this upstream-message divergence. That
choice must remain an observed difference, not be normalized into a PASS.

RealSource's byte-array read and transferTo lack an explicit closed check in
the official implementation as well as Main. Its close marks the source
closed before delegating, and retains buffered bytes if the delegate close
throws. RealSink closes the delegate even if flushing buffered data throws,
keeps the first failure, and does not retry a completed close. PeekSource
records the actual head segment and position after a first successful fill.
These details are preserved; no speculative behavioral change is proposed.

## V3 Native EOF constructor gap

The independent V2 review found ledger `klib-fc162bb4315d0dce` missing:
`core/native/src/-NonJvmPlatform.kt:40` declares public
`EOFException(message: String?, cause: Throwable?)`. Common expect and the
JVM `java.io.EOFException` typealias expose only noarg/message constructors.
V3 adds exactly one secondary constructor forwarding to existing
`IOException(message, cause)`; no Runtime ABI, Throwable storage or lowering
change is proposed. The original constructors and all V2 production changes
remain. No ledger state is promoted.

The added Core method requires exactly three public Native constructors,
nullable message/cause types, exact formal names, no default/vararg parameters,
correct receiver/result and open EOFException -> IOException inheritance.
Actual current library mode requires all three exact metadata records and
real constructor links, no default stubs. Named arguments and an actual user
subclass super call are analyzed in both modes.

The new Native-specific fixture checks noarg/message compatibility, each
message/cause null combination, original cause identity, catch-as-IOException
object identity, derived constructor forwarding and cause reuse. Every printed
success is preceded by Kotlin `check` assertions; nonzero native exits fail.
Its nine-line expected stdout is explicitly derived from those assertions and
pinned Native semantics, not a raw JVM or official Native execution. It has
Source/current stdlib library × O0/O2 coverage prepared, all NOT_RUN. The old
41-row raw reference and its fixture inputs/provenance are byte unchanged.

A separate bounded actual JVM reference has eight raw rows/193 bytes, both
exits0 and empty stderr. It uses pinned official 0.9.1 JVM aliases to execute
shared IOException(message,cause) null/identity and legacy EOF constructors;
reflection asserts EOFException is java.io.EOFException and lacks the Native
extra constructor. This supports shared-superclass and alias controls only:
it does not execute or substitute the Native-only constructor. There is no
transplanted Native class or Java initCause adapter pretending to be that API.
The scratch oracle retains full SDK/source/raw hashes and fully reaped SIDs.

## Evidence and coverage boundaries

One authorized bounded scratch JVM fixture compiled and ran against the
already pinned 0.9.1 jars. Its 41 rows observe short reads, zero-byte data/EOF,
partial EOF consumption, source and dual-sink failure identity, idempotent
close, hintEmit/emit/flush/close order, partial throwing writes, named/default
array arguments, discardingSink, initially empty peeks, multiple peeks,
non-consumption, shared multi-segment copies, head replacement invalidation,
and independent peek close. This is a supplemental reference, not execution
of any original upstream assertion or a separately compiled JVM producer.

The future Backend library lane uses real native object-producing `.kklib`,
checks its manifest/objects and public runContract export, compiles only
Consumer.kt with an artifact search path, fixes entryPointFQName explicitly,
and compares actual exit, stderr, and every stdout byte. It pins source
inputs and full stdlib/producer file hashes. Its cross-artifact entry invokes
the producer's user RawSource/RawSink implementation and internal virtual
calls; direct consumer-side subtype dispatch is covered semantically by the
Core source/library test, not falsely claimed as a separate JVM ABI probe.

The original required source closure has 866 concrete execution IDs:
six Source factories ×124 methods, two Sink factories ×47, and CommonReal
Source/Sink 12+16. Their exact existing JVM and Linux Native reference results
are all PASS, without rerunning the suites. Candidate IDs remain NOT_RUN.
The first focused buffering subset has 250 IDs: 33 methods × six Source
factories, 12 × two Sink factories, plus the 28 CommonReal methods. Other 616
IDs remain in the crosswalk as overlap with Buffer/numeric/UTF8/ByteString
families; they are not deleted or declared out of scope. Original sources,
factory constructors, shared one-byte segments, helpers, and driver invocation
blocks remain byte-preserved. Original peekLarge early returns for the two
one-byte factories are retained; those PASS statuses do not prove that large
peek branch executed on those factories.

Core checks exact function identity, receiver, formal names/types/defaults,
BINARY annotations, Source/Sink buffer property annotations and sealed/public
visibility, user RawSource/RawSink subtyping, inherited RawSource/RawSink vs
direct Buffer calls, and named/default array calls. Four independent private
or internal implementation constructor inputs must each fail per mode.
These negatives do not yet assert diagnostic codes or exact statement ranges.
Source expressions carrying defaults are pinned in the expected JSON, while
metadata default flags and executable default behavior are checked separately.
This preparation does not claim cache HIT: the future test must publish and
import the actual current TestStdlibCache artifact with manifest/full hashes.

RawSource must read at least one byte for a positive byteCount or report EOF;
a user source illegally returning zero forever is outside this fixture's
contract. RawSink returns Unit, so "short write" here means observable partial
consumption before an exception, not a made-up numerical write result.
Concurrent publication/thread safety, JVM typealias identity and Java
Flushable/InputStream/ByteChannel ABI, and Apple interop are not inferred from
common Native tests. The 32 JVM rows require explicit disposition/evidence
with KUU-1762; the public marker/exception rows among the common 40 need their
own exact checks before the whole ledger can advance.

## Required next gates

1. After all frozen Main workers exit, review/apply this proposal on the actual
   base, separately validate KUU-1771 where inherited literal/tower coverage
   requires it, and resolve the imported-const prerequisite for originals.
2. Fresh swift build and focused IOBufferingAPIContractTests (4 methods/8 cases), then fresh
   IOBufferingContractsExecutionTests (3 methods/10 cases) with no parallel SwiftPM/no skip-build.
   Publish actual compiler/test binary/resource/Runtime/ABI/toolchain pins and
   a newly produced stdlib with matching Kotlin manifest, never an old fallback.
3. Execute the 250 byte-preserved original buffering IDs with source/library
   O0/O2 and a real test-library consumer. Compile whole needed original body
   closure without replacing assertions or numeric literals. Stop/reap first
   failure, preserve raw output, and retain per-ID lifecycle observations.
4. Resolve overlap/remaining ledger rows and Java ABI ownership before Ready.
   The full 1188 catalog and general seven-observation paired runner are still
   NOT_RUN/UNMEASURED and paired PASS0; this small fixture is not their substitute.

Generated success artifacts may be cleaned only after saving raw output,
all generated hashes, actual exit and byte comparison outside the exclusively
owned UUID directory. Failures preserve the entire directory. No disk or
cache cleanup was performed during this preparation.


V2 failure-evidence correction: non-zero CommandRunner results are caught;
stdout/stderr are encoded from the returned Strings without trimming, saved
with argv/exit/hash/size outside the failed UUID, then the original error is
rethrown. Timeout/launch errors expose only formatted diagnostics, so receipts
explicitly leave actual exit and raw original bytes unknown. No generated
failure directory is removed. Successful cleanup remains proof-before-cleanup.
This harness change and all prepared cases have not been Swift typechecked or
executed; parsing alone is not validation of the exception-path behavior.
