import Dispatch
import Foundation

struct HeapObjectRecord {
    let pointer: UnsafeMutableRawPointer
    let byteCount: Int
}

struct ActiveFrameRecord {
    let functionID: UInt32
    let frameBase: UnsafeMutableRawPointer?
}

struct FrameMapDescriptorC {
    let rootCount: UInt32
    let rootOffsets: UnsafePointer<Int32>?
}

/// `typeToken` uniquely identifies a `KClass<T>` at runtime, so caching by it
/// alone ensures stable hits across repeated evaluations.
struct KClassCacheKey: Hashable {
    let typeToken: Int
}

/// A Java Class handle is canonical per Kotlin classifier, except for runtime
/// values whose JVM class depends on their concrete representation (arrays,
/// collection implementations, and generated function classes).
struct JavaClassCacheKey: Hashable {
    let typeToken: Int
    var runtimeClassName: String? = nil
    var functionIdentity: Int? = nil
    var enclosingClassName: String? = nil
}

/// Per-category count of GC roots discovered while seeding the mark worklist,
/// mapped onto `kotlin.native.runtime.RootSetStatistics`'s four pools:
/// `threadLocalReferences` counts rooted thread-local values,
/// `stackReferences` counts frame-map/coroutine roots, `globalReferences`
/// counts global root slots plus runtime-internal reflection roots, and
/// `stableReferences` counts StableRef / Pinned targets plus foreign-resource
/// lease roots and retained atomic-cell payloads (the "internal usages" bucket
/// of the upstream API).
struct RuntimeGCRootSetCounts {
    var threadLocalReferences: Int64 = 0
    var stackReferences: Int64 = 0
    var globalReferences: Int64 = 0
    var stableReferences: Int64 = 0
}

/// Statistics gathered by one mark-and-sweep pass over the managed heap.
struct RuntimeGCMarkSweepStats {
    var markedCount: Int64 = 0
    var sweptCount: Int64 = 0
    var keptCount: Int64 = 0
    var memoryUsageBeforeBytes: Int64 = 0
    var memoryUsageAfterBytes: Int64 = 0
    var rootSet = RuntimeGCRootSetCounts()
}

/// Immutable per-pass record backing `kotlin.native.runtime.GC.lastGCInfo`.
/// Written under gcLock once per `kk_gc_collect` pass; `postGcCleanupTimeNs`
/// is patched in afterwards under an epoch guard because retired-lease ARC
/// destruction deliberately runs outside gcLock. Optional `*TimeNs` fields
/// are nil only for collector phases this runtime does not have — it is a
/// single-pause collector, so the second-pause fields are always nil.
struct RuntimeGCInfoSnapshot {
    var epoch: Int64
    var startTimeNs: Int64
    var endTimeNs: Int64
    var firstPauseRequestTimeNs: Int64
    var firstPauseStartTimeNs: Int64
    var firstPauseEndTimeNs: Int64
    var secondPauseRequestTimeNs: Int64?
    var secondPauseStartTimeNs: Int64?
    var secondPauseEndTimeNs: Int64?
    var postGcCleanupTimeNs: Int64?
    var rootSet: RuntimeGCRootSetCounts
    var markedCount: Int64
    var sweptCount: Int64
    var keptCount: Int64
    var memoryUsageBeforeBytes: Int64
    var memoryUsageAfterBytes: Int64

    /// Field order is part of the Kotlin-facing ABI: `GC.kt`'s `__lastGCInfo`
    /// unpacks these indices into the GCInfo constructor. Absent optional
    /// timestamps serialize as `runtimeNullSentinelInt` (Int64.min).
    var serializedFieldValues: [Int] {
        func ns(_ value: Int64?) -> Int {
            guard let value else { return runtimeNullSentinelInt }
            return Int(clamping: value)
        }
        return [
            Int(clamping: epoch),
            Int(clamping: startTimeNs),
            Int(clamping: endTimeNs),
            Int(clamping: firstPauseRequestTimeNs),
            Int(clamping: firstPauseStartTimeNs),
            Int(clamping: firstPauseEndTimeNs),
            ns(secondPauseRequestTimeNs),
            ns(secondPauseStartTimeNs),
            ns(secondPauseEndTimeNs),
            ns(postGcCleanupTimeNs),
            Int(clamping: rootSet.threadLocalReferences),
            Int(clamping: rootSet.stackReferences),
            Int(clamping: rootSet.globalReferences),
            Int(clamping: rootSet.stableReferences),
            Int(clamping: markedCount),
            Int(clamping: sweptCount),
            Int(clamping: keptCount),
            Int(clamping: memoryUsageBeforeBytes),
            Int(clamping: memoryUsageAfterBytes),
        ]
    }
}

