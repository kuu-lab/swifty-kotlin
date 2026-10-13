# atomicfu 0.33.0 implementation plan

This plan covers the pinned Kotlin/Native API of
`fc175fc575419ca9eae0d3c14cefe9c5cd7ca351` (0.33.0, Kotlin 2.3.10).
[The declaration ledger](atomicfu-0.33.0/README.md) is the source of exact
signatures, visibility, annotations and upstream spans. It has 150 Native ABI
identities (142 Kotlin-public, 8 PublishedApi internal) and 126 rendered Native
signatures. The historical 130 rendered signatures also included four JS/Wasm
signatures from five identities; those exclusions remain separate and their
missing source annotation facts are unknown.

The inventory repair adds documentation, pinned evidence and Python checks. It
does not add `Sources/CompilerCore/Stdlib/kotlinx/atomicfu`, bridge declarations,
or product runtime tests. The existing discovery/import fixtures construct local
marker classes and cannot establish actual atomicfu registration or operation
semantics. KUU-1732 and parent KUU-1728 remain incomplete.

## Feature boundaries

| Feature | Required next evidence | Status after this inventory repair |
| --- | --- | --- |
| V01 inventory | exact ABI identities, targets, visibility and annotation arguments checked against pinned source bytes | ledger repaired; no product implementation claim |
| F06 imports | actual bundled symbols through wildcard, individual, fully qualified and alias imports; coexistence with both standard atomic packages | pending actual registration and source/artifact binder gates |
| C01 Kotlin public layer | real factories/wrappers and executable bodies without external atomicfu plugin | pending; local mock declarations do not count |
| V08 ABI/pipeline | actual source-backed binding, correct bridge ABI/handles, explicit stdlib artifact loading and real link/run | pending; inventory Python checks do not count |
| Parent KUU-1728 operations | atomicity, arithmetic/identity, delegated properties, update loops, arrays, locks/parking and concurrency/lifetime contracts | separate operation slices; not completed by registration |

A registration-only change can establish named types, official factories and
symbol ownership for a limited subset, with omissions explicitly recorded. It
cannot close all F06/C01/V08 until the complete required surface and real gates
exist. Do not fill remaining declarations with placeholder returns or bodies that
throw UnsupportedOperationException to claim coverage. Native Trace's specified
no-op is the explicit exception; even it must preserve callback evaluation.

## Source registration and ownership

Place real Kotlin implementations below
`Sources/CompilerCore/Stdlib/kotlinx/atomicfu/` and `.../locks/`. `Package.swift`
copies the Stdlib resource tree and `BundledStdlib.collectBundledStdlibSources`
recursively discovers `.kt` files as deterministic `__bundled_kotlinx/atomicfu/...`
virtual paths. No separate resource manifest or synthetic Swift atomicfu registry
is needed. Inventory source copies under `docs/` are not compiler resources.

Use ordinary nominal Kotlin wrappers with official `kotlinx.atomicfu` ownership;
never typealias these wrappers to standard atomic types. An alias would expose
standard load/store/compareAndExchange APIs absent from atomicfu and remove the
nominal distinction. Keep official internal constructors and the eight factory
overloads (four scalar families, with and without TraceBase), not public marker
constructors. Public inline members' `@PublishedApi internal a` fields need real
source/artifact accessibility, including the eight internal property/getter ABI
rows. Preserve annotation retention, targets, deprecation messages/levels and
ExperimentalThreadBlockingApi's ERROR opt-in rather than names alone.

The existing BundledDeclarationIndex uses receiver/owner FQName, name and arity;
standard atomics and atomicfu therefore have different keys. CompilerKnownNames
atomic scalar factory recognition is restricted to explicit standard/Java FQNames.
No static new index-matching blocker was found, but these observations are not an
actual binder proof. Do not add ordinary atomicfu wrappers to the raw standard
atomic factory whitelist or rewrite their `this` to runtime box handles.

## Real delegates for all Native type families

