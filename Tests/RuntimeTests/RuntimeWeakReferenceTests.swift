@testable import Runtime
import Testing

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
