import Dispatch
import Testing
@testable import Runtime

private final class RuntimeHandleReleaseProbe: @unchecked Sendable {
    let value: Int
    private let deinitialized: DispatchSemaphore

    init(value: Int, deinitialized: DispatchSemaphore) {
        self.value = value
        self.deinitialized = deinitialized
    }

    deinit {
        // A final release under the nonrecursive GC lock would deadlock.
        runtimeStorage.withGCLock { _ in }
        deinitialized.signal()
    }
}

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

        // Both canonical resolvers must keep a returned object alive after its
        // registry owner is released. Failed casts must not leak a retain.
        let deinitialized = DispatchSemaphore(value: 0)
        let retainedRaw = registerRuntimeObject(RuntimeHandleReleaseProbe(
            value: 7, deinitialized: deinitialized
        ))
        var typed = resolveRuntimeHandle(retainedRaw, as: RuntimeHandleReleaseProbe.self)
        var untyped = resolveRuntimeObjectHandle(retainedRaw)
        #expect(typed?.value == 7)
        #expect((untyped as? RuntimeHandleReleaseProbe) === typed)
        #expect(resolveRuntimeHandle(retainedRaw, as: RuntimeArrayBox.self) == nil)
        #expect(kk_object_release(retainedRaw) == 1)
        #expect(resolveRuntimeObjectHandle(retainedRaw) == nil)
        #expect(typed?.value == 7)
        typed = nil
        withExtendedLifetime(untyped) {
            #expect(deinitialized.wait(timeout: .now()) == .timedOut)
        }
        untyped = nil
        #expect(deinitialized.wait(timeout: .now() + 3) == .success)

        // Low bits on primitive handles are tags, not the ARC object address.
        // A value outside the identity cache gives this control one real owner.
        let tagged = kk_box_int(20_000)
        var primitive = resolveRuntimeObjectHandle(tagged) as? RuntimeIntBox
        #expect(primitive?.value == 20_000)
        #expect(resolveRuntimeHandle(tagged, as: RuntimeHandleReleaseProbe.self) == nil)
        #expect(kk_object_release(tagged) == 1)
        #expect(primitive?.value == 20_000)
        #expect(resolveRuntimeObjectHandle(tagged) == nil)
        primitive = nil

        // Use the real atomic kernel as well: removal of its external owner
        // must not free storage while an already resolved operation holds it.
        let atomicRaw = kk_atomic_ref_create(17)
        var atomic = resolveRuntimeHandle(atomicRaw, as: AtomicRefBox.self)
        #expect(kk_object_release(atomicRaw) == 1)
        atomic?.store(23)
        #expect(atomic?.load() == 23)
        #expect(resolveRuntimeHandle(atomicRaw, as: AtomicRefBox.self) == nil)
        atomic = nil

        // Race registry release against each real canonical resolver. A valid
        // result or nil is allowed; retaining a freed pointer is never allowed.
        // This is a bounded race regression, not a scheduler-fairness proof.
        let baseline = runtimeObjectPointerCount()
        for value in 0 ..< 256 {
            let finalized = DispatchSemaphore(value: 0)
            let raw = registerRuntimeObject(RuntimeHandleReleaseProbe(
                value: value, deinitialized: finalized
            ))
            let ready = DispatchSemaphore(value: 0)
            let start = DispatchSemaphore(value: 0)
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                ready.signal()
                #expect(start.wait(timeout: .now() + 3) == .success)
                #expect(kk_object_release(raw) == 1)
            }
            #expect(ready.wait(timeout: .now() + 3) == .success)
            start.signal()
            var resolved: AnyObject?
            if value.isMultiple(of: 2) {
                resolved = resolveRuntimeHandle(raw, as: RuntimeHandleReleaseProbe.self)
            } else {
                resolved = resolveRuntimeObjectHandle(raw)
            }
            if let probe = resolved as? RuntimeHandleReleaseProbe {
                #expect(probe.value == value)
            }
            let completed = group.wait(timeout: .now() + 3) == .success
            #expect(completed)
            // Do not reset runtime isolation under an undrained worker. The
            // existing outer finite gate watchdog handles a genuine deadlock.
            if !completed { group.wait() }
            #expect(resolveRuntimeHandle(raw, as: RuntimeHandleReleaseProbe.self) == nil)
            #expect(resolveRuntimeObjectHandle(raw) == nil)
            #expect(kk_object_release(raw) == 0)
            resolved = nil
            #expect(finalized.wait(timeout: .now() + 3) == .success)
        }
        #expect(runtimeObjectPointerCount() == baseline)
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