| Atomicfu source family | Concrete implementation path | Required checks / unresolved boundary |
| --- | --- | --- |
| AtomicInt / AtomicLong | official Native wrappers retain `a: kotlin.concurrent.AtomicInt/AtomicLong`; delegate value/CAS/fetch-add and exchange loops to those existing real standard objects | internal constructor/PublishedApi metadata, 32/64-bit wraparound, CAS/update retries and inline export |
| AtomicBoolean | official Native layout retains `a: kotlin.concurrent.AtomicInt` with 0/1 encoding; standard AtomicBoolean is also real but substituting its type would change the indexed internal ABI | preserve Boolean encoding and exact internal field type; test both success/failure CAS |
| AtomicRef<T> | official Native `a: kotlin.concurrent.AtomicReference<T>` delegate; reuse standard member load/store/exchange and identity CAS, retaining class T binding | nullable values, equal-but-distinct identities, boxed scalars, generic ABI marshal and GC lifetime |
| AtomicIntArray / AtomicLongArray / AtomicBooleanArray / AtomicArray<T> | reuse pinned common bodies `Array(size) { atomic(0/0L/false/null) }`, so each stable element wrapper owns a real scalar delegate | size/bounds, repeated get identity/aliasing, initial values, nullable T and official constructor visibility/deprecation |
| TraceBase / TraceBase.None / TraceFormat / Trace / named / default format | retain actual common declarations and Native bodies: Trace returns None and named returns None; TraceFormat retains formatting body | append no-op is specified; invoke must evaluate event() before append; lambda/event/format arguments still evaluate normally |
| OptionalJsName / ExperimentalThreadBlockingApi | real annotation declarations with the indexed retention/Target/OptIn/RequiresOptIn and arguments | source/artifact annotation metadata and diagnostics; no fabricated excluded JS arguments |
| SynchronizedObject / ReentrantLock alias / reentrantLock / synchronized / withLock | use a real owned recursive-lock delegate or port the pinned owner/CAS/monitor algorithm; keep Native ReentrantLock as the SynchronizedObject alias | recursive ownership count, wrong-thread unlock error, exception-safe finally, tryLock and delegate lifetime; missing kernel operations below |
| SynchronousMutex | port the pinned NativeMutex fair queue using real scalar/ref atomics and a real ParkingSupport delegate | reentrancy, FIFO, timeout cancellation, wrong-owner unlock; coroutine Mutex is not an equivalent delegate |
| ParkingHandle / ParkingSupport | real per-thread handle retaining a one-bit permit and OS wait/wake delegate; public Kotlin layer handles Duration/TimeMark conversion | same-thread handle identity, different-thread isolation, pre-unpark coalescing, monotonic timeout/deadline, spurious wakeups, lifetime |

The legacy standard atomics used in the official Native `a` signatures and the
canonical `kotlin.concurrent.atomics` source family already share real Runtime
C-atomic kernels. Standard factories allocate runtime atomic boxes, and their
Kotlin members call the registered load/store/CAS/CAX/fetch-add bridges. Delegate
through the inner standard object: `atomicfu ordinary object -> field a -> real
standard member -> existing Runtime ABI -> C11 cell`. Existing kernels are in
`RuntimeAtomic.swift` and `RuntimeCAtomics`; this is not a new atomicfu ABI.
Passing an ordinary atomicfu `this` directly to `__kk_atomic_*` violates the box
representation and can produce the type-guard fallback zero value. Do not use
that shortcut. Canonical standard AtomicArray methods also use real kernels,
but replacing atomicfu arrays with per-index views requires additional stable
wrapper-identity proof; the pinned Array-of-wrappers body avoids that change.

For reference delegates, preserve the existing class-generic member marshal path.
Standard AtomicReference/AtomicArray source documents why function-generic extern
nullable results are unsafe for some values. A newly declared free generic raw
bridge is not an equivalent shortcut. No new runtime entry is needed for scalar
or array registration using existing delegates; operation claims still require
actual tests of the delegated contracts.

### Lock and parking kernel boundary

`RuntimePreconditions.swift` already implements `__kk_synchronized` with an
NSRecursiveLock per object and shared monitor-table lifetime. Its lock/unlock
helpers used by Lazy are real, but their current ABI does not provide atomicfu's
nonblocking tryLock, owner-validation exceptions, timed waits or per-thread
parking handles. They cannot by themselves establish the complete lock surface.
A safe lock slice can reuse that recursive kernel after adding audited private
handle operations (create, lock, tryLock, unlock with outThrown/owner checks) and
retaining the handle for its Kotlin delegate. Verify recursive ownership and
same-key monitor compatibility, not only uncontended entry/exit.

