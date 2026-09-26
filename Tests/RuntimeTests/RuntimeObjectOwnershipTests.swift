import Testing
@testable import Runtime

@Suite(.serialized, .runtimeIsolation(.all))
struct RuntimeObjectOwnershipTests {
    @Test
    func releaseRemovesHandleBeforeDroppingARCReference() {
        let object = kk_object_new(2, 503)
        _ = kk_object_register_vtable_method(object, 0, 0x1234)

        #expect(runtimeIsRegisteredObject(object))
        #expect(kk_object_type_id(object) == 503)
        #expect(kk_object_release(object) == 1)

        #expect(!runtimeIsRegisteredObject(object))
        #expect(runtimeObjectTypeID(rawValue: object) == nil)
        #expect(kk_object_release(object) == 0)
    }

    @Test
    func releaseDoesNotBreakPinnedObjectOwnership() {
        let object = kk_box_int(7)
        let pinned = kk_pin_object(object)

        #expect(kk_object_release(object) == 0)
        #expect(kk_pinned_get(pinned) == object)
        #expect(kk_unpin_object(pinned) == object)
        #expect(kk_object_release(object) == 1)
    }

    @Test
    func borrowedSentinelsAreNotPassedToARCRelease() {
        let suspended = Int(bitPattern: kk_coroutine_suspended())
        let flowStopped = __kk_flow_stopped()
        let nonCancellable = kk_non_cancellable_instance()

        #expect(kk_object_release(suspended) == 0)
        #expect(kk_object_release(flowStopped) == 0)
        #expect(kk_object_release(nonCancellable) == 0)
    }

    @Test
    func boxedAllocationLoopKeepsRegistryAndResidentMemoryBounded() {
        let baselineObjectCount = runtimeObjectPointerCount()
        let baselineResidentBytes = runtimeCaptureMemorySnapshot().totalBytes
        var peakObjectCount = baselineObjectCount
        var peakResidentBytes = baselineResidentBytes

        for value in 0 ..< 100_000 {
            let object = kk_box_int(value)
            if value.isMultiple(of: 256) {
                peakObjectCount = max(peakObjectCount, runtimeObjectPointerCount())
                peakResidentBytes = max(
                    peakResidentBytes,
                    runtimeCaptureMemorySnapshot().totalBytes
                )
            }
            #expect(kk_unbox_int(object) == value)
            #expect(kk_object_release(object) == 1)
        }

        #expect(runtimeObjectPointerCount() == baselineObjectCount)
        #expect(peakObjectCount <= baselineObjectCount + 1)
        // The allocator may retain freed pages, so the RSS assertion uses a
        // generous fixed envelope while the registry count proves no linear
        // accumulation of live box ownership.
        #expect(peakResidentBytes <= baselineResidentBytes + 64 * 1024 * 1024)
    }

    private func runtimeIsRegisteredObject(_ raw: Int) -> Bool {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: raw) else {
            return false
        }
        return runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: pointer))
        }
    }

    private func runtimeObjectPointerCount() -> Int {
        runtimeStorage.withGCLock { state in
            state.objectPointers.count
        }
    }
}
