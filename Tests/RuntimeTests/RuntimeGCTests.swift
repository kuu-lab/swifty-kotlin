@testable import Runtime
import Dispatch
import Foundation
import RuntimeABI
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private final class ConcurrentFrameSlot: @unchecked Sendable {
    let pointer: UnsafeMutablePointer<UnsafeMutableRawPointer?>

    init(_ value: UnsafeMutableRawPointer?) {
        pointer = .allocate(capacity: 1)
        pointer.initialize(to: value)
    }

    deinit {
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }
}

private final class ConcurrentParkerHolder: @unchecked Sendable {
    var parker: RuntimeAtomicfuParker?
}

private final class ConcurrentStdioProbe: @unchecked Sendable {
    let stream: RuntimeStdioInputStreamBox
    init(_ stream: RuntimeStdioInputStreamBox) { self.stream = stream }
}

private final class ConcurrentArrayViewProbe: @unchecked Sendable {
    let box: RuntimeArrayBox
    private let lock = NSLock()
    private var mismatches = 0
    private var viewRaw = 0

    init(_ box: RuntimeArrayBox) { self.box = box }
    func recordMismatch() {
        lock.lock()
        mismatches += 1
        lock.unlock()
    }
    func recordView(_ raw: Int) {
        lock.lock()
        viewRaw = raw
        lock.unlock()
    }
    func snapshot() -> (Int, Int) {
        lock.lock()
        defer { lock.unlock() }
        return (mismatches, viewRaw)
    }
}

private func waitUntil(_ predicate: () -> Bool, timeout: TimeInterval = 5) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !predicate() {
        if Date() >= deadline { return false }
        Thread.sleep(forTimeInterval: 0.001)
    }
    return true
}

private struct FrameMapDescriptorC {
    let rootCount: UInt32
    let rootOffsets: UnsafePointer<Int32>?
}

private struct ObjHeaderProbe {
    let typeInfo: UnsafePointer<KTypeInfo>?
    let flags: UInt32
    let size: UInt32
}

private func withTestTypeInfo(
    fieldOffsets: [UInt32],
    body: (UnsafePointer<KTypeInfo>) -> Void
) {
    let typeName = Array("Test.Type\0".utf8).map(CChar.init)
    let offsetStorage = fieldOffsets.isEmpty ? [UInt32(0)] : fieldOffsets
    var emptyVtableEntry = UnsafeRawPointer(bitPattern: 0x1)!

    typeName.withUnsafeBufferPointer { nameBuffer in
        offsetStorage.withUnsafeBufferPointer { offsetBuffer in
            withUnsafePointer(to: &emptyVtableEntry) { vtablePointer in
                var typeInfo = KTypeInfo(
                    fqName: nameBuffer.baseAddress!,
                    instanceSize: 0,
                    fieldCount: UInt32(fieldOffsets.count),
                    fieldOffsets: offsetBuffer.baseAddress!,
                    vtableSize: 0,
                    vtable: vtablePointer,
                    itable: nil,
                    gcDescriptor: nil
                )
                withUnsafePointer(to: &typeInfo, body)
            }
        }
    }
}

private func withDummyTypeInfo(_ body: (UnsafeRawPointer) -> Void) {
    withTestTypeInfo(fieldOffsets: []) { typeInfoPtr in
        body(UnsafeRawPointer(typeInfoPtr))
    }
}

private func waitForGCRequest(timeout: TimeInterval = 5) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !runtimeGCSafepoints.collectionRequested {
        if Date() >= deadline { return false }
        Thread.sleep(forTimeInterval: 0.001)
    }
    return true
}

private func gcResultReleaseDuringMap(
    _ capture: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let slots = UnsafeMutablePointer<Int>(bitPattern: capture) else { return 0 }
    outThrown?.pointee = 0
    _ = kk_object_release(slots[0])
    kk_gc_collect()
    return kk_weak_ref_get(slots[1]) == value ? 1 : 0
}

private func gcTestGeneratedSuspendEntry(
    _ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else { return 0 }
    let value = Int(state.functionID)
    let isFailure = state.label != 0
    kk_gc_shadow_push()
    kk_gc_shadow_set(0, value)
    kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: value))
    let result = isFailure ? 0 : value
    let thrown = isFailure ? value : 0
    outThrown?.pointee = thrown
    kk_gc_shadow_pop(result, thrown)
    return result
}

private func gcTestWorkerProducer(_ capture: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    return capture
}

private func gcTestWorkerJob(_ capture: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = capture
    _ = value
    outThrown?.pointee = 0
    return 0
}

private func gcTestWorkerRawJob(_ value: Int) -> Int {
    _ = value
    return 0
}

private final class GCFlowProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    private var weak = 0
    private var observed = false
    private var count = 0
    private var emitCount = 0

    func configure(value: Int, weak: Int) {
        lock.lock()
        self.value = value
        self.weak = weak
        observed = false
        count = 0
        emitCount = 0
        lock.unlock()
    }

    func values() -> (Int, Int) {
        lock.lock()
        defer { lock.unlock() }
        return (value, weak)
    }

    func record(_ alive: Bool) {
        lock.lock()
        observed = alive
        lock.unlock()
    }

    func isObserved() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return observed
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    func countSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func incrementEmit() {
        lock.lock()
        emitCount += 1
        lock.unlock()
    }

    func emitCountSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return emitCount
    }
}

private let gcFlowProbe = GCFlowProbe()

private enum GCFlowTag: Int {
    case emit = 0
    case map = 1
    case filter = 2
    case take = 3
    case distinctUntilChanged = 5
    case transform = 11
    case onCompletion = 20
}

private func gcTestFlowEmitter(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    _ = kk_flow_emit(0, 1, GCFlowTag.emit.rawValue)
    return 0
}

private func gcTestFlowMap(_ closure: Int, _ input: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = closure
    _ = input
    outThrown?.pointee = 0
    let (value, _) = gcFlowProbe.values()
    kk_gc_shadow_push()
    kk_gc_shadow_set(0, value)
    kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: value))
    kk_gc_shadow_pop(value, 0)
    return value
}

private func gcTestFlowFilter(_ closure: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = closure
    outThrown?.pointee = 0
    kk_gc_shadow_push()
    kk_gc_shadow_pop(1, 0)
    kk_gc_collect()
    let (_, weak) = gcFlowProbe.values()
    gcFlowProbe.record(kk_weak_ref_get(weak) == value)
    return 1
}

private func gcTestFlowCollector(_ closure: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = closure
    outThrown?.pointee = 0
    kk_gc_collect()
    let (_, weak) = gcFlowProbe.values()
    gcFlowProbe.record(gcFlowProbe.isObserved() && kk_weak_ref_get(weak) == value)
    return 0
}

private func gcTestFlowTransform(_ input: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = input
    outThrown?.pointee = 0
    let (value, weak) = gcFlowProbe.values()
    kk_gc_shadow_push()
    kk_gc_shadow_set(0, value)
    kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: value))
    _ = kk_flow_emit(0, value, GCFlowTag.emit.rawValue)
    kk_gc_shadow_pop(0, 0)
    kk_gc_collect()
    gcFlowProbe.record(kk_weak_ref_get(weak) == value)
    return 0
}

private func gcTestFlowEmitterChecksLast(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    _ = kk_flow_emit(0, 1, GCFlowTag.emit.rawValue)
    kk_gc_shadow_push()
    kk_gc_shadow_pop(0, 0)
    kk_gc_collect()
    let (value, weak) = gcFlowProbe.values()
    gcFlowProbe.record(kk_weak_ref_get(weak) == value)
    return 0
}

private func gcTestFlowNoopCollector(_ closure: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = closure
    _ = value
    outThrown?.pointee = 0
    return 0
}

private func gcTestFlowFirstCompletion(_ closure: Int, _ cause: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = closure
    _ = cause
    let (failure, _) = gcFlowProbe.values()
    kk_gc_shadow_push()
    kk_gc_shadow_set(0, failure)
    kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: failure))
    outThrown?.pointee = failure
    kk_gc_shadow_pop(0, failure)
    return 0
}

private func gcTestFlowSecondCompletion(_ closure: Int, _ cause: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = closure
    _ = cause
    outThrown?.pointee = 0
    kk_gc_shadow_push()
    kk_gc_shadow_pop(0, 0)
    kk_gc_collect()
    let (failure, weak) = gcFlowProbe.values()
    gcFlowProbe.record(kk_weak_ref_get(weak) == failure)
    return 0
}

private func gcTestFlowMapFailure(_ closure: Int, _ input: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = closure
    _ = input
    let (failure, _) = gcFlowProbe.values()
    kk_gc_shadow_push()
    kk_gc_shadow_set(0, failure)
    kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: failure))
    outThrown?.pointee = failure
    kk_gc_shadow_pop(0, failure)
    return 0
}

private func gcTestFlowEmitterChecksFailure(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    _ = kk_flow_emit(0, 1, GCFlowTag.emit.rawValue)
    kk_gc_shadow_push()
    kk_gc_shadow_pop(0, 0)
    kk_gc_collect()
    let (failure, weak) = gcFlowProbe.values()
    gcFlowProbe.record(kk_weak_ref_get(weak) == failure)
    return 0
}

private func gcTestFlowEmitterTwice(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    _ = kk_flow_emit(0, 1, GCFlowTag.emit.rawValue)
    _ = kk_flow_emit(0, 1, GCFlowTag.emit.rawValue)
    return 0
}

private func gcTestFlowIdentityTransform(_ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    _ = kk_flow_emit(0, value, GCFlowTag.emit.rawValue)
    return 0
}

private func gcTestFlowCountingCollector(_ closure: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = closure
    _ = value
    outThrown?.pointee = 0
    gcFlowProbe.increment()
    return 0
}

private func gcTestFlowEmitterStopsOnSentinel(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    for value in 1 ... 2 {
        gcFlowProbe.incrementEmit()
        if kk_flow_emit(0, value, GCFlowTag.emit.rawValue) == __kk_flow_stopped() { break }
    }
    return 0
}

private func gcTestFlowDoubleTransform(_ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    _ = kk_flow_emit(0, value, GCFlowTag.emit.rawValue)
    _ = kk_flow_emit(0, value + 10, GCFlowTag.emit.rawValue)
    return 0
}

@Suite(.runtimeIsolation(.gcAndMetadata))
struct RuntimeGCTests {
    @Test func unattachedForeignResourceKeepsItsCaptureAlive() {
        withDummyTypeInfo { typeInfo in
            let captured = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(captured)
            let token = runtimeForeignResourceCreate(NSObject(), roots: [UInt(bitPattern: captured)])
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            runtimeForeignResourceDiscardUnattached(token)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func attachedForeignResourceCaptureFollowsHeapOwner() {
        withDummyTypeInfo { typeInfo in
            let owner = kk_alloc(16, typeInfo)
            let captured = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(captured)
            let token = runtimeForeignResourceCreate(NSObject(), roots: [UInt(bitPattern: captured)])
            #expect(runtimeForeignResourceAttach(token, owner: Int(bitPattern: owner)))
            let root = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
            root.initialize(to: owner)
            kk_register_global_root(root)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            kk_unregister_global_root(root)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            #expect(runtimeForeignResource(token, as: NSObject.self) == nil)
            root.deinitialize(count: 1)
            root.deallocate()
        }
    }

    @Test func attachedForeignResourceCaptureFollowsManagedObjectOwner() {
        withDummyTypeInfo { typeInfo in
            let owner = kk_object_new(0, 0x36_26_07)
            let captured = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(captured)
            let token = runtimeForeignResourceCreate(NSObject(), roots: [UInt(bitPattern: captured)])
            #expect(runtimeForeignResourceAttach(token, owner: owner))
            let root = ConcurrentFrameSlot(UnsafeMutableRawPointer(bitPattern: owner))
            kk_register_global_root(root.pointer)
            kk_gc_collect()
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == captured)
            kk_unregister_global_root(root.pointer)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            #expect(runtimeForeignResource(token, as: NSObject.self) == nil)
            _ = kk_object_release(weak)
        }
    }

    @Test func retainedFunctionValueKeepsManagedCaptureAlive() {
        withDummyTypeInfo { typeInfo in
            let captured = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(captured)
            let function = kk_suspend_function_create(0, captured, 0, 0)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            #expect(kk_object_release(function) == 1)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func retainedTripleKeepsAllManagedElementsAlive() {
        withDummyTypeInfo { typeInfo in
            let elements = (0 ..< 3).map { _ in Int(bitPattern: kk_alloc(16, typeInfo)) }
            let weak = elements.map(kk_weak_ref_create)
            let triple = kk_triple_new(elements[0], elements[1], elements[2])
            kk_gc_collect()
            for reference in weak {
                #expect(kk_weak_ref_get(reference) != runtimeNullSentinelInt)
            }
            #expect(kk_object_release(triple) == 1)
            kk_gc_collect()
            for reference in weak {
                #expect(kk_weak_ref_get(reference) == runtimeNullSentinelInt)
            }
        }
    }

    @Test func retainedPairKeepsBothManagedElementsAlive() {
        withDummyTypeInfo { typeInfo in
            let first = Int(bitPattern: kk_alloc(16, typeInfo))
            let second = Int(bitPattern: kk_alloc(16, typeInfo))
            let firstWeak = kk_weak_ref_create(first)
            let secondWeak = kk_weak_ref_create(second)
            let pair = kk_pair_new(first, second)
            kk_gc_collect()
            #expect(kk_weak_ref_get(firstWeak) == first)
            #expect(kk_weak_ref_get(secondWeak) == second)
            #expect(kk_object_release(pair) == 1)
            kk_gc_collect()
            #expect(kk_weak_ref_get(firstWeak) == runtimeNullSentinelInt)
            #expect(kk_weak_ref_get(secondWeak) == runtimeNullSentinelInt)
        }
    }

    @Test func retainedFutureKeepsManagedResultUntilFramedConsumerReleasesIt() {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            let future = kk_future_new()
            _ = kk_future_complete(future, value)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == value)
            kk_gc_shadow_push()
            #expect(kk_future_result(future) == value)
            #expect(kk_future_consume(future) == value)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == value)
            kk_gc_shadow_pop(0, 0)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            #expect(kk_object_release(future) == 1)
        }
    }