`RuntimeSync.swift`'s RuntimeMutexHandle and `kotlin.concurrent.Lock.withLock`
are non-reentrant; coroutine Mutex additionally supports coroutine suspension
and owner tokens. Do not silently use these for atomicfu ReentrantLock or
SynchronousMutex. SynchronousMutex's pinned NativeMutex is reentrant and has fair
parking-queue/timeout semantics. Prefer porting its real algorithm after a real
ParkingSupport backend exists. An OS delegate alternative must prove the same
contracts, including timeout cancellation and fairness, before being substituted.

The current public ABI has no verified full ThreadParker/parking kernel. Port the
pinned ThreadParker/NativeMutex algorithms above real OS condition/futex wait/wake
and thread-local identity, or introduce a private capability with audited
Duration conversion and retained handle lifetime. Unpark must store at most one
permit before a park, not a counting semaphore; no-op park/unpark is invalid.
All lock/parking types can follow this concrete source-delegate path, but they
remain implementation work, not fabricated completed registrations. New private
kernel entries, when necessary, must update RuntimeABISpec, throw/handle contracts,
link checks and runtime concurrency tests, with the §13-2 reason/count/specVersion
required by [the stdlib pipeline](stdlib-pipeline.md). Do not add public atomicfu
`kk_*` APIs or pretend this ledger adds those runtime capabilities.

## Next exact source-binding gate

After real Kotlin declarations land, compare the compiler's resolved source
symbols against **all 150 Native ABI identities**, including properties,
accessors, overloads, generic/receiver/return types, visibility and annotation
arguments. Build the expected catalog from the pinned ledger, then independently
normalize actual symbol/metadata types (including the official Native alias),
with no missing or unexpected public member set. Track unimplemented rows as
failures/omissions; do not reduce the expected catalog or count mock declarations.
Keep the five excluded JS/Wasm identities outside Native coverage and their
unavailable source facts unknown.

For F06 use actual bundle source and an explicit freshly produced stdlib artifact
with no source fallback. Check `sourceOrigin`, owner FQName and distinct SymbolID
for wildcard, individual, fully qualified and alias imports beside both standard
atomic packages. Negative controls reject wrong/public scalar constructors and
atomicfu `load/store/compareAndExchange/MemoryOrder` surface leakage. Check private
versus PublishedApi field visibility and backing access from separate inline-body
consumers. Discovery must name actual product resources, not a temporary marker.

For C01/V08 use fresh `swift build`, targeted source/import and producer/consumer
metadata tests, Runtime ABI declaration/link validation, then bounded source and
explicit-library Native compile/link/run. Preserve exact artifact/input hashes
and actual exits; no wrapper ABI bypass or external atomicfu plugin. Use genuine
atomic operations and nullable/identity controls, Native Trace callback side
effects, and lock owner/reentrancy/exception tests. Expand operation/concurrency
coverage in parent KUU-1728 slices rather than calling the entire library done
from an import smoke. The pipeline's enforcing and dual-oracle requirements still
apply. The scratch inventory repair ran only focused Python tests; none of these
product gates has been newly executed by it.

## Prepared actual-source registration slice (KUU-1732)

This slice is prepared code, not a completed compatibility claim. It registers
all 150 pinned Native identities as real bundled Kotlin declarations: 142 public
and eight PublishedApi internal property/getter identities. `ReentrantLock` is
also preserved as the official source typealias to `SynchronizedObject`; it is
not an additional Native nominal identity. The five JS/Wasm-only ABI rows stay
excluded. Their missing platform source facts remain unknown.