struct GCState {
    var heapObjects: [UInt: HeapObjectRecord] = [:]
    var nextForeignResourceToken: Int = 1
    var foreignResources: [Int: RuntimeForeignResourceLease] = [:]
    var retiredForeignResources: [RuntimeForeignResourceLease] = []
    var objectPointers = RuntimePointerSet()
    /// Existing retained reference cells are external owners, not swept boxes.
    /// Trace their direct kk_alloc payloads until replacement or owner release.
    var retainedAtomicReferenceHandles: Set<UInt> = []
    /// Borrowed pointers in `objectPointers` whose lifetime is owned by a
    /// singleton or a dedicated runtime registry rather than passRetained.
    var borrowedObjectPointers: Set<UInt> = []
    /// Canonical boxed Unit pointer, retained in `objectPointers` across GC resets.
    var unitBoxPointer: UInt? = nil
    var globalRootSlots: Set<UInt> = []
    var frameMaps: [UInt32: [Int32]] = [:]
    var activeFrames: [ActiveFrameRecord] = []
    var coroutineRoots: Set<UInt> = []
    /// Per-target refcount for `kotlin.native.ref.Pinned<T>` (kk_pin_object/
    /// kk_unpin_object). Every pin call returns an independent `RuntimePinnedBox`
    /// handle, so the same target may be pinned by several handles at once;
    /// the GC root must survive until the last handle unpins. A plain
    /// membership set would let one handle's unpin drop the root while a
    /// sibling pin is still held, leaving it dangling into freed memory.
    var pinnedObjectCounts: [UInt: Int] = [:]
    /// Per-target refcount for `kotlinx.cinterop.StableRef` (kk_stable_ref_create/
    /// _dispose). The same target object may be wrapped by several
    /// independent StableRef handles at once — see kk_stable_ref_create.
    var stableRefCounts: [UInt: Int] = [:]
    /// Kotlin/JVM reference-identity cache for `kk_box_*` primitive boxing:
    /// Boolean (both values), Char (0..127), and Int/Long/Short/Byte
    /// (-128..127) boxes share one canonical object per value, so `===` on
    /// two independently boxed values matches the JVM. Keys are
    /// `(primitiveTypeBase << 32) | payloadBits`; values are tagged handles.
    /// Unsigned kinds and Float/Double are deliberately absent — JVM does
    /// not cache them.
    var identityPrimitiveBoxCache: [Int64: Int] = [:]
    /// Tagged handles minted through `identityPrimitiveBoxCache`. A shared
    /// cache box must never be nominal-type tagged in place, so
    /// `kk_tag_value_class_box` consults this set and clones instead.
    var identityPrimitiveBoxHandles: Set<UInt> = []
    /// Canonical Any-erased box handle per enum entry, keyed by enum class ID
    /// and ordinal. Kotlin/JVM enum entries are singletons, so boxing the
    /// same entry twice must return one object for `===` to observe reference
    /// identity (KUU-2957). Handles are also registered in
    /// `identityPrimitiveBoxHandles` so value-class tagging clones the shared
    /// box instead of mutating it in place.
    var enumIdentityBoxCache: [RuntimeEnumBoxCacheKey: Int] = [:]
    /// Monotonic counter of completed GC passes, surfaced as `GCInfo.epoch`.
    /// The first recorded pass reports epoch 1.
    var gcEpoch: Int64 = 0
    /// Statistics of the most recently completed GC pass (`GC.lastGCInfo`).
    var lastGCInfo: RuntimeGCInfoSnapshot? = nil
}

struct MetadataState {
    var kClassBoxCache: [KClassCacheKey: Int] = [:]
    var javaClassCache: [JavaClassCacheKey: Int] = [:]
    var primitiveJavaClassCache: [Int: Int] = [:]
    var delegatedPropertyStubCache: [String: Int] = [:]
    var kTypeProjectionStarRaw: Int?
    var kTypeParameterCache: [Int: Int] = [:]
    var enumEntriesCache: [Int64: Int] = [:]
    var enumValuesByTypeToken: [Int64: [RuntimeEnumValueDescriptor]] = [:]
    // Enum Class handles outlive the boxed entry used to obtain javaClass.
    var enumClassifierIDs: Set<Int64> = []
    var objectTypeByPointer: [UInt: Int64] = [:]
    var arrayTypeIDsByPointer: [UInt: Set<Int64>] = [:]
    var typeParents: [Int64: Set<Int64>] = [:]
    /// Set once the static reflection hierarchy edges are in `typeParents`;
    /// cleared with `typeParents` so a metadata reset re-registers them.
    var reflectionTypeEdgesRegistered = false
    var primitiveTypeEdgesRegistered = false
    var rangeTypeEdgesRegistered = false
    var jobFamilyTypeEdgesRegistered = false
    var coroutineDispatcherTypeEdgesRegistered = false
    var sortedCollectionTypeEdgesRegistered = false
    var mapEntryTypeEdgesRegistered = false
    var cinteropTypeEdgesRegistered = false
    var dataClassIDs: Set<Int64> = []
    /// Bitmask of object slot indices holding primary-constructor properties, per data class.
    /// Absent entries mean "every stored slot participates" (legacy registration).
    var dataClassFieldMasks: [Int64: Int64] = [:]
    var objectVtableMethods: [UInt: [Int: Int]] = [:]
    var objectEqualsOverrides: [UInt: Int] = [:]
    var objectHashCodeOverrides: [UInt: Int] = [:]
    var objectAnyToStringMethods: [UInt: Int] = [:]
    var nominalAnyToStringMethods: [Int64: Int] = [:]
    var objectItableMethods: [UInt: [UInt64: Int]] = [:]
    var objectInterfaceSlots: [UInt: [Int64: Int]] = [:]
}

struct FlowState {
    var flowHandles: [UInt: AnyObject] = [:]
    var flowRetainCounts: [UInt: Int] = [:]
}

struct ThreadLocalState {
    var threadLocalBoxes: Set<UInt> = []
    var threadLocalValues: [UInt: [ObjectIdentifier: Int]] = [:]
}

struct DelegateState {
    var callableRefMetadataByValue: [Int: RuntimeCallableRefMetadata] = [:]
    var samAdapterIdentityByValue: [Int: RuntimeSamAdapterIdentity] = [:]
    var functionArityByPointer: [Int: Int] = [:]
    var functionDescriptionsByValue: [Int: String] = [:]
    var functionEnclosingClassNamesByPointer: [Int: String] = [:]
}

/// Non-reentrant mutual-exclusion lock for the runtime's global state tables.
///
/// `NSLock` dispatches `lock`/`unlock` through `objc_msgSend` on Darwin, which
/// showed up as `objc_msgSend$unlock` next to `pthread_mutex_unlock` in the
/// hot path profile (KUU-3018). `os_unfair_lock` is acquired and released with
/// a single atomic operation when uncontended and needs no ObjC dispatch. The
/// storage is heap-allocated once because the lock must never move.
final class RuntimeFastLock: @unchecked Sendable {
    #if canImport(Darwin)
        private let storage: UnsafeMutablePointer<os_unfair_lock>

        init() {
            storage = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
            storage.initialize(to: os_unfair_lock())
        }

        deinit {
            storage.deallocate()
        }

        @inline(__always)
        func lock() {
            os_unfair_lock_lock(storage)
        }

