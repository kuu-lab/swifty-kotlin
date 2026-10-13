KUU-1728 retained atomic payload bridge — staged proposal, not Native final GC

Base Atomic HEAD c4a8be190047f9bfdfbc8bc233556e8ae9095b37 was clean and read-only.
This patch changes no Native API, source visibility/annotation, Runtime C ABI,
metadata format, allocation representation, compiler raw-factory whitelist,
GC reset ownership policy, or public lifetime operation. It does not turn every
registered box into a managed heap allocation. All actual tests are pending.

Two allocation/lifetime domains are present:

| Path at the reviewed base | Ownership/root/traversal/sweep consequence |
| --- | --- |
| RuntimeGC.swift:308 kk_alloc -> heapObjects; :337 collection; :690 mark/sweep | Header KTypeInfo field offsets are traced; only heapObjects are swept and deallocated. |
| RuntimeStringArray.swift:1457 kk_object_new -> RuntimeObjectBox; :2936/:2956 field writes | Normal Kotlin class/wrapper allocation is passRetained + objectPointers, outside heapObjects. RuntimeArrayBox stores RuntimeValue words; no box child visitor is called by GC. |
| RuntimeCollectionHelpers.swift:1033 registerRuntimeObject | Registered Swift boxes have an external retained ownership; registry membership is not a managed reachability verdict. |
| RuntimeAtomic.swift:363/:414 AtomicRefBox; :727/:793 AtomicRefArrayBox | C11 cells store opaque words. Previously their managed payloads were never appended to GC's worklist. |
| RuntimeObjectOwnership.swift:8/:51 release | Explicit release removes the registry first, then metadata and ARC ownership. Pin/StableRef/borrowed/Unit refusals remain intact. Managed kk_alloc objects are intentionally excluded. |
| RuntimeAtomicfuSynchronization.swift:209/:244 Lock/Parker creation | Real Swift kernels are retained registered boxes. Holding/blocked calls have local Swift strong references; no GC finalizer traces or owns these boxes. |
| RuntimeAtomicfuSynchronization.swift:157 AtomicfuParkingRoot | Real pthread TLS owner registers a global slot containing an ordinary wrapper, removes that slot on thread destruction. Existing collector skips that registered wrapper; slot existence alone proves neither child tracing nor kernel reclamation. |
| RuntimeGC.swift:726 root walker | Global, manually registered frames, coroutine, pin/StableRef, ThreadLocal and callable roots are enumerated. A root word that names a registered box is skipped by the heap-only mark loop. |
| docs/arch-014-frame-map-emission.md; docs/spec.md J16.2 | Generated frame/global root emission is not wired. A thread-stop handshake is not implemented by the GC registry NSLock alone. |

Concrete static reproducer: with a valid live KTypeInfo descriptor and isolated
GC state, kk_alloc(payload); kk_atomic_ref_create(payload); kk_gc_collect();
require heap count1. Current root enumeration never visits the AtomicRef cell;
unless another real root exists, sweep removes that payload. This is a source
consequence and a PREPARED failure, not a measured run. Never dereference the
removed pointer in a probe. Retained ordinary Kotlin payloads do not demonstrate
this bug, because they are outside heapObjects and retained independently.

Minimal patch scope:

- Track only retained AtomicRef/RefArray factory handles in GCState. This is a
  subset of objectPointers, not a new GC-owning retain or public API.
- During collection, load their C11 cell words and append only exact existing
  managed-heap keys. Header traversal and heap sweeping are unchanged. Opaque
  raw words can conservatively collide with a live managed address; this may
  retain an extra object, so this bridge is not a precise new field-tag scheme.
- Reference-cell store/exchange/CAS and the collector's root snapshot use the
  existing GC lock. Int/Long/Boolean kernels remain untouched. CAS matching gets
  the already-locked object registry, avoiding nonrecursive NSLock reentry;
  matching rules and seq-cst C11 operations remain unchanged.
- Explicit release/reset-owned release removes the auxiliary handle membership
  together with registry removal; clear/replacement exposes removed heap payloads
  to the existing sweep. Retained kernels themselves are not automatically swept.
  Ordinary Kotlin owner paths currently do not emit kk_object_release. Thus an
  uncollected retained cell still keeps its payload; this bridge alone does not
  establish automatic whole-owner/payload bounded reclamation.

Incoming managed values and returned old values still require a real caller root.
The bridge is not permission to collect unrooted operands on another thread.
Managed payloads nested behind ordinary RuntimeObjectBox/Array/List fields remain
outside this narrow bridge. The array-of factory's source array needs its own
root/tracing contract. Force-reset invalidates the managed heap as before; probes
release/clear their owned cells before TypeInfo teardown and isolation reset.