`AtomicFU.kt` keeps the four distinct ordinary atomicfu nominals and official
legacy `a` field types. Values and operations delegate through actual standard
objects to existing atomic kernels; no raw factory whitelist, synthetic atomicfu
registry, plugin transformation or direct wrapper-address shortcut is added.
Ref `getAndSet` uses the standard class-T member exchange so nullable/reference
marshalling stays with that member. Boolean keeps Int 0/1 backing. The common
retry/update bodies and arrays keep their pinned algorithms; each array stores
one stable wrapper per element. Trace/None append bodies are the specified
Native no-op, while `invoke` still evaluates `event()` and the real formatter
retains its callback. There are no unsupported-operation placeholder bodies.

`locks/` owns public source behavior. Its private blocking kernels implement
actual recursive thread ownership, FIFO acquisition and timed cancellation,
owner validation, one-bit parking permits, cross-thread unpark, and a per-thread
stable ParkingHandle factory cache. A coroutine Mutex cannot satisfy these
contracts and is not used. Native `SynchronizedObject.unlock` uses
IllegalArgumentException (`require` upstream); SynchronousMutex uses
IllegalStateException (`check` upstream). Duration conversion stays in Kotlin.

The eight private ABI additions are admitted as OS synchronization / memory
representation / GC-and-TLS mechanisms under stdlib-pipeline §13-2, rather than
as new public atomicfu operations. Their complete signatures, throwing flags,
lifetimes and thread-safety contract are in
[atomicfu-runtime-kernel-contract.md](atomicfu-runtime-kernel-contract.md).
The existing Runtime registered-object table retains Swift boxes for the
Runtime lifetime; ordinary GC currently sweeps `kk_alloc` heap records, not
those registered boxes. This slice follows that ownership model. TLS root slots
are removed at thread exit; that fact must not be reported as reclamation of a
registered wrapper/kernel. Changing the existing registered-object collector is
a separate memory-management scope. Force-reset invalidates cached wrapper
values and requires the existing isolation rule: all worker threads joined.

Prepared enforcing checks use actual compiler sources/artifacts, not local mock
AtomicInt declarations: four Core cases (150 exact identities in source/library,
plus negative visibility/leak tests), twelve Backend cases (source/library O0/O2
for scalar/array/Trace, lock/parking, and independent producer/consumer), and ten
Runtime methods. The two compiled symbol snapshots are independently compared
by `check_atomicfu_compiled_api.py` against expected types, nullability, receiver,
generic bounds, defaults, inline flags, visibility, mutable properties and
argument-bearing annotations from the pinned ledger. Unexpected public or
PublishedApi symbols fail. Generator/checker Python tests are controls of the
checker, never actual registration evidence.

These expectations have not been compiled or executed during preparation.
Fixture stdout is specification-derived and needs the pinned actual Native
reference before it can be called an oracle. Compile source first, publish a
fresh source/RuntimeABI-matched stdlib artifact, then verify the imported lane
and separate consumer with no source fallback. Archive compiler/resources/ABI/
Runtime/complete artifact file hashes, actual exits and finite watchdog reaping.
Do not reuse old artifacts or bypass normal fingerprint validation. Keep normal
standard-atomic regression checks and the parent stack's annotation-retention /
startup/entry ABI fixes in the future base. OptionalJsName's flattened ordinary
annotation still preserves BINARY OptionalExpectation; its multiplatform
legality and metadata behavior need actual compiler validation.

F06/C01/V08 remain incomplete until these real gates pass. Parent KUU-1728 still
owns wider operation/concurrency conformance, target grids, performance and
atomicfu plugin compatibility; this registration slice does not establish those.

### v2 preparation follow-up

The private parking factory uses the existing exact-link Function0 adapter;
no scalar raw-factory whitelist or additional private ABI is introduced. The
Parker completes wake handoff before unpark returns and preserves a subsequent
pre-permit while the old owner cleans up. Runtime regression proposals observe
the TLS root while its worker is live and require worker drain before reset.
Backend proposals retain every failing source/executable/producer and save
compile results plus dependency/executable hashes before assertions. Success-only
owned cleanup follows completed execution and exact ASCII expected Data match.
CommandRunner exposes decoded UTF-8 strings: those receipts are not arbitrary
raw byte streams; an outer gate must retain its own raw stdout/stderr.

Syntax parsing and nine Python checker controls are preparation validation only.
Actual source/library/KIR/Runtime execution remains NOT_RUN.