        @inline(__always)
        func unlock() {
            os_unfair_lock_unlock(storage)
        }
    #else
        private let storage: UnsafeMutablePointer<pthread_mutex_t>

        init() {
            storage = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
            storage.initialize(to: pthread_mutex_t())
            pthread_mutex_init(storage, nil)
        }

        deinit {
            pthread_mutex_destroy(storage)
            storage.deallocate()
        }

        @inline(__always)
        func lock() {
            pthread_mutex_lock(storage)
        }

        @inline(__always)
        func unlock() {
            pthread_mutex_unlock(storage)
        }
    #endif
}

final class RuntimeStorageBox: @unchecked Sendable {
    private let gcLock = RuntimeFastLock()
    private let metadataLock = RuntimeFastLock()
    private let flowLock = RuntimeFastLock()
    private let threadLocalLock = RuntimeFastLock()
    private let delegateLock = RuntimeFastLock()
    private let delegatedPropertyStubLock = NSLock()

    // Each state table is guarded by its lock above and lives behind a stable
    // heap pointer. Reaching a table through a class stored property would make
    // every `body(&state)` call pay `swift_beginAccess`/`swift_endAccess`
    // (dynamic exclusivity enforcement); the lock already provides the
    // exclusivity, so the pointer indirection removes that overhead (KUU-3018).
    private let gcState = RuntimeStorageBox.makeState(GCState())
    private let metadataState = RuntimeStorageBox.makeState(MetadataState())
    private let flowState = RuntimeStorageBox.makeState(FlowState())
    private let threadLocalState = RuntimeStorageBox.makeState(ThreadLocalState())
    private let delegateState = RuntimeStorageBox.makeState(DelegateState())

    private static func makeState<State>(_ initial: State) -> UnsafeMutablePointer<State> {
        let pointer = UnsafeMutablePointer<State>.allocate(capacity: 1)
        pointer.initialize(to: initial)
        return pointer
    }

    let coroutineSuspendedBox = RuntimeStringBox("COROUTINE_SUSPENDED")
    let flowStopSentinelBox = RuntimeStringBox("FLOW_STOP_SENTINEL")
    /// Sentinel returned via callerState.resume(with:) when a lazy sequence
    /// coroutine reaches the end of the builder lambda.  Callers compare the
    /// resumed value against kk_sequence_completed_sentinel() to distinguish
    /// "done" from a real element.
    let sequenceCompletedBox = RuntimeStringBox("SEQUENCE_COMPLETED")

    @discardableResult
    @inline(__always)
    func withGCLock<R>(_ body: (inout GCState) -> R) -> R {
        gcLock.lock()
        defer { gcLock.unlock() }
        return body(&gcState.pointee)
    }

    @discardableResult
    @inline(__always)
    func withMetadataLock<R>(_ body: (inout MetadataState) -> R) -> R {
        metadataLock.lock()
        defer { metadataLock.unlock() }
        return body(&metadataState.pointee)
    }

    @discardableResult
    @inline(__always)
    func withFlowLock<R>(_ body: (inout FlowState) -> R) -> R {
        flowLock.lock()
        defer { flowLock.unlock() }
        return body(&flowState.pointee)
    }

    @discardableResult
    @inline(__always)
    func withFlowAndGCLocks<R>(_ body: (inout FlowState, inout GCState) -> R) -> R {
        flowLock.lock()
        gcLock.lock()
        defer {
            gcLock.unlock()
            flowLock.unlock()
        }
        return body(&flowState.pointee, &gcState.pointee)
    }

    @discardableResult
    @inline(__always)
    func withThreadLocalLock<R>(_ body: (inout ThreadLocalState) -> R) -> R {
        threadLocalLock.lock()
        defer { threadLocalLock.unlock() }
        return body(&threadLocalState.pointee)
    }

    @discardableResult
    @inline(__always)
    func withDelegateLock<R>(_ body: (inout DelegateState) -> R) -> R {
        delegateLock.lock()
        defer { delegateLock.unlock() }
        return body(&delegateState.pointee)
    }

    @discardableResult
    @inline(__always)
    func withDelegatedPropertyStubLock<R>(_ body: () -> R) -> R {
        delegatedPropertyStubLock.lock()
        defer { delegatedPropertyStubLock.unlock() }
        return body()
    }
}

let runtimeStorage = RuntimeStorageBox()

let kkObjMarkFlag: UInt32 = 1 << 0

private let runtimeGCDefaultTargetHeapBytes = 100 * 1024 * 1024

// KSP-1263 defaults: this runtime processes finalizers synchronously during
// `kk_gc_collect` rather than dispatching batches to the main thread, so
// these knobs are tunable state without an independent scheduler backing them.
private let runtimeGCDefaultMainThreadFinalizerBatchSize = 100
private let runtimeGCDefaultMainThreadFinalizerMaxTimeInTaskNs = 10_000_000 // 10ms
private let runtimeGCDefaultMainThreadFinalizerMinTimeBetweenTasksNs = 0

private final class RuntimeGCTuningState: @unchecked Sendable {
    private let lock = NSLock()
    private var targetHeapBytes = runtimeGCDefaultTargetHeapBytes
    private var targetHeapUtilization = 0.5
    private var maxHeapBytes = max(
        runtimeGCDefaultTargetHeapBytes,
        Int(clamping: ProcessInfo.processInfo.physicalMemory)
    )
    private var mainThreadFinalizerProcessorBatchSize = runtimeGCDefaultMainThreadFinalizerBatchSize
    private var mainThreadFinalizerProcessorMaxTimeInTaskNs = runtimeGCDefaultMainThreadFinalizerMaxTimeInTaskNs
    private var mainThreadFinalizerProcessorMinTimeBetweenTasksNs = runtimeGCDefaultMainThreadFinalizerMinTimeBetweenTasksNs

