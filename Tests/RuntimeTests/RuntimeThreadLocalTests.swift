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

private final class ThreadLocalBackgroundValueBox: @unchecked Sendable {
    let pointer = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    init() { pointer.initialize(to: -1) }
    deinit {
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }
}

@Suite(.runtimeIsolation(.gcAndThreadLocal))
struct RuntimeThreadLocalTests {
    @Test func removeClearsCurrentThreadValue() {
        let receiver = __kk_thread_local_new()
        _ = __kk_thread_local_store(receiver, 42)
        #expect(__kk_thread_local_has_value(receiver) == 1)
        #expect(__kk_thread_local_remove(receiver) == 0)
        #expect(__kk_thread_local_has_value(receiver) == 0)
        #expect(__kk_thread_local_value(receiver) == runtimeNullSentinelInt)
    }

    @Test func removingValueReleasesItsGCRoot() {
        withThreadLocalDummyTypeInfo { info in
            let object = kk_alloc(16, info)
            let receiver = __kk_thread_local_new()
            let weak = kk_weak_ref_create(Int(bitPattern: object))
            _ = __kk_thread_local_store(receiver, Int(bitPattern: object))
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            _ = __kk_thread_local_remove(receiver)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test(arguments: [0, 42, runtimeNullSentinelInt])
    func storageDistinguishesUninitializedFromStoredValues(value: Int) {
        let receiver = __kk_thread_local_new()
        #expect(__kk_thread_local_has_value(receiver) == 0)
        #expect(__kk_thread_local_value(receiver) == runtimeNullSentinelInt)
        #expect(__kk_thread_local_store(receiver, value) == 0)
        #expect(__kk_thread_local_has_value(receiver) == 1)
        #expect(__kk_thread_local_value(receiver) == value)
    }

    @Test func storageIsThreadLocalAndInstanceLocal() {
        let receiver = __kk_thread_local_new()
        let other = __kk_thread_local_new()
        _ = __kk_thread_local_store(receiver, 12)
        #expect(__kk_thread_local_has_value(other) == 0)
        let background = ThreadLocalBackgroundValueBox()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            if __kk_thread_local_has_value(receiver) == 0 {
                _ = __kk_thread_local_store(receiver, 24)
                background.pointer.pointee = __kk_thread_local_value(receiver)
                _ = __kk_thread_local_remove(receiver)
                if __kk_thread_local_has_value(receiver) != 0 {
                    background.pointer.pointee = -2
                }
            }
            done.signal()
        }
        done.wait()
        #expect(background.pointer.pointee == 24)
        #expect(__kk_thread_local_value(receiver) == 12)
    }

    @Test func storedObjectRemainsRootedAcrossGC() {
        withThreadLocalDummyTypeInfo { info in
            let object = kk_alloc(16, info)
            let receiver = __kk_thread_local_new()
            _ = __kk_thread_local_store(receiver, Int(bitPattern: object))
            #expect(kk_runtime_heap_object_count() == 1)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 1)
            #expect(__kk_thread_local_value(receiver) == Int(bitPattern: object))
        }
    }

    @Test func threadExitDropsOnlyThatThreadsRoots() {
        withThreadLocalDummyTypeInfo { info in
            let mainObject = kk_alloc(16, info)
            let workerObject = kk_alloc(16, info)
            let mainRaw = Int(bitPattern: mainObject)
            let workerRaw = Int(bitPattern: workerObject)
            let mainWeak = kk_weak_ref_create(mainRaw)
            let workerWeak = kk_weak_ref_create(workerRaw)
            let first = __kk_thread_local_new()
            let second = __kk_thread_local_new()
            _ = __kk_thread_local_store(first, mainRaw)
            let ready = DispatchSemaphore(value: 0)
            let allowExit = DispatchSemaphore(value: 0)
            let thread = Thread {
                _ = __kk_thread_local_store(first, workerRaw)
                _ = __kk_thread_local_store(second, workerRaw)
                ready.signal()
                allowExit.wait()
            }
            thread.start()
            let didStart = ready.wait(timeout: .now() + 3) == .success
            #expect(didStart)
            guard didStart else {
                allowExit.signal()
                while !thread.isFinished { Thread.sleep(forTimeInterval: 0.005) }
                return
            }
            kk_gc_collect()
            #expect(kk_weak_ref_get(mainWeak) != runtimeNullSentinelInt)
            #expect(kk_weak_ref_get(workerWeak) != runtimeNullSentinelInt)
            allowExit.signal()

            let deadline = Date(timeIntervalSinceNow: 3)
            var cleaned = false
            while Date() < deadline {
                cleaned = thread.isFinished && runtimeStorage.withThreadLocalLock { state in
                    state.threadLocalValues[UInt(bitPattern: first)]?.count == 1
                        && state.threadLocalValues[UInt(bitPattern: second)] == nil
                }
                if cleaned { break }
                Thread.sleep(forTimeInterval: 0.005)
            }
            #expect(cleaned)
            // Do not reset test isolation while a worker can still use it.
            while !thread.isFinished { Thread.sleep(forTimeInterval: 0.005) }
            if cleaned {
                kk_gc_collect()
                #expect(kk_weak_ref_get(workerWeak) == runtimeNullSentinelInt)
                #expect(kk_weak_ref_get(mainWeak) != runtimeNullSentinelInt)
                #expect(__kk_thread_local_value(first) == mainRaw)
                _ = __kk_thread_local_remove(first)
                kk_gc_collect()
                #expect(kk_weak_ref_get(mainWeak) == runtimeNullSentinelInt)
            }
        }
    }

    @Test func concurrentCollectionPreservesPublishedThreadLocalValue() {
        withThreadLocalDummyTypeInfo { info in
            let object = kk_alloc(16, info)
            let receiver = __kk_thread_local_new()
            let weak = kk_weak_ref_create(Int(bitPattern: object))
            let root = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
            root.initialize(to: object)
            kk_register_global_root(root)
            let started = DispatchSemaphore(value: 0)
            let stop = DispatchSemaphore(value: 0)
            let finished = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                started.signal()
                while stop.wait(timeout: .now()) == .timedOut {
                    kk_gc_collect()
                }
                finished.signal()
            }
            started.wait()
            _ = __kk_thread_local_store(receiver, Int(bitPattern: object))
            kk_unregister_global_root(root)
            for _ in 0..<100 { kk_gc_collect() }
            stop.signal()
            finished.wait()
            #expect(kk_weak_ref_get(weak) != runtimeNullSentinelInt)
            _ = __kk_thread_local_remove(receiver)
            kk_gc_collect()
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            root.deinitialize(count: 1)
            root.deallocate()
        }
    }
}
