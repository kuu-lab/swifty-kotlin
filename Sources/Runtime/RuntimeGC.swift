import Dispatch
import Foundation
import RuntimeCAtomics

struct HeapObjectRecord {
    let pointer: UnsafeMutableRawPointer
    let byteCount: Int
    /// Distinguishes allocations that reuse the same address.
    let generation: UInt64
}

enum TracedGCReference {
    case heap(key: UInt, generation: UInt64)
    case managed(key: UInt, generation: UInt64)
    case result(key: UInt, generation: UInt64)
}

struct ActiveFrameRecord {
    let functionID: UInt32
    let frameBase: UnsafeMutableRawPointer?
    /// Non-nil for compiler-emitted shadow frames whose root slots are stored
    /// contiguously at `frameBase`.
    let rootCount: Int?
}

struct GCShadowFrame {
    var slots: [Int: Int] = [:]
    /// Values returned by native operations remain rooted until this frame returns.
    var handoffs: Set<Int> = []
}

private final class RuntimeResetFrameGate: @unchecked Sendable {
    let lock = NSRecursiveLock()
}

private let runtimeResetFrameGate = RuntimeResetFrameGate()

private func runtimeWithResetFrameGate<T>(_ body: () -> T) -> T {
    runtimeResetFrameGate.lock.lock()
    defer { runtimeResetFrameGate.lock.unlock() }
    return body()
}

/// Keep frame creation and a multi-part test reset mutually exclusive. The
/// body is not called when frames or queued work prevent a reset.
@discardableResult
func runtimeWithQuiescentGCFrames(_ body: () -> Void) -> Bool {
    runtimeWithQuiescentGCFramesResult {
        body()
        return true
    }
}

@discardableResult
func runtimeWithQuiescentGCFramesResult(_ body: () -> Bool) -> Bool {
    runtimeWithResetFrameGate {
        let isQuiescent = runtimeStorage.withGCLock { state in
            state.shadowFrames.isEmpty && state.activeFrames.isEmpty && state.pendingResetWork == 0
        }
        guard isQuiescent else { return false }
        return body()
    }
}

/// Protect a queued native callback before it has had a chance to push its
/// first shadow frame. Its owner finishes the lease after the callback exits.
final class RuntimeGCResetWorkLease: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true

    init() {
        runtimeWithResetFrameGate {
            runtimeStorage.withGCLock { $0.pendingResetWork += 1 }
        }
    }

    func finish() {
        lock.lock()
        guard active else {
            lock.unlock()
            return
        }
        active = false
        lock.unlock()
        runtimeWithResetFrameGate {
            runtimeStorage.withGCLock { $0.pendingResetWork -= 1 }
        }
    }

    deinit { finish() }
}

@discardableResult
func runtimeRecordShadowHandoffLocked(
    _ value: Int, threadID: ObjectIdentifier, state: inout GCState
) -> Bool {
    guard value != 0, value != runtimeNullSentinelInt,
          let count = state.shadowFrames[threadID]?.count, count > 0 else { return false }
    state.shadowFrames[threadID]?[count - 1].handoffs.insert(value)
    return true
}

final class RuntimeStorageHeapRoots {
    weak var storage: AnyObject?
    var fields: [Int: UInt]

    init(storage: AnyObject, fields: [Int: UInt]) {
        self.storage = storage
        self.fields = fields
    }
}

final class RuntimeTracedLeaseRoots {
    weak var storage: AnyObject?
    let references: [TracedGCReference]

    init(storage: AnyObject, references: [TracedGCReference]) {
        self.storage = storage
        self.references = references
    }
}

final class RuntimeCoroutineRootStorage {}

final class RuntimeGCRootedValue {
    let value: Int
    private let gcRootStorage = RuntimeCoroutineRootStorage()

    init(_ value: Int) {
        self.value = value
        runtimeStorage.withGCLock { state in
            runtimeRecordCoroutineHeapRootsLocked([value], storage: gcRootStorage, state: &state)
        }
    }