    func currentTargetHeapBytes() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return targetHeapBytes
    }

    func setTargetHeapBytes(_ value: Int) {
        lock.lock()
        defer { lock.unlock() }
        targetHeapBytes = value
    }

    func currentTargetHeapUtilization() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return targetHeapUtilization
    }

    func setTargetHeapUtilization(_ value: Double) {
        lock.lock()
        defer { lock.unlock() }
        targetHeapUtilization = value
    }

    func currentMaxHeapBytes() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return maxHeapBytes
    }

    func setMaxHeapBytes(_ value: Int) {
        lock.lock()
        defer { lock.unlock() }
        maxHeapBytes = value
    }

    /// Called by `.runtimeIsolation(.gcOnly)` test resets so a test that mutates a
    /// knob cannot leak state into an unrelated test running later in the same
    /// process.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        targetHeapBytes = runtimeGCDefaultTargetHeapBytes
        targetHeapUtilization = 0.5
        maxHeapBytes = max(
            runtimeGCDefaultTargetHeapBytes,
            Int(clamping: ProcessInfo.processInfo.physicalMemory)
        )
    }

    func currentMainThreadFinalizerProcessorBatchSize() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return mainThreadFinalizerProcessorBatchSize
    }

    func setMainThreadFinalizerProcessorBatchSize(_ value: Int) {
        lock.lock()
        defer { lock.unlock() }
        mainThreadFinalizerProcessorBatchSize = value
    }

    func currentMainThreadFinalizerProcessorMaxTimeInTaskNs() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return mainThreadFinalizerProcessorMaxTimeInTaskNs
    }

    func setMainThreadFinalizerProcessorMaxTimeInTaskNs(_ value: Int) {
        lock.lock()
        defer { lock.unlock() }
        mainThreadFinalizerProcessorMaxTimeInTaskNs = value
    }

    func currentMainThreadFinalizerProcessorMinTimeBetweenTasksNs() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return mainThreadFinalizerProcessorMinTimeBetweenTasksNs
    }

    func setMainThreadFinalizerProcessorMinTimeBetweenTasksNs(_ value: Int) {
        lock.lock()
        defer { lock.unlock() }
        mainThreadFinalizerProcessorMinTimeBetweenTasksNs = value
    }
}

private let runtimeGCTuningState = RuntimeGCTuningState()

@_cdecl("kk_alloc")
public func kk_alloc(_ size: UInt32, _ typeInfo: UnsafeRawPointer) -> UnsafeMutableRawPointer {
    let headerSize = MemoryLayout<KKObjHeader>.stride
    let alignment = max(MemoryLayout<KKObjHeader>.alignment, MemoryLayout<UInt64>.alignment)
    let allocationSize = max(Int(size), headerSize)
    let ptr = UnsafeMutableRawPointer.allocate(byteCount: allocationSize, alignment: alignment)
    ptr.initializeMemory(as: UInt8.self, repeating: 0, count: allocationSize)
    let typedInfo = typeInfo.assumingMemoryBound(to: KTypeInfo.self)
    ptr.assumingMemoryBound(to: KKObjHeader.self).pointee = KKObjHeader(
        typeInfo: typedInfo,
        flags: 0,
        size: UInt32(allocationSize)
    )
    runtimeStorage.withGCLock { state in
        state.heapObjects[UInt(bitPattern: ptr)] = HeapObjectRecord(
            pointer: ptr,
            byteCount: allocationSize
        )
    }
    return ptr
}

// `_ gcRaw: Int = 0` carries the `GC` object receiver that bundled-source member
// `external fun`/property-accessor calls pass across the ABI (see Platform.kt's
// identical bridge functions). The default keeps every pre-existing zero-argument
// Swift call site (tests, `RuntimeMemory.swift`) source-compatible: Swift call
// sites fill the default at compile time, while compiled Kotlin always supplies it.
@inline(__always)
private func runtimeGCNowNanos() -> Int64 {
    Int64(clamping: DispatchTime.now().uptimeNanoseconds)
}

@_cdecl("kk_gc_collect")
public func kk_gc_collect(_ gcRaw: Int = 0) {
    _ = gcRaw
    // This collector is a single synchronous stop-the-world pass: gcLock
    // acquisition is the "pause request", the locked mark+sweep is the pause,
    // and the ARC destruction of retired leases is the post-GC cleanup.
    let startTimeNs = runtimeGCNowNanos()
    let threadLocalRoots = runtimeStorage.withThreadLocalLock { state in
        state.threadLocalValues
    }
    let callableRoots = runtimeCallableReflectionRoots()
    let firstPauseRequestTimeNs = runtimeGCNowNanos()
    var passEpoch: Int64 = 0
    let retired = runtimeStorage.withGCLock { state -> [RuntimeForeignResourceLease] in
        let firstPauseStartTimeNs = runtimeGCNowNanos()
        let stats = performMarkAndSweepLocked(
            state: &state,
            threadLocalValues: threadLocalRoots,
            callableRoots: callableRoots
        )
        let firstPauseEndTimeNs = runtimeGCNowNanos()
        let retired = state.retiredForeignResources
        state.retiredForeignResources.removeAll()
        let endTimeNs = runtimeGCNowNanos()
        state.gcEpoch += 1
        passEpoch = state.gcEpoch
        state.lastGCInfo = RuntimeGCInfoSnapshot(
            epoch: passEpoch,
            startTimeNs: startTimeNs,
            endTimeNs: endTimeNs,
            firstPauseRequestTimeNs: firstPauseRequestTimeNs,
            firstPauseStartTimeNs: firstPauseStartTimeNs,
            firstPauseEndTimeNs: firstPauseEndTimeNs,
            secondPauseRequestTimeNs: nil,
            secondPauseStartTimeNs: nil,
            secondPauseEndTimeNs: nil,
            postGcCleanupTimeNs: nil,
            rootSet: stats.rootSet,
            markedCount: stats.markedCount,
            sweptCount: stats.sweptCount,
            keptCount: stats.keptCount,
            memoryUsageBeforeBytes: stats.memoryUsageBeforeBytes,
            memoryUsageAfterBytes: stats.memoryUsageAfterBytes
        )
        return retired
    }
    withExtendedLifetime(retired) {} // ARC destruction outside gcLock.
    let postGcCleanupTimeNs = runtimeGCNowNanos()
    runtimeStorage.withGCLock { state in
        // A newer pass may have already published its own snapshot; only patch
        // in the cleanup timestamp while this pass is still the latest one.
        guard state.lastGCInfo?.epoch == passEpoch else {
            return
        }
        state.lastGCInfo?.postGcCleanupTimeNs = postGcCleanupTimeNs
    }
}

