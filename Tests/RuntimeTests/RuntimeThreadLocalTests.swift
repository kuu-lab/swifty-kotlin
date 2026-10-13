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
}