    func rootedValue() -> Int {
        withExtendedLifetime(self) {
            let threadID = ObjectIdentifier(Thread.current)
            runtimeStorage.withGCLock { state in
                runtimeRecordShadowHandoffLocked(value, threadID: threadID, state: &state)
            }
            return value
        }
    }
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
    var nextHeapGeneration: UInt64 = 0
    /// `kk_object_new` boxes use ARC storage but participate in the same
    /// reachability pass as `kk_alloc` objects. `objectPointers` remains the
    /// handle registry; this set identifies the subset the collector owns.
    var managedObjectPointers: Set<UInt> = []
    var managedObjectGenerations: [UInt: UInt64] = [:]
    var nextManagedObjectGeneration: UInt64 = 0
    /// New allocations and values crossing a generated function return are
    /// held here until a shadow root slot is published or the next collection
    /// completes. This closes the short handoff window between runtime calls.
    var pendingGCRoots: Set<UInt> = []
    /// ARC releases are deferred until after `gcLock` is released so object
    /// deinitializers may safely call back into the runtime.
    var retiredManagedObjects: [UnsafeMutableRawPointer] = []
    var nextForeignResourceToken: Int = 1
    var foreignResources: [Int: RuntimeForeignResourceLease] = [:]
    var retiredForeignResources: [RuntimeForeignResourceLease] = []
    var objectPointers = RuntimePointerSet()
    /// Existing retained reference cells are external owners, not swept boxes.
    /// Trace their direct kk_alloc payloads until replacement or owner release.
    var retainedAtomicReferenceHandles: Set<UInt> = []
    /// Direct managed-heap references of retained boxes with tracked fields.
    var retainedObjectHeapFields: [UInt: [Int: UInt]] = [:]
    /// Immutable edges whose children are traced only if their owner is reached.
    var tracedObjectReferences: [UInt: [TracedGCReference]] = [:]
    var tracedResultGenerations: [UInt: UInt64] = [:]
    var nextTracedResultGeneration: UInt64 = 0
    var tracedResultLeaseRoots: [ObjectIdentifier: RuntimeTracedLeaseRoots] = [:]
    /// Shared array storage is weakly referenced so its roots disappear when
    /// the last retained array/view releases the storage.
    var retainedArrayHeapFields: [ObjectIdentifier: RuntimeStorageHeapRoots] = [:]
    /// Each registered array or view owns its shared storage independently.
    var arrayStorageByOwner: [UInt: ObjectIdentifier] = [:]
    /// Job wrapper links are published under gcLock for the collector.
    var objectJobHandles: [UInt: Int] = [:]
    /// Coroutine terminal and handoff values follow their native storage lifetime.
    var retainedCoroutineHeapFields: [ObjectIdentifier: RuntimeStorageHeapRoots] = [:]
    /// In-flight Future operations keep their result even if its handle is released.
    var retainedFutureHeapFields: [ObjectIdentifier: RuntimeStorageHeapRoots] = [:]
    /// Borrowed pointers in `objectPointers` whose lifetime is owned by a
    /// singleton or a dedicated runtime registry rather than passRetained.
    var borrowedObjectPointers: Set<UInt> = []
    /// Canonical boxed Unit pointer, retained in `objectPointers` across GC resets.
    var unitBoxPointer: UInt? = nil
    var globalRootSlots: Set<UInt> = []
    /// Compiler-owned static globals contain intptr words rather than Swift
    /// pointer values. Their addresses remain valid for the process lifetime.
    var globalWordRootSlots: Set<UInt> = []
    /// Mirror thread-local words so collection never dereferences TLS storage
    /// after its owning thread exits.
    var threadLocalGlobalValues: [ObjectIdentifier: [UInt: Int]] = [:]
    var frameMaps: [UInt32: [Int32]] = [:]
    var activeFrames: [ObjectIdentifier: [ActiveFrameRecord]] = [:]
    // Shadow roots contain raw ABI words. Registry membership is checked by the
    // collector before any word is treated as a managed pointer.
    var shadowFrames: [ObjectIdentifier: [GCShadowFrame]] = [:]
    var pendingResetWork = 0
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

func runtimeRecordCoroutineHeapRootsLocked(
    _ values: [Int], storage: RuntimeCoroutineRootStorage, state: inout GCState
) {
    let storageID = ObjectIdentifier(storage)
    var fields: [Int: UInt] = [:]
    for (index, raw) in values.enumerated() {
        let key = UInt(bitPattern: raw)
        if state.heapObjects[key] != nil || state.objectPointers.contains(key) {
            fields[index] = key
        }
    }
    if fields.isEmpty {
        state.retainedCoroutineHeapFields.removeValue(forKey: storageID)
    } else {
        state.retainedCoroutineHeapFields[storageID] = RuntimeStorageHeapRoots(storage: storage, fields: fields)
    }
}

enum RuntimeCompletionHandoff {
    case all
    case valueOrExceptionWhenCompleted
    case exceptionWhenCompleted
    case exception
}

func runtimeRecordCompletionHandoffLocked(
    _ handoff: RuntimeCompletionHandoff, completed: Bool, value: Int, exception: Int,
    threadID: ObjectIdentifier, state: inout GCState
) {
    switch handoff {
    case .all:
        runtimeRecordShadowHandoffLocked(value, threadID: threadID, state: &state)
        runtimeRecordShadowHandoffLocked(exception, threadID: threadID, state: &state)
    case .valueOrExceptionWhenCompleted:
        if completed {
            runtimeRecordShadowHandoffLocked(exception == 0 ? value : exception, threadID: threadID, state: &state)
        }
    case .exceptionWhenCompleted:
        if completed { runtimeRecordShadowHandoffLocked(exception, threadID: threadID, state: &state) }
    case .exception:
        runtimeRecordShadowHandoffLocked(exception, threadID: threadID, state: &state)
    }
}

func recordRetainedBoxManagedHeapFieldsLocked(_ box: AnyObject, owner: UInt, state: inout GCState) {
    if let array = box as? RuntimeArrayBox {
        array.recordManagedHeapFieldsLocked(owner: owner, state: &state)
    } else if let list = box as? RuntimeListBox, let storageID = list.gcArrayStorageID() {
        state.arrayStorageByOwner[owner] = storageID
    } else if let function = box as? RuntimeFunctionValueBox {
        let capture = UInt(bitPattern: function.closureRaw)
        if state.heapObjects[capture] != nil || state.objectPointers.contains(capture) {
            state.retainedObjectHeapFields[owner] = [-1: capture]
        }
    } else if let pair = box as? RuntimePairBox {
        recordRetainedBoxManagedHeapValuesLocked(
            [pair.firstValue, pair.secondValue], owner: owner, state: &state
        )
    } else if let triple = box as? RuntimeTripleBox {
        recordRetainedBoxManagedHeapValuesLocked(
            [triple.firstValue, triple.secondValue, triple.thirdValue], owner: owner, state: &state
        )
    } else if let result = box as? RuntimeResultBox {
        let payload = result.isSuccess ? result.value : result.exception
        let child = UInt(bitPattern: payload)
        let reference: TracedGCReference?
        if let allocation = state.heapObjects[child] {
            reference = .heap(key: child, generation: allocation.generation)
        } else if let generation = state.managedObjectGenerations[child] {
            reference = .managed(key: child, generation: generation)
        } else if let generation = state.tracedResultGenerations[child] {
            reference = .result(key: child, generation: generation)
        } else {
            reference = nil
        }
        if let reference {
            if state.tracedResultGenerations[owner] == nil {
                precondition(state.nextTracedResultGeneration < UInt64.max, "Result generation exhausted")
                state.nextTracedResultGeneration += 1
                state.tracedResultGenerations[owner] = state.nextTracedResultGeneration
            }
            state.tracedObjectReferences[owner] = [reference]
        } else {
            state.tracedObjectReferences.removeValue(forKey: owner)
            state.tracedResultGenerations.removeValue(forKey: owner)
        }
    }
}

private func recordRetainedBoxManagedHeapValuesLocked(
    _ values: [RuntimeValue], owner: UInt, state: inout GCState
) {
    var fields: [Int: UInt] = [:]
    for (index, value) in values.enumerated() {
        guard let raw = value.childReferenceRawValue else { continue }
        let child = UInt(bitPattern: raw)
        if state.heapObjects[child] != nil || state.objectPointers.contains(child) {
            fields[index] = child
        }
    }
    if fields.isEmpty {
        state.retainedObjectHeapFields.removeValue(forKey: owner)
    } else {
        state.retainedObjectHeapFields[owner] = fields
    }
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
    /// Nominal type IDs that belong to value classes — every class ID
    /// `kk_tag_value_class_box`/`kk_value_class_box` has tagged a box with.
    /// `objectTypeByPointer` also tags lists, map entries, iterators and other
    /// runtime internals, so equality cannot treat every tagged pointer as a
    /// value-class box; this set distinguishes them (KUU-3616).
    var valueClassTypeIDs: Set<Int64> = []
    var arrayTypeIDsByPointer: [UInt: Set<Int64>] = [:]
    var typeParents: [Int64: Set<Int64>] = [:]
    /// Set once the static reflection hierarchy edges are in `typeParents`;
    /// cleared with `typeParents` so a metadata reset re-registers them.
    var reflectionTypeEdgesRegistered = false
    var primitiveTypeEdgesRegistered = false
    var rangeTypeEdgesRegistered = false
    var jobFamilyTypeEdgesRegistered = false
    var channelFamilyTypeEdgesRegistered = false
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
    /// Reverse index for removing a thread's values when its pthread exits.
    var threadLocalReceiversByOwner: [ObjectIdentifier: Set<UInt>] = [:]
}

struct DelegateState {
    var callableRefMetadataByValue: [Int: RuntimeCallableRefMetadata] = [:]
    var functionValueCallableRefIdentityByValue: [Int: RuntimeCallableReferenceIdentity] = [:]
    var callableAdapterIdentityByValue: [Int: RuntimeCallableAdapterIdentity] = [:]
    var functionTypePayloadByValue: [Int: Int] = [:]
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
    /// resumed value against this box's pointer to distinguish
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
    func withThreadLocalAndGCLocks<R>(_ body: (inout ThreadLocalState, inout GCState) -> R) -> R {
        threadLocalLock.lock()
        gcLock.lock()
        defer {
            gcLock.unlock()
            threadLocalLock.unlock()
        }
        return body(&threadLocalState.pointee, &gcState.pointee)
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
    runtimeRegisterHeapAllocation(ptr, byteCount: allocationSize)
    return ptr
}

/// The pointer is already initialized and must not be registered elsewhere.
func runtimeRegisterHeapAllocation(_ pointer: UnsafeMutableRawPointer, byteCount: Int) {
    runtimeStorage.withGCLock { state in
        let key = UInt(bitPattern: pointer)
        precondition(state.heapObjects[key] == nil, "Managed heap address is already registered")
        precondition(state.nextHeapGeneration < UInt64.max, "Managed heap generation exhausted")
        state.nextHeapGeneration += 1
        state.heapObjects[key] = HeapObjectRecord(
            pointer: pointer,
            byteCount: byteCount,
            generation: state.nextHeapGeneration
        )
    }
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
    // Only enrolled mutators participate in the safepoint protocol. Other
    // threads and arbitrary direct frame-slot writes are not protected yet.
    let startTimeNs = runtimeGCNowNanos()
    let firstPauseRequestTimeNs = runtimeGCNowNanos()
    runtimeGCSafepoints.beginCollection()
    defer { runtimeGCSafepoints.endCollection() }
    let callableRoots = runtimeCallableRoots()
    var passEpoch: Int64 = 0
    // Hold the thread-local lock until marking has finished: taking a snapshot
    // before acquiring gcLock can miss a value published in the intervening gap.
    let retired = runtimeStorage.withThreadLocalAndGCLocks { threadLocal, state -> ([RuntimeForeignResourceLease], [UnsafeMutableRawPointer]) in
        let firstPauseStartTimeNs = runtimeGCNowNanos()
        let stats = performMarkAndSweepLocked(
            state: &state,
            threadLocalValues: threadLocal.threadLocalValues,
            callableRoots: callableRoots
        )
        let firstPauseEndTimeNs = runtimeGCNowNanos()
        let retired = state.retiredForeignResources
        state.retiredForeignResources.removeAll()
        let retiredManagedObjects = state.retiredManagedObjects
        state.retiredManagedObjects.removeAll()
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
        return (retired, retiredManagedObjects)
    }
    withExtendedLifetime(retired.0) {} // ARC destruction outside gcLock.
    for pointer in retired.1 {
        Unmanaged<AnyObject>.fromOpaque(pointer).release()
    }
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

// Kotlin global slots are registered by generated code before loading or
// storing a reference-valued global.
@discardableResult
@_cdecl("kk_register_global_root")
public func kk_register_global_root(_ slot: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int {
    guard let slot else {
        return 0
    }
    runtimeStorage.withGCLock { state in
        state.globalRootSlots.insert(UInt(bitPattern: slot))
    }
    return 0
}

public func kk_unregister_global_root(_ slot: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) {
    guard let slot else {
        return
    }
    runtimeStorage.withGCLock { state in
        state.globalRootSlots.remove(UInt(bitPattern: slot))
    }
}

/// Publish a compiler-owned static global and its value atomically with GC.
@_cdecl("kk_gc_store_global")
@discardableResult
public func kk_gc_store_global(_ slot: UnsafeMutablePointer<Int>?, _ value: Int) -> Int {
    guard let slot else { preconditionFailure("GC global root slot is null") }
    runtimeStorage.withGCLock { state in
        state.globalWordRootSlots.insert(UInt(bitPattern: slot))
        slot.pointee = value
    }
    return 0
}

private final class GCThreadLocalGlobalOwner {
    deinit {
        let ownerID = ObjectIdentifier(self)
        runtimeStorage.withGCLock { state in
            state.threadLocalGlobalValues.removeValue(forKey: ownerID)
        }
    }
}

private let gcThreadLocalGlobalOwnerKey = makePthreadKey()

/// Mirror the word instead of registering the address of per-thread storage,
/// which may become invalid when the thread terminates.
@_cdecl("kk_gc_store_thread_local_global")
@discardableResult
public func kk_gc_store_thread_local_global(_ slot: UnsafeMutablePointer<Int>?, _ value: Int) -> Int {
    guard let slot else { preconditionFailure("GC thread-local global slot is null") }
    let owner: GCThreadLocalGlobalOwner
    if let existing: GCThreadLocalGlobalOwner = pthreadGetValue(gcThreadLocalGlobalOwnerKey) {
        owner = existing
    } else {
        owner = GCThreadLocalGlobalOwner()
        pthreadSetValue(gcThreadLocalGlobalOwnerKey, owner)
    }
    let ownerID = ObjectIdentifier(owner)
    let slotID = UInt(bitPattern: slot)
    runtimeStorage.withGCLock { state in
        slot.pointee = value
        if value == 0 || value == runtimeNullSentinelInt {
            state.threadLocalGlobalValues[ownerID]?.removeValue(forKey: slotID)
            if state.threadLocalGlobalValues[ownerID]?.isEmpty == true {
                state.threadLocalGlobalValues.removeValue(forKey: ownerID)
            }
        } else {
            state.threadLocalGlobalValues[ownerID, default: [:]][slotID] = value
        }
    }
    return 0
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
    let threadID = ObjectIdentifier(Thread.current)
    runtimeWithResetFrameGate {
        runtimeStorage.withGCLock { state in
            state.activeFrames[threadID, default: []].append(
                ActiveFrameRecord(functionID: functionID, frameBase: frameBase, rootCount: nil)
            )
        }
    }
}

/// Serializes a frame-root write with root scanning during collection.
/// The caller must keep the slot allocated until its frame is popped and keep
/// the value rooted until this write completes. This is not a safepoint protocol.
// DEAD-CDECL-TEST-HOOK: GC-FRAME - Runtime tests exercise synchronized root writes.
@_cdecl("kk_store_frame_root")
public func kk_store_frame_root(
    _ slot: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
    _ value: UnsafeMutableRawPointer?
) {
    guard let slot else { return }
    runtimeStorage.withGCLock { _ in
        slot.pointee = value
    }
}

// DEAD-CDECL-TEST-HOOK: GC-FRAME - Runtime tests balance synthetic frames.
@_cdecl("kk_pop_frame")
public func kk_pop_frame() {
    let threadID = ObjectIdentifier(Thread.current)
    runtimeStorage.withGCLock { state in
        if state.activeFrames[threadID]?.isEmpty == false {
            state.activeFrames[threadID]?.removeLast()
            if state.activeFrames[threadID]?.isEmpty == true {
                state.activeFrames.removeValue(forKey: threadID)
            }
        }
    }
}

/// Publishes compiler-owned raw Kotlin reference slots as a GC frame.
@_cdecl("kk_gc_push_root_frame")
public func kk_gc_push_root_frame(_ rootSlots: UnsafeMutableRawPointer?, _ rootCount: Int) -> Int {
    guard let rootSlots, rootCount > 0 else { return 0 }
    let threadID = ObjectIdentifier(Thread.current)
    runtimeWithResetFrameGate {
        runtimeStorage.withGCLock { state in
            state.activeFrames[threadID, default: []].append(
                ActiveFrameRecord(functionID: 0, frameBase: rootSlots, rootCount: rootCount)
            )
        }
    }
    return 0
}

/// Publishes a root slot and retires its allocation or return handoff.
@_cdecl("kk_gc_root_store")
public func kk_gc_root_store(_ slot: UnsafeMutablePointer<Int>?, _ value: Int) -> Int {
    guard let slot else { return 0 }
    runtimeStorage.withGCLock { state in
        slot.pointee = value
        state.pendingGCRoots.remove(UInt(bitPattern: value))
    }
    return 0
}

/// Retains a return value until its caller publishes a root slot.
@_cdecl("kk_gc_frame_leave")
public func kk_gc_frame_leave(_ returnValue: Int, _ hasRootFrame: Int) -> Int {
    let threadID = ObjectIdentifier(Thread.current)
    runtimeStorage.withGCLock { state in
        if hasRootFrame != 0, state.activeFrames[threadID]?.isEmpty == false {
            state.activeFrames[threadID]?.removeLast()
            if state.activeFrames[threadID]?.isEmpty == true {
                state.activeFrames.removeValue(forKey: threadID)
            }
        }
        let key = UInt(bitPattern: returnValue)
        if state.heapObjects[key] != nil || state.objectPointers.contains(key) {
            state.pendingGCRoots.insert(key)
        }
    }
    return 0
}

// These operations serialize root records, but do not stop mutators or protect
// a freshly allocated value before it is published. A safepoint protocol is
// required before generated code can rely on them for automatic reclamation.
@_cdecl("kk_gc_shadow_push")
@discardableResult
public func kk_gc_shadow_push() -> Int {
    let threadID = ObjectIdentifier(Thread.current)
    runtimeWithResetFrameGate {
        runtimeStorage.withGCLock { state in
            state.shadowFrames[threadID, default: []].append(GCShadowFrame())
        }
    }
    return 0
}

@_cdecl("kk_gc_shadow_set")
@discardableResult
public func kk_gc_shadow_set(_ slot: Int, _ value: Int) -> Int {
    let threadID = ObjectIdentifier(Thread.current)
    runtimeStorage.withGCLock { state in
        guard let count = state.shadowFrames[threadID]?.count, count > 0, slot >= 0 else {
            preconditionFailure("GC shadow root write requires an active frame and a nonnegative slot")
        }
        state.shadowFrames[threadID]?[count - 1].slots[slot] = value
        if state.shadowFrames[threadID]?[count - 1].slots[-1] == value {
            state.shadowFrames[threadID]?[count - 1].slots.removeValue(forKey: -1)
        }
        if state.shadowFrames[threadID]?[count - 1].slots[-2] == value {
            state.shadowFrames[threadID]?[count - 1].slots.removeValue(forKey: -2)
        }
    }
    return 0
}

@_cdecl("kk_gc_shadow_pop")
@discardableResult
public func kk_gc_shadow_pop(_ result: Int, _ thrown: Int) -> Int {
    runtimePopGCShadowFrame(result, thrown, preservingParentHandoffs: false)
}

// Native helper frames can run between a generated return and its caller's
// slot write. Preserve any outstanding caller handoff before publishing a new
// native result; an explicit per-call commit is needed to retire it earlier.
@discardableResult
func runtimePopNativeGCShadowFrame(_ result: Int, _ thrown: Int) -> Int {
    runtimePopGCShadowFrame(result, thrown, preservingParentHandoffs: true)
}

private func runtimePopGCShadowFrame(
    _ result: Int, _ thrown: Int, preservingParentHandoffs: Bool
) -> Int {
    let threadID = ObjectIdentifier(Thread.current)
    runtimeStorage.withGCLock { state in
        guard let count = state.shadowFrames[threadID]?.count, count > 0 else {
            preconditionFailure("GC shadow frame pop requires an active frame")
        }
        if preservingParentHandoffs, count > 1 {
            for slot in [-1, -2] {
                guard let previous = state.shadowFrames[threadID]?[count - 2].slots[slot],
                      previous != 0, previous != runtimeNullSentinelInt
                else { continue }
                let key = UInt(bitPattern: previous)
                if state.heapObjects[key] != nil || state.objectPointers.contains(key) {
                    state.shadowFrames[threadID]?[count - 2].handoffs.insert(previous)
                }
            }
        }
        state.shadowFrames[threadID]?.removeLast()
        if count == 1 {
            state.shadowFrames.removeValue(forKey: threadID)
        } else {
            // Negative slots are reserved for handoff until the caller records
            // the returned value and exception in its own frame.
            state.shadowFrames[threadID]?[count - 2].slots[-1] = result
            state.shadowFrames[threadID]?[count - 2].slots[-2] = thrown
        }
    }
    return 0
}

// DEAD-CDECL-TEST-HOOK: GC-FRAME - Backend tests check generated frame balance.
@_cdecl("kk_gc_shadow_depth")
public func kk_gc_shadow_depth() -> Int {
    let threadID = ObjectIdentifier(Thread.current)
    return runtimeStorage.withGCLock { state in
        state.shadowFrames[threadID]?.count ?? 0
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
    _ = runtimeTryForceReset()
}

@discardableResult
func runtimeTryForceReset() -> Bool {
    runtimeWithQuiescentGCFramesResult {
        guard runtimeTryResetGC() else { return false }
        kk_runtime_reset_metadata()
        kk_runtime_reset_flow()
        kk_runtime_reset_thread_local()
        kk_runtime_reset_delegate()
        runtimeResetDebugState()
        return true
    }
}

/// `objectPointers` is deliberately preserved: every entry is a box the runtime
/// still holds a `passRetained` reference to, so dropping the entry reclaims
/// nothing and only makes a live handle unresolvable. Test isolation resets run
/// while other suites of the same process still own such handles, and an
/// unresolvable live handle surfaces as a KSWIFTK-RUNTIME-0001 invalid-handle
/// panic (invalid range/array/string handle). Entries are removed by whoever
/// releases the box.
@discardableResult
func kk_runtime_reset_gc() -> Bool {
    runtimeTryResetGC()
}

/// Test isolation cannot destroy frame records or their heap while a native
/// callback is still unwinding on another thread. In that case leave the
/// runtime intact; a later isolation reset can run after those frames exit.
private func runtimeTryResetGC() -> Bool {
    runtimeWithQuiescentGCFrames {
        runtimeResetAtomicfuParkingCaches()
        let retired = runtimeStorage.withGCLock { state -> [RuntimeForeignResourceLease] in
            var retired = state.retiredForeignResources
            state.retiredForeignResources.removeAll()
            for token in Array(state.foreignResources.keys) {
                if state.foreignResources[token]?.owner != nil,
                   let lease = state.foreignResources.removeValue(forKey: token) { retired.append(lease) }
            }
            for (key, object) in state.heapObjects {
                runtimeForgetFrozenObject(Int(bitPattern: key))
                object.pointer.deallocate()
            }
            state.heapObjects.removeAll(keepingCapacity: false)
            // Registered ARC boxes survive reset. Preserve their edges to other
            // registered boxes, but discard references to the freed kk_alloc heap.
            let registered = state.objectPointers
            state.retainedObjectHeapFields = state.retainedObjectHeapFields.reduce(into: [:]) { retained, entry in
                guard registered.contains(entry.key) else { return }
                let fields = entry.value.filter { registered.contains($0.value) }
                if !fields.isEmpty { retained[entry.key] = fields }
            }
            func keepRegisteredFields(_ mirrors: inout [ObjectIdentifier: RuntimeStorageHeapRoots]) {
                mirrors = mirrors.filter { $0.value.storage != nil }
                for roots in mirrors.values {
                    roots.fields = roots.fields.filter { registered.contains($0.value) }
                }
            }
            keepRegisteredFields(&state.retainedArrayHeapFields)
            keepRegisteredFields(&state.retainedCoroutineHeapFields)
            keepRegisteredFields(&state.retainedFutureHeapFields)
            state.arrayStorageByOwner = state.arrayStorageByOwner.filter { registered.contains($0.key) }
            state.objectJobHandles = state.objectJobHandles.filter { registered.contains($0.key) }
            state.tracedResultLeaseRoots = state.tracedResultLeaseRoots.filter { $0.value.storage != nil }
            pruneTracedObjectReferencesLocked(state: &state)
            state.globalRootSlots.removeAll(keepingCapacity: false)
            state.globalWordRootSlots.removeAll(keepingCapacity: false)
            state.threadLocalGlobalValues.removeAll(keepingCapacity: false)
            state.frameMaps.removeAll(keepingCapacity: false)
            state.activeFrames.removeAll(keepingCapacity: false)
            state.shadowFrames.removeAll(keepingCapacity: false)
            state.coroutineRoots.removeAll(keepingCapacity: false)
            state.pendingGCRoots.removeAll(keepingCapacity: false)
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
            state.channelFamilyTypeEdgesRegistered = false
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
        state.functionTypePayloadByValue.removeValue(forKey: Int(bitPattern: key))
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
            state.arrayStorageByOwner.removeValue(forKey: key)
            state.objectJobHandles.removeValue(forKey: key)
            state.borrowedObjectPointers.remove(key)
            state.retainedObjectHeapFields.removeValue(forKey: key)
            state.tracedObjectReferences.removeValue(forKey: key)
            state.tracedResultGenerations.removeValue(forKey: key)
        }
    }
}

func kk_runtime_reset_thread_local() {
    let boxes = runtimeStorage.withThreadLocalLock { state -> [UnsafeMutableRawPointer] in
        let boxes = state.threadLocalBoxes.compactMap(UnsafeMutableRawPointer.init(bitPattern:))
        state.threadLocalBoxes.removeAll(keepingCapacity: false)
        state.threadLocalValues.removeAll(keepingCapacity: false)
        state.threadLocalReceiversByOwner.removeAll(keepingCapacity: false)
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
            state.managedObjectPointers.remove(key)
            state.managedObjectGenerations.removeValue(forKey: key)
            state.pendingGCRoots.remove(key)
            state.arrayStorageByOwner.removeValue(forKey: key)
            state.objectJobHandles.removeValue(forKey: key)
            state.retainedAtomicReferenceHandles.remove(key)
            state.retainedObjectHeapFields.removeValue(forKey: key)
            state.tracedObjectReferences.removeValue(forKey: key)
            state.tracedResultGenerations.removeValue(forKey: key)
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
        state.functionValueCallableRefIdentityByValue.removeAll(keepingCapacity: false)
        state.callableAdapterIdentityByValue.removeAll(keepingCapacity: false)
        state.functionTypePayloadByValue.removeAll(keepingCapacity: false)
        state.functionDescriptionsByValue.removeAll(keepingCapacity: false)
        state.functionEnclosingClassNamesByPointer.removeAll(keepingCapacity: false)
    }
}

@discardableResult
func performMarkAndSweepLocked(state: inout GCState, threadLocalValues: [UInt: [ObjectIdentifier: Int]] = [:], callableRoots: [Int] = []) -> RuntimeGCMarkSweepStats {
    var stats = RuntimeGCMarkSweepStats()
    stats.memoryUsageBeforeBytes = state.heapObjects.values.reduce(Int64(0)) { $0 &+ Int64($1.byteCount) }
    state.retainedArrayHeapFields = state.retainedArrayHeapFields.filter { $0.value.storage != nil }
    state.retainedCoroutineHeapFields = state.retainedCoroutineHeapFields.filter { $0.value.storage != nil }
    state.retainedFutureHeapFields = state.retainedFutureHeapFields.filter { $0.value.storage != nil }
    state.tracedResultLeaseRoots = state.tracedResultLeaseRoots.filter { $0.value.storage != nil }
    var worklist: [UnsafeMutableRawPointer] = []
    worklist.reserveCapacity(state.heapObjects.count + state.managedObjectPointers.count)
    collectRootPointersLocked(state: state, threadLocalValues: threadLocalValues, counts: &stats.rootSet, into: &worklist)
    var resolvedCallableRoots = 0
    for rawRoot in callableRoots {
        if let pointer = UnsafeMutableRawPointer(bitPattern: rawRoot) {
            worklist.append(pointer)
            resolvedCallableRoots += 1
        }
    }
    stats.rootSet.globalReferences += Int64(resolvedCallableRoots)
    // Unattached and externally retained owners keep their captures alive.
    // Managed owners expose captures only when the owner is reachable.
    var seededLeaseRoots = 0
    for lease in state.foreignResources.values {
        if lease.owner == nil || lease.owner.map({
            state.objectPointers.contains($0) && !state.managedObjectPointers.contains($0)
        }) == true {
            let roots = (lease.dependentRoots + lease.attachmentRoots).compactMap(UnsafeMutableRawPointer.init(bitPattern:))
            worklist.append(contentsOf: roots)
            seededLeaseRoots += roots.count
        }
    }
    let retainedAtomicRootsStart = worklist.count
    collectRetainedAtomicPayloadRootsLocked(state: state, into: &worklist)
    stats.rootSet.stableReferences += Int64(seededLeaseRoots + worklist.count - retainedAtomicRootsStart)

    guard !state.heapObjects.isEmpty || !state.managedObjectPointers.isEmpty else {
        pruneTracedObjectReferencesLocked(state: &state)
        return stats
    }

    var markedManagedObjects: Set<UInt> = []
    markedManagedObjects.reserveCapacity(state.managedObjectPointers.count)
    var visitedRuntimeBoxes: Set<UInt> = []
    while let current = worklist.popLast() {
        let key = UInt(bitPattern: current)
        if let object = state.heapObjects[key] {
            let header = object.pointer.assumingMemoryBound(to: KKObjHeader.self)
            if (header.pointee.flags & kkObjMarkFlag) == 0 {
                header.pointee.flags |= kkObjMarkFlag
                stats.markedCount += 1
                appendObjectChildrenLocked(of: object, into: &worklist)
                for lease in state.foreignResources.values where lease.owner == key {
                    worklist.append(contentsOf: (lease.dependentRoots + lease.attachmentRoots).compactMap(UnsafeMutableRawPointer.init(bitPattern:)))
                }
            }
        }

        if state.managedObjectPointers.contains(key),
           markedManagedObjects.insert(key).inserted
        {
            stats.markedCount += 1
            for lease in state.foreignResources.values where lease.owner == key {
                worklist.append(contentsOf: (lease.dependentRoots + lease.attachmentRoots).compactMap(UnsafeMutableRawPointer.init(bitPattern:)))
            }
        }

        // Retained runtime containers are not swept by this pass, but walking
        // their direct child handles lets a reachable Kotlin object retain
        // objects held through arrays, lists, sets, maps, and closure boxes.
        if state.objectPointers.contains(key),
           visitedRuntimeBoxes.insert(key).inserted
        {
            if state.managedObjectPointers.contains(key), let fields = state.retainedObjectHeapFields[key] {
                for child in fields.values {
                    if let pointer = UnsafeMutableRawPointer(bitPattern: child) {
                        worklist.append(pointer)
                    }
                }
            }
            for child in state.tracedObjectReferences[key] ?? [] {
                let childKey: UInt
                switch child {
                case let .heap(key, generation):
                    guard state.heapObjects[key]?.generation == generation else { continue }
                    childKey = key
                case let .managed(key, generation):
                    guard state.managedObjectGenerations[key] == generation,
                          state.managedObjectPointers.contains(key) else { continue }
                    childKey = key
                case let .result(key, generation):
                    guard state.tracedResultGenerations[key] == generation,
                          state.objectPointers.contains(key) else { continue }
                    childKey = key
                }
                if let pointer = UnsafeMutableRawPointer(bitPattern: childKey) {
                    worklist.append(pointer)
                }
            }
            appendRuntimeBoxChildrenLocked(of: current, state: state, into: &worklist)
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
            runtimeForgetFrozenObject(Int(bitPattern: key))
            object.pointer.deallocate()
            stats.sweptCount += 1
        }
    }
    state.heapObjects = survivors
    for key in Array(state.managedObjectPointers) where !markedManagedObjects.contains(key) {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: key) else {
            continue
        }
        state.managedObjectPointers.remove(key)
        state.managedObjectGenerations.removeValue(forKey: key)
        state.pendingGCRoots.remove(key)
        _ = state.objectPointers.remove(key)
        state.arrayStorageByOwner.removeValue(forKey: key)
        state.objectJobHandles.removeValue(forKey: key)
        state.retainedObjectHeapFields.removeValue(forKey: key)
        state.tracedObjectReferences.removeValue(forKey: key)
        state.tracedResultGenerations.removeValue(forKey: key)
        let tokens = state.foreignResources.compactMap { $0.value.owner == key ? $0.key : nil }
        for token in tokens {
            if let lease = state.foreignResources.removeValue(forKey: token) {
                state.retiredForeignResources.append(lease)
            }
        }
        removeRuntimeObjectMetadata(forObjectKey: key)
        runtimeForgetFrozenObject(Int(bitPattern: pointer))
        state.retiredManagedObjects.append(pointer)
        stats.sweptCount += 1
    }
    state.pendingGCRoots.removeAll(keepingCapacity: false)
    pruneTracedObjectReferencesLocked(state: &state)
    return stats
}

/// Keep only Result edges that can still reach a live managed allocation.
/// Reverse traversal avoids order-dependent stale chains and handles cycles.
private func pruneTracedObjectReferencesLocked(state: inout GCState) {
    var parents: [UInt: [UInt]] = [:]
    var liveOwners: Set<UInt> = []
    var worklist: [UInt] = []
    for (owner, references) in state.tracedObjectReferences where state.objectPointers.contains(owner) {
        for reference in references {
            switch reference {
            case let .heap(key, generation):
                if state.heapObjects[key]?.generation == generation, liveOwners.insert(owner).inserted {
                    worklist.append(owner)
                }
            case let .managed(key, generation):
                if state.managedObjectGenerations[key] == generation,
                   state.managedObjectPointers.contains(key), liveOwners.insert(owner).inserted {
                    worklist.append(owner)
                }
            case let .result(key, generation):
                if state.tracedResultGenerations[key] == generation, state.objectPointers.contains(key) {
                    parents[key, default: []].append(owner)
                }
            }
        }
    }
    while let child = worklist.popLast() {
        for parent in parents[child] ?? [] where liveOwners.insert(parent).inserted {
            worklist.append(parent)
        }
    }
    for (owner, references) in state.tracedObjectReferences {
        guard liveOwners.contains(owner) else {
            state.tracedObjectReferences.removeValue(forKey: owner)
            state.tracedResultGenerations.removeValue(forKey: owner)
            continue
        }
        state.tracedObjectReferences[owner] = references.filter { reference in
            switch reference {
            case let .heap(key, generation):
                return state.heapObjects[key]?.generation == generation
            case let .managed(key, generation):
                return state.managedObjectGenerations[key] == generation && state.managedObjectPointers.contains(key)
            case let .result(key, generation):
                return liveOwners.contains(key) && state.tracedResultGenerations[key] == generation
            }
        }
    }
}

private func appendRuntimeBoxChildrenLocked(
    of pointer: UnsafeMutableRawPointer,
    state: GCState,
    into worklist: inout [UnsafeMutableRawPointer]
) {
    let rawValue = Int(bitPattern: pointer)
    let basePointer = runtimePrimitiveBoxBasePointer(from: rawValue) ?? pointer
    let object = Unmanaged<AnyObject>.fromOpaque(basePointer).takeUnretainedValue()
    let childRefs: [Int]
    if let array = object as? RuntimeArrayBox {
        childRefs = array.gcChildRefsLocked(state: state)
    } else if let list = object as? RuntimeListBox {
        childRefs = list.gcChildRefsLocked(state: state)
    } else if let provider = object as? RuntimeChildReferenceProviding {
        childRefs = provider.childRefs
    } else {
        return
    }
    for rawChild in childRefs {
        guard rawChild != 0,
              rawChild != runtimeNullSentinelInt,
              let child = UnsafeMutableRawPointer(bitPattern: rawChild)
        else {
            continue
        }
        let childKey = UInt(bitPattern: child)
        guard state.heapObjects[childKey] != nil
                || state.managedObjectPointers.contains(childKey)
                || state.objectPointers.contains(childKey)
        else {
            continue
        }
        worklist.append(child)
    }
}

func collectRootPointersLocked(state: GCState, threadLocalValues: [UInt: [ObjectIdentifier: Int]], counts: inout RuntimeGCRootSetCounts, into worklist: inout [UnsafeMutableRawPointer]) {
    for (owner, fields) in state.retainedObjectHeapFields
    where state.objectPointers.contains(owner) && !state.managedObjectPointers.contains(owner) {
        for child in fields.values {
            guard let value = UnsafeMutableRawPointer(bitPattern: child) else { continue }
            worklist.append(value)
            counts.stableReferences += 1
        }
    }

    let externallyOwnedArrayStorage = Set(state.arrayStorageByOwner.compactMap { owner, storageID in
        state.objectPointers.contains(owner) && !state.managedObjectPointers.contains(owner) ? storageID : nil
    })
    for (storageID, roots) in state.retainedArrayHeapFields
    where roots.storage != nil && externallyOwnedArrayStorage.contains(storageID) {
        for child in roots.fields.values {
            guard let value = UnsafeMutableRawPointer(bitPattern: child) else { continue }
            worklist.append(value)
            counts.stableReferences += 1
        }
    }

    for roots in state.retainedCoroutineHeapFields.values where roots.storage != nil {
        for child in roots.fields.values {
            guard let value = UnsafeMutableRawPointer(bitPattern: child) else { continue }
            worklist.append(value)
            counts.stableReferences += 1
        }
    }

    for roots in state.retainedFutureHeapFields.values where roots.storage != nil {
        for child in roots.fields.values {
            guard let value = UnsafeMutableRawPointer(bitPattern: child) else { continue }
            worklist.append(value)
            counts.stableReferences += 1
        }
    }

    for roots in state.tracedResultLeaseRoots.values where roots.storage != nil {
        for reference in roots.references {
            let key: UInt
            switch reference {
            case let .heap(address, generation):
                guard state.heapObjects[address]?.generation == generation else { continue }
                key = address
            case let .managed(address, generation):
                guard state.managedObjectGenerations[address] == generation,
                      state.managedObjectPointers.contains(address) else { continue }
                key = address
            case let .result(address, generation):
                guard state.tracedResultGenerations[address] == generation,
                      state.objectPointers.contains(address) else { continue }
                key = address
            }
            if let pointer = UnsafeMutableRawPointer(bitPattern: key) {
                worklist.append(pointer)
                counts.stableReferences += 1
            }
        }
    }

    for slotAddress in state.globalRootSlots {
        guard let slot = UnsafeMutablePointer<UnsafeMutableRawPointer?>(bitPattern: slotAddress),
              let value = slot.pointee
        else {
            continue
        }
        worklist.append(value)
        counts.globalReferences += 1
    }

    for slotAddress in state.globalWordRootSlots where !state.globalRootSlots.contains(slotAddress) {
        guard let slot = UnsafeMutablePointer<Int>(bitPattern: slotAddress),
              slot.pointee != runtimeNullSentinelInt,
              let value = UnsafeMutableRawPointer(bitPattern: slot.pointee)
        else { continue }
        worklist.append(value)
        counts.globalReferences += 1
    }

    for frames in state.activeFrames.values {
        for frame in frames {
            if let rootCount = frame.rootCount, let frameBase = frame.frameBase {
                let slots = frameBase.assumingMemoryBound(to: Int.self)
                for index in 0 ..< rootCount {
                    let raw = slots[index]
                    guard raw != 0, raw != runtimeNullSentinelInt,
                          let value = UnsafeMutableRawPointer(bitPattern: raw)
                    else { continue }
                    worklist.append(value)
                    counts.stackReferences += 1
                }
                continue
            }
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
    }

    for frames in state.shadowFrames.values {
        for frame in frames {
            for raw in frame.slots.values {
                guard raw != runtimeNullSentinelInt,
                      (state.heapObjects[UInt(bitPattern: raw)] != nil || state.objectPointers.contains(UInt(bitPattern: raw))),
                      let value = UnsafeMutableRawPointer(bitPattern: raw)
                else { continue }
                worklist.append(value)
                counts.stackReferences += 1
            }
            for raw in frame.handoffs {
                guard raw != runtimeNullSentinelInt,
                      (state.heapObjects[UInt(bitPattern: raw)] != nil || state.objectPointers.contains(UInt(bitPattern: raw))),
                      let value = UnsafeMutableRawPointer(bitPattern: raw)
                else { continue }
                worklist.append(value)
                counts.stackReferences += 1
            }
        }
    }

    for pendingRoot in state.pendingGCRoots {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: pendingRoot) else {
            continue
        }
        worklist.append(ptr)
        counts.stackReferences += 1
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

    for threadValues in state.threadLocalGlobalValues.values {
        for raw in threadValues.values {
            guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { continue }
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
