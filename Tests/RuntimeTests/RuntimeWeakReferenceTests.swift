import Dispatch
import Foundation
@testable import Runtime
import Testing

private final class WeakReadRaceResult: @unchecked Sendable {
    var value: Int = runtimeNullSentinelInt
}

/// KUU-1666: immediate words are live referents, while tracked heap referents
/// still become null after collection and are never rooted by a weak handle.
@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeWeakReferenceTests {
    @Test(arguments: [0, -1, Int(Int32.min), Int(Int32.max)])
    func immediateIntReferentsRoundTrip(value: Int) {
        let weakRaw = kk_weak_ref_create(value)
        #expect(kk_weak_ref_get(weakRaw) == value)
    }

    @Test
    func zeroImmediateIsLiveUntilExplicitClear() {
        let weakRaw = kk_weak_ref_create(0)
        #expect(kk_weak_ref_get(weakRaw) == 0)

        #expect(kk_weak_ref_clear(weakRaw) == 0)
        #expect(kk_weak_ref_get(weakRaw) == runtimeNullSentinelInt)
    }

    @Test(arguments: [0, 1, 0x7A, 0xD83D, 0xFFFF])
    func immediateBooleanAndCharWordsRoundTrip(value: Int) {
        let weakRaw = kk_weak_ref_create(value)
        #expect(kk_weak_ref_get(weakRaw) == value)
    }

    @Test
    func taggedPrimitiveBoxesRemainLiveReferents() {
        let intRaw = kk_box_int(-2_147_483_648)
        let longMinRaw = kk_box_long_nonnull_static(Int.min)
        let longMaxRaw = kk_box_long_static(Int.max)
        let falseRaw = kk_box_bool(0)
        let charRaw = kk_box_char(0xD83D)

        #expect(kk_unbox_int(kk_weak_ref_get(kk_weak_ref_create(intRaw))) == -2_147_483_648)
        #expect(kk_unbox_long_static(kk_weak_ref_get(kk_weak_ref_create(longMinRaw))) == Int.min)
        #expect(kk_unbox_long_static(kk_weak_ref_get(kk_weak_ref_create(longMaxRaw))) == Int.max)
        #expect(kk_unbox_bool(kk_weak_ref_get(kk_weak_ref_create(falseRaw))) == 0)
        #expect(kk_unbox_char(kk_weak_ref_get(kk_weak_ref_create(charRaw))) == 0xD83D)
    }

    @Test
    func releasedTaggedReferentReturnsNullWithoutDereferencingIt() {
        let referentRaw = kk_box_int(12_345)
        let weakRaw = kk_weak_ref_create(referentRaw)

        #expect(kk_object_release(referentRaw) == 1)
        #expect(kk_weak_ref_get(weakRaw) == runtimeNullSentinelInt)
    }

    @Test
    func collectedHeapReferentReturnsNullSentinel() {
        withWeakReferenceTestTypeInfo { typeInfo in
            let object = kk_alloc(16, typeInfo)
            let weakRaw = kk_weak_ref_create(Int(bitPattern: object))
            #expect(kk_weak_ref_get(weakRaw) != runtimeNullSentinelInt)

            kk_gc_collect()

            #expect(kk_runtime_heap_object_count() == 0)
            #expect(kk_weak_ref_get(weakRaw) == runtimeNullSentinelInt)
        }
    }

    @Test
    func recycledHeapAddressDoesNotReviveOldWeakReference() {
        withWeakReferenceTestTypeInfo { typeInfo in
            let pointer = kk_alloc(16, typeInfo)
            let raw = Int(bitPattern: pointer)
            let oldWeak = kk_weak_ref_create(raw)
            #expect(kk_weak_ref_get(oldWeak) == raw)

            // Deterministically model an allocator reusing the same storage.
            // Removing the old record ends its lifetime in the managed heap;
            // registering the initialized storage again creates a new one.
            runtimeStorage.withGCLock { state in
                _ = state.heapObjects.removeValue(forKey: UInt(bitPattern: pointer))
            }
            runtimeRegisterHeapAllocation(pointer, byteCount: 16)
            let newWeak = kk_weak_ref_create(raw)
            #expect(kk_weak_ref_get(oldWeak) == runtimeNullSentinelInt)
            #expect(kk_weak_ref_get(newWeak) == raw)
            kk_gc_collect()
            #expect(kk_weak_ref_get(newWeak) == runtimeNullSentinelInt)
        }
    }

    @Test
    func weakReadsAtomicallyPublishTheirResultSlots() {
        withWeakReferenceTestTypeInfo { typeInfo in
            let first = Int(bitPattern: kk_alloc(16, typeInfo))
            let second = Int(bitPattern: kk_alloc(16, typeInfo))
            let firstWeak = kk_weak_ref_create(first)
            let secondWeak = kk_weak_ref_create(second)
            kk_gc_shadow_push()
            #expect(kk_weak_ref_get_rooted(firstWeak, 0) == first)
            #expect(kk_weak_ref_get_rooted(secondWeak, 1) == second)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 2)

            kk_gc_shadow_set(0, 0)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 1)
            #expect(kk_weak_ref_get(firstWeak) == runtimeNullSentinelInt)

            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 1)
            kk_gc_shadow_set(1, 0)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 0)
            #expect(kk_weak_ref_get(secondWeak) == runtimeNullSentinelInt)
            kk_gc_shadow_pop(0, 0)
        }
    }

    @Test
    func weakReadAndConcurrentCollectionHaveAnAtomicHandoff() {
        withWeakReferenceTestTypeInfo { typeInfo in
            for _ in 0 ..< 64 {
                let raw = Int(bitPattern: kk_alloc(16, typeInfo))
                let weak = kk_weak_ref_create(raw)
                let result = WeakReadRaceResult()
                let ready = DispatchSemaphore(value: 0)
                let start = DispatchSemaphore(value: 0)
                let read = DispatchSemaphore(value: 0)
                let release = DispatchSemaphore(value: 0)
                let finished = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    kk_gc_shadow_push()
                    ready.signal()
                    start.wait()
                    result.value = kk_weak_ref_get_rooted(weak, 0)
                    read.signal()
                    release.wait()
                    kk_gc_shadow_pop(0, 0)
                    finished.signal()
                }
                ready.wait()
                start.signal()
                kk_gc_collect()
                read.wait()
                if result.value == raw {
                    #expect(kk_runtime_heap_object_count() == 1)
                } else {
                    #expect(result.value == runtimeNullSentinelInt)
                    #expect(kk_runtime_heap_object_count() == 0)
                }
                release.signal()
                finished.wait()
                kk_gc_collect()
                #expect(kk_runtime_heap_object_count() == 0)
            }
        }
    }

    @Test
    func repeatedWeakReadsKeepSeparateResultSlots() {
        withWeakReferenceTestTypeInfo { typeInfo in
            let raw = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(raw)
            kk_gc_shadow_push()
            #expect(kk_weak_ref_get_rooted(weak, 0) == raw)
            #expect(kk_weak_ref_get_rooted(weak, 1) == raw)

            kk_gc_shadow_set(0, 0)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 1)
            kk_gc_shadow_set(1, 0)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 0)
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
            kk_gc_shadow_pop(0, 0)
        }
    }

    @Test
    func unrelatedAliasDoesNotConsumePendingWeakRead() {
        withWeakReferenceTestTypeInfo { typeInfo in
            let raw = Int(bitPattern: kk_alloc(16, typeInfo))
            let weak = kk_weak_ref_create(raw)
            kk_gc_shadow_push()
            #expect(kk_weak_ref_get(weak) == raw)

            // An unrelated alias may have the same value as a pending read.
            kk_gc_shadow_set(3, raw)
            kk_gc_shadow_set(3, 0)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 1)

            kk_gc_shadow_pop(0, 0)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 0)
            #expect(kk_weak_ref_get(weak) == runtimeNullSentinelInt)
        }
    }

    @Test
    func immediateReadDoesNotConsumeAnotherWeakReadAtSameAddress() {
        withWeakReferenceTestTypeInfo { typeInfo in
            let pointer = kk_alloc(16, typeInfo)
            let raw = Int(bitPattern: pointer)
            // Create an immediate with the same bits as a later allocation.
            runtimeStorage.withGCLock { state in
                _ = state.heapObjects.removeValue(forKey: UInt(bitPattern: pointer))
            }
            let immediateWeak = kk_weak_ref_create(raw)
            runtimeRegisterHeapAllocation(pointer, byteCount: 16)
            let heapWeak = kk_weak_ref_create(raw)
            kk_gc_shadow_push()
            #expect(kk_weak_ref_get(heapWeak) == raw)
            #expect(kk_weak_ref_get_rooted(immediateWeak, 4) == raw)
            kk_gc_shadow_set(4, 0)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 1)
            kk_gc_shadow_pop(0, 0)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 0)
            #expect(kk_weak_ref_get(heapWeak) == runtimeNullSentinelInt)
            #expect(kk_weak_ref_get(immediateWeak) == raw)
        }
    }
}

private func withWeakReferenceTestTypeInfo(_ body: (UnsafeRawPointer) -> Void) {
    let typeName = Array("Test.WeakReference\0".utf8).map(CChar.init)
    let offsetStorage = [UInt32(0)]
    var emptyVtableEntry = UnsafeRawPointer(bitPattern: 0x1)!
    typeName.withUnsafeBufferPointer { nameBuffer in
        offsetStorage.withUnsafeBufferPointer { offsetBuffer in
            withUnsafePointer(to: &emptyVtableEntry) { vtablePointer in
                var typeInfo = KTypeInfo(
                    fqName: nameBuffer.baseAddress!,
                    instanceSize: 0,
                    fieldCount: 0,
                    fieldOffsets: offsetBuffer.baseAddress!,
                    vtableSize: 0,
                    vtable: vtablePointer,
                    itable: nil,
                    gcDescriptor: nil
                )
                withUnsafePointer(to: &typeInfo) { typeInfoPointer in
                    body(UnsafeRawPointer(typeInfoPointer))
                }
            }
        }
    }
}
