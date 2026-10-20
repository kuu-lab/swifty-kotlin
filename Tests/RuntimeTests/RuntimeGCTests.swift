@testable import Runtime
import Testing

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

@Suite(.runtimeIsolation(.gcAndMetadata))
struct RuntimeGCTests {
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
            _ = kk_alloc(16, ti)
            kk_gc_collect()

            let snapshot = lastGCInfoSnapshot()
            #expect(snapshot != nil)
            guard let snapshot else { return }

            #expect(snapshot.epoch == 1)
            #expect(snapshot.sweptCount == 1)
            #expect(snapshot.keptCount == 0)
            #expect(snapshot.markedCount == 0)
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
            #expect(snapshot.markedCount == 4)
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
