import Dispatch
import Foundation
@testable import Runtime
import Testing

private func withThreadLocalTestTypeInfo(
    fieldOffsets: [UInt32],
    body: (UnsafePointer<KTypeInfo>) -> Void
) {
    let typeName = Array("ThreadLocal.Test.Type\0".utf8).map(CChar.init)
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

private func withThreadLocalDummyTypeInfo(_ body: (UnsafeRawPointer) -> Void) {
    withThreadLocalTestTypeInfo(fieldOffsets: []) { typeInfoPtr in
        body(UnsafeRawPointer(typeInfoPtr))
    }
}

private final class ThreadLocalThunkState: @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private var configuredReturnValue = 0

    func reset() {
        lock.lock()
        callCount = 0
        configuredReturnValue = 0
        lock.unlock()
    }

    func incrementingValue() -> Int {
        lock.lock()
        callCount += 1
        let value = callCount
        lock.unlock()
        return value
    }

    func configuredValue() -> Int {
        lock.lock()
        callCount += 1
        let value = configuredReturnValue
        lock.unlock()
        return value
    }

    func setConfiguredReturnValue(_ value: Int) {
        lock.lock()
        configuredReturnValue = value
        lock.unlock()
    }

    func callCountSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return callCount
    }
}

private let threadLocalThunkState = ThreadLocalThunkState()

private let incrementingThreadLocalThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in
    threadLocalThunkState.incrementingValue()
}

private let configuredThreadLocalThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in
    threadLocalThunkState.configuredValue()
}

private let incrementingThreadLocalThunkPtr = unsafeBitCast(incrementingThreadLocalThunk, to: Int.self)
private let configuredThreadLocalThunkPtr = unsafeBitCast(configuredThreadLocalThunk, to: Int.self)

private final class ThreadLocalBackgroundValueBox: @unchecked Sendable {
    let pointer: UnsafeMutablePointer<Int>

    init(initialValue: Int) {
        pointer = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        pointer.initialize(to: initialValue)
    }

    deinit {
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }
}

private func resetRuntimeThreadLocalTestState() {
    threadLocalThunkState.reset()
}

@Suite(.runtimeIsolation(.gcAndThreadLocal, resetAdditionalState: resetRuntimeThreadLocalTestState))
struct RuntimeThreadLocalTests {
    @Test func getOrSetCachesWithinSameThread() {
        let receiver = kk_thread_local_new()

        let first = kk_thread_local_getOrSet(
            receiver,
            incrementingThreadLocalThunkPtr,
            0,
            nil as UnsafeMutablePointer<Int>?
        )
        let second = kk_thread_local_getOrSet(
            receiver,
            incrementingThreadLocalThunkPtr,
            0,
            nil as UnsafeMutablePointer<Int>?
        )

        #expect(first == 1)
        #expect(second == 1)
        #expect(threadLocalThunkState.callCountSnapshot() == 1)
    }

    @Test func getOrSetIsThreadLocalAcrossThreads() {
        let receiver = kk_thread_local_new()

        let mainValue = kk_thread_local_getOrSet(
            receiver,
            incrementingThreadLocalThunkPtr,
            0,
            nil as UnsafeMutablePointer<Int>?
        )

        let backgroundValue = ThreadLocalBackgroundValueBox(initialValue: -1)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            backgroundValue.pointer.pointee = kk_thread_local_getOrSet(
                receiver,
                incrementingThreadLocalThunkPtr,
                0,
                nil as UnsafeMutablePointer<Int>?
            )
            group.leave()
        }
        #expect(group.wait(timeout: .now() + .seconds(5)) == .success)

        let secondMainValue = kk_thread_local_getOrSet(
            receiver,
            incrementingThreadLocalThunkPtr,
            0,
            nil as UnsafeMutablePointer<Int>?
        )

        #expect(mainValue == 1)
        #expect(backgroundValue.pointer.pointee == 2)
        #expect(secondMainValue == 1)
        #expect(threadLocalThunkState.callCountSnapshot() == 2)
    }

    @Test func getOrSetDoesNotCacheRuntimeNullSentinel() {
        threadLocalThunkState.setConfiguredReturnValue(runtimeNullSentinelInt)
        let receiver = kk_thread_local_new()

        let first = kk_thread_local_getOrSet(
            receiver,
            configuredThreadLocalThunkPtr,
            0,
            nil as UnsafeMutablePointer<Int>?
        )
        let second = kk_thread_local_getOrSet(
            receiver,
            configuredThreadLocalThunkPtr,
            0,
            nil as UnsafeMutablePointer<Int>?
        )

        #expect(first == runtimeNullSentinelInt)
        #expect(second == runtimeNullSentinelInt)
        #expect(threadLocalThunkState.callCountSnapshot() == 2)
    }

    @Test func getOrSetCachesZero() {
        threadLocalThunkState.setConfiguredReturnValue(0)
        let receiver = kk_thread_local_new()

        let first = kk_thread_local_getOrSet(
            receiver,
            configuredThreadLocalThunkPtr,
            0,
            nil as UnsafeMutablePointer<Int>?
        )
        let second = kk_thread_local_getOrSet(
            receiver,
            configuredThreadLocalThunkPtr,
            0,
            nil as UnsafeMutablePointer<Int>?
        )

        #expect(first == 0)
        #expect(second == 0)
        #expect(threadLocalThunkState.callCountSnapshot() == 1)
    }

    @Test func getOrSetKeepsAllocatedObjectAliveAcrossGC() {
        withThreadLocalDummyTypeInfo { ti in
            let object = kk_alloc(16, ti)
            let objectHandle = Int(bitPattern: object)
            threadLocalThunkState.setConfiguredReturnValue(objectHandle)
            let receiver = kk_thread_local_new()

            let stored = kk_thread_local_getOrSet(
                receiver,
                configuredThreadLocalThunkPtr,
                0,
                nil as UnsafeMutablePointer<Int>?
            )

            #expect(stored == objectHandle)
            #expect(threadLocalThunkState.callCountSnapshot() == 1)
            #expect(kk_runtime_heap_object_count() == 1)

            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 1)
        }
    }
}
