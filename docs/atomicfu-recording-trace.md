# Explicit Native recording Trace extension (KUU-1728, prepared)

This proposal adds real Kotlin implementation in `kswiftk.atomicfu`. It does not
change `kotlinx.atomicfu.Trace`, `TraceBase.None`, `TraceBase.named`, the four
Native scalar nominals, their factories, arrays, or the pinned 150 Native ABI
identities (142 public / eight PublishedApi internal;126 rendered signatures).
The new namespace is KSwiftK-specific and must be explicitly imported. The
unknown original121 ID catalog and uncreated62 child issues stay unknown.

```kotlin
import kswiftk.atomicfu.RecordingTrace
import kswiftk.atomicfu.recordingAtomic
val trace = RecordingTrace(32)
val state = recordingAtomic(0, trace.named("state"))
state.incrementAndGet()
println(trace.toString()) // 0: state.incAndGet():1
```

Native `atomic(0, trace)` remains an ordinary no-op-traced Native atomic. Use
`recordingAtomic` to request operation recording. It returns one of four
separate ordinary nominals `RecordingAtomicInt/Long/Boolean/Ref`, backed by a
real original atomicfu delegate and the existing standard C11 atomic kernels.
No ordinary wrapper address is passed to a raw kernel. The unrecorded Native
path and exact Native ledger are unchanged. This is a source-layer explicit
mode, not an atomicfu compiler plugin or an unboxing transformation.

## Ring and callback contract

`RecordingTrace(size=32, format=traceFormatDefault)` requires a requested size
in1..1_048_576 and rounds up to a power of two. This upper bound is an explicit
KSwiftK contract: the original JVM factory only requires size>=1 and has
Int-overflow limitations. The Native factory accepts invalid sizes because its
specified result is None; that behavior remains unchanged.

An existing source-owned SynchronizedObject protects fixed event/index arrays,
head/count/index. No new Runtime kernel or ABI is introduced. A batch of1..4
fully evaluated events obtains one append lock, reserves contiguous indices,
and stores the batch in order. When more events arrive than capacity, oldest
entries are replaced. Int indices wrap; copied list order remains oldest first.
`snapshot()` copies immutable Entry wrappers referencing the original event
objects. Later appends cannot change that snapshot's entries, although a
user-owned mutable event can still change its own textual representation.

Unnamed event stringification is deferred until formatting, as in JVM TraceImpl.
`RecordingTrace.named(name)` returns another RecordingTrace sharing storage and
format. It eagerly stringifies each event as `name.event`, as in JVM NamedTrace;
chained names compose as `outer.inner.event`. A named batch stringifies all
arguments in source order before locking/committing. A failure in any of those
callbacks propagates and commits none of that batch. The member named API is
intentionally typed RecordingTrace. If erased to TraceBase and the original
Native `kotlinx.atomicfu.named` extension is called, that API still returns None.

Inherited TraceBase.invoke evaluates event() exactly once, even on None, before
append. Normal Kotlin explicit/default arguments are evaluated once in their
ordinary order; None does not erase callback/default/argument side effects or
exceptions. RecordingTrace formatting obtains a copied snapshot, releases the
storage lock, then calls TraceFormat.format(index,event). Formatter failure
propagates and does not clear the ring; formatter reentry can append and affects
a subsequent snapshot, not the copied output being formatted. No arbitrary
user formatter/toString callback is intentionally invoked under the storage lock.

Fixed ring arrays bound the logical retained event slots. The existing Runtime
registered-object table permanently retains many boxes; this proposal does not
claim bounded total process allocation or managed reclamation. Append stores
raw event/index slots without allocating an Entry per event. Snapshot allocates
copied entries and a list; those allocations still follow existing Runtime GC
limitations. GC survival alone cannot prove marking of atomic/event payloads.

## Explicit scalar hooks

Each recording scalar wraps one real Native delegate, exposes value/lazySet/
compareAndSet/getAndSet/delegation, and numeric arithmetic where applicable.
Every successful store/lazySet/exchange/arithmetic operation records once;
compareAndSet records only on success. Same-value successful operations also
record. `+=`/`-=` delegate to getAndAdd and record once. Retry update/getAndUpdate/
updateAndGet use the wrapper's real CAS and record only the successful attempt;
user transforms may execute again after contention, just as the Native retry
algorithm permits. Loop reads do not create modification records.

