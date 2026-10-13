# KUU-1763 Apple IO candidate draft

This is authored implementation preparation. No candidate build, Kotlin frontend,
SDK type check, library generation, or native execution has been performed.
All six API rows and all 25 original execution IDs remain UNVERIFIED.

Pinned upstream: `362bdc35e159bad6da1e08101c8321792d762281`. The previous official
macos_arm64 reference run `38073241455` passed the 25 originals. That result is
reference evidence only. The candidate preserves their bodies, retains original
files byte for byte under `Originals`, and adds only file-level invisible-access
suppression to the candidate ports. This models the original test friend-module
access to internal RealSource/RealSink without making those classes public.
The separate public-only producer has no visibility escape.

The six extension bodies use actual Foundation SDK objects. Typed Kotlin
facades carry opaque SDK lease tokens; Swift calls NSData, InputStream,
OutputStream, RunLoop, Thread and recursive locks. Source/Sink stream IO and
state transitions stay Kotlin. Swift custom streams subclass the real SDK
InputStream/OutputStream and forward to Kotlin controllers. No in-memory fake
NSData or NSStream is supplied. A test-only Atomicfu facade forwards the
original test calls to existing real AtomicInt and SDK NSRecursiveLock; it is
not an Atomicfu verification claim.

AppleCore.kt is preserved byte for byte, including the pinned read(-1)
normalization to zero and subsequent EOF result. That code has an unreachable
negative-result IOException branch; the draft does not invent a behavior fix.
The extra SDK error fixture asserts the pinned clamp/EOF and no-tail-consumption
semantics, still awaiting an actual macOS candidate/reference oracle. Buffer
snapshots retain upstream traversal and bounds, but SDK copy initialization plus
a finally-free keeps a throwing Kotlin wrapper constructor from double-freeing
a transferred malloc buffer.

Required focused execution after review:

1. Fresh macOS swift build; SDK type checking is required, Swift parse is insufficient.
2. IOAppleAPIContractTests: one method/two source-library cases, exact six
   receiver/result/visibility/default signatures from real metadata and exact
   source OptIn class-literal arguments versus library SOURCE-retention absence.
3. RuntimeAppleFoundationTests: four methods/four cases, actual copied NSData,
   ARC release with the retained box owner, native/Kotlin byte synchronization,
   no-copy caller-owned storage/creation rollback and actual NSError cause identity.
4. IOAppleInteropExecutionTests: four methods/twelve cases. Both original
   compound driver and public-only contracts use source O0/O2, actual fresh
   stdlib .kklib O0/O2 and actual separate producer/consumer O0/O2. The original
   driver executes all 25 bodies in each of six lanes: 150 original executions.

All native runs require exit 0, empty stderr and exact expected stdout. The 50
BEGIN/PASS lines are driver guards derived from pinned IDs, not original raw
reference stdout. They are valid only when all unchanged assertions execute.
CommandRunner nonzero results are retained before rethrow. Its String API can
replace invalid UTF8 and exposes no PID/SID or original timeout output; receipts
state those limits. Outer runner records raw Swift streams, finite deadlines and
process session exits. Only successful UUID-owned artifacts are cleaned, after
full hashes and producer/stdlb unchanged checks; failures are retained.

This draft is not ready to mark KUU-1763 complete. Review/validation dependencies:

- The current runtime allocates normal class/closure objects as retained
  RuntimeObjectBox, not kk_alloc heap objects. SDK leases follow explicit
  runtimeReleaseObject; heap owners follow sweep. General boxed-object automatic
  GC is not implemented here. Timely automatic SDK reclamation or cross-GC/ARC
  cycle collection therefore remains an existing runtime dependency.
- No general ObjC importer, SDK inheritance importer or native protocol
  nominal mapping has been implemented. These are real object facades for the
  six APIs and the specific SDK surface needed by the 25 bodies. Arbitrary
  Objective-C ingress/subclass overrides, all Foundation APIs, and Kotlin
  external ARC-retained callback graphs are not proven by this patch.
- CFRunLoopRef uses a real CF pointer with opaque CPointer<*> source typing.
  Nominal __CFRunLoop pointee import remains a SDK importer gap; do not report
  full platform.CoreFoundation type fidelity.
- Original utilApple.kt retains captured local lateinit. KUU-1764 read checks/
  storage requirements are not hidden by rewriting that helper; original
  assignment-before-read needs the actual candidate gate, not a static claim
  that this helper necessarily fails.
- SDK Swift overrides, strict concurrency, real cinterop constructor/hierarchy,
  reified numeric conversion source/imported behavior, virtual dispatch and
  callback/throwing ABI must pass actual macOS gates. Pure parse/apply checks do
  not establish those behaviors.

Prepared but unexecuted additional contracts cover the pinned input -1/EOF
normalization with no tail consumption, output short write/zero capacity/error
and actual NSError cause identity. Additional mandatory probes before Ready: weak delegate
replacement/release; stopping/moving/unsubscribing run loops with queued blocks;
no-copy NSData freeWhenDone true;
nullable and primitive callback boxing; managed-heap SDK lease sweep and pending
creation rollback. These are residual coverage, not passed methods in this draft.

The 1727 full catalog, Apple-independent JVM45/interop work, other platform IO,
and general Foundation API coverage remain separate. No APIs are target-out.

Official numeric bridge annotations are pinned to the local Kotlin 2.3.10
Native sources zip: UnsafeNumber keeps its required actualPlatformTypes array,
TYPEALIAS/FUNCTION/PROPERTY targets, BINARY retention and ERROR opt-in level.
Primitive convert receivers keep reified R : Any and ExperimentalForeignApi;
Kotlin bodies replace the Native typed intrinsic, pending source/library gates.
The CI requires actual Darwin, macos-26 and the existing Swift 6.3 setup action;
no job has been dispatched and no SDK availability is inferred from YAML alone.

Apply sequence: refresh on the published combined IO5 scope (1729 V3 and the
1761 whitespace-only V6 pins), then review this Apple patch; keep the captured
local lateinit KUU-1764 prerequisite explicit. The saved initial author baseline
and the final readonly apply-check baseline differ only by parent work recorded
in the scratch receipt. This proposal does not rewrite any IO5 paths.

V2 failure lifecycle: Backend UUID work directories are created under the uploaded
KSWIFTK_IO1763_RECEIPT_DIRECTORY before staging or compiling. Compile exits,
diagnostics and generated bytes/hashes are written before assertion; failures
retain their sources/objects/producer/executable in the artifact path. Success
cleanup is still restricted to that created UUID after full immutable proof.
The outer runner always attempts inputs.after/products.after/partial counts and
terminal evidence in finally, including execute/count-parser failures. Its retained
artifact manifest lists actual paths, sizes and hashes; it excludes itself and the
mutable terminal record. No decoded CommandRunner text is relabeled as arbitrary
raw program bytes. SDK/product code and all assertion coverage are unchanged.

Recoverable execute exceptions also enter owned-session termination/reap before
propagating their original error. A live descendant after launcher exit remains
incomplete even if it is then terminated. PID1-owned zombies are listed separately
from live workers. Hard SIGKILL of this Python process or host loss cannot run
Python finally; such interrupted receipts remain incomplete and require external
process inspection. No receipt promises proof unavailable after host loss.
