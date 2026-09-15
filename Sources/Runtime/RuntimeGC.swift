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

/// Cache key for `__kk_kclass_create`.
/// `typeToken` uniquely identifies a `KClass<T>` at runtime, so caching by it
/// alone ensures stable hits across repeated evaluations.
struct KClassCacheKey: Hashable {
    let typeToken: Int
}

struct GCState {
    var heapObjects: [UInt: HeapObjectRecord] = [:]
    var objectPointers: Set<UInt> = []
    /// Canonical boxed Unit pointer, retained in `objectPointers` across GC resets.
    var unitBoxPointer: UInt? = nil
    var globalRootSlots: Set<UInt> = []
    var frameMaps: [UInt32: [Int32]] = [:]
    var activeFrames: [ActiveFrameRecord] = []
    var coroutineRoots: Set<UInt> = []
    var pinnedObjects: Set<UInt> = []
}

struct MetadataState {
    var kClassBoxCache: [KClassCacheKey: Int] = [:]
    var enumEntriesCache: [Int64: Int] = [:]
    var objectTypeByPointer: [UInt: Int64] = [:]
    var typeParents: [Int64: Set<Int64>] = [:]
    var dataClassIDs: Set<Int64> = []
    var objectVtableMethods: [UInt: [Int: Int]] = [:]
    var objectEqualsOverrides: [UInt: Int] = [:]
    var objectAnyToStringMethods: [UInt: Int] = [:]
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
}

final class RuntimeStorageBox: @unchecked Sendable {
    private let gcLock = NSLock()
    private let metadataLock = NSLock()
    private let flowLock = NSLock()
    private let threadLocalLock = NSLock()
    private let delegateLock = NSLock()

    private var gcState = GCState()
    private var metadataState = MetadataState()
    private var flowState = FlowState()
    private var threadLocalState = ThreadLocalState()
    private var delegateState = DelegateState()

    let coroutineSuspendedBox = RuntimeStringBox("COROUTINE_SUSPENDED")
    let flowStopSentinelBox = RuntimeStringBox("FLOW_STOP_SENTINEL")
    /// Sentinel returned via callerState.resume(with:) when a lazy sequence
    /// coroutine reaches the end of the builder lambda.  Callers compare the
    /// resumed value against kk_sequence_completed_sentinel() to distinguish
    /// "done" from a real element (CORO-004 infrastructure).
    let sequenceCompletedBox = RuntimeStringBox("SEQUENCE_COMPLETED")

    @discardableResult
    @inline(__always)
    func withGCLock<R>(_ body: (inout GCState) -> R) -> R {
        gcLock.lock()
        defer { gcLock.unlock() }
        return body(&gcState)
    }

    @discardableResult
    @inline(__always)
    func withMetadataLock<R>(_ body: (inout MetadataState) -> R) -> R {
        metadataLock.lock()
        defer { metadataLock.unlock() }
        return body(&metadataState)
    }

    @discardableResult
    @inline(__always)
    func withFlowLock<R>(_ body: (inout FlowState) -> R) -> R {
        flowLock.lock()
        defer { flowLock.unlock() }
        return body(&flowState)
    }

    @discardableResult
    @inline(__always)
    func withThreadLocalLock<R>(_ body: (inout ThreadLocalState) -> R) -> R {
        threadLocalLock.lock()
        defer { threadLocalLock.unlock() }
        return body(&threadLocalState)
    }