@_cdecl("kk_gc_schedule")
public func kk_gc_schedule(_ gcRaw: Int = 0) -> Int {
    _ = gcRaw
    kk_gc_collect()
    return 0
}

/// Hands the recorded `RuntimeGCInfoSnapshot` to Kotlin as a flat `List<Long>`
/// (see `serializedFieldValues` for the index layout). Returns
/// `runtimeNullSentinelInt` while no GC pass has completed. The snapshot
/// struct is copied under gcLock, so the returned list is an immutable
/// per-pass view even if a concurrent collection lands mid-read.
@_cdecl("kk_gc_last_gc_info")
public func kk_gc_last_gc_info(_ gcRaw: Int = 0) -> Int {
    _ = gcRaw
    guard let snapshot = runtimeStorage.withGCLock({ $0.lastGCInfo }) else {
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(RuntimeListBox(elements: snapshot.serializedFieldValues))
}

@_cdecl("kk_gc_target_heap_bytes")
public func kk_gc_target_heap_bytes(_ gcRaw: Int = 0) -> Int {
    _ = gcRaw
    return runtimeGCTuningState.currentTargetHeapBytes()
}

@_cdecl("kk_gc_target_heap_bytes_set")
public func kk_gc_target_heap_bytes_set(_ gcRaw: Int, _ value: Int) -> Int {
    _ = gcRaw
    runtimeGCTuningState.setTargetHeapBytes(value)
    return 0
}

// `kk_gc_target_heap_utilization` used to return a genuine Swift `Double`, but
// every external-fun call this compiler emits passes Double/Float as their raw
// IEEE bit pattern packed into an `Int` (there is no floating-point LLVM type in
// the backend at all - see e.g. `__kk_math_sqrt`). Once this property became a
// real bundled-source declaration instead of a synthetic sema stub, a genuine
// `Double` return would read back as a garbage register value. Fixed here to use
// the same bit-pattern convention as every other Double-typed external fun.
@_cdecl("kk_gc_target_heap_utilization")
public func kk_gc_target_heap_utilization(_ gcRaw: Int = 0) -> Int {
    _ = gcRaw
    return kk_double_to_bits(runtimeGCTuningState.currentTargetHeapUtilization())
}

@_cdecl("kk_gc_target_heap_utilization_set")
public func kk_gc_target_heap_utilization_set(_ gcRaw: Int, _ value: Int) -> Int {
    _ = gcRaw
    runtimeGCTuningState.setTargetHeapUtilization(kk_bits_to_double(value))
    return 0
}

@_cdecl("kk_gc_max_heap_bytes")
public func kk_gc_max_heap_bytes(_ gcRaw: Int = 0) -> Int {
    _ = gcRaw
    return runtimeGCTuningState.currentMaxHeapBytes()
}

@_cdecl("kk_gc_max_heap_bytes_set")
public func kk_gc_max_heap_bytes_set(_ gcRaw: Int, _ value: Int) -> Int {
    _ = gcRaw
    runtimeGCTuningState.setMaxHeapBytes(value)
    return 0
}

// This target always processes finalizers, so `available` is unconditionally
// true; the remaining members are plain tunable state (see the state comment
// above `RuntimeGCTuningState`).
@_cdecl("kk_gc_main_thread_finalizer_processor_available")
public func kk_gc_main_thread_finalizer_processor_available(_ receiverRaw: Int) -> Int {
    _ = receiverRaw
    return 1
}

@_cdecl("kk_gc_main_thread_finalizer_processor_batch_size_load")
public func kk_gc_main_thread_finalizer_processor_batch_size_load(_ receiverRaw: Int) -> Int {
    _ = receiverRaw
    return runtimeGCTuningState.currentMainThreadFinalizerProcessorBatchSize()
}

@_cdecl("kk_gc_main_thread_finalizer_processor_batch_size_store")
public func kk_gc_main_thread_finalizer_processor_batch_size_store(_ receiverRaw: Int, _ value: Int) -> Int {
    _ = receiverRaw
    runtimeGCTuningState.setMainThreadFinalizerProcessorBatchSize(value)
    return 0
}

@_cdecl("kk_gc_main_thread_finalizer_processor_max_time_in_task_load")
public func kk_gc_main_thread_finalizer_processor_max_time_in_task_load(_ receiverRaw: Int) -> Int {
    _ = receiverRaw
    return runtimeGCTuningState.currentMainThreadFinalizerProcessorMaxTimeInTaskNs()
}

@_cdecl("kk_gc_main_thread_finalizer_processor_max_time_in_task_store")
public func kk_gc_main_thread_finalizer_processor_max_time_in_task_store(_ receiverRaw: Int, _ value: Int) -> Int {
    _ = receiverRaw
    runtimeGCTuningState.setMainThreadFinalizerProcessorMaxTimeInTaskNs(value)
    return 0
}

@_cdecl("kk_gc_main_thread_finalizer_processor_min_time_between_tasks_load")
public func kk_gc_main_thread_finalizer_processor_min_time_between_tasks_load(_ receiverRaw: Int) -> Int {
    _ = receiverRaw
    return runtimeGCTuningState.currentMainThreadFinalizerProcessorMinTimeBetweenTasksNs()
}

@_cdecl("kk_gc_main_thread_finalizer_processor_min_time_between_tasks_store")
public func kk_gc_main_thread_finalizer_processor_min_time_between_tasks_store(_ receiverRaw: Int, _ value: Int) -> Int {
    _ = receiverRaw
    runtimeGCTuningState.setMainThreadFinalizerProcessorMinTimeBetweenTasksNs(value)
    return 0
}

// These Swift helpers remain available to Runtime tests. Restore their C exports
// only when the Kotlin compiler has a global-root emission path.
public func kk_register_global_root(_ slot: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) {
    guard let slot else {
        return
    }
    runtimeStorage.withGCLock { state in
        state.globalRootSlots.insert(UInt(bitPattern: slot))
    }
}

public func kk_unregister_global_root(_ slot: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) {
    guard let slot else {
        return
    }
    runtimeStorage.withGCLock { state in
        state.globalRootSlots.remove(UInt(bitPattern: slot))
    }
}

// DEAD-CDECL-TEST-HOOK: GC-FRAME - Runtime tests register synthetic stack maps.
@_cdecl("kk_register_frame_map")
public func kk_register_frame_map(_ functionID: UInt32, _ mapPtr: UnsafeRawPointer?) {
    runtimeStorage.withGCLock { state in
        guard let mapPtr else {
            state.frameMaps.removeValue(forKey: functionID)
            return
        }
        let descriptor = mapPtr.assumingMemoryBound(to: FrameMapDescriptorC.self).pointee
        let count = Int(descriptor.rootCount)
        guard count > 0, let offsetsPtr = descriptor.rootOffsets else {
            state.frameMaps[functionID] = []
            return
        }
        let offsets = Array(UnsafeBufferPointer(start: offsetsPtr, count: count))
        state.frameMaps[functionID] = offsets
    }
}

// DEAD-CDECL-TEST-HOOK: GC-FRAME - Runtime tests exercise frame registration and scanning.
@_cdecl("kk_push_frame")
public func kk_push_frame(_ functionID: UInt32, _ frameBase: UnsafeMutableRawPointer?) {
    runtimeStorage.withGCLock { state in
        state.activeFrames.append(ActiveFrameRecord(functionID: functionID, frameBase: frameBase))
    }
}

// DEAD-CDECL-TEST-HOOK: GC-FRAME - Runtime tests balance synthetic frames.
@_cdecl("kk_pop_frame")
public func kk_pop_frame() {
    runtimeStorage.withGCLock { state in
        if !state.activeFrames.isEmpty {
            _ = state.activeFrames.removeLast()
        }
    }
}

@_cdecl("kk_register_coroutine_root")
public func kk_register_coroutine_root(_ value: UnsafeMutableRawPointer?) {
    guard let value else {
        return
    }
    runtimeStorage.withGCLock { state in
        state.coroutineRoots.insert(UInt(bitPattern: value))
    }
}

@_cdecl("kk_unregister_coroutine_root")
public func kk_unregister_coroutine_root(_ value: UnsafeMutableRawPointer?) {
    guard let value else {
        return
    }
    runtimeStorage.withGCLock { state in
        state.coroutineRoots.remove(UInt(bitPattern: value))
    }
}

// DEAD-CDECL-TEST-HOOK: GC-METRICS - Runtime tests assert managed heap object counts.
@_cdecl("kk_runtime_heap_object_count")
public func kk_runtime_heap_object_count() -> UInt32 {
    runtimeStorage.withGCLock { state in
        UInt32(state.heapObjects.count)
    }
}

// DEAD-CDECL-TEST-HOOK: RUNTIME-RESET - Runtime tests isolate process-global runtime state.
@_cdecl("kk_runtime_force_reset")
public func kk_runtime_force_reset() {
    kk_runtime_reset_gc()
    kk_runtime_reset_metadata()
    kk_runtime_reset_flow()
    kk_runtime_reset_thread_local()
    kk_runtime_reset_delegate()
    runtimeResetDebugState()
}

/// `objectPointers` is deliberately preserved: every entry is a box the runtime
/// still holds a `passRetained` reference to, so dropping the entry reclaims
/// nothing and only makes a live handle unresolvable. Test isolation resets run
/// while other suites of the same process still own such handles, and an
/// unresolvable live handle surfaces as a KSWIFTK-RUNTIME-0001 invalid-handle
/// panic (invalid range/array/string handle). Entries are removed by whoever
/// releases the box.
func kk_runtime_reset_gc() {
    runtimeResetAtomicfuParkingCaches()
    let retired = runtimeStorage.withGCLock { state -> [RuntimeForeignResourceLease] in
        var retired = state.retiredForeignResources
        state.retiredForeignResources.removeAll()
        for token in Array(state.foreignResources.keys) {
            if state.foreignResources[token]?.owner != nil,
               let lease = state.foreignResources.removeValue(forKey: token) { retired.append(lease) }
        }
        for (_, object) in state.heapObjects {
            object.pointer.deallocate()
        }
        state.heapObjects.removeAll(keepingCapacity: false)
        state.globalRootSlots.removeAll(keepingCapacity: false)
        state.frameMaps.removeAll(keepingCapacity: false)
        state.activeFrames.removeAll(keepingCapacity: false)
        state.coroutineRoots.removeAll(keepingCapacity: false)
        state.pinnedObjectCounts.removeAll(keepingCapacity: false)
        state.stableRefCounts.removeAll(keepingCapacity: false)
        state.gcEpoch = 0
        state.lastGCInfo = nil
        return retired
    }
    withExtendedLifetime(retired) {}
    runtimeGCTuningState.reset()
    resetCaseInsensitiveOrderCache()
}

func kk_runtime_reset_metadata() {
    let cachedReflectionBoxes = runtimeStorage.withDelegatedPropertyStubLock {
        runtimeStorage.withMetadataLock { state -> [UnsafeMutableRawPointer] in
            var boxes = state.kClassBoxCache.values.compactMap(UnsafeMutableRawPointer.init(bitPattern:))
            boxes += state.javaClassCache.values.compactMap(UnsafeMutableRawPointer.init(bitPattern:))
            boxes += state.primitiveJavaClassCache.values.compactMap(UnsafeMutableRawPointer.init(bitPattern:))
            boxes += state.delegatedPropertyStubCache.values.compactMap(UnsafeMutableRawPointer.init(bitPattern:))
            if let starRaw = state.kTypeProjectionStarRaw,
               let pointer = UnsafeMutableRawPointer(bitPattern: starRaw) {
                boxes.append(pointer)
            }
            boxes += state.kTypeParameterCache.values.compactMap(UnsafeMutableRawPointer.init(bitPattern:))
            state.kClassBoxCache.removeAll(keepingCapacity: false)
            state.javaClassCache.removeAll(keepingCapacity: false)
            state.primitiveJavaClassCache.removeAll(keepingCapacity: false)
            state.delegatedPropertyStubCache.removeAll(keepingCapacity: false)
            state.kTypeProjectionStarRaw = nil
            state.kTypeParameterCache.removeAll(keepingCapacity: false)
            state.objectTypeByPointer.removeAll(keepingCapacity: false)
            state.arrayTypeIDsByPointer.removeAll(keepingCapacity: false)
            state.typeParents.removeAll(keepingCapacity: false)
            state.reflectionTypeEdgesRegistered = false
            state.primitiveTypeEdgesRegistered = false
            state.rangeTypeEdgesRegistered = false
            state.jobFamilyTypeEdgesRegistered = false
            state.coroutineDispatcherTypeEdgesRegistered = false
            state.sortedCollectionTypeEdgesRegistered = false
            state.mapEntryTypeEdgesRegistered = false
            state.cinteropTypeEdgesRegistered = false
            state.dataClassIDs.removeAll(keepingCapacity: false)
            state.dataClassFieldMasks.removeAll(keepingCapacity: false)
            state.objectVtableMethods.removeAll(keepingCapacity: false)
            state.objectEqualsOverrides.removeAll(keepingCapacity: false)
            state.objectHashCodeOverrides.removeAll(keepingCapacity: false)
            state.objectAnyToStringMethods.removeAll(keepingCapacity: false)
            state.nominalAnyToStringMethods.removeAll(keepingCapacity: false)
            state.objectItableMethods.removeAll(keepingCapacity: false)
            state.objectInterfaceSlots.removeAll(keepingCapacity: false)
            return boxes
        }
    }
    releaseRegisteredRuntimeBoxes(cachedReflectionBoxes)
    runtimeKClassMetadataRegistry.reset()
    runtimeKClassObjectRegistry.reset()
    runtimeKConstructorRegistry.reset()
    runtimeKMemberRegistry.reset()
    runtimeJavaMethodRegistry.reset()
    runtimeJavaFieldRegistry.reset()
    runtimeKCompanionRegistry.reset()
    runtimeKNestedClassRegistry.reset()
}

func removeRuntimeObjectMetadata(forObjectKey key: UInt) {
    runtimeStorage.withMetadataLock { state in
        state.kClassBoxCache = state.kClassBoxCache.filter { _, raw in
            UInt(bitPattern: raw) != key
        }
        state.javaClassCache = state.javaClassCache.filter { _, raw in
            UInt(bitPattern: raw) != key
        }
        state.primitiveJavaClassCache = state.primitiveJavaClassCache.filter { _, raw in
            UInt(bitPattern: raw) != key
        }
        if state.kTypeProjectionStarRaw == Int(bitPattern: key) {
            state.kTypeProjectionStarRaw = nil
        }
        state.kTypeParameterCache = state.kTypeParameterCache.filter { _, raw in
            UInt(bitPattern: raw) != key
        }
        state.objectTypeByPointer.removeValue(forKey: key)
        state.arrayTypeIDsByPointer.removeValue(forKey: key)
        state.objectVtableMethods.removeValue(forKey: key)
        state.objectEqualsOverrides.removeValue(forKey: key)
        state.objectHashCodeOverrides.removeValue(forKey: key)
        state.objectAnyToStringMethods.removeValue(forKey: key)
        state.objectItableMethods.removeValue(forKey: key)
        state.objectInterfaceSlots.removeValue(forKey: key)
    }
    runtimeStorage.withDelegateLock { state in
        state.functionDescriptionsByValue.removeValue(forKey: Int(bitPattern: key))
    }
}

func kk_runtime_reset_flow() {
    let flowKeys = runtimeStorage.withFlowLock { state -> [UInt] in
        let keys = Array(state.flowHandles.keys)
        state.flowHandles.removeAll(keepingCapacity: false)
        state.flowRetainCounts.removeAll(keepingCapacity: false)
        return keys
    }
    runtimeStorage.withGCLock { state in
        for key in flowKeys {
            state.objectPointers.remove(key)
            state.borrowedObjectPointers.remove(key)
        }
    }
}

func kk_runtime_reset_thread_local() {
    let boxes = runtimeStorage.withThreadLocalLock { state -> [UnsafeMutableRawPointer] in
        let boxes = state.threadLocalBoxes.compactMap(UnsafeMutableRawPointer.init(bitPattern:))
        state.threadLocalBoxes.removeAll(keepingCapacity: false)
        state.threadLocalValues.removeAll(keepingCapacity: false)
        return boxes
    }
    releaseRegisteredRuntimeBoxes(boxes)
}

/// Release boxes registered in `objectPointers`, dropping their registration
/// first so no handle can resolve to the freed memory.
private func releaseRegisteredRuntimeBoxes(_ pointers: [UnsafeMutableRawPointer]) {
    guard !pointers.isEmpty else {
        return
    }
    runtimeStorage.withGCLock { state in
        for pointer in pointers {
            let key = UInt(bitPattern: pointer)
            state.objectPointers.remove(key)
            state.retainedAtomicReferenceHandles.remove(key)
        }
    }
    for pointer in pointers {
        // Primitive box handles registered under tagged bits need the base
        // object pointer for ARC release.
        let base = runtimePrimitiveBoxBasePointer(from: Int(bitPattern: pointer)) ?? pointer
        Unmanaged<AnyObject>.fromOpaque(base).release()
    }
}

func kk_runtime_reset_delegate() {
    runtimeStorage.withDelegateLock { state in
        state.callableRefMetadataByValue.removeAll(keepingCapacity: false)
        state.samAdapterIdentityByValue.removeAll(keepingCapacity: false)
        state.functionArityByPointer.removeAll(keepingCapacity: false)
        state.functionDescriptionsByValue.removeAll(keepingCapacity: false)
        state.functionEnclosingClassNamesByPointer.removeAll(keepingCapacity: false)
    }
}

@discardableResult
func performMarkAndSweepLocked(state: inout GCState, threadLocalValues: [UInt: [ObjectIdentifier: Int]] = [:], callableRoots: [Int] = []) -> RuntimeGCMarkSweepStats {
    var stats = RuntimeGCMarkSweepStats()
    stats.memoryUsageBeforeBytes = state.heapObjects.values.reduce(Int64(0)) { $0 &+ Int64($1.byteCount) }
    guard !state.heapObjects.isEmpty else {
        return stats
    }

    var worklist: [UnsafeMutableRawPointer] = []
    worklist.reserveCapacity(state.heapObjects.count)
    collectRootPointersLocked(state: state, threadLocalValues: threadLocalValues, counts: &stats.rootSet, into: &worklist)
    var resolvedCallableRoots = 0
    for rawRoot in callableRoots {
        if let pointer = UnsafeMutableRawPointer(bitPattern: rawRoot) {
            worklist.append(pointer)
            resolvedCallableRoots += 1
        }
    }
    stats.rootSet.globalReferences += Int64(resolvedCallableRoots)
    // Box owners are retained until runtimeReleaseObject; roots attached to an
    // SDK lease follow that existing lifetime. Heap owners are handled as edges.
    var seededLeaseRoots = 0
    for lease in state.foreignResources.values {
        if let owner = lease.owner, state.objectPointers.contains(owner) {
            let roots = (lease.dependentRoots + lease.attachmentRoots).compactMap(UnsafeMutableRawPointer.init(bitPattern:))
            worklist.append(contentsOf: roots)
            seededLeaseRoots += roots.count
        }
    }
    let retainedAtomicRootsStart = worklist.count
    collectRetainedAtomicPayloadRootsLocked(state: state, into: &worklist)
    stats.rootSet.stableReferences += Int64(seededLeaseRoots + worklist.count - retainedAtomicRootsStart)

    while let current = worklist.popLast() {
        let key = UInt(bitPattern: current)
        guard let object = state.heapObjects[key] else {
            continue
        }
        let header = object.pointer.assumingMemoryBound(to: KKObjHeader.self)
        if (header.pointee.flags & kkObjMarkFlag) != 0 {
            continue
        }
        header.pointee.flags |= kkObjMarkFlag
        stats.markedCount += 1
        appendObjectChildrenLocked(of: object, into: &worklist)
        for lease in state.foreignResources.values where lease.owner == key {
            worklist.append(contentsOf: (lease.dependentRoots + lease.attachmentRoots).compactMap(UnsafeMutableRawPointer.init(bitPattern:)))
        }
    }

    var survivors: [UInt: HeapObjectRecord] = [:]
    survivors.reserveCapacity(state.heapObjects.count)
    for (key, object) in state.heapObjects {
        let header = object.pointer.assumingMemoryBound(to: KKObjHeader.self)
        if (header.pointee.flags & kkObjMarkFlag) != 0 {
            header.pointee.flags &= ~kkObjMarkFlag
            survivors[key] = object
            stats.keptCount += 1
            stats.memoryUsageAfterBytes &+= Int64(object.byteCount)
        } else {
            let tokens = state.foreignResources.compactMap { $0.value.owner == key ? $0.key : nil }
            for token in tokens {
                if let lease = state.foreignResources.removeValue(forKey: token) {
                    state.retiredForeignResources.append(lease)
                }
            }
            removeRuntimeObjectMetadata(forObjectKey: key)
            object.pointer.deallocate()
            stats.sweptCount += 1
        }
    }
    state.heapObjects = survivors
    return stats
}

func collectRootPointersLocked(state: GCState, threadLocalValues: [UInt: [ObjectIdentifier: Int]], counts: inout RuntimeGCRootSetCounts, into worklist: inout [UnsafeMutableRawPointer]) {
    for slotAddress in state.globalRootSlots {
        guard let slot = UnsafeMutablePointer<UnsafeMutableRawPointer?>(bitPattern: slotAddress),
              let value = slot.pointee
        else {
            continue
        }
        worklist.append(value)
        counts.globalReferences += 1
    }

    for frame in state.activeFrames {
        guard let frameBase = frame.frameBase,
              let offsets = state.frameMaps[frame.functionID]
        else {
            continue
        }
        for offset in offsets {
            let slot = frameBase.advanced(by: Int(offset)).assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
            if let value = slot.pointee {
                worklist.append(value)
                counts.stackReferences += 1
            }
        }
    }

    for root in state.coroutineRoots {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: root) else {
            continue
        }
        worklist.append(ptr)
        counts.stackReferences += 1
    }

    for pinned in state.pinnedObjectCounts.keys {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: pinned) else {
            continue
        }
        worklist.append(ptr)
        counts.stableReferences += 1
    }

    for stableRefTarget in state.stableRefCounts.keys {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: stableRefTarget) else {
            continue
        }
        worklist.append(ptr)
        counts.stableReferences += 1
    }

    for threadValues in threadLocalValues.values {
        for raw in threadValues.values {
            guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
                continue
            }
            worklist.append(ptr)
            counts.threadLocalReferences += 1
        }
    }
}

func appendObjectChildrenLocked(of object: HeapObjectRecord, into worklist: inout [UnsafeMutableRawPointer]) {
    let header = object.pointer.assumingMemoryBound(to: KKObjHeader.self).pointee
    guard let typeInfo = header.typeInfo else {
        return
    }
    let descriptor = typeInfo.pointee
    let fieldCount = Int(descriptor.fieldCount)
    guard fieldCount > 0 else {
        return
    }

    for index in 0 ..< fieldCount {
        let offset = Int(descriptor.fieldOffsets[index])
        if offset + MemoryLayout<UnsafeMutableRawPointer?>.size > object.byteCount {
            continue
        }
        let fieldSlot = object.pointer.advanced(by: offset).assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
        if let child = fieldSlot.pointee {
            worklist.append(child)
        }
    }
}