Prepared tests are Runtime7 methods/cases and Backend2 methods x4 source/library
O0/O2 =8 cases (15 new cases total). Runtime assertions use actual heap counts,
failed-CAS/no-update-root, replacement, array element removal, typed heap child
traversal, explicitly rooted concurrent operands, direct real-method lock
exclusion, and weak ARC references after explicit release. Weak Lock/Parker ARC
controls intentionally show that GC alone
still does not reclaim those registered kernels. Backend6+2 ASCII output rows
are prepared compatibility expectations, not a measured oracle and not managed
reclamation proof. Real separate user .kklib/consumer, actual fresh Stdlib file
hashes, no source fallback, dependency before/after hashes, failure retention and
10-second execution controls reuse the existing production test helper.

Next owned-box migration has concrete prerequisites, not a blanket sweep:

1. First run the narrow direct-cell baseline/fix Runtime scope with saved real
   stdout/diagnostics, finite group kill/reap and original/fixed input hashes.
2. Instrument a real global/TLS root -> ordinary wrapper field -> managed payload
   test with no alternate roots, then clear/remove that real root and prove
   reclamation. Include two wrappers sharing a kernel/array element, a shared
   ParkingHandle surviving producer-thread exit, actual TLS destructor release,
   and negative no-root/cleared-field controls. Root count alone is insufficient.
3. Before enabling box reclamation, establish real generated root slots for every
   live reference across nested calls, aliases, early/exception returns, captured
   closures and producer/imported bodies; generated singleton/global roots and
   a mutator safepoint/stop handshake are required. ARCH-014's root0 calls are not
   a substitute. Closed family opt-in must keep unrelated borrowed/static boxes,
   primitives, caches and explicitly owned APIs on their existing paths.
4. Supply a typed box-child visitor using field/reference metadata (not all raw
   words), and synchronize every included mutable field/array path with the GC
   protocol. Registered handles must be retained atomically during resolution:
   current resolveRuntimeHandle checks membership under GC lock then casts after
   unlocking, which would race a future concurrent sweep/release. Obtain the
   Swift strong reference before unlocking when introducing automatic release.
5. Remove registrations/dispatch metadata under the collector lock, queue owned
   ARC releases and perform deinit/finalizer work outside that lock: TLS root
   destructors unregister through the same lock and may otherwise deadlock.
   Waiter/owner operations must retain their kernel through completion; reset
   and finite-failure cleanup must drain workers before heap/TLS reset.
6. Only after these controls pass, prove unrooted ordinary owner/array/kernel
   counts and weak references return to baseline over bounded allocation loops,
   across all source/library O0/O2 and actual producer/consumer lanes, including
   GC during reference publication and shared handles after originating exit.

No new private/public ABI is proposed here (delta0). §13 rationale is the
existing Runtime memory representation/GC mechanism. Runtime line growth and
one new internal visitor/index pay for real direct payload reachability; global
GC-lock contention on reference modifications is an explicit cost that needs
measurement, not an unmeasured performance claim. Full box reclamation may need
compiler/runtime root descriptors, but no speculative bridge signature or ticket
ID is invented before existing retained-root/frame ABI capabilities are verified.
Unknown original121 IDs and uncreated62 children remain unknown. Recording Trace,
unbox/LLVM optimizations, distribution and future targets remain separate work.


## V2 prepared real-method mutation exclusion control

The existing concurrent heap-count control keeps both payloads externally rooted.
It does not enforce each mutation's GC lock, and exported handle resolution takes
the same lock before the method. V2 adds one Runtime method/case, resolving and
strongly retaining real scalar/array boxes before holding the collector lock. A
worker invokes the real scalar store/exchange/compareAndExchange and array
store/exchange/compareAndSet/compareAndExchange methods directly, then the real
lock-free C11 reads must remain100 during a100ms held-lock observation and become
200 after unlock and worker completion. No mock mutation, alternate resolver,
managed payload, descriptor, public ABI, or production test hook is introduced.

The ready signal is immediately before the real call; a descheduled worker could
hide a removed lock. This bounded observation does not prove scheduler fairness
or a complete mutator/collector handshake. All normal waits are finite. Failure
to drain records an expectation failure and keeps the runtime isolation scope
open until actual worker drain; the mandatory finite outer process-group
watchdog handles a true deadlock. This failure-only wait prevents the trait's
unconditional teardown GC reset from running under a still-active mutation.
Raw owners are released only after drain; no fully-drained claim is made before
an actual future gate receipt. Counts are now7 Runtime cases plus8 Backend
source/library/O0/O2 cases =9 methods/15 cases PREPARED. Actual tests remain0.
All four Runtime source files and all Kotlin fixtures/expectations are V1 byte
identical. General ordinary boxed graph/stack roots/automatic owner GC remain
NOT_READY and are not made complete by this test-only strengthening.