Messages use pinned JVM scalar conventions: set(v),lazySet(v),CAS(e,u),
getAndSet(v):old,getAndInc():old,getAndDec():old,getAndAdd(d):old,
addAndGet(d):new,incAndGet():new,decAndGet():new. Boolean exchange deliberately
prints the public Boolean old value; the JVM internal implementation interpolates
its Int0/1 representation. This explicit extension does not claim that JVM
implementation detail as a Native compatibility requirement.

A real mutation completes before its message is interpolated/appended. If a
payload.toString or a custom TraceBase.append fails, the same exception propagates
and the committed atomic value is not rolled back. Failed CAS and None skip
message construction, so no payload stringification effect is introduced.
Factories always pass None to the ordinary delegate; a second tracing path is
not installed. The extension factory default creates one RecordingTrace for its
wrapper. RecordingAtomic.trace retains the same selected trace instance.

Concurrent atomic modification order is the delegate's real atomic order.
Recorded order is successful append-lock order, potentially different across
concurrent operations because interpolation/appending follows the mutation.
There is no claim of one global atomic linearization order across wrappers,
just as JVM post-operation tracing can interleave. Use the actual snapshot order
when interpreting logs. Reads/toString of a recording scalar do not record.

## Provenance and future enforcing gates

Pinned upstream commit:fc175fc575419ca9eae0d3c14cefe9c5cd7ca351 (atomicfu0.33.0).
JVM Trace.kt and AtomicFU.kt plus Native Trace.kt and common TraceFormat.kt are
SHA-bound in the scratch preparation. JVM algorithms/messages were read only;
no fresh JVM/Native/candidate/compiler/SwiftPM execution occurred. New extension
expected files are specification-derived PREPARED expectations, not measured
reference or candidatePASS. Old Native56-row baseline, old150 index and old gate
failures remain unchanged. The original121 catalog is unresolved; no new names
are assigned to missing IDs or hypothetical62 children.

New focused tests:Core2methods/10cases (source/library positives and four
visibility/import negatives), Backend4methods/16cases (three fixtures plus real
separate producer/consumer at source/library ×O0/O2), Runtime2methods/2cases of
the actual existing lock kernel. Core keeps source/flags/chosen public callee/
ordinary compiled link guards. Existing Native150 exact compiled-symbol tests
must remain in the gate; a hand-written metadata fixture is not a substitute.
Backend uses actual fresh TestStdlibCache, no default artifact or source fallback,
full dependency/executable/source hashes, completed exit0+exact decoded-UTF8
ASCII expected comparison,10s process run, and failure-retained products. An
outer PID/start/process-group/subreaper watchdog must bound in-process compilation
and preserve raw streams; CommandRunner exposes decoded streams only.

Producer source mode produces a real user .kklib with bundled source; producer
library mode uses explicit fresh stdlib .kklib. Both independent consumers import
the producer plus explicit fresh stdlib with no fallback. The producer keeps a
private event type and exported session/counter/inline bump; consumer verifies
real shared storage/event dispatch and retained copied snapshots. Relocated
installation/distribution is still a separate parent task.

Runtime tests exercise actual existing recursive lock serialization and typed
kernel identity across collection. They are not a mock ring or a complete Trace
concurrency proof. Bounded workers drain before Runtime isolation reset. Kotlin
GC fixture verifies live event identity/replacement only. Actual concurrent
compiled-Trace stress, atomic payload tracing/replacement reclamation, release
and thread-exit collector integration remain parent follow-ups; current Kotlin
thread-source surface has not been established by this proposal.

## §13 budget and remaining scope

New product private/public Runtime cdecls:+0/+0. New Runtime ABI signatures:+0;
Runtime specVersion unchanged. Product Runtime/CompilerCore Sema/KIR/Backend
implementation changes:0; raw-factory whitelist changes:0. The real existing
owned synchronization+8 mechanisms are reused through ordinary source methods.
Kotlin source grows for explicit ring and four distinct delegated wrappers;
this keeps original API semantics/nominal identity and avoids a raw wrapper ABI
shortcut. Test/docs/API-ledger growth has an explicit new namespace scope.

Full Kotlin/Sema/KIR/Swift typechecking and execution remain NOT_RUN in scratch.
Root may apply only after active Main/Atomic freeze and capacity gates finish,
then freshbuild, actual Native150 plus new28 focused cases and ABI link controls.
Keep the first failing raw logs/source/executable/producer, stop without retries,
and report partial completions honestly. Neither this proposal nor a future
manual-appendPASS closes unbox/LLVM/direct-storage/array/delegate transformations,
Trace erasure, performance, GC, distribution or future-target parent requirements.