    @discardableResult
    @inline(__always)
    func withDelegateLock<R>(_ body: (inout DelegateState) -> R) -> R {
        delegateLock.lock()
        defer { delegateLock.unlock() }
        return body(&delegateState)
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

    /// Restores every tuning knob to its process-startup default. Called by
    /// `.runtimeIsolation(.gcOnly)` test resets so a test that mutates a knob
    /// cannot leak state into an unrelated test running later in the same process.
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
@_cdecl("kk_gc_collect")
public func kk_gc_collect(_ gcRaw: Int = 0) {
    _ = gcRaw
    let threadLocalRoots = runtimeStorage.withThreadLocalLock { state in
        state.threadLocalValues
    }
    runtimeStorage.withGCLock { state in
        performMarkAndSweepLocked(state: &state, threadLocalValues: threadLocalRoots)
    }
}

@_cdecl("kk_gc_schedule")
public func kk_gc_schedule(_ gcRaw: Int = 0) -> Int {
    _ = gcRaw
    kk_gc_collect()
    return 0
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

// KSP-1263: kotlin.native.runtime.GC.MainThreadFinalizerProcessor bridges.
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

// (a) RF-DEAD-002: 配線予定 → GC global root API (CInterop / native global 変数サポート)
// `kk_global_root_slot_*` 動的名が補間 emit だが、公開 API としての register/unregister も配線予定。
@_cdecl("kk_register_global_root")
public func kk_register_global_root(_ slot: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) {
    guard let slot else {
        return
    }
    runtimeStorage.withGCLock { state in
        state.globalRootSlots.insert(UInt(bitPattern: slot))
    }
}

@_cdecl("kk_unregister_global_root")
public func kk_unregister_global_root(_ slot: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) {
    guard let slot else {
        return
    }
    runtimeStorage.withGCLock { state in
        state.globalRootSlots.remove(UInt(bitPattern: slot))
    }
}

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

@_cdecl("kk_push_frame")
public func kk_push_frame(_ functionID: UInt32, _ frameBase: UnsafeMutableRawPointer?) {
    runtimeStorage.withGCLock { state in
        state.activeFrames.append(ActiveFrameRecord(functionID: functionID, frameBase: frameBase))
    }
}

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

// (b) RF-DEAD-002: テスト支援 API — Kotlin プログラムから直接呼ばれない。
// RuntimeTests がテスト間でヒープオブジェクト数を検査するためのセム。
@_cdecl("kk_runtime_heap_object_count")
public func kk_runtime_heap_object_count() -> UInt32 {
    runtimeStorage.withGCLock { state in
        UInt32(state.heapObjects.count)
    }
}

// (b) RF-DEAD-002: テスト支援 API — Kotlin プログラムから直接呼ばれない。
// RuntimeTests がテスト間でランタイム全状態をリセットするためのセム。
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
    runtimeStorage.withGCLock { state in
        for (_, object) in state.heapObjects {
            object.pointer.deallocate()
        }
        state.heapObjects.removeAll(keepingCapacity: false)
        state.globalRootSlots.removeAll(keepingCapacity: false)
        state.frameMaps.removeAll(keepingCapacity: false)
        state.activeFrames.removeAll(keepingCapacity: false)
        state.coroutineRoots.removeAll(keepingCapacity: false)
        state.pinnedObjects.removeAll(keepingCapacity: false)
    }
    runtimeGCTuningState.reset()
    resetCaseInsensitiveOrderCache()
}

func kk_runtime_reset_metadata() {
    let kClassBoxes = runtimeStorage.withMetadataLock { state -> [UnsafeMutableRawPointer] in
        let boxes = state.kClassBoxCache.values.compactMap(UnsafeMutableRawPointer.init(bitPattern:))
        state.kClassBoxCache.removeAll(keepingCapacity: false)
        state.objectTypeByPointer.removeAll(keepingCapacity: false)
        state.typeParents.removeAll(keepingCapacity: false)
        state.dataClassIDs.removeAll(keepingCapacity: false)
        state.objectVtableMethods.removeAll(keepingCapacity: false)
        state.objectEqualsOverrides.removeAll(keepingCapacity: false)
        state.objectAnyToStringMethods.removeAll(keepingCapacity: false)
        state.objectItableMethods.removeAll(keepingCapacity: false)
        state.objectInterfaceSlots.removeAll(keepingCapacity: false)
        return boxes
    }
    releaseRegisteredRuntimeBoxes(kClassBoxes)
    runtimeKClassMetadataRegistry.reset()
    runtimeKConstructorRegistry.reset()
    runtimeKMemberRegistry.reset()
}

private func removeRuntimeObjectMetadata(forObjectKey key: UInt) {
    runtimeStorage.withMetadataLock { state in
        state.objectTypeByPointer.removeValue(forKey: key)
        state.objectVtableMethods.removeValue(forKey: key)
        state.objectEqualsOverrides.removeValue(forKey: key)
        state.objectAnyToStringMethods.removeValue(forKey: key)
        state.objectItableMethods.removeValue(forKey: key)
        state.objectInterfaceSlots.removeValue(forKey: key)
    }
}

func kk_runtime_reset_flow() {
    runtimeStorage.withFlowLock { state in
        state.flowHandles.removeAll(keepingCapacity: false)
        state.flowRetainCounts.removeAll(keepingCapacity: false)
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
            state.objectPointers.remove(UInt(bitPattern: pointer))
        }
    }
    for pointer in pointers {
        Unmanaged<AnyObject>.fromOpaque(pointer).release()
    }
}

func kk_runtime_reset_delegate() {
    runtimeStorage.withDelegateLock { state in
        state.callableRefMetadataByValue.removeAll(keepingCapacity: false)
    }
}

func performMarkAndSweepLocked(state: inout GCState, threadLocalValues: [UInt: [ObjectIdentifier: Int]] = [:]) {
    guard !state.heapObjects.isEmpty else {
        return
    }

    var worklist: [UnsafeMutableRawPointer] = []
    worklist.reserveCapacity(state.heapObjects.count)
    collectRootPointersLocked(state: state, threadLocalValues: threadLocalValues, into: &worklist)

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
        appendObjectChildrenLocked(of: object, into: &worklist)
    }

    var survivors: [UInt: HeapObjectRecord] = [:]
    survivors.reserveCapacity(state.heapObjects.count)
    for (key, object) in state.heapObjects {
        let header = object.pointer.assumingMemoryBound(to: KKObjHeader.self)
        if (header.pointee.flags & kkObjMarkFlag) != 0 {
            header.pointee.flags &= ~kkObjMarkFlag
            survivors[key] = object
        } else {
            removeRuntimeObjectMetadata(forObjectKey: key)
            object.pointer.deallocate()
        }
    }
    state.heapObjects = survivors
}

func collectRootPointersLocked(state: GCState, threadLocalValues: [UInt: [ObjectIdentifier: Int]], into worklist: inout [UnsafeMutableRawPointer]) {
    for slotAddress in state.globalRootSlots {
        guard let slot = UnsafeMutablePointer<UnsafeMutableRawPointer?>(bitPattern: slotAddress),
              let value = slot.pointee
        else {
            continue
        }
        worklist.append(value)
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
            }
        }
    }

    for root in state.coroutineRoots {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: root) else {
            continue
        }
        worklist.append(ptr)
    }

    for pinned in state.pinnedObjects {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: pinned) else {
            continue
        }
        worklist.append(ptr)
    }

    for threadValues in threadLocalValues.values {
        for raw in threadValues.values {
            guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
                continue
            }
            worklist.append(ptr)
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