    @Test func nativeFutureConsumerKeepsResultUntilFutureIsReleased() {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            let future = kk_future_new()
            _ = kk_future_complete(future, value)
            #expect(kk_future_consume(future) == value)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == value)
            #expect(kk_object_release(future) == 1)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func inFlightFutureKeepsResultAfterHandleRelease() {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            let future = kk_future_new()
            _ = kk_future_complete(future, value)
            var inFlight = resolveRuntimeHandle(future, as: RuntimeFutureBox.self)
            #expect(inFlight != nil)
            #expect(kk_object_release(future) == 1)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == value)
            #expect(inFlight?.result() == value)
            inFlight = nil
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func futureResultSurvivesAnotherThreadConsumingIt() {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            let future = kk_future_new()
            _ = kk_future_complete(future, value)
            let readFinished = DispatchSemaphore(value: 0)
            let correctResult = DispatchSemaphore(value: 0)
            let finishReader = DispatchSemaphore(value: 0)
            let readerFinished = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                kk_gc_shadow_push()
                if kk_future_result(future) == value { correctResult.signal() }
                readFinished.signal()
                finishReader.wait()
                kk_gc_shadow_pop(0, 0)
                readerFinished.signal()
            }
            let read = readFinished.wait(timeout: .now() + .seconds(5))
            #expect(read == .success)
            if read == .success {
                #expect(correctResult.wait(timeout: .now() + .seconds(1)) == .success)
                kk_gc_shadow_push()
                #expect(kk_future_consume(future) == value)
                kk_gc_shadow_pop(0, 0)
                kk_gc_collect()
                #expect(kk_weak_ref_get(weak) == value)
            }
            finishReader.signal()
            #expect(readerFinished.wait(timeout: .now() + .seconds(5)) == .success)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            #expect(kk_object_release(future) == 1)
        }
    }

    @Test(arguments: [0, 1, 2])
    func completedJobKeepsManagedTerminalValueAlive(kind: Int) {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            var job: RuntimeJobHandle? = RuntimeJobHandle()
            weak var weakJob = job
            switch kind {
            case 0:
                #expect(job?.complete(with: value) == true)
            case 1:
                #expect(job?.completeExceptionally(with: value) == true)
            default:
                #expect(job?.cancel(message: "test", cause: value) == true)
            }
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == value)
            job = nil
            #expect(weakJob == nil)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func joinedValueSurvivesJobReleaseUntilCallerFrameEnds() {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            var job: RuntimeJobHandle? = RuntimeJobHandle()
            weak var weakJob = job
            #expect(job?.complete(with: value) == true)
            kk_gc_shadow_push()
            #expect(job?.join() == value)
            job = nil
            #expect(weakJob == nil)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == value)
            kk_gc_shadow_pop(0, 0)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test(arguments: [false, true])
    func deferredSnapshotSurvivesJobReleaseUntilCallerFrameEnds(isFailure: Bool) {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            var job: RuntimeJobHandle? = RuntimeJobHandle()
            let handle = registerRuntimeObject(job!)
            if isFailure {
                #expect(job?.completeExceptionally(with: value) == true)
            } else {
                #expect(job?.complete(with: value) == true)
            }
            kk_gc_shadow_push()
            var thrown = 0
            let result = __kk_deferred_get_completed(handle, &thrown)
            if isFailure {
                #expect(result == 0)
                #expect(thrown == value)
            } else {
                #expect(result == value)
                #expect(thrown == 0)
            }
            #expect(kk_object_release(handle) == 1)
            job = nil
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == value)
            kk_gc_shadow_pop(0, 0)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test(arguments: [false, true])
    func deferredTaskSnapshotSurvivesReleaseUntilCallerFrameEnds(isFailure: Bool) {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            var task: RuntimeAsyncTask? = RuntimeAsyncTask()
            let handle = registerRuntimeObject(task!)
            if isFailure {
                task?.completeExceptionally(with: value)
            } else {
                task?.complete(with: value)
            }
            kk_gc_shadow_push()
            var thrown = 0
            let result = __kk_deferred_get_completed(handle, &thrown)
            if isFailure {
                #expect(result == 0)
                #expect(thrown == value)
            } else {
                #expect(result == value)
                #expect(thrown == 0)
            }
            #expect(kk_object_release(handle) == 1)
            task = nil
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == value)
            kk_gc_shadow_pop(0, 0)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test(arguments: [false, true])
    func successfulDeferredExceptionQueryDoesNotRootResult(isTask: Bool) {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            var owner: AnyObject?
            if isTask {
                let task = RuntimeAsyncTask()
                task.complete(with: value)
                owner = task
            } else {
                let job = RuntimeJobHandle()
                #expect(job.complete(with: value))
                owner = job
            }
            let handle = registerRuntimeObject(owner!)
            kk_gc_shadow_push()
            var thrown = 0
            #expect(__kk_deferred_completion_exception(handle, &thrown) == runtimeNullSentinelInt)
            #expect(thrown == 0)
            #expect(kk_object_release(handle) == 1)
            owner = nil
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            kk_gc_shadow_pop(0, 0)
        }
    }

    @Test(arguments: [false, true])
    func suspendedContinuationKeepsAwaitedResultAfterTaskRelease(isFailure: Bool) {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            let continuation = RuntimeContinuationState(functionID: 0)
            var task: RuntimeAsyncTask? = RuntimeAsyncTask()
            weak var weakTask = task
            if case .some(.suspended) = task?.awaitResult(callerState: continuation) {
                // Completion will resume the continuation through the registered callback.
            } else {
                Issue.record("The incomplete task must suspend the awaiting continuation")
            }
            if isFailure {
                task?.completeExceptionally(with: value)
            } else {
                task?.complete(with: value)
            }
            task = nil
            #expect(weakTask == nil)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == value)
            if isFailure {
                #expect(continuation.thrownException == value)
                continuation.thrownException = 0
            } else {
                #expect(continuation.completion == Int64(value))
                continuation.completion = 0
            }
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func continuationKeepsSpilledAndLauncherValuesUntilCleared() {
        withDummyTypeInfo { typeInfo in
            let spilled = Int(bitPattern: kk_alloc(16, typeInfo))
            let argument = Int(bitPattern: kk_alloc(16, typeInfo))
            let spilledWeak = kk_weak_ref_create(spilled)
            let argumentWeak = kk_weak_ref_create(argument)
            let continuation = RuntimeContinuationState(functionID: 0)
            continuation.setSpillSlot(3, value: Int64(spilled))
            continuation.setLauncherArg(4, value: Int64(argument))
            kk_gc_collect()
            #expect(kk_weak_ref_get(spilledWeak) == spilled)
            #expect(kk_weak_ref_get(argumentWeak) == argument)
            continuation.clearSpillSlots()
            continuation.setLauncherArg(4, value: 0)
            kk_gc_collect()
            #expect(kk_weak_ref_get(spilledWeak) == runtimeNullSentinelInt)
            #expect(kk_weak_ref_get(argumentWeak) == runtimeNullSentinelInt)
        }
    }

    @Test func continuationArgumentSnapshotSurvivesSourceUpdates() {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            let source = RuntimeContinuationState(functionID: 0)
            let destination = RuntimeContinuationState(functionID: 0)
            source.setLauncherArg(0, value: Int64(value))
            source.withRetainedLauncherArgs { args in
                source.replaceLauncherArgs([:])
                kk_gc_collect()
                #expect(kk_weak_ref_get(weak) == value)
                destination.replaceLauncherArgs(args)
            }
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == value)
            destination.replaceLauncherArgs([:])
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test(arguments: [false, true])
    func suspendEntryKeepsGeneratedReturnDuringNativeCompletion(isFailure: Bool) {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: value))
            let continuation = kk_coroutine_continuation_new(value)
            runtimeContinuationState(from: continuation)?.label = isFailure ? 1 : 0
            let entry = unsafeBitCast(
                gcTestGeneratedSuspendEntry as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
                to: Int.self
            )
            let callbackEntered = DispatchSemaphore(value: 0)
            let releaseCallback = DispatchSemaphore(value: 0)
            let workerFinished = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                _ = runSuspendEntryLoopWithContinuation(
                    entryPointRaw: entry,
                    continuation: continuation,
                    onCompletion: { result, thrown in
                        #expect((isFailure ? thrown : result) == value)
                        callbackEntered.signal()
                        releaseCallback.wait()
                    }
                )
                workerFinished.signal()
            }
            let entered = callbackEntered.wait(timeout: .now() + .seconds(5)) == .success
            #expect(entered)
            if entered {
                kk_gc_collect()
                #expect(kk_weak_ref_get(weak) == value)
            }
            releaseCallback.signal()
            let finished = workerFinished.wait(timeout: .now() + .seconds(5)) == .success
            #expect(finished)
            if !finished { workerFinished.wait() }
            _ = kk_coroutine_state_exit(continuation, 0)
        }
    }

    @Test(arguments: [0, 1, 2])
    func queuedWorkerArgumentsStayAliveUntilExecution(mode: Int) {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let capture = Int(bitPattern: kk_alloc(16, typeInfo))
            let valueWeak = kk_weak_ref_create(value)
            let captureWeak = kk_weak_ref_create(capture)
            kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: value))
            kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: capture))
            let handle = kk_worker_new(0)
            guard let worker = resolveRuntimeHandle(handle, as: RuntimeWorkerBox.self) else {
                Issue.record("Worker handle was not registered")
                return
            }
            let blockerStarted = DispatchSemaphore(value: 0)
            let unblock = DispatchSemaphore(value: 0)
            #expect(worker.execute {
                blockerStarted.signal()
                unblock.wait()
            })
            let started = blockerStarted.wait(timeout: .now() + .seconds(5)) == .success
            #expect(started)
            var future = 0
            var futureProtected = true
            if started {
                switch mode {
                case 0:
                    let callback = unsafeBitCast(
                        gcTestWorkerProducer as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
                        to: Int.self
                    )
                    #expect(kk_worker_execute_after(handle, 0, callback, capture) == 1)
                case 1:
                    let producer = unsafeBitCast(
                        gcTestWorkerProducer as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
                        to: Int.self
                    )
                    let job = unsafeBitCast(
                        gcTestWorkerJob as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int,
                        to: Int.self
                    )
                    future = kk_worker_execute(handle, 0, producer, value, job, capture)
                    #expect(future != 0)
                default:
                    let job = unsafeBitCast(gcTestWorkerRawJob as @convention(c) (Int) -> Int, to: Int.self)
                    future = __kk_native_concurrent_execute_impl(handle, 0, value, job)
                    #expect(future != 0)
                }
                kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: value))
                kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: capture))
                kk_gc_collect()
                if mode != 0 { #expect(kk_weak_ref_get(valueWeak) == value) }
                if mode != 2 { #expect(kk_weak_ref_get(captureWeak) == capture) }
                if future != 0 {
                    futureProtected = kk_object_release(future) == 0
                    #expect(futureProtected)
                }
                // Queued native callbacks have not published a frame yet.
                let canReset = runtimeWithQuiescentGCFrames {}
                #expect(!canReset)
                if !canReset { #expect(!kk_runtime_reset_gc()) }
            }
            unblock.signal()
            worker.requestTermination(processScheduled: true)
            #expect(waitUntil { runtimeWithQuiescentGCFrames {} })
            kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: value))
            kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: capture))
            kk_gc_collect()
            #expect(kk_weak_ref_get(valueWeak) == runtimeNullSentinelInt)
            #expect(kk_weak_ref_get(captureWeak) == runtimeNullSentinelInt)
            if future != 0, futureProtected { #expect(kk_object_release(future) == 1) }
            _ = kk_worker_request_termination(handle, 0)
            _ = kk_object_release(handle)
        }
    }

    @Test func queuedNativeRootsReleasePinsBeforeTheResetLease() {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let key = UInt(bitPattern: value)
            let roots = RuntimeQueuedGCRoots([value, value])
            #expect(runtimeStorage.withGCLock { $0.pinnedObjectCounts[key] } == 2)
            #expect(!kk_runtime_reset_gc())
            DispatchQueue.concurrentPerform(iterations: 8) { _ in roots.finish() }
            #expect(runtimeStorage.withGCLock { $0.pinnedObjectCounts[key] } == nil)

            var nextPin: RuntimeForeignCallbackPin? = RuntimeForeignCallbackPin(root: value)
            roots.finish()
            #expect(runtimeStorage.withGCLock { $0.pinnedObjectCounts[key] } == 1)
            nextPin?.finish()
            let newestPin = RuntimeForeignCallbackPin(root: value)
            nextPin = nil
            #expect(runtimeStorage.withGCLock { $0.pinnedObjectCounts[key] } == 1)
            newestPin.finish()
            #expect(runtimeStorage.withGCLock { $0.pinnedObjectCounts[key] } == nil)
            #expect(kk_runtime_reset_gc())
        }
    }

    @Test func rejectedWorkerSubmissionsReleaseQueuedRoots() {
        let handle = kk_worker_new(0)
        let termination = kk_worker_request_termination(handle, 0)
        let producer = unsafeBitCast(
            gcTestWorkerProducer as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let job = unsafeBitCast(
            gcTestWorkerJob as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let rawJob = unsafeBitCast(gcTestWorkerRawJob as @convention(c) (Int) -> Int, to: Int.self)
        #expect(kk_worker_execute(handle, 0, producer, 0, job, 0) == 0)
        #expect(__kk_native_concurrent_execute_impl(handle, 0, 0, rawJob) == 0)
        #expect(kk_worker_execute_after(handle, 0, producer, 0) == 0)
        #expect(runtimeWithQuiescentGCFrames {})
        _ = kk_object_release(termination)
        _ = kk_object_release(handle)
    }

    @Test func bufferedChannelKeepsValueThroughReceiveHandoff() {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            let channel = RuntimeChannelHandle(capacity: 1)
            #expect(channel.trySend(value) == .success)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == value)
            kk_gc_shadow_push()
            var received = 0
            #expect(channel.tryReceive(outValue: &received) == .success)
            #expect(received == value)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == value)
            kk_gc_shadow_pop(0, 0)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func channelCanReleaseItsOwnBufferedHandle() {
        let channel = kk_channel_create(1)
        #expect(kk_channel_try_send(channel, channel) == kChannelResultSuccess)
        #expect(kk_object_release(channel) == 1)
    }

    @Test(arguments: [true, false])
    func resultKeepsManagedPayloadOnlyWhileRooted(isSuccess: Bool) {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            let result = isSuccess ? runtimeResultSuccess(value) : runtimeResultFailure(value)
            kk_gc_shadow_push()
            kk_gc_shadow_set(0, result)
            kk_gc_collect()
            #expect(runtimeStorage.withGCLock { $0.heapObjects[UInt(bitPattern: value)] != nil })
            kk_gc_shadow_set(0, 0)
            kk_gc_collect()
            #expect(runtimeStorage.withGCLock { $0.tracedObjectReferences[UInt(bitPattern: result)] == nil })
            #expect(runtimeStorage.withGCLock { $0.tracedResultGenerations[UInt(bitPattern: result)] == nil })
            kk_gc_shadow_pop(0, 0)
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            #expect(kk_object_release(result) == 1)
        }
    }

    @Test(arguments: [true, false])
    func nestedResultKeepsOrdinaryObjectOnlyWhileRooted(isSuccess: Bool) {
        let value = kk_object_new(0, 0x36_26_08)
        let weak = kk_weak_ref_create(value)
        let inner = isSuccess ? runtimeResultSuccess(value) : runtimeResultFailure(value)
        let outer = runtimeResultSuccess(inner)
        kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: outer))
        kk_gc_collect() // Consume the allocation handoff.
        kk_gc_collect()
        #expect(kk_weak_ref_get(weak) == value)
        kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: outer))
        kk_gc_collect()
        #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        #expect(kk_object_release(outer) == 1)
        #expect(kk_object_release(inner) == 1)
        _ = kk_object_release(weak)
    }

    @Test func resultAccessKeepsOrdinaryObjectAfterOwnerRelease() {
        let value = kk_object_new(0, 0x36_26_09)
        let weak = kk_weak_ref_create(value)
        let result = runtimeResultSuccess(value)
        var access = runtimeResultAccessFromRaw(result)
        #expect(access != nil)
        #expect(kk_object_release(result) == 1)
        kk_gc_collect() // Consume the allocation handoff.
        kk_gc_collect()
        #expect(kk_weak_ref_get(weak) == value)
        withExtendedLifetime(access) {}
        access = nil
        kk_gc_collect()
        #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        _ = kk_object_release(weak)
    }

    @Test func nestedResultsTraceManagedPayloadOnlyWhileRooted() {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            var results: [Int] = []
            var current = value
            for _ in 0 ..< 32 {
                current = runtimeResultSuccess(current)
                results.append(current)
            }
            kk_gc_shadow_push()
            kk_gc_shadow_set(0, current)
            kk_gc_collect()
            #expect(runtimeStorage.withGCLock { $0.heapObjects[UInt(bitPattern: value)] != nil })
            kk_gc_shadow_set(0, 0)
            kk_gc_collect()
            #expect(runtimeStorage.withGCLock { state in
                results.allSatisfy { result in
                    state.tracedObjectReferences[UInt(bitPattern: result)] == nil &&
                        state.tracedResultGenerations[UInt(bitPattern: result)] == nil
                }
            })
            kk_gc_shadow_pop(0, 0)
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            for result in results.reversed() {
                #expect(kk_object_release(result) == 1)
            }
        }
    }

    @Test func sharedResultPayloadSurvivesUntilLastParentRootIsCleared() {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            let inner = runtimeResultSuccess(value)
            let first = runtimeResultSuccess(inner)
            let second = runtimeResultSuccess(inner)
            kk_gc_shadow_push()
            kk_gc_shadow_set(0, first)
            kk_gc_shadow_set(1, second)
            kk_gc_collect()
            kk_gc_shadow_set(0, 0)
            kk_gc_collect()
            #expect(runtimeStorage.withGCLock { $0.heapObjects[UInt(bitPattern: value)] != nil })
            kk_gc_shadow_set(1, 0)
            kk_gc_collect()
            kk_gc_shadow_pop(0, 0)
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            #expect(kk_object_release(first) == 1)
            #expect(kk_object_release(second) == 1)
            #expect(kk_object_release(inner) == 1)
        }
    }

    @Test func resultPayloadSurvivesOwnerReleaseDuringMapCallback() {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            let result = runtimeResultSuccess(value)
            var capture = [result, weak]
            let callback = unsafeBitCast(
                gcResultReleaseDuringMap as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int,
                to: Int.self
            )
            var thrown = 0
            let mapped = capture.withUnsafeMutableBufferPointer { slots in
                runtimeResultMap(result, callback, Int(bitPattern: slots.baseAddress!), &thrown)
            }
            #expect(thrown == 0)
            #expect(runtimeResultGetOrThrow(mapped, &thrown) == 1)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            #expect(kk_object_release(mapped) == 1)
        }
    }

    @Test(arguments: [true, false])
    func resultAccessProtectsContinuationUntilPayloadIsPublished(isSuccess: Bool) {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            let result = isSuccess ? runtimeResultSuccess(value) : runtimeResultFailure(value)
            var access = runtimeResultAccessFromRaw(result)
            #expect(access != nil)
            #expect(kk_object_release(result) == 1)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == value)
            let continuation = RuntimeContinuationState(functionID: 0)
            if isSuccess {
                #expect(continuation.resume(with: access?.box.value ?? 0) == nil)
            } else {
                #expect(continuation.resume(withException: access?.box.exception ?? 0) == nil)
            }
            access = nil
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == value)
            if isSuccess {
                continuation.completion = 0
            } else {
                continuation.thrownException = 0
            }
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test(arguments: [true, false])
    func cancellableContinuationKeepsPendingResultUntilDelivery(isSuccess: Bool) {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            var continuation: RuntimeCancellableContinuation? = RuntimeCancellableContinuation(delegate: 0)
            if isSuccess {
                continuation?.resume(value: value, onCancellation: {})
            } else {
                continuation?.resume(failure: value)
            }
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == value)
            var thrown = 0
            let delivered = continuation?.getResult(&thrown) ?? 0
            #expect(isSuccess ? delivered == value : thrown == value)
            continuation = nil
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func reversedMapValuesViewTracesItsBackingMap() {
        let map = registerRuntimeObject(RuntimeMapBox(keys: [1], values: [2]))
        let values = RuntimeListBox(mapValuesOf: map)
        let valuesHandle = registerRuntimeObject(values)
        let reversed = RuntimeListBox(reversedViewOf: values)
        #expect(Set(reversed.childRefs) == Set([valuesHandle, map]))
        let slice = RuntimeListBox(subListOf: reversed, fromIndex: 0, toIndex: 1)
        #expect(Set(slice.childRefs).isSuperset(of: [valuesHandle, map]))
        let reversedHandle = registerRuntimeObject(reversed)
        _ = kk_freeze_object(reversedHandle)
        #expect(kk_is_frozen(valuesHandle) == 1)
        #expect(kk_is_frozen(map) == 1)
        #expect(kk_object_release(reversedHandle) == 1)
        #expect(kk_object_release(valuesHandle) == 1)
        #expect(kk_object_release(map) == 1)
    }

    @Test func collectingReversedMapValuesViewKeepsItsElement() {
        let managed = kk_object_new(0, 1)
        let weak = kk_weak_ref_create(managed)
        let map = registerRuntimeObject(RuntimeMapBox(keys: [1], values: [managed]))
        let values = RuntimeListBox(mapValuesOf: map)
        let reversed = registerRuntimeObject(RuntimeListBox(reversedViewOf: values))
        kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: reversed))
        kk_gc_collect()
        #expect(kk_weak_ref_get(weak) == managed)
        kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: reversed))
        #expect(kk_object_release(reversed) == 1)
        #expect(kk_object_release(map) == 1)
        #expect(kk_object_release(managed) == 1)
    }

    @Test func freezingViewSkipsUnregisteredIntermediateHandle() {
        let map = registerRuntimeObject(RuntimeMapBox(keys: [1], values: [2]))
        let intermediate = RuntimeListBox(mapValuesOf: map)
        let intermediateRaw = Int(bitPattern: Unmanaged.passUnretained(intermediate).toOpaque())
        let reversed = registerRuntimeObject(RuntimeListBox(reversedViewOf: intermediate))
        _ = kk_freeze_object(reversed)
        #expect(kk_is_frozen(intermediateRaw) == 0)
        #expect(kk_is_frozen(map) == 1)
        #expect(kk_object_release(reversed) == 1)
        #expect(kk_object_release(map) == 1)
    }

    @Test func sweptHeapObjectDoesNotLeaveFrozenAddressBehind() {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            _ = kk_freeze_object(value)
            #expect(kk_is_frozen(value) == 1)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            #expect(kk_is_frozen(value) == 0)
        }
    }

    @Test func sortedMapRangeTracesBackingMapAndOutOfRangeValues() {
        let outside = kk_object_new(0, 1)
        let base = RuntimeMapBox(keys: [0, 2], values: [outside, 7])
        base.enableSorted(comparatorRaw: 0)
        let baseHandle = registerRuntimeObject(base)
        let range = RuntimeSortedRange(lowerBoundRaw: 1, upperBoundRaw: 3)
        let view = RuntimeMapBox(rangeViewOf: base, range: range)
        #expect(view.childRefs.contains(baseHandle))
        #expect(view.childRefs.contains(outside))
        let viewHandle = registerRuntimeObject(view)
        _ = kk_freeze_object(viewHandle)
        #expect(kk_is_frozen(baseHandle) == 1)
        #expect(kk_object_release(viewHandle) == 1)
        #expect(kk_object_release(baseHandle) == 1)
        #expect(kk_object_release(outside) == 1)
    }

    @Test func mapKeySetViewTracesItsBackingMap() {
        let map = registerRuntimeObject(RuntimeMapBox(keys: [1], values: [2]))
        let keys = RuntimeSetBox(mapKeysOf: map)
        #expect(keys.childRefs.contains(map))
        #expect(kk_object_release(map) == 1)
    }

    @Test func deeplyNestedCollectionViewsEnumerateWithoutRecursion() {
        let depth = 3_000
        var lists = [RuntimeListBox(elements: [1])]
        var maps = [RuntimeMapBox(keys: [1], values: [2])]
        var sets = [RuntimeSetBox(elements: [1])]
        for _ in 0 ..< depth {
            lists.append(RuntimeListBox(reversedViewOf: lists.last!))
            maps.append(RuntimeMapBox(descendingViewOf: maps.last!))
            sets.append(RuntimeSetBox(descendingViewOf: sets.last!))
        }
        #expect(lists.last?.childRefs.count == depth + 1)
        #expect(maps.last?.childRefs.count == depth + 2)
        #expect(sets.last?.childRefs.count == depth + 1)
        while !lists.isEmpty { lists.removeLast() }
        while !maps.isEmpty { maps.removeLast() }
        while !sets.isEmpty { sets.removeLast() }
    }

    @Test func channelResultKeepsReceivedValueUntilRelease() {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            let channel = kk_channel_create(1)
            #expect(kk_channel_try_send(channel, value) == kChannelResultSuccess)
            let result = __kk_channel_try_receive(channel)
            #expect(kk_object_release(channel) == 1)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == value)
            #expect(__kk_channel_result_value_or_null(result) == value)
            #expect(kk_object_release(result) == 1)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func channelKeepsCloseCauseForItsLifetime() {
        withDummyTypeInfo { typeInfo in
            let cause = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(cause)
            var channel: RuntimeChannelHandle? = RuntimeChannelHandle(capacity: 0)
            #expect(channel?.close(cause: cause) == true)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == cause)
            #expect(channel?.closeCauseSnapshot() == cause)
            channel = nil
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func channelCloseHandlerKeepsItsCaptureUntilInvocation() {
        withDummyTypeInfo { typeInfo in
            let capture = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(capture)
            let channel = RuntimeChannelHandle(capacity: 0)
            let callback = unsafeBitCast(
                gcTestWorkerJob as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int,
                to: Int.self
            )
            #expect(channel.addCloseHandler(fnPtr: callback, closureRaw: capture))
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == capture)
            #expect(channel.close())
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func channelIteratorKeepsPeekedValueUntilNext() {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            let channel = kk_channel_create(1)
            #expect(kk_channel_try_send(channel, value) == kChannelResultSuccess)
            let iterator = kk_channel_iterator(channel)
            #expect(kk_channel_iterator_hasNext(iterator) == 1)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == value)
            kk_gc_shadow_push()
            #expect(kk_channel_iterator_next(iterator) == value)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == value)
            kk_gc_shadow_pop(0, 0)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            #expect(kk_object_release(iterator) == 1)
            #expect(kk_object_release(channel) == 1)
        }
    }

    @Test func coroutineAndFutureMirrorsIncludeOrdinaryObjects() {
        let object = kk_object_new(0, 1)
        let key = UInt(bitPattern: object)
        let continuation = RuntimeContinuationState(functionID: 0)
        continuation.setLauncherArg(0, value: Int64(object))
        let future = kk_future_new()
        _ = kk_future_complete(future, object)
        #expect(kk_future_is_ready(future) == 1)
        let tracked = runtimeStorage.withGCLock { state in
            (
                state.retainedCoroutineHeapFields.values.contains { $0.storage != nil && $0.fields.values.contains(key) },
                state.retainedFutureHeapFields.values.contains { $0.storage != nil && $0.fields.values.contains(key) }
            )
        }
        #expect(tracked.0)
        #expect(tracked.1)
        #expect(kk_object_release(future) == 1)
        continuation.replaceLauncherArgs([:])
        #expect(kk_object_release(object) == 1)
    }

    @Test func flowMapResultSurvivesNextCallbackAndCollection() {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            gcFlowProbe.configure(value: value, weak: weak)
            kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: value))
            let emitter = unsafeBitCast(
                gcTestFlowEmitter as @convention(c) (UnsafeMutablePointer<Int>?) -> Int,
                to: Int.self
            )
            let map = unsafeBitCast(
                gcTestFlowMap as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int,
                to: Int.self
            )
            let filter = unsafeBitCast(
                gcTestFlowFilter as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int,
                to: Int.self
            )
            let collector = unsafeBitCast(
                gcTestFlowCollector as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int,
                to: Int.self
            )
            let source = kk_flow_create(emitter, 0)
            let mapped = kk_flow_emit(source, map, GCFlowTag.map.rawValue)
            let filtered = kk_flow_emit(mapped, filter, GCFlowTag.filter.rawValue)
            _ = kk_flow_collect(filtered, collector, 0, 0)
            #expect(gcFlowProbe.isObserved())
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            _ = __kk_flow_release(filtered)
            _ = __kk_flow_release(mapped)
            _ = __kk_flow_release(source)
        }
    }

    @Test func flowTransformKeepsEmittedValueDuringCallback() {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            gcFlowProbe.configure(value: value, weak: weak)
            kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: value))
            let emitter = unsafeBitCast(
                gcTestFlowEmitter as @convention(c) (UnsafeMutablePointer<Int>?) -> Int,
                to: Int.self
            )
            let transform = unsafeBitCast(
                gcTestFlowTransform as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
                to: Int.self
            )
            let collector = unsafeBitCast(
                gcTestFlowCollector as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int,
                to: Int.self
            )
            let source = kk_flow_create(emitter, 0)
            let transformed = kk_flow_emit(source, transform, GCFlowTag.transform.rawValue)
            _ = kk_flow_collect(transformed, collector, 0, 0)
            #expect(gcFlowProbe.isObserved())
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            _ = __kk_flow_release(transformed)
            _ = __kk_flow_release(source)
        }
    }

    @Test func flowDistinctKeepsPreviousValueAcrossEmissions() {
        withDummyTypeInfo { typeInfo in
            let value = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(value)
            gcFlowProbe.configure(value: value, weak: weak)
            kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: value))
            let emitter = unsafeBitCast(
                gcTestFlowEmitterChecksLast as @convention(c) (UnsafeMutablePointer<Int>?) -> Int,
                to: Int.self
            )
            let map = unsafeBitCast(
                gcTestFlowMap as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int,
                to: Int.self
            )
            let collector = unsafeBitCast(
                gcTestFlowNoopCollector as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int,
                to: Int.self
            )
            let source = kk_flow_create(emitter, 0)
            let mapped = kk_flow_emit(source, map, GCFlowTag.map.rawValue)
            let distinct = kk_flow_emit(mapped, 0, GCFlowTag.distinctUntilChanged.rawValue)
            _ = kk_flow_collect(distinct, collector, 0, 0)
            #expect(gcFlowProbe.isObserved())
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            _ = __kk_flow_release(distinct)
            _ = __kk_flow_release(mapped)
            _ = __kk_flow_release(source)
        }
    }

    @Test func flowKeepsFirstCompletionFailureDuringLaterHandler() {
        withDummyTypeInfo { typeInfo in
            let failure = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(failure)
            gcFlowProbe.configure(value: failure, weak: weak)
            kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: failure))
            let emitter = unsafeBitCast(
                gcTestFlowEmitter as @convention(c) (UnsafeMutablePointer<Int>?) -> Int,
                to: Int.self
            )
            let first = unsafeBitCast(
                gcTestFlowFirstCompletion as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int,
                to: Int.self
            )
            let second = unsafeBitCast(
                gcTestFlowSecondCompletion as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int,
                to: Int.self
            )
            let collector = unsafeBitCast(
                gcTestFlowNoopCollector as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int,
                to: Int.self
            )
            let source = kk_flow_create(emitter, 0)
            let firstStage = kk_flow_emit(source, first, GCFlowTag.onCompletion.rawValue)
            let secondStage = kk_flow_emit(firstStage, second, GCFlowTag.onCompletion.rawValue)
            var thrown = 0
            #expect(kk_flow_collect(secondStage, collector, 0, 0, &thrown) == failure)
            #expect(thrown == failure)
            #expect(gcFlowProbe.isObserved())
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            _ = __kk_flow_release(secondStage)
            _ = __kk_flow_release(firstStage)
            _ = __kk_flow_release(source)
        }
    }

    @Test func flowKeepsStreamingFailureUntilEmitterReturns() {
        withDummyTypeInfo { typeInfo in
            let failure = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(failure)
            gcFlowProbe.configure(value: failure, weak: weak)
            kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: failure))
            let emitter = unsafeBitCast(
                gcTestFlowEmitterChecksFailure as @convention(c) (UnsafeMutablePointer<Int>?) -> Int,
                to: Int.self
            )
            let map = unsafeBitCast(
                gcTestFlowMapFailure as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int,
                to: Int.self
            )
            let collector = unsafeBitCast(
                gcTestFlowNoopCollector as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int,
                to: Int.self
            )
            let source = kk_flow_create(emitter, 0)
            let mapped = kk_flow_emit(source, map, GCFlowTag.map.rawValue)
            var thrown = 0
            #expect(kk_flow_collect(mapped, collector, 0, 0, &thrown) == failure)
            #expect(thrown == failure)
            #expect(gcFlowProbe.isObserved())
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            _ = __kk_flow_release(mapped)
            _ = __kk_flow_release(source)
        }
    }

    @Test func flowDistinctBeforeTransformKeepsStateAcrossEmissions() {
        gcFlowProbe.configure(value: 0, weak: 0)
        let emitter = unsafeBitCast(
            gcTestFlowEmitterTwice as @convention(c) (UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let transform = unsafeBitCast(
            gcTestFlowIdentityTransform as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let collector = unsafeBitCast(
            gcTestFlowCountingCollector as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let source = kk_flow_create(emitter, 0)
        let distinct = kk_flow_emit(source, 0, GCFlowTag.distinctUntilChanged.rawValue)
        let transformed = kk_flow_emit(distinct, transform, GCFlowTag.transform.rawValue)
        _ = kk_flow_collect(transformed, collector, 0, 0)
        #expect(gcFlowProbe.countSnapshot() == 1)
        _ = __kk_flow_release(transformed)
        _ = __kk_flow_release(distinct)
        _ = __kk_flow_release(source)
    }

    @Test(arguments: [0, 1, 2, 3])
    func flowTakeStopsUpstreamAroundTransform(mode: Int) {
        gcFlowProbe.configure(value: 0, weak: 0)
        let emitter = unsafeBitCast(
            gcTestFlowEmitterStopsOnSentinel as @convention(c) (UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let transform = mode >= 2
            ? unsafeBitCast(gcTestFlowDoubleTransform as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
            : unsafeBitCast(gcTestFlowIdentityTransform as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int, to: Int.self)
        let collector = unsafeBitCast(
            gcTestFlowCountingCollector as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let source = kk_flow_create(emitter, 0)
        let first = mode == 1
            ? kk_flow_emit(source, transform, GCFlowTag.transform.rawValue)
            : kk_flow_emit(source, mode == 3 ? 5 : 1, GCFlowTag.take.rawValue)
        let second = mode == 1
            ? kk_flow_emit(first, 1, GCFlowTag.take.rawValue)
            : kk_flow_emit(first, transform, GCFlowTag.transform.rawValue)
        let last = mode == 3 ? kk_flow_emit(second, 2, GCFlowTag.take.rawValue) : second
        _ = kk_flow_collect(last, collector, 0, 0)
        #expect(gcFlowProbe.emitCountSnapshot() == 1)
        #expect(gcFlowProbe.countSnapshot() == (mode >= 2 ? 2 : 1))
        if mode == 3 { _ = __kk_flow_release(last) }
        _ = __kk_flow_release(second)
        _ = __kk_flow_release(first)
        _ = __kk_flow_release(source)
    }

    @Test func collectorRunsWhileWorkerDrainsItsQueue() {
        let worker = RuntimeWorkerBox(name: nil)
        let jobStarted = DispatchSemaphore(value: 0)
        let releaseJob = DispatchSemaphore(value: 0)
        let terminatorStarted = DispatchSemaphore(value: 0)
        let terminatorDone = DispatchSemaphore(value: 0)
        let collectorDone = DispatchSemaphore(value: 0)
        #expect(worker.execute {
            jobStarted.signal()
            releaseJob.wait()
        })
        #expect(jobStarted.wait(timeout: .now() + .seconds(5)) == .success)
        DispatchQueue.global().async {
            runtimeGCSafepoints.enter()
            terminatorStarted.signal()
            worker.requestTermination(processScheduled: true)
            runtimeGCSafepoints.leave()
            terminatorDone.signal()
        }
        #expect(terminatorStarted.wait(timeout: .now() + .seconds(5)) == .success)
        #expect(waitUntil { worker.isTerminated })
        DispatchQueue.global().async {
            kk_gc_collect()
            collectorDone.signal()
        }
        let collectedWhileBlocked = collectorDone.wait(timeout: .now() + .seconds(1)) == .success
        #expect(collectedWhileBlocked)
        releaseJob.signal()
        if !collectedWhileBlocked { #expect(collectorDone.wait(timeout: .now() + .seconds(5)) == .success) }
        #expect(terminatorDone.wait(timeout: .now() + .seconds(5)) == .success)
    }

    @Test func concurrentContinuationSlotUpdatesKeepBothValues() {
        withDummyTypeInfo { typeInfo in
            let first = Int(bitPattern: kk_alloc(16, typeInfo))
            let second = Int(bitPattern: kk_alloc(16, typeInfo))
            let firstWeak = kk_weak_ref_create(first)
            let secondWeak = kk_weak_ref_create(second)
            let continuation = RuntimeContinuationState(functionID: 0)
            kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: first))
            kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: second))
            let group = DispatchGroup()
            for (index, value) in [first, second].enumerated() {
                group.enter()
                DispatchQueue.global().async {
                    for _ in 0 ..< 100 {
                        continuation.setLauncherArg(Int64(index), value: Int64(value))
                    }
                    group.leave()
                }
            }
            let finished = group.wait(timeout: .now() + .seconds(5)) == .success
            #expect(finished)
            if !finished { group.wait() }
            kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: first))
            kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: second))
            kk_gc_collect()
            #expect(kk_weak_ref_get(firstWeak) == first)
            #expect(kk_weak_ref_get(secondWeak) == second)
            continuation.replaceLauncherArgs([:])
            kk_gc_collect()
            #expect(kk_weak_ref_get(firstWeak) == runtimeNullSentinelInt)
            #expect(kk_weak_ref_get(secondWeak) == runtimeNullSentinelInt)
        }
    }

    @Test func explicitJobBindingReusesAnExistingLazyBinding() {
        let classID = runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.JobSupport")
        let wrapper = kk_object_new(0, Int(classID))
        #expect(kk_job_is_active(wrapper) == 1)
        let original = resolveRuntimeHandle(wrapper, as: RuntimeObjectBox.self)?.coroutineJobHandle ?? 0
        #expect(original != 0)
        #expect(kk_job_complete(wrapper, 42) == 1)

        let proposed = kk_job_new()
        let effective = __kk_job_bind_wrapper(wrapper, proposed, 0)
        #expect(effective == original)
        #expect(kk_job_is_completed(wrapper) == 1)
        #expect(kk_job_complete(effective, 99) == 0)
        #expect(kk_object_release(proposed) == 1)
        #expect(kk_object_release(wrapper) == 1)
        if let pointer = UnsafeMutableRawPointer(bitPattern: original) {
            Unmanaged<RuntimeJobHandle>.fromOpaque(pointer).release()
        }
    }

    @Test func mutableMapEntryTracksReplacement() {
        withDummyTypeInfo { typeInfo in
            let original = Int(bitPattern: kk_alloc(16, typeInfo))
            let replacement = Int(bitPattern: kk_alloc(16, typeInfo))
            let originalWeak = kk_weak_ref_create(original)
            let replacementWeak = kk_weak_ref_create(replacement)
            let map = registerRuntimeObject(RuntimeMapBox(keys: [7], values: [original]))
            let entry = runtimeMutableMapEntryNew(mapRaw: map, key: 7, value: original)
            kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: replacement))
            kk_gc_collect()
            #expect(kk_weak_ref_get(originalWeak) == original)

            var thrown = 0
            #expect(kk_mutable_map_entry_setValue(entry, replacement, &thrown) == original)
            #expect(thrown == 0)
            kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: replacement))
            kk_gc_collect()
            #expect(kk_weak_ref_get(originalWeak) == runtimeNullSentinelInt)
            #expect(kk_weak_ref_get(replacementWeak) == replacement)
            #expect(kk_object_release(entry) == 1)
            #expect(kk_object_release(map) == 1)
            kk_gc_collect()
            #expect(kk_weak_ref_get(replacementWeak) == runtimeNullSentinelInt)
        }
    }

    @Test func mutableMapEntryReturnSurvivesCollectionUntilCallerFrameEnds() {
        withDummyTypeInfo { typeInfo in
            let original = Int(bitPattern: kk_alloc(16, typeInfo))
            let replacement = Int(bitPattern: kk_alloc(16, typeInfo))
            let originalWeak = kk_weak_ref_create(original)
            let map = registerRuntimeObject(RuntimeMapBox(keys: [7], values: [original]))
            let entry = runtimeMutableMapEntryNew(mapRaw: map, key: 7, value: original)
            kk_gc_shadow_push()
            var thrown = 0
            #expect(kk_mutable_map_entry_setValue(entry, replacement, &thrown) == original)
            #expect(thrown == 0)
            kk_gc_collect()
            #expect(kk_weak_ref_get(originalWeak) == original)
            kk_gc_shadow_pop(0, 0)
            kk_gc_collect()
            #expect(kk_weak_ref_get(originalWeak) == runtimeNullSentinelInt)
            #expect(kk_object_release(entry) == 1)
            #expect(kk_object_release(map) == 1)
        }
    }

    @Test func mutableMapEntryUpdatesTrackedValueWithoutThrownSlot() {
        withDummyTypeInfo { typeInfo in
            let original = Int(bitPattern: kk_alloc(16, typeInfo))
            let replacement = Int(bitPattern: kk_alloc(16, typeInfo))
            let originalWeak = kk_weak_ref_create(original)
            let replacementWeak = kk_weak_ref_create(replacement)
            let map = registerRuntimeObject(RuntimeMapBox(keys: [7], values: [original]))
            let entry = runtimeMutableMapEntryNew(mapRaw: map, key: 7, value: original)
            #expect(kk_mutable_map_entry_setValue(entry, replacement, nil) == original)
            kk_gc_collect()
            #expect(kk_weak_ref_get(originalWeak) == runtimeNullSentinelInt)
            #expect(kk_weak_ref_get(replacementWeak) == replacement)
            #expect(kk_object_release(entry) == 1)
            #expect(kk_object_release(map) == 1)
        }
    }

    @Test func failedMapEntryUpdateWithoutThrownSlotKeepsOriginalValue() {
        withDummyTypeInfo { typeInfo in
            let original = Int(bitPattern: kk_alloc(16, typeInfo))
            let replacement = Int(bitPattern: kk_alloc(16, typeInfo))
            let originalWeak = kk_weak_ref_create(original)
            let replacementWeak = kk_weak_ref_create(replacement)
            let map = registerRuntimeObject(RuntimeMapBox(keys: [7], values: [original]))
            let entry = runtimeMutableMapEntryNew(mapRaw: map, key: 7, value: original)
            resolveRuntimeHandle(map, as: RuntimeMapBox.self)?.freeze()
            #expect(kk_mutable_map_entry_setValue(entry, replacement, nil) == runtimeNullSentinelInt)
            kk_gc_collect()
            #expect(kk_weak_ref_get(originalWeak) == original)
            #expect(kk_weak_ref_get(replacementWeak) == runtimeNullSentinelInt)
            #expect(kk_object_release(entry) == 1)
            #expect(kk_object_release(map) == 1)
        }
    }

    @Test func concurrentPairWritesAndCollectionPreservePublishedElement() {
        withDummyTypeInfo { typeInfo in
            let first = Int(bitPattern: kk_alloc(16, typeInfo))
            let second = Int(bitPattern: kk_alloc(16, typeInfo))
            let firstWeak = kk_weak_ref_create(first)
            let secondWeak = kk_weak_ref_create(second)
            let pair = kk_pair_new(0, first)
            kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: first))
            kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: second))
            let started = DispatchSemaphore(value: 0)
            let finished = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                started.signal()
                for index in 0 ..< 200 {
                    resolveRuntimeHandle(pair, as: RuntimePairBox.self)?
                        .setSecondValue(RuntimeValue(raw: index.isMultiple(of: 2) ? first : second))
                }
                resolveRuntimeHandle(pair, as: RuntimePairBox.self)?
                    .setSecondValue(RuntimeValue(raw: second))
                finished.signal()
            }
            started.wait()
            for _ in 0 ..< 100 { kk_gc_collect() }
            finished.wait()
            kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: first))
            kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: second))
            kk_gc_collect()
            #expect(kk_weak_ref_get(firstWeak) == runtimeNullSentinelInt)
            #expect(kk_weak_ref_get(secondWeak) == second)
            #expect(kk_object_release(pair) == 1)
            kk_gc_collect()
            #expect(kk_weak_ref_get(secondWeak) == runtimeNullSentinelInt)
        }
    }

    @Test func retainedArrayKeepsManagedElementAliveThroughForeignLease() {
        withDummyTypeInfo { typeInfo in
            let captured = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(captured)
            let array = kk_array_new(1)
            _ = kk_array_set(array, 0, captured, nil)
            let token = runtimeForeignResourceCreate(NSObject(), roots: [UInt(bitPattern: array)])
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            runtimeForeignResourceDiscardUnattached(token)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            _ = kk_array_set(array, 0, 0, nil)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            #expect(kk_object_release(array) == 1)
        }
    }

    @Test func retainedFunctionValueKeepsManagedCaptureThroughArray() {
        withDummyTypeInfo { typeInfo in
            let captured = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(captured)
            let array = kk_array_new(1)
            _ = kk_array_set(array, 0, captured, nil)
            let function = kk_suspend_function_create(0, array, 0, 0)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            #expect(kk_object_release(function) == 1)
            #expect(kk_object_release(array) == 1)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func sharedArrayStorageKeepsManagedElementAfterViewRelease() {
        withDummyTypeInfo { typeInfo in
            let captured = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(captured)
            let original = kk_array_new(1)
            guard let box = resolveRuntimeHandle(original, as: RuntimeArrayBox.self) else {
                Issue.record("Array handle must resolve before creating a view")
                return
            }
            let view = box.primitiveView(rawValue: original, sourceTypeID: 987_101, targetTypeID: 987_102)
            _ = kk_array_set(view, 0, captured, nil)
            #expect(kk_object_release(view) == 1)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            _ = kk_array_set(original, 0, 0, nil)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            #expect(kk_object_release(original) == 1)
        }
    }

    @Test func preinitializedArrayKeepsManagedElementAlive() {
        withDummyTypeInfo { typeInfo in
            let captured = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(captured)
            let array = runtimeMakeArrayRaw([captured])
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            _ = kk_array_set(array, 0, 0, nil)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            #expect(kk_object_release(array) == 1)
        }
    }

    @Test func concurrentArrayWritesAndCollectionPreservePublishedElement() {
        withDummyTypeInfo { typeInfo in
            let captured = kk_alloc(16, typeInfo)
            let raw = Int(bitPattern: captured)
            let weak = kk_weak_ref_create(raw)
            let array = kk_array_new(1)
            let root = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
            root.initialize(to: captured)
            kk_register_global_root(root)
            let started = DispatchSemaphore(value: 0)
            let finished = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                started.signal()
                for index in 0 ..< 200 {
                    _ = kk_array_set(array, 0, index.isMultiple(of: 2) ? raw : 0, nil)
                }
                _ = kk_array_set(array, 0, raw, nil)
                finished.signal()
            }
            started.wait()
            for _ in 0 ..< 100 { kk_gc_collect() }
            finished.wait()
            kk_unregister_global_root(root)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            _ = kk_array_set(array, 0, 0, nil)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            #expect(kk_object_release(array) == 1)
            root.deinitialize(count: 1)
            root.deallocate()
        }
    }

    @Test func concurrentByteStoragePublicationAndViewReadsAreConsistent() {
        let expected = [17, -2, 31, -128]
        for _ in 0 ..< 32 {
            let box = RuntimeArrayBox(length: expected.count)
            box.elements = expected
            let raw = registerRuntimeObject(box)
            let probe = ConcurrentArrayViewProbe(box)
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                for _ in 0 ..< 128 where probe.box.elements != expected {
                    probe.recordMismatch()
                }
            }
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                guard let address = probe.box.nativeByteAddress(at: 0) else {
                    probe.recordMismatch()
                    return
                }
                if Array(UnsafeBufferPointer(start: address, count: expected.count))
                    != expected.map({ UInt8(truncatingIfNeeded: $0) }) {
                    probe.recordMismatch()
                }
                probe.recordView(probe.box.primitiveView(
                    rawValue: raw, sourceTypeID: 987_201, targetTypeID: 987_202
                ))
            }
            let finished = group.wait(timeout: .now() + 5) == .success
            #expect(finished)
            if !finished { group.wait() }
            let (mismatches, view) = probe.snapshot()
            #expect(mismatches == 0)
            #expect(view != 0)
            if view != 0 { #expect(kk_object_release(view) == 1) }
            #expect(kk_object_release(raw) == 1)
        }
    }

    @Test func retainedObjectFieldKeepsManagedAllocationAlive() {
        withDummyTypeInfo { typeInfo in
            let owner = kk_object_new(1, 12345)
            let ownerRoot = ConcurrentFrameSlot(UnsafeMutableRawPointer(bitPattern: owner))
            kk_register_global_root(ownerRoot.pointer)
            defer { kk_unregister_global_root(ownerRoot.pointer) }
            let child = kk_alloc(16, typeInfo)
            let weak = kk_weak_ref_create(Int(bitPattern: child))
            var thrown = 0
            _ = kk_array_set(owner, 0, Int(bitPattern: child), &thrown)
            #expect(thrown == 0)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            _ = kk_array_set(owner, 0, 0, &thrown)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            #expect(runtimeReleaseObject(owner))
        }
    }

    @Test func releasingRetainedObjectReleasesManagedFieldRoot() {
        withDummyTypeInfo { typeInfo in
            let owner = kk_object_new(1, 12345)
            let child = kk_alloc(16, typeInfo)
            let weak = kk_weak_ref_create(Int(bitPattern: child))
            _ = kk_array_set_typed(owner, 0, Int(bitPattern: child), 0)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            #expect(runtimeReleaseObject(owner))
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func valueClassBoxRegistersPreinitializedManagedPayload() {
        withDummyTypeInfo { typeInfo in
            let child = kk_alloc(16, typeInfo)
            let weak = kk_weak_ref_create(Int(bitPattern: child))
            let owner = kk_value_class_box(Int(bitPattern: child), 12345)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            #expect(runtimeReleaseObject(owner))
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func replacingObjectFieldStorageUpdatesManagedRoots() {
        withDummyTypeInfo { typeInfo in
            let owner = kk_object_new(1, 12345)
            let ownerRoot = ConcurrentFrameSlot(UnsafeMutableRawPointer(bitPattern: owner))
            kk_register_global_root(ownerRoot.pointer)
            defer { kk_unregister_global_root(ownerRoot.pointer) }
            guard let box = runtimeArrayBox(from: owner) else {
                Issue.record("Object box was not registered")
                return
            }
            let first = kk_alloc(16, typeInfo)
            let firstWeak = kk_weak_ref_create(Int(bitPattern: first))
            box.values = [RuntimeValue(raw: Int(bitPattern: first))]
            kk_gc_collect()
            #expect(kk_weak_ref_get(firstWeak) != runtimeNullSentinelInt)
            let second = kk_alloc(16, typeInfo)
            let secondWeak = kk_weak_ref_create(Int(bitPattern: second))
            box.elements = [Int(bitPattern: second)]
            kk_gc_collect()
            #expect(kk_weak_ref_get(firstWeak) == runtimeNullSentinelInt)
            #expect(kk_weak_ref_get(secondWeak) != runtimeNullSentinelInt)
            box.setValue(RuntimeValue(raw: 0), at: 0)
            kk_gc_collect()
            #expect(kk_weak_ref_get(secondWeak) == runtimeNullSentinelInt)
            #expect(runtimeReleaseObject(owner))
        }
    }

    @Test func concurrentCollectionPreservesPublishedObjectField() {
        withDummyTypeInfo { typeInfo in
            let owner = kk_object_new(1, 12345)
            let ownerRoot = ConcurrentFrameSlot(UnsafeMutableRawPointer(bitPattern: owner))
            kk_register_global_root(ownerRoot.pointer)
            defer { kk_unregister_global_root(ownerRoot.pointer) }
            let child = kk_alloc(16, typeInfo)
            let weak = kk_weak_ref_create(Int(bitPattern: child))
            let temporary = ConcurrentFrameSlot(child)
            kk_register_global_root(temporary.pointer)
            let started = DispatchSemaphore(value: 0)
            let stop = DispatchSemaphore(value: 0)
            let finished = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                started.signal()
                while stop.wait(timeout: .now()) == .timedOut { kk_gc_collect() }
                finished.signal()
            }
            started.wait()
            var thrown = 0
            _ = kk_array_set(owner, 0, Int(bitPattern: child), &thrown)
            kk_unregister_global_root(temporary.pointer)
            for _ in 0..<100 { kk_gc_collect() }
            stop.signal()
            finished.wait()
            #expect(thrown == 0)
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            _ = kk_array_set(owner, 0, 0, &thrown)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            #expect(runtimeReleaseObject(owner))
        }
    }

    @Test func compilerGlobalStorePublishesAndClearsRoot() {
        withDummyTypeInfo { typeInfo in
            let object = kk_alloc(16, typeInfo)
            let weak = kk_weak_ref_create(Int(bitPattern: object))
            let slot = UnsafeMutablePointer<Int>.allocate(capacity: 1)
            slot.initialize(to: 0)
            defer {
                runtimeStorage.withGCLock { state in
                    _ = state.globalWordRootSlots.remove(UInt(bitPattern: slot))
                }
                slot.deinitialize(count: 1)
                slot.deallocate()
            }
            kk_gc_store_global(slot, Int(bitPattern: object))
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            kk_gc_store_global(slot, 0)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func globalSlotRegisteredByBothFrameSystemsCountsOnce() {
        withDummyTypeInfo { typeInfo in
            kk_gc_collect()
            guard let baseline = lastGCInfoSnapshot() else {
                Issue.record("baseline pass should have been recorded")
                return
            }
            let object = kk_alloc(16, typeInfo)
            let slot = UnsafeMutablePointer<Int>.allocate(capacity: 1)
            slot.initialize(to: 0)
            let pointerSlot = UnsafeMutableRawPointer(slot).assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
            defer {
                kk_unregister_global_root(pointerSlot)
                runtimeStorage.withGCLock { state in
                    _ = state.globalWordRootSlots.remove(UInt(bitPattern: slot))
                }
                slot.deinitialize(count: 1)
                slot.deallocate()
            }
            _ = kk_register_global_root(pointerSlot)
            _ = kk_gc_store_global(slot, Int(bitPattern: object))
            kk_gc_collect()
            #expect(lastGCInfoSnapshot()?.rootSet.globalReferences == baseline.rootSet.globalReferences + 1)
        }
    }

    @Test func concurrentCollectionPreservesPublishedCompilerGlobal() {
        withDummyTypeInfo { typeInfo in
            let object = kk_alloc(16, typeInfo)
            let weak = kk_weak_ref_create(Int(bitPattern: object))
            let temporary = ConcurrentFrameSlot(object)
            let slot = UnsafeMutablePointer<Int>.allocate(capacity: 1)
            slot.initialize(to: 0)
            defer {
                runtimeStorage.withGCLock { state in
                    _ = state.globalWordRootSlots.remove(UInt(bitPattern: slot))
                }
                slot.deinitialize(count: 1)
                slot.deallocate()
            }
            kk_register_global_root(temporary.pointer)
            let started = DispatchSemaphore(value: 0)
            let stop = DispatchSemaphore(value: 0)
            let finished = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                started.signal()
                while stop.wait(timeout: .now()) == .timedOut { kk_gc_collect() }
                finished.signal()
            }
            started.wait()
            kk_gc_store_global(slot, Int(bitPattern: object))
            kk_unregister_global_root(temporary.pointer)
            for _ in 0..<100 { kk_gc_collect() }
            stop.signal()
            finished.wait()
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            kk_gc_store_global(slot, 0)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func compilerThreadLocalGlobalRootEndsWithItsThread() {
        withDummyTypeInfo { typeInfo in
            let object = ConcurrentFrameSlot(kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(Int(bitPattern: object.pointer.pointee!))
            let ownersBefore = runtimeStorage.withGCLock { Set($0.threadLocalGlobalValues.keys) }
            let ready = DispatchSemaphore(value: 0)
            let freeStorage = DispatchSemaphore(value: 0)
            let storageFreed = DispatchSemaphore(value: 0)
            let allowExit = DispatchSemaphore(value: 0)
            let thread = Thread {
                let slot = UnsafeMutablePointer<Int>.allocate(capacity: 1)
                slot.initialize(to: 0)
                kk_gc_store_thread_local_global(slot, Int(bitPattern: object.pointer.pointee!))
                ready.signal()
                freeStorage.wait()
                slot.deinitialize(count: 1)
                slot.deallocate()
                storageFreed.signal()
                allowExit.wait()
            }
            thread.start()
            ready.wait()
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            freeStorage.signal()
            storageFreed.wait()
            // Collection must use the mirrored value, not the freed TLS slot.
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            allowExit.signal()
            #expect(waitUntil {
                thread.isFinished && runtimeStorage.withGCLock { Set($0.threadLocalGlobalValues.keys) == ownersBefore }
            })
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func compilerThreadLocalGlobalClearReleasesRoot() {
        withDummyTypeInfo { typeInfo in
            let object = kk_alloc(16, typeInfo)
            let weak = kk_weak_ref_create(Int(bitPattern: object))
            let slot = UnsafeMutablePointer<Int>.allocate(capacity: 1)
            slot.initialize(to: 0)
            defer {
                slot.deinitialize(count: 1)
                slot.deallocate()
            }
            kk_gc_store_thread_local_global(slot, Int(bitPattern: object))
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            kk_gc_store_thread_local_global(slot, 0)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func safepointHooksHaveNonThrowingVoidABI() {
        let names = [
            "__kk_gc_mutator_enter",
            "__kk_gc_mutator_leave",
            "__kk_gc_safepoint",
            "__kk_gc_mutator_blocking_begin",
            "__kk_gc_mutator_blocking_end",
        ]
        for name in names {
            let entries = RuntimeABISpec.gcFunctions.filter { $0.name == name }
            #expect(entries.count == 1)
            #expect(entries.first?.returnType == .void)
            #expect(entries.first?.parameters.isEmpty == true)
            #expect(entries.first?.isThrowing == false)
        }
    }

    @Test func collectionWaitsForEnrolledMutatorSafepoint() {
        withDummyTypeInfo { typeInfo in
            let object = ConcurrentFrameSlot(kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(Int(bitPattern: object.pointer.pointee!))
            let entered = DispatchSemaphore(value: 0)
            let poll = DispatchSemaphore(value: 0)
            let polled = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let workerDone = DispatchSemaphore(value: 0)
            let collectorDone = DispatchSemaphore(value: 0)

            DispatchQueue.global().async {
                __kk_gc_mutator_enter()
                kk_gc_shadow_push()
                kk_gc_shadow_set(0, Int(bitPattern: object.pointer.pointee!))
                entered.signal()
                poll.wait()
                __kk_gc_safepoint()
                polled.signal()
                release.wait()
                kk_gc_shadow_pop(0, 0)
                __kk_gc_mutator_leave()
                workerDone.signal()
            }
            entered.wait()
            DispatchQueue.global().async {
                kk_gc_collect()
                collectorDone.signal()
            }
            #expect(waitForGCRequest())
            #expect(collectorDone.wait(timeout: .now() + .milliseconds(20)) == .timedOut)
            poll.signal()
            #expect(collectorDone.wait(timeout: .now() + .seconds(5)) == .success)
            #expect(polled.wait(timeout: .now() + .seconds(5)) == .success)
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            release.signal()
            #expect(workerDone.wait(timeout: .now() + .seconds(5)) == .success)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func collectionCanProceedWhileAnEnrolledMutatorWaitsForNonDaemonThreads() {
        _ = __kk_thread_non_daemon_start()
        let ready = DispatchSemaphore(value: 0)
        let waiterFinished = DispatchSemaphore(value: 0)
        let collected = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            __kk_gc_mutator_enter()
            ready.signal()
            _ = __kk_thread_wait_non_daemon()
            __kk_gc_mutator_leave()
            waiterFinished.signal()
        }
        let waiterReady = ready.wait(timeout: .now() + .seconds(5))
        #expect(waiterReady == .success)
        guard waiterReady == .success else {
            _ = __kk_thread_non_daemon_finish()
            return
        }
        DispatchQueue.global().async {
            kk_gc_collect()
            collected.signal()
        }
        let collectionBeforeFinish = collected.wait(timeout: .now() + .seconds(2))
        _ = __kk_thread_non_daemon_finish()
        #expect(collectionBeforeFinish == .success)
        #expect(waiterFinished.wait(timeout: .now() + .seconds(5)) == .success)
        if collectionBeforeFinish != .success {
            #expect(collected.wait(timeout: .now() + .seconds(5)) == .success)
        }
    }

    @Test func collectionCanProceedWhileAnEnrolledMutatorJoinsAJob() {
        let job = RuntimeJobHandle()
        job.markStarted()
        let ready = DispatchSemaphore(value: 0)
        let joined = DispatchSemaphore(value: 0)
        let correctResult = DispatchSemaphore(value: 0)
        let collected = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            let previousLoop = RuntimeEventLoop.current
            RuntimeEventLoop.current = nil
            defer { RuntimeEventLoop.current = previousLoop }
            __kk_gc_mutator_enter()
            ready.signal()
            if job.join() == 42 { correctResult.signal() }
            __kk_gc_mutator_leave()
            joined.signal()
        }
        let waiterReady = ready.wait(timeout: .now() + .seconds(5))
        #expect(waiterReady == .success)
        guard waiterReady == .success else {
            _ = job.complete(with: 42)
            return
        }
        DispatchQueue.global().async {
            kk_gc_collect()
            collected.signal()
        }
        let collectionBeforeCompletion = collected.wait(timeout: .now() + .seconds(2))
        _ = job.complete(with: 42)
        #expect(collectionBeforeCompletion == .success)
        #expect(joined.wait(timeout: .now() + .seconds(5)) == .success)
        #expect(correctResult.wait(timeout: .now() + .seconds(1)) == .success)
        if collectionBeforeCompletion != .success {
            #expect(collected.wait(timeout: .now() + .seconds(5)) == .success)
        }
    }

    @Test func collectionCanProceedWhileAnEnrolledMutatorAwaitsAFuture() {
        let future = kk_future_new()
        let ready = DispatchSemaphore(value: 0)
        let waiterFinished = DispatchSemaphore(value: 0)
        let correctResult = DispatchSemaphore(value: 0)
        let collected = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            __kk_gc_mutator_enter()
            ready.signal()
            if kk_future_result(future) == 42 { correctResult.signal() }
            __kk_gc_mutator_leave()
            waiterFinished.signal()
        }
        let waiterReady = ready.wait(timeout: .now() + .seconds(5))
        #expect(waiterReady == .success)
        guard waiterReady == .success else {
            _ = kk_future_complete(future, 42)
            return
        }
        DispatchQueue.global().async {
            kk_gc_collect()
            collected.signal()
        }
        let collectionBeforeCompletion = collected.wait(timeout: .now() + .seconds(2))
        _ = kk_future_complete(future, 42)
        #expect(collectionBeforeCompletion == .success)
        #expect(waiterFinished.wait(timeout: .now() + .seconds(5)) == .success)
        #expect(correctResult.wait(timeout: .now() + .seconds(1)) == .success)
        if collectionBeforeCompletion != .success {
            #expect(collected.wait(timeout: .now() + .seconds(5)) == .success)
        }
        #expect(kk_object_release(future) == 1)
    }

    @Test func joinedMutatorWaitsForCollectionBeforeResuming() {
        let job = RuntimeJobHandle()
        job.markStarted()
        let ready = DispatchSemaphore(value: 0)
        let joined = DispatchSemaphore(value: 0)
        let collectorEntered = DispatchSemaphore(value: 0)
        let finishCollection = DispatchSemaphore(value: 0)
        let collectorFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            let previousLoop = RuntimeEventLoop.current
            RuntimeEventLoop.current = nil
            defer { RuntimeEventLoop.current = previousLoop }
            __kk_gc_mutator_enter()
            ready.signal()
            _ = job.join()
            __kk_gc_mutator_leave()
            joined.signal()
        }
        let waiterReady = ready.wait(timeout: .now() + .seconds(5))
        #expect(waiterReady == .success)
        guard waiterReady == .success else {
            _ = job.complete(with: 42)
            return
        }
        DispatchQueue.global().async {
            runtimeGCSafepoints.beginCollection()
            collectorEntered.signal()
            finishCollection.wait()
            runtimeGCSafepoints.endCollection()
            collectorFinished.signal()
        }
        let collectorStarted = collectorEntered.wait(timeout: .now() + .seconds(5))
        _ = job.complete(with: 42)
        #expect(collectorStarted == .success)
        if collectorStarted == .success {
            #expect(joined.wait(timeout: .now() + .milliseconds(20)) == .timedOut)
        }
        finishCollection.signal()
        #expect(collectorFinished.wait(timeout: .now() + .seconds(5)) == .success)
        #expect(joined.wait(timeout: .now() + .seconds(5)) == .success)
    }

    @Test func collectionCanProceedWhileAnEnrolledMutatorDrainsAnIdleEventLoop() {
        let loop = RuntimeEventLoop()
        let done = RuntimeCompletionFlag()
        let ready = DispatchSemaphore(value: 0)
        let loopFinished = DispatchSemaphore(value: 0)
        let collected = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            __kk_gc_mutator_enter()
            ready.signal()
            loop.run(until: { done.isSet })
            __kk_gc_mutator_leave()
            loopFinished.signal()
        }
        let waiterReady = ready.wait(timeout: .now() + .seconds(5))
        #expect(waiterReady == .success)
        guard waiterReady == .success else {
            done.set()
            loop.wake()
            return
        }
        DispatchQueue.global().async {
            kk_gc_collect()
            collected.signal()
        }
        let collectionBeforeCompletion = collected.wait(timeout: .now() + .seconds(2))
        done.set()
        loop.wake()
        #expect(collectionBeforeCompletion == .success)
        #expect(loopFinished.wait(timeout: .now() + .seconds(5)) == .success)
        if collectionBeforeCompletion != .success {
            #expect(collected.wait(timeout: .now() + .seconds(5)) == .success)
        }
    }

    @Test(arguments: [false, true])
    func collectionCanProceedDuringDrainingSemaphoreWait(hasEventLoop: Bool) {
        let ready = DispatchSemaphore(value: 0)
        let signal = DispatchSemaphore(value: 0)
        let waiterFinished = DispatchSemaphore(value: 0)
        let collected = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            let previousLoop = RuntimeEventLoop.current
            RuntimeEventLoop.current = hasEventLoop ? RuntimeEventLoop() : nil
            defer { RuntimeEventLoop.current = previousLoop }
            __kk_gc_mutator_enter()
            ready.signal()
            runtimeWaitDrainingEventLoop(signal)
            __kk_gc_mutator_leave()
            waiterFinished.signal()
        }
        let waiterReady = ready.wait(timeout: .now() + .seconds(5))
        #expect(waiterReady == .success)
        guard waiterReady == .success else {
            signal.signal()
            return
        }
        DispatchQueue.global().async {
            kk_gc_collect()
            collected.signal()
        }
        let collectionBeforeSignal = collected.wait(timeout: .now() + .seconds(2))
        signal.signal()
        #expect(collectionBeforeSignal == .success)
        #expect(waiterFinished.wait(timeout: .now() + .seconds(5)) == .success)
        if collectionBeforeSignal != .success {
            #expect(collected.wait(timeout: .now() + .seconds(5)) == .success)
        }
    }

    @Test func eventLoopWorkRemainsActiveUntilItsSafepoint() {
        let loop = RuntimeEventLoop()
        let done = RuntimeCompletionFlag()
        let workStarted = DispatchSemaphore(value: 0)
        let poll = DispatchSemaphore(value: 0)
        let workFinished = DispatchSemaphore(value: 0)
        let collected = DispatchSemaphore(value: 0)
        let loopFinished = DispatchSemaphore(value: 0)
        loop.enqueue {
            workStarted.signal()
            poll.wait()
            __kk_gc_safepoint()
            workFinished.signal()
        }
        DispatchQueue.global().async {
            __kk_gc_mutator_enter()
            loop.run(until: { done.isSet })
            __kk_gc_mutator_leave()
            loopFinished.signal()
        }
        let started = workStarted.wait(timeout: .now() + .seconds(5))
        #expect(started == .success)
        guard started == .success else {
            poll.signal()
            done.set()
            loop.wake()
            return
        }
        DispatchQueue.global().async {
            kk_gc_collect()
            collected.signal()
        }
        #expect(waitForGCRequest())
        #expect(collected.wait(timeout: .now() + .milliseconds(20)) == .timedOut)
        poll.signal()
        #expect(collected.wait(timeout: .now() + .seconds(5)) == .success)
        #expect(workFinished.wait(timeout: .now() + .seconds(5)) == .success)
        done.set()
        loop.wake()
        #expect(loopFinished.wait(timeout: .now() + .seconds(5)) == .success)
    }

    @Test func concurrentCollectorsParkWhileWaitingForEachOther() {
        let entered = DispatchSemaphore(value: 0)
        let firstStart = DispatchSemaphore(value: 0)
        let secondStart = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            __kk_gc_mutator_enter()
            entered.signal()
            firstStart.wait()
            kk_gc_collect()
            __kk_gc_mutator_leave()
            finished.signal()
        }
        DispatchQueue.global().async {
            __kk_gc_mutator_enter()
            entered.signal()
            secondStart.wait()
            kk_gc_collect()
            __kk_gc_mutator_leave()
            finished.signal()
        }
        entered.wait()
        entered.wait()
        firstStart.signal()
        #expect(waitForGCRequest())
        secondStart.signal()
        #expect(finished.wait(timeout: .now() + .seconds(5)) == .success)
        #expect(finished.wait(timeout: .now() + .seconds(5)) == .success)
    }

    @Test func blockedMutatorAndCallbackCoordinateWithCollection() {
        withDummyTypeInfo { typeInfo in
            let object = ConcurrentFrameSlot(kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(Int(bitPattern: object.pointer.pointee!))
            let blocked = DispatchSemaphore(value: 0)
            let startCallback = DispatchSemaphore(value: 0)
            let callbackEntered = DispatchSemaphore(value: 0)
            let callbackReturned = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let finished = DispatchSemaphore(value: 0)
            let firstGC = DispatchSemaphore(value: 0)
            let secondGC = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                __kk_gc_mutator_enter()
                kk_gc_shadow_push()
                kk_gc_shadow_set(0, Int(bitPattern: object.pointer.pointee!))
                __kk_gc_mutator_blocking_begin()
                blocked.signal()
                startCallback.wait()
                __kk_gc_mutator_enter()
                callbackEntered.signal()
                __kk_gc_mutator_leave()
                callbackReturned.signal()
                release.wait()
                __kk_gc_mutator_blocking_end()
                kk_gc_shadow_pop(0, 0)
                __kk_gc_mutator_leave()
                finished.signal()
            }
            blocked.wait()
            var callbackWhileCollecting: DispatchTimeoutResult = .timedOut
            runtimeStorage.withGCLock { _ in
                DispatchQueue.global().async {
                    kk_gc_collect()
                    firstGC.signal()
                }
                #expect(waitForGCRequest())
                startCallback.signal()
                callbackWhileCollecting = callbackEntered.wait(timeout: .now() + .milliseconds(20))
                #expect(callbackWhileCollecting == .timedOut)
            }
            #expect(firstGC.wait(timeout: .now() + .seconds(5)) == .success)
            if callbackWhileCollecting == .timedOut {
                #expect(callbackEntered.wait(timeout: .now() + .seconds(5)) == .success)
            }
            #expect(callbackReturned.wait(timeout: .now() + .seconds(5)) == .success)
            DispatchQueue.global().async {
                kk_gc_collect()
                secondGC.signal()
            }
            #expect(secondGC.wait(timeout: .now() + .seconds(5)) == .success)
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            release.signal()
            #expect(finished.wait(timeout: .now() + .seconds(5)) == .success)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func collectionFromBlockingRegionPreservesParkedState() {
        let firstFinished = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let workerFinished = DispatchSemaphore(value: 0)
        let secondFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            __kk_gc_mutator_enter()
            __kk_gc_mutator_blocking_begin()
            kk_gc_collect()
            firstFinished.signal()
            release.wait()
            __kk_gc_mutator_blocking_end()
            __kk_gc_mutator_leave()
            workerFinished.signal()
        }
        #expect(firstFinished.wait(timeout: .now() + .seconds(5)) == .success)
        DispatchQueue.global().async {
            kk_gc_collect()
            secondFinished.signal()
        }
        #expect(secondFinished.wait(timeout: .now() + .seconds(5)) == .success)
        release.signal()
        #expect(workerFinished.wait(timeout: .now() + .seconds(5)) == .success)
    }

    @Test func collectionProceedsWhileEnrolledMutatorIsParked() {
        withDummyTypeInfo { typeInfo in
            let object = ConcurrentFrameSlot(kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(Int(bitPattern: object.pointer.pointee!))
            let holder = ConcurrentParkerHolder()
            let ready = DispatchSemaphore(value: 0)
            let workerFinished = DispatchSemaphore(value: 0)
            let collected = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                __kk_gc_mutator_enter()
                kk_gc_shadow_push()
                kk_gc_shadow_set(0, Int(bitPattern: object.pointer.pointee!))
                let parker = RuntimeAtomicfuParker()
                holder.parker = parker
                ready.signal()
                _ = parker.park(timeoutNanos: -1)
                kk_gc_shadow_pop(0, 0)
                __kk_gc_mutator_leave()
                workerFinished.signal()
            }
            ready.wait()
            guard let parker = holder.parker else {
                Issue.record("Worker did not create its parker")
                return
            }
            #expect(waitUntil { parker.hasWaitingOwner })
            DispatchQueue.global().async {
                kk_gc_collect()
                collected.signal()
            }
            let collectedWhileParked = collected.wait(timeout: .now() + .seconds(5))
            #expect(collectedWhileParked == .success)
            if collectedWhileParked == .success {
                #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            }
            parker.unpark()
            #expect(workerFinished.wait(timeout: .now() + .seconds(5)) == .success)
            if collectedWhileParked != .success {
                #expect(collected.wait(timeout: .now() + .seconds(5)) == .success)
            }
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func collectionProceedsWhileEnrolledMutatorWaitsForLock() {
        withDummyTypeInfo { typeInfo in
            let object = ConcurrentFrameSlot(kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(Int(bitPattern: object.pointer.pointee!))
            let lock = RuntimeAtomicfuRecursiveLock()
            #expect(lock.acquire(timeoutNanos: -1))
            let ready = DispatchSemaphore(value: 0)
            let workerFinished = DispatchSemaphore(value: 0)
            let collected = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                __kk_gc_mutator_enter()
                kk_gc_shadow_push()
                kk_gc_shadow_set(0, Int(bitPattern: object.pointer.pointee!))
                ready.signal()
                let acquired = lock.acquire(timeoutNanos: -1)
                if acquired { _ = lock.release() }
                kk_gc_shadow_pop(0, 0)
                __kk_gc_mutator_leave()
                workerFinished.signal()
            }
            ready.wait()
            #expect(waitUntil { lock.queuedWaiterCount == 1 })
            DispatchQueue.global().async {
                kk_gc_collect()
                collected.signal()
            }
            let collectedWhileWaiting = collected.wait(timeout: .now() + .seconds(5))
            #expect(collectedWhileWaiting == .success)
            if collectedWhileWaiting == .success {
                #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            }
            #expect(lock.release())
            #expect(workerFinished.wait(timeout: .now() + .seconds(5)) == .success)
            if collectedWhileWaiting != .success {
                #expect(collected.wait(timeout: .now() + .seconds(5)) == .success)
            }
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test func unparkedMutatorWaitsForCollectionBeforeResuming() {
        let holder = ConcurrentParkerHolder()
        let ready = DispatchSemaphore(value: 0)
        let workerFinished = DispatchSemaphore(value: 0)
        let collected = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            __kk_gc_mutator_enter()
            let parker = RuntimeAtomicfuParker()
            holder.parker = parker
            ready.signal()
            _ = parker.park(timeoutNanos: -1)
            __kk_gc_mutator_leave()
            workerFinished.signal()
        }
        ready.wait()
        guard let parker = holder.parker else {
            Issue.record("Worker did not create its parker")
            return
        }
        #expect(waitUntil { parker.hasWaitingOwner })
        var workerWhileCollecting: DispatchTimeoutResult = .timedOut
        runtimeStorage.withGCLock { _ in
            DispatchQueue.global().async {
                kk_gc_collect()
                collected.signal()
            }
            #expect(waitForGCRequest())
            parker.unpark()
            workerWhileCollecting = workerFinished.wait(timeout: .now() + .milliseconds(20))
            #expect(workerWhileCollecting == .timedOut)
        }
        #expect(collected.wait(timeout: .now() + .seconds(5)) == .success)
        if workerWhileCollecting == .timedOut {
            #expect(workerFinished.wait(timeout: .now() + .seconds(5)) == .success)
        }
    }

    @Test func shadowFramesPreserveReturnAndThrownValuesAcrossPop() {
        withDummyTypeInfo { typeInfo in
            let result = Int(bitPattern: kk_alloc(16, typeInfo))
            let thrown = Int(bitPattern: kk_alloc(16, typeInfo))
            let resultWeak = kk_weak_ref_create(result)
            let thrownWeak = kk_weak_ref_create(thrown)
            kk_gc_shadow_push()
            kk_gc_shadow_push()
            kk_gc_shadow_set(0, result)
            kk_gc_shadow_set(1, thrown)
            kk_gc_collect()
            #expect(kk_weak_ref_get(resultWeak) != runtimeNullSentinelInt)
            #expect(kk_weak_ref_get(thrownWeak) != runtimeNullSentinelInt)

            kk_gc_shadow_pop(result, thrown)
            kk_gc_collect()
            #expect(kk_weak_ref_get_rooted(resultWeak, 2) != runtimeNullSentinelInt)
            #expect(kk_weak_ref_get_rooted(thrownWeak, 3) != runtimeNullSentinelInt)
            kk_gc_shadow_set(2, 0)
            kk_gc_shadow_set(3, 0)

            kk_gc_shadow_set(0, result)
            kk_gc_shadow_set(1, thrown)
            kk_gc_shadow_set(0, 0)
            kk_gc_shadow_set(1, 0)
            kk_gc_collect()
            #expect(kk_weak_ref_get(resultWeak) == runtimeNullSentinelInt)
            #expect(kk_weak_ref_get(thrownWeak) == runtimeNullSentinelInt)

            kk_gc_shadow_pop(0, 0)
            kk_gc_collect()
            #expect(kk_weak_ref_get(resultWeak) == runtimeNullSentinelInt)
            #expect(kk_weak_ref_get(thrownWeak) == runtimeNullSentinelInt)
        }
    }

    @Test(arguments: [false, true])
    func nativeChannelFramePreservesPendingCallerReturn(iterator: Bool) {
        withDummyTypeInfo { typeInfo in
            let pending = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(pending)
            let channel = kk_channel_create(1)
            #expect(kk_channel_try_send(channel, 1) == kChannelResultSuccess)
            kk_gc_shadow_push()
            kk_gc_shadow_push()
            kk_gc_shadow_set(0, pending)
            kk_gc_shadow_pop(pending, 0)
            if iterator {
                let cursor = kk_channel_iterator(channel)
                #expect(kk_channel_iterator_hasNext(cursor) == 1)
                #expect(kk_object_release(cursor) == 1)
            } else {
                let result = __kk_channel_try_receive(channel)
                #expect(kk_object_release(result) == 1)
            }
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == pending)
            kk_gc_shadow_pop(0, 0)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            #expect(kk_object_release(channel) == 1)
        }
    }

    @Test func shadowFramesAreIsolatedBetweenThreads() {
        withDummyTypeInfo { typeInfo in
            let mainObject = kk_alloc(16, typeInfo)
            let workerObject = kk_alloc(16, typeInfo)
            let mainWeak = kk_weak_ref_create(Int(bitPattern: mainObject))
            let workerWeak = kk_weak_ref_create(Int(bitPattern: workerObject))
            let workerValue = ConcurrentFrameSlot(workerObject)
            let ready = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let finished = DispatchSemaphore(value: 0)

            kk_gc_shadow_push()
            kk_gc_shadow_set(0, Int(bitPattern: mainObject))
            DispatchQueue.global().async {
                kk_gc_shadow_push()
                kk_gc_shadow_set(0, Int(bitPattern: workerValue.pointer.pointee!))
                ready.signal()
                release.wait()
                kk_gc_shadow_pop(0, 0)
                finished.signal()
            }
            ready.wait()
            kk_gc_shadow_pop(0, 0)
            kk_gc_collect()
            #expect(kk_weak_ref_get(mainWeak) == runtimeNullSentinelInt)
            #expect(kk_weak_ref_get(workerWeak) != runtimeNullSentinelInt)
            release.signal()
            finished.wait()
            kk_gc_collect()
            #expect(kk_weak_ref_get(workerWeak) == runtimeNullSentinelInt)
        }
    }

    @Test(arguments: [false, true])
    func resetPreservesInFlightNestedShadowFrames(fullReset: Bool) {
        let result = kk_object_new(0, 0x36_26_20)
        let thrown = kk_object_new(0, 0x36_26_21)
        let resultWeak = kk_weak_ref_create(result)
        let thrownWeak = kk_weak_ref_create(thrown)
        let ready = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            defer { finished.signal() }
            kk_gc_shadow_push()
            kk_gc_shadow_push()
            kk_gc_shadow_set(0, result)
            kk_gc_shadow_set(1, thrown)
            ready.signal()
            guard resume.wait(timeout: .now() + 10) == .success else {
                Issue.record("reset test worker was not resumed")
                kk_gc_shadow_pop(0, 0)
                kk_gc_shadow_pop(0, 0)
                return
            }
            let depth = kk_gc_shadow_depth()
            #expect(depth == 2)
            guard depth == 2 else { return }
            kk_gc_shadow_pop(result, thrown)
            kk_gc_collect()
            #expect(kk_weak_ref_get(resultWeak) == result)
            #expect(kk_weak_ref_get(thrownWeak) == thrown)
            kk_gc_shadow_pop(0, 0)
        }

        let started = ready.wait(timeout: .now() + 10) == .success
        #expect(started)
        if started {
            let didReset = fullReset ? runtimeTryForceReset() : kk_runtime_reset_gc()
            #expect(!didReset)
            #expect(runtimeStorage.withGCLock { $0.managedObjectPointers.contains(UInt(bitPattern: result)) })
            #expect(runtimeStorage.withGCLock { $0.managedObjectPointers.contains(UInt(bitPattern: thrown)) })
        }
        resume.signal()
        let completed = finished.wait(timeout: .now() + 10) == .success
        #expect(completed)
        guard completed else { return }
        kk_gc_collect()
        #expect(kk_weak_ref_get(resultWeak) == runtimeNullSentinelInt)
        #expect(kk_weak_ref_get(thrownWeak) == runtimeNullSentinelInt)
        _ = kk_object_release(resultWeak)
        _ = kk_object_release(thrownWeak)
    }

    @Test func resetPreservesActiveRootFrameAndAllowsLaterReset() {
        withDummyTypeInfo { typeInfo in
            let object = kk_alloc(16, typeInfo)
            let slot = UnsafeMutablePointer<Int>.allocate(capacity: 1)
            slot.initialize(to: Int(bitPattern: object))
            defer { slot.deinitialize(count: 1); slot.deallocate() }
            _ = kk_gc_push_root_frame(UnsafeMutableRawPointer(slot), 1)
            #expect(!kk_runtime_reset_gc())
            #expect(runtimeStorage.withGCLock { $0.heapObjects[UInt(bitPattern: object)] != nil })
            _ = kk_gc_frame_leave(0, 1)
            #expect(kk_runtime_reset_gc())
            #expect(runtimeStorage.withGCLock { $0.heapObjects[UInt(bitPattern: object)] == nil })
        }
    }

    @Test func resetDefersQueuedNativeWorkUntilItsLeaseFinishes() {
        withDummyTypeInfo { typeInfo in
            let object = kk_alloc(16, typeInfo)
            let lease = RuntimeGCResetWorkLease()
            #expect(!runtimeWithQuiescentGCFrames {})
            #expect(!kk_runtime_reset_gc())
            #expect(runtimeStorage.withGCLock { $0.heapObjects[UInt(bitPattern: object)] != nil })
            lease.finish()
            lease.finish()
            #expect(runtimeWithQuiescentGCFrames {})
            #expect(kk_runtime_reset_gc())
            #expect(runtimeStorage.withGCLock { $0.heapObjects[UInt(bitPattern: object)] == nil })
        }
    }

    @Test func frameCreationWaitsUntilCompositeResetFinishes() {
        let attempted = DispatchSemaphore(value: 0)
        let created = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let performed = runtimeWithQuiescentGCFrames {
            DispatchQueue.global().async {
                attempted.signal()
                kk_gc_shadow_push()
                created.signal()
                kk_gc_shadow_pop(0, 0)
                finished.signal()
            }
            #expect(attempted.wait(timeout: .now() + 5) == .success)
            #expect(created.wait(timeout: .now() + .milliseconds(30)) == .timedOut)
            for reset in runtimeIsolationResetFunctions(for: .gcAndMetadata) { #expect(reset()) }
        }
        #expect(performed)
        #expect(created.wait(timeout: .now() + 5) == .success)
        #expect(finished.wait(timeout: .now() + 5) == .success)
    }

    @Test func nestedResetFailureStopsTheIsolationTransaction() {
        var completedLaterReset = false
        let performed = runtimeWithQuiescentGCFramesResult {
            kk_gc_shadow_push()
            defer { kk_gc_shadow_pop(0, 0) }
            let resets: [() -> Bool] = [
                kk_runtime_reset_gc,
                { completedLaterReset = true; return true },
            ]
            for reset in resets where !reset() { return false }
            return true
        }
        #expect(!performed)
        #expect(!completedLaterReset)
    }

    @Test func processWaitDoesNotBlockCollectionOfAnEnrolledMutator() {
        let command = registerRuntimeObject(RuntimeStringBox("/bin/sleep\0" + "5"))
        defer { _ = runtimeReleaseObject(command) }
        let process = __kk_process_start(command)
        #expect(process != 0)
        guard process != 0 else { return }
        let waiting = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let collected = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            __kk_gc_mutator_enter()
            waiting.signal()
            _ = __kk_process_wait_for(process)
            __kk_gc_mutator_leave()
            finished.signal()
        }
        #expect(waiting.wait(timeout: .now() + 5) == .success)
        DispatchQueue.global().async {
            kk_gc_collect()
            collected.signal()
        }
        let earlyCollection = collected.wait(timeout: .now() + 2)
        #expect(earlyCollection == .success)
        if earlyCollection == .timedOut {
            #expect(collected.wait(timeout: .now() + 10) == .success)
        }
        let finishedBeforeCollection = finished.wait(timeout: .now()) == .success
        #expect(!finishedBeforeCollection)
        if !finishedBeforeCollection {
            #expect(finished.wait(timeout: .now() + 10) == .success)
        }
    }

    @Test func inputReadDoesNotBlockCollectionOfAnEnrolledMutator() {
        var descriptors = [Int32](repeating: -1, count: 2)
        #expect(pipe(&descriptors) == 0)
        guard descriptors[0] >= 0, descriptors[1] >= 0 else { return }
        let readDescriptor = descriptors[0]
        let writeDescriptor = descriptors[1]
        guard let file = fdopen(readDescriptor, "r") else {
            close(readDescriptor)
            close(writeDescriptor)
            Issue.record("fdopen failed")
            return
        }
        let probe = ConcurrentStdioProbe(RuntimeStdioInputStreamBox(stream: file))
        defer { close(writeDescriptor) }
        let waiting = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let collected = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            defer {
                probe.stream.close()
                finished.signal()
            }
            __kk_gc_mutator_enter()
            waiting.signal()
            #expect(probe.stream.readByte() == 65)
            __kk_gc_mutator_leave()
        }
        #expect(waiting.wait(timeout: .now() + 5) == .success)
        DispatchQueue.global().async {
            kk_gc_collect()
            collected.signal()
        }
        let earlyCollection = collected.wait(timeout: .now() + 2)
        #expect(earlyCollection == .success)
        let finishedBeforeWrite = finished.wait(timeout: .now()) == .success
        #expect(!finishedBeforeWrite)
        if !finishedBeforeWrite {
            var byte: UInt8 = 65
            #expect(write(writeDescriptor, &byte, 1) == 1)
        }
        if earlyCollection == .timedOut {
            #expect(collected.wait(timeout: .now() + 10) == .success)
        }
        if !finishedBeforeWrite {
            #expect(finished.wait(timeout: .now() + 10) == .success)
        }
    }

    @Test func fileReadDoesNotBlockCollectionOfAnEnrolledMutator() {
        var descriptors = [Int32](repeating: -1, count: 2)
        #expect(pipe(&descriptors) == 0)
        guard descriptors[0] >= 0, descriptors[1] >= 0 else { return }
        let readDescriptor = descriptors[0]
        let writeDescriptor = descriptors[1]
        defer { close(writeDescriptor) }
        let buffer = kk_array_new(1)
        let waiting = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let collected = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            defer {
                close(readDescriptor)
                _ = runtimeReleaseObject(buffer)
                finished.signal()
            }
            __kk_gc_mutator_enter()
            kk_gc_shadow_push()
            kk_gc_shadow_set(0, buffer)
            waiting.signal()
            var thrown = 0
            #expect(__kk_io_fs_read(Int(readDescriptor), buffer, 0, 1, &thrown) == 1)
            #expect(thrown == 0)
            #expect(kk_array_get_inbounds(buffer, 0) == 65)
            kk_gc_shadow_pop(0, 0)
            __kk_gc_mutator_leave()
        }
        #expect(waiting.wait(timeout: .now() + 5) == .success)
        DispatchQueue.global().async {
            kk_gc_collect()
            collected.signal()
        }
        let earlyCollection = collected.wait(timeout: .now() + 2)
        #expect(earlyCollection == .success)
        let finishedBeforeWrite = finished.wait(timeout: .now()) == .success
        #expect(!finishedBeforeWrite)
        if !finishedBeforeWrite {
            var byte: UInt8 = 65
            #expect(write(writeDescriptor, &byte, 1) == 1)
        }
        if earlyCollection == .timedOut {
            #expect(collected.wait(timeout: .now() + 10) == .success)
        }
        if !finishedBeforeWrite {
            #expect(finished.wait(timeout: .now() + 10) == .success)
        }
    }

    @Test func fileWriteDoesNotBlockCollectionOfAnEnrolledMutator() {
        var descriptors = [Int32](repeating: -1, count: 2)
        #expect(pipe(&descriptors) == 0)
        guard descriptors[0] >= 0, descriptors[1] >= 0 else { return }
        let readDescriptor = descriptors[0]
        let writeDescriptor = descriptors[1]
        defer {
            close(readDescriptor)
            close(writeDescriptor)
        }
        let originalFlags = fcntl(writeDescriptor, F_GETFL)
        guard originalFlags >= 0, fcntl(writeDescriptor, F_SETFL, originalFlags | O_NONBLOCK) == 0 else {
            Issue.record("Could not configure pipe for the GC write test")
            return
        }
        let fill = [UInt8](repeating: 0, count: 4096)
        var filled = 0
        while true {
            let count = fill.withUnsafeBytes { buffer in
                write(writeDescriptor, buffer.baseAddress!, buffer.count)
            }
            if count < 0, errno == EAGAIN { break }
            guard count > 0, filled < 16 * 1024 * 1024 else {
                Issue.record("Could not fill pipe for the GC write test")
                return
            }
            filled += count
        }
        guard fcntl(writeDescriptor, F_SETFL, originalFlags) == 0 else {
            Issue.record("Could not restore blocking pipe mode")
            return
        }
        let source = kk_array_new(1)
        _ = kk_array_set(source, 0, 65, nil)
        defer { _ = runtimeReleaseObject(source) }
        let waiting = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let collected = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            __kk_gc_mutator_enter()
            kk_gc_shadow_push()
            kk_gc_shadow_set(0, source)
            waiting.signal()
            var thrown = 0
            #expect(__kk_io_fs_write(Int(writeDescriptor), source, 0, 1, &thrown) == 0)
            #expect(thrown == 0)
            kk_gc_shadow_pop(0, 0)
            __kk_gc_mutator_leave()
            finished.signal()
        }
        #expect(waiting.wait(timeout: .now() + 5) == .success)
        DispatchQueue.global().async {
            kk_gc_collect()
            collected.signal()
        }
        let earlyCollection = collected.wait(timeout: .now() + 2)
        #expect(earlyCollection == .success)
        let finishedBeforeDrain = finished.wait(timeout: .now()) == .success
        #expect(!finishedBeforeDrain)
        if !finishedBeforeDrain {
            var drain = [UInt8](repeating: 0, count: 4096)
            let count = drain.withUnsafeMutableBytes { buffer in
                read(readDescriptor, buffer.baseAddress!, buffer.count)
            }
            #expect(count > 0)
        }
        if earlyCollection == .timedOut {
            #expect(collected.wait(timeout: .now() + 10) == .success)
        }
        if !finishedBeforeDrain {
            #expect(finished.wait(timeout: .now() + 10) == .success)
        }
    }

    #if canImport(Darwin)
    @Test func foundationLockWaitDoesNotBlockCollectionOfAnEnrolledMutator() {
        var thrown = 0
        let lock = __kk_foundation_lock_create(&thrown)
        #expect(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(lock) }
        _ = __kk_foundation_lock_lock(lock, &thrown)
        #expect(thrown == 0)
        let waiting = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let collected = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            __kk_gc_mutator_enter()
            waiting.signal()
            var failure = 0
            _ = __kk_foundation_lock_lock(lock, &failure)
            #expect(failure == 0)
            _ = __kk_foundation_lock_unlock(lock, &failure)
            __kk_gc_mutator_leave()
            finished.signal()
        }
        #expect(waiting.wait(timeout: .now() + 5) == .success)
        DispatchQueue.global().async {
            kk_gc_collect()
            collected.signal()
        }
        let earlyCollection = collected.wait(timeout: .now() + 2)
        #expect(earlyCollection == .success)
        let finishedBeforeUnlock = finished.wait(timeout: .now()) == .success
        #expect(!finishedBeforeUnlock)
        _ = __kk_foundation_lock_unlock(lock, &thrown)
        #expect(thrown == 0)
        if earlyCollection == .timedOut {
            #expect(collected.wait(timeout: .now() + 10) == .success)
        }
        if !finishedBeforeUnlock {
            #expect(finished.wait(timeout: .now() + 10) == .success)
        }
    }

    #endif

    @Test func shadowFrameWritesRemainStableDuringCollection() {
        withDummyTypeInfo { typeInfo in
            let first = ConcurrentFrameSlot(kk_alloc(16, typeInfo))
            let second = ConcurrentFrameSlot(kk_alloc(16, typeInfo))
            let firstRaw = Int(bitPattern: first.pointer.pointee!)
            let secondRaw = Int(bitPattern: second.pointer.pointee!)
            let firstWeak = kk_weak_ref_create(firstRaw)
            let secondWeak = kk_weak_ref_create(secondRaw)
            let ready = DispatchSemaphore(value: 0)
            let written = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let finished = DispatchSemaphore(value: 0)
            kk_register_global_root(first.pointer)
            kk_register_global_root(second.pointer)
            DispatchQueue.global().async {
                kk_gc_shadow_push()
                kk_gc_shadow_set(0, firstRaw)
                ready.signal()
                for index in 0..<200 {
                    kk_gc_shadow_set(0, index.isMultiple(of: 2) ? firstRaw : secondRaw)
                }
                kk_gc_shadow_set(0, firstRaw)
                written.signal()
                release.wait()
                kk_gc_shadow_pop(0, 0)
                finished.signal()
            }
            ready.wait()
            for _ in 0..<200 { kk_gc_collect() }
            written.wait()
            kk_unregister_global_root(first.pointer)
            kk_unregister_global_root(second.pointer)
            kk_gc_collect()
            #expect(kk_weak_ref_get(firstWeak) != runtimeNullSentinelInt)
            #expect(kk_weak_ref_get(secondWeak) == runtimeNullSentinelInt)
            release.signal()
            finished.wait()
            kk_gc_collect()
            #expect(kk_weak_ref_get(firstWeak) == runtimeNullSentinelInt)
        }
    }

    @Test func concurrentFrameRootWritesAreSerializedWithCollection() throws {
        let spec = try #require(RuntimeABISpec.gcFunctions.first { $0.name == "kk_store_frame_root" })
        #expect(spec.parameters.map(\.type) == [.nullableRawPointerPointer, .nullableOpaquePointer])
        #expect(spec.returnType == .void && !spec.isThrowing)
        var rootOffset: Int32 = 0
        withUnsafePointer(to: &rootOffset) { offset in
            var descriptor = FrameMapDescriptorC(rootCount: 1, rootOffsets: offset)
            withUnsafePointer(to: &descriptor) { kk_register_frame_map(79, UnsafeRawPointer($0)) }
        }
        defer { kk_register_frame_map(79, nil) }

        withDummyTypeInfo { typeInfo in
            let first = ConcurrentFrameSlot(kk_alloc(16, typeInfo))
            let second = ConcurrentFrameSlot(kk_alloc(16, typeInfo))
            let frame = ConcurrentFrameSlot(nil)
            let firstWeak = kk_weak_ref_create(Int(bitPattern: first.pointer.pointee!))
            let secondWeak = kk_weak_ref_create(Int(bitPattern: second.pointer.pointee!))
            let registered = DispatchSemaphore(value: 0)
            let written = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let finished = DispatchSemaphore(value: 0)
            kk_register_global_root(first.pointer)
            kk_register_global_root(second.pointer)
            DispatchQueue.global().async {
                kk_push_frame(79, UnsafeMutableRawPointer(frame.pointer))
                registered.signal()
                for index in 0..<200 {
                    kk_store_frame_root(frame.pointer, index.isMultiple(of: 2) ? first.pointer.pointee : second.pointer.pointee)
                }
                kk_store_frame_root(frame.pointer, first.pointer.pointee)
                written.signal()
                release.wait()
                kk_pop_frame()
                finished.signal()
            }
            registered.wait()
            for _ in 0..<200 { kk_gc_collect() }
            written.wait()
            kk_unregister_global_root(first.pointer)
            kk_unregister_global_root(second.pointer)
            kk_gc_collect()
            #expect(kk_weak_ref_get(firstWeak) != runtimeNullSentinelInt)
            #expect(kk_weak_ref_get(secondWeak) == runtimeNullSentinelInt)
            release.signal()
            finished.wait()
            kk_gc_collect()
            #expect(kk_weak_ref_get(firstWeak) == runtimeNullSentinelInt)
        }
    }

    @Test func framePopOnlyRemovesTheCallingThreadsFrame() {
        var rootOffset: Int32 = 0
        withUnsafePointer(to: &rootOffset) { offset in
            var descriptor = FrameMapDescriptorC(rootCount: 1, rootOffsets: offset)
            withUnsafePointer(to: &descriptor) { kk_register_frame_map(78, UnsafeRawPointer($0)) }
        }
        defer { kk_register_frame_map(78, nil) }

        withDummyTypeInfo { typeInfo in
            let mainObject = kk_alloc(16, typeInfo)
            let workerObject = kk_alloc(16, typeInfo)
            let mainWeak = kk_weak_ref_create(Int(bitPattern: mainObject))
            let workerWeak = kk_weak_ref_create(Int(bitPattern: workerObject))
            let mainSlot = ConcurrentFrameSlot(mainObject)
            let workerSlot = ConcurrentFrameSlot(workerObject)
            let registered = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let finished = DispatchSemaphore(value: 0)

            kk_push_frame(78, UnsafeMutableRawPointer(mainSlot.pointer))
            DispatchQueue.global().async {
                kk_push_frame(78, UnsafeMutableRawPointer(workerSlot.pointer))
                registered.signal()
                release.wait()
                kk_pop_frame()
                finished.signal()
            }
            registered.wait()
            kk_pop_frame()
            kk_pop_frame()
            kk_gc_collect()
            #expect(kk_weak_ref_get(mainWeak) == runtimeNullSentinelInt)
            #expect(kk_weak_ref_get(workerWeak) != runtimeNullSentinelInt)
            release.signal()
            finished.wait()
            kk_gc_collect()
            #expect(kk_weak_ref_get(workerWeak) == runtimeNullSentinelInt)
        }
    }

    @Test func callableReflectionKeepsCapturedReceiverAlive() {
        withDummyTypeInfo { ti in
            let captured = Int(bitPattern: kk_alloc(16, ti))
            let callable = registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: 0, closureRaw: 0, arity: 0))
            let tagged = kk_callable_ref_tag_kfunction(callable, runtimeMakeStringRaw("bound"), runtimeMakeStringRaw("kotlin.Int"), 0, 0)
            let environment = registerRuntimeObject(RuntimeListBox(elements: [captured]))
            let empty = registerRuntimeObject(RuntimeListBox(elements: []))
            _ = __kk_kcallable_register(tagged, 0, environment, empty, empty, 1, 0, 0, empty)
            defer { runtimeStorage.withDelegateLock { $0.callableRefMetadataByValue.removeValue(forKey: tagged) } }
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 1)
        }
    }

    @Test func testGCCollectsUnreachableAllocation() {
        withDummyTypeInfo { ti in
            _ = kk_alloc(16, ti)
            #expect(kk_runtime_heap_object_count() == 1)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 0)
        }
    }

    @Test func testGlobalRootPreventsCollectionUntilCleared() {
        withDummyTypeInfo { ti in
            let slot = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
            slot.initialize(to: kk_alloc(16, ti))
            defer {
                slot.deinitialize(count: 1)
                slot.deallocate()
            }

            kk_register_global_root(slot)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 1)

            slot.pointee = nil
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 0)
            kk_unregister_global_root(slot)
        }
    }

    @Test func testFrameMapRootsProtectActiveFramePointers() {
        var rootOffset: Int32 = 0
        withUnsafePointer(to: &rootOffset) { offsetPtr in
            var descriptor = FrameMapDescriptorC(rootCount: 1, rootOffsets: offsetPtr)
            _ = descriptor.rootCount
            _ = descriptor.rootOffsets
            withUnsafePointer(to: &descriptor) { descriptorPtr in
                kk_register_frame_map(77, UnsafeRawPointer(descriptorPtr))
            }
        }

        withDummyTypeInfo { ti in
            let frameRootSlot = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
            frameRootSlot.initialize(to: kk_alloc(8, ti))
            defer {
                frameRootSlot.deinitialize(count: 1)
                frameRootSlot.deallocate()
            }

            kk_push_frame(77, UnsafeMutableRawPointer(frameRootSlot))
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 1)

            frameRootSlot.pointee = nil
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 0)
            kk_pop_frame()

            kk_register_frame_map(77, nil)
        }
    }

    @Test func testCoroutineRootRegistrationPreventsCollection() {
        withDummyTypeInfo { ti in
            let object = kk_alloc(12, ti)
            kk_register_coroutine_root(object)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 1)

            kk_unregister_coroutine_root(object)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 0)
        }
    }

    @Test func testReachableRuntimeObjectRetainsItsChildrenAndWeakReferencesClearAfterSweep() {
        let child = kk_object_new(0, 0x36_26_01)
        let weak = kk_weak_ref_create(child)
        let parent = kk_object_new(1, 0x36_26_02)
        _ = kk_array_set_typed(parent, 0, child, 0)

        let rootSlot = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
        rootSlot.initialize(to: UnsafeMutableRawPointer(bitPattern: parent))
        defer {
            kk_unregister_global_root(rootSlot)
            rootSlot.deinitialize(count: 1)
            rootSlot.deallocate()
            _ = kk_object_release(weak)
        }
        kk_register_global_root(rootSlot)

        // The first pass consumes allocation handoff roots while the explicit
        // parent root keeps both the parent and its child alive.
        kk_gc_collect()
        kk_gc_collect()
        #expect(kk_weak_ref_get(weak) == child)

        rootSlot.pointee = nil
        kk_gc_collect()
        #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
    }

    @Test func unreachableManagedObjectCycleIsCollected() {
        let first = kk_object_new(1, 0x36_26_03)
        let second = kk_object_new(1, 0x36_26_04)
        let firstWeak = kk_weak_ref_create(first)
        let secondWeak = kk_weak_ref_create(second)
        defer {
            _ = kk_object_release(firstWeak)
            _ = kk_object_release(secondWeak)
        }
        _ = kk_array_set_typed(first, 0, second, 0)
        _ = kk_array_set_typed(second, 0, first, 0)

        kk_gc_collect() // Consume allocation handoffs.
        kk_gc_collect()
        #expect(kk_weak_ref_get(firstWeak) == runtimeNullSentinelInt)
        #expect(kk_weak_ref_get(secondWeak) == runtimeNullSentinelInt)
    }

    @Test func managedObjectFieldsSurviveGCReset() {
        let parent = kk_object_new(1, 0x36_26_0C)
        let child = kk_object_new(0, 0x36_26_0D)
        let weak = kk_weak_ref_create(child)
        _ = kk_array_set_typed(parent, 0, child, 0)
        #expect(kk_runtime_reset_gc())
        kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: parent))
        kk_gc_collect()
        #expect(kk_weak_ref_get(weak) == child)
        kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: parent))
        kk_gc_collect()
        #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        _ = kk_object_release(weak)
    }

    @Test func managedResultPayloadSurvivesGCReset() {
        let child = kk_object_new(0, 0x36_26_0E)
        let weak = kk_weak_ref_create(child)
        let result = runtimeResultSuccess(child)
        #expect(kk_runtime_reset_gc())
        kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: result))
        kk_gc_collect()
        #expect(kk_weak_ref_get(weak) == child)
        kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: result))
        kk_gc_collect()
        #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        #expect(kk_object_release(result) == 1)
        _ = kk_object_release(weak)
    }

    @Test(arguments: [0, 1, 2, 3, 4, 5])
    func reachableObjectKeepsAuxiliaryChildren(kind: Int) throws {
        let parent = kk_object_new(0, 0x36_26_0F)
        let child = kk_object_new(0, 0x36_26_10)
        let weak = kk_weak_ref_create(child)
        let object = try #require(resolveRuntimeHandle(parent, as: RuntimeObjectBox.self))
        switch kind {
        case 0:
            object.backingListBox = RuntimeListBox(elements: [child])
        case 1:
            object.backingSetBox = RuntimeSetBox(elements: [child])
        case 2:
            object.backingMapBox = RuntimeMapBox(keys: [1], values: [child])
        case 3:
            object.throwableCause = child
        case 4:
            object.throwableSuppressed = [child]
        default:
            let array = RuntimeArrayBox(length: 1)
            array.elements = [child]
            object.backingListBox = RuntimeListBox(arrayViewOf: array)
        }
        kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: parent))
        kk_gc_collect() // Consume allocation handoffs.
        kk_gc_collect()
        #expect(kk_weak_ref_get(weak) == child)
        kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: parent))
        kk_gc_collect()
        #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        _ = kk_object_release(weak)
    }

    @Test func retainedArrayViewKeepsSharedStorageChildrenAlive() throws {
        let owner = kk_object_new(1, 0x36_26_05)
        let child = kk_object_new(0, 0x36_26_06)
        let weak = kk_weak_ref_create(child)
        defer { _ = kk_object_release(weak) }
        _ = kk_array_set_typed(owner, 0, child, 0)
        let array = try #require(runtimeArrayBox(from: owner))
        let view = array.primitiveView(rawValue: owner, sourceTypeID: 987_301, targetTypeID: 987_302)

        kk_gc_collect() // Consume allocation handoffs.
        kk_gc_collect()
        #expect(kk_weak_ref_get(weak) == child)
        #expect(kk_object_release(view) == 1)
        kk_gc_collect()
        #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
    }

    @Test func rootedListViewTracesUnregisteredArrayStorage() {
        let child = kk_object_new(0, 0x36_26_0A)
        let weak = kk_weak_ref_create(child)
        let array = RuntimeArrayBox(length: 1)
        array.elements = [child]
        let list = registerRuntimeObject(RuntimeListBox(arrayViewOf: array))
        kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: list))
        kk_gc_collect() // Consume the allocation handoff.
        kk_gc_collect()
        #expect(kk_weak_ref_get(weak) == child)
        kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: list))
        kk_gc_collect()
        #expect(kk_weak_ref_get(weak) == child)
        #expect(kk_object_release(list) == 1)
        kk_gc_collect()
        #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        _ = kk_object_release(weak)
    }

    @Test(arguments: [false, true])
    func retainedListViewKeepsSharedArrayChildrenAlive(reversed: Bool) throws {
        let child = kk_object_new(0, 0x36_26_0B)
        let weak = kk_weak_ref_create(child)
        let arrayRaw = kk_array_new(1)
        _ = kk_array_set_typed(arrayRaw, 0, child, 0)
        let array = try #require(runtimeArrayBox(from: arrayRaw))
        let base = RuntimeListBox(arrayViewOf: array)
        let list = registerRuntimeObject(reversed ? RuntimeListBox(reversedViewOf: base) : base)
        #expect(kk_object_release(arrayRaw) == 1)
        kk_gc_collect() // Consume the allocation handoff.
        kk_gc_collect()
        #expect(kk_weak_ref_get(weak) == child)
        #expect(kk_object_release(list) == 1)
        kk_gc_collect()
        #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        _ = kk_object_release(weak)
    }

    @Test func testAllocInitializesObjectHeader() {
        withTestTypeInfo(fieldOffsets: []) { typeInfoPtr in
            let object = kk_alloc(32, UnsafeRawPointer(typeInfoPtr))
            let header = object.assumingMemoryBound(to: ObjHeaderProbe.self).pointee
            #expect(header.size == 32)
            #expect(
                UInt(bitPattern: header.typeInfo)
                    == UInt(bitPattern: typeInfoPtr)
            )
            #expect(header.flags == 0)
        }
    }

    @Test func testGCTracesChildReferenceThroughObjectHeaderTypeInfo() {
        let fieldOffset = UInt32(MemoryLayout<ObjHeaderProbe>.stride)
        let parentSize = UInt32(MemoryLayout<ObjHeaderProbe>.stride + MemoryLayout<UnsafeMutableRawPointer?>.stride)

        withTestTypeInfo(fieldOffsets: [fieldOffset]) { typeInfoPtr in
            let parent = kk_alloc(parentSize, UnsafeRawPointer(typeInfoPtr))
            withDummyTypeInfo { childTI in
                let child = kk_alloc(16, childTI)
                let slot = parent.advanced(by: Int(fieldOffset)).assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
                slot.pointee = child

                let rootSlot = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
                rootSlot.initialize(to: parent)
                defer {
                    rootSlot.deinitialize(count: 1)
                    rootSlot.deallocate()
                }

                kk_register_global_root(rootSlot)
                kk_gc_collect()
                #expect(kk_runtime_heap_object_count() == 2)

                rootSlot.pointee = nil
                kk_gc_collect()
                #expect(kk_runtime_heap_object_count() == 0)
                kk_unregister_global_root(rootSlot)
            }
        }
    }

    // MARK: - GC.lastGCInfo recorder (KUU-2691)

    private func lastGCInfoSnapshot() -> RuntimeGCInfoSnapshot? {
        runtimeStorage.withGCLock { $0.lastGCInfo }
    }

    /// Returns the serialized field list and releases its box; the field
    /// values are plain Ints, so the snapshot outlives the handle.
    private func lastGCInfoFieldValues() -> [Int]? {
        let raw = kk_gc_last_gc_info()
        guard raw != runtimeNullSentinelInt else { return nil }
        defer { _ = runtimeReleaseObject(raw) }
        return runtimeListBox(from: raw)?.elements
    }

    @Test func testLastGCInfoIsNullBeforeAnyCollection() {
        #expect(kk_gc_last_gc_info() == runtimeNullSentinelInt)
        #expect(lastGCInfoSnapshot() == nil)
    }

    @Test func testLastGCInfoRecordsPassStatistics() {
        withDummyTypeInfo { ti in
            kk_gc_collect()
            guard let baseline = lastGCInfoSnapshot() else {
                Issue.record("baseline pass should have been recorded")
                return
            }
            _ = kk_alloc(16, ti)
            kk_gc_collect()

            let snapshot = lastGCInfoSnapshot()
            #expect(snapshot != nil)
            guard let snapshot else { return }

            #expect(snapshot.epoch == baseline.epoch + 1)
            #expect(snapshot.sweptCount == 1)
            #expect(snapshot.keptCount == 0)
            #expect(snapshot.markedCount == baseline.markedCount)
            #expect(snapshot.memoryUsageBeforeBytes == Int64(MemoryLayout<KKObjHeader>.stride))
            #expect(snapshot.memoryUsageAfterBytes == 0)

            #expect(snapshot.startTimeNs <= snapshot.firstPauseRequestTimeNs)
            #expect(snapshot.firstPauseRequestTimeNs <= snapshot.firstPauseStartTimeNs)
            #expect(snapshot.firstPauseStartTimeNs <= snapshot.firstPauseEndTimeNs)
            #expect(snapshot.firstPauseEndTimeNs <= snapshot.endTimeNs)
            #expect(snapshot.secondPauseRequestTimeNs == nil)
            #expect(snapshot.secondPauseStartTimeNs == nil)
            #expect(snapshot.secondPauseEndTimeNs == nil)
            // kk_gc_collect is synchronous: once it returns, reclamation is done.
            if let cleanup = snapshot.postGcCleanupTimeNs {
                #expect(snapshot.endTimeNs <= cleanup)
            } else {
                Issue.record("postGcCleanupTimeNs should be recorded once collect returns")
            }
        }
    }

    @Test func testLastGCInfoEpochIncrementsAcrossCollections() {
        kk_gc_collect()
        #expect(lastGCInfoSnapshot()?.epoch == 1)
        kk_gc_collect()
        #expect(lastGCInfoSnapshot()?.epoch == 2)
    }

    @Test func testLastGCInfoCountsRootSetByPool() {
        // This suite only holds gc+metadata isolation; borrow the threadLocal
        // lock as well so the root we plant here cannot leak into another
        // thread-local suite's pass (or survive into a later test's heap
        // census — `__kk_thread_local_store` has no dispose counterpart).
        let threadLocalLease = RuntimeTestIsolationLease(lockSet: .threadLocalOnly)
        defer {
            kk_runtime_reset_thread_local()
            threadLocalLease.release()
        }
        // Count each pool as a delta over a baseline pass so ambient roots
        // left behind by other suites cannot skew the attribution.
        kk_gc_collect()
        guard let baseline = lastGCInfoSnapshot() else {
            Issue.record("baseline pass should have been recorded")
            return
        }

        withDummyTypeInfo { ti in
            let rooted = kk_alloc(24, ti)
            let slot = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
            slot.initialize(to: rooted)
            defer {
                slot.deinitialize(count: 1)
                slot.deallocate()
            }
            kk_register_global_root(slot)
            defer { kk_unregister_global_root(slot) }

            let coroutineRooted = kk_alloc(8, ti)
            kk_register_coroutine_root(coroutineRooted)
            defer { kk_unregister_coroutine_root(coroutineRooted) }

            let pinned = kk_alloc(8, ti)
            let pinHandle = kk_pin_object(Int(bitPattern: pinned))
            defer { _ = kk_unpin_object(pinHandle) }

            let threadLocal = __kk_thread_local_new()
            _ = __kk_thread_local_store(threadLocal, Int(bitPattern: kk_alloc(8, ti)))

            _ = kk_alloc(16, ti) // unrooted: swept by the pass

            kk_gc_collect()

            let snapshot = lastGCInfoSnapshot()
            #expect(snapshot != nil)
            guard let snapshot else { return }

            #expect(snapshot.epoch == baseline.epoch + 1)
            #expect(snapshot.rootSet.globalReferences == baseline.rootSet.globalReferences + 1)
            #expect(snapshot.rootSet.stackReferences == baseline.rootSet.stackReferences + 1)
            #expect(snapshot.rootSet.stableReferences == baseline.rootSet.stableReferences + 1)
            #expect(snapshot.rootSet.threadLocalReferences == baseline.rootSet.threadLocalReferences + 1)

            // kk_alloc pads requests below the object-header stride (16 bytes).
            let header = Int64(MemoryLayout<KKObjHeader>.stride)
            #expect(snapshot.markedCount == baseline.markedCount + 4)
            #expect(snapshot.keptCount == 4)
            #expect(snapshot.sweptCount == 1)
            #expect(snapshot.memoryUsageBeforeBytes == 24 + header * 4)
            #expect(snapshot.memoryUsageAfterBytes == 24 + header * 3)
            #expect(kk_runtime_heap_object_count() == 4)
        }
    }

    @Test func testLastGCInfoReturnsDistinctImmutableSnapshots() {
        kk_gc_collect()
        let first = lastGCInfoFieldValues()
        #expect(first != nil)
        kk_gc_collect()
        let second = lastGCInfoFieldValues()
        #expect(second != nil)
        guard let first, let second else { return }

        // Each call yields a snapshot of the latest pass: the first still
        // reports epoch 1 while the second reports epoch 2 — the later
        // collection did not retroactively rewrite the earlier list.
        #expect(first.first == 1)
        #expect(second.first == 2)
        #expect(second == lastGCInfoSnapshot()?.serializedFieldValues)
    }

    @Test func testLastGCInfoListLayoutMatchesSnapshot() {
        withDummyTypeInfo { ti in
            _ = kk_alloc(16, ti)
            kk_gc_collect()
            let snapshot = lastGCInfoSnapshot()
            let fields = lastGCInfoFieldValues()
            #expect(snapshot != nil && fields != nil)
            guard let snapshot, let fields else { return }
            #expect(fields == snapshot.serializedFieldValues)
        }
    }

    @Test func testGCRemovesPerObjectDispatchMetadataForSweptHeapObject() {
        withDummyTypeInfo { ti in
            let object = kk_alloc(16, ti)
            let objectRaw = Int(bitPattern: object)
            let objectKey = UInt(bitPattern: object)
            let itableKey = (UInt64(UInt32(2)) << 32) | UInt64(UInt32(3))

            runtimeRegisterObjectType(rawValue: objectRaw, classID: 42)
            _ = kk_object_register_itable_iface(objectRaw, 7, 2)
            _ = kk_object_register_itable_method(objectRaw, 2, 3, 0x1000)
            _ = kk_object_register_vtable_method(objectRaw, 4, 0x2000)
            _ = kk_object_register_equals_override(objectRaw, 0x3000)
            _ = kk_object_register_hashcode_override(objectRaw, 0x3100)

            runtimeStorage.withMetadataLock { state in
                #expect(state.objectTypeByPointer[objectKey] == 42)
                #expect(state.objectInterfaceSlots[objectKey]?[7] == 2)
                #expect(state.objectItableMethods[objectKey]?[itableKey] == 0x1000)
                #expect(state.objectVtableMethods[objectKey]?[4] == 0x2000)
                #expect(state.objectEqualsOverrides[objectKey] == 0x3000)
                #expect(state.objectHashCodeOverrides[objectKey] == 0x3100)
            }

            kk_gc_collect()

            #expect(kk_runtime_heap_object_count() == 0)
            runtimeStorage.withMetadataLock { state in
                #expect(state.objectTypeByPointer[objectKey] == nil)
                #expect(state.objectInterfaceSlots[objectKey] == nil)
                #expect(state.objectItableMethods[objectKey] == nil)
                #expect(state.objectVtableMethods[objectKey] == nil)
                #expect(state.objectEqualsOverrides[objectKey] == nil)
                #expect(state.objectHashCodeOverrides[objectKey] == nil)
            }
        }
    }
}
