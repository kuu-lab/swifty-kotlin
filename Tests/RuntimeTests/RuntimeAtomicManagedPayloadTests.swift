import Dispatch
import Foundation
import Testing
@testable import Runtime

private func withAtomicPayloadTypeInfo(
    offsets: [UInt32] = [],
    body: (UnsafeRawPointer) -> Void
) {
    let name = Array("Atomic.ManagedPayload\0".utf8).map(CChar.init)
    let fields = offsets.isEmpty ? [UInt32(0)] : offsets
    var emptyVtable = UnsafeRawPointer(bitPattern: 1)!
    name.withUnsafeBufferPointer { names in
        fields.withUnsafeBufferPointer { fieldOffsets in
            withUnsafePointer(to: &emptyVtable) { vtable in
                var descriptor = KTypeInfo(
                    fqName: names.baseAddress!, instanceSize: 0,
                    fieldCount: UInt32(offsets.count), fieldOffsets: fieldOffsets.baseAddress!,
                    vtableSize: 0, vtable: vtable, itable: nil, gcDescriptor: nil
                )
                withUnsafePointer(to: &descriptor) { body(UnsafeRawPointer($0)) }
            }
        }
    }
}

@Suite(.serialized, .runtimeIsolation(.gcAndMetadata))
struct RuntimeAtomicManagedPayloadTests {
    @Test func retainedScalarProtectsManagedPayloadUntilReplacementAndOwnerRelease() {
        withAtomicPayloadTypeInfo { info in
            let payload = kk_alloc(32, info)
            let cell = kk_atomic_ref_create(Int(bitPattern: payload))
            weak var box: AtomicRefBox? = resolveRuntimeHandle(cell, as: AtomicRefBox.self)
            #expect(runtimeStorage.withGCLock { $0.retainedAtomicReferenceHandles.contains(UInt(bitPattern: cell)) })
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 1)
            // Never dereference a collected payload: registry count is the oracle.
            #expect(__kk_atomic_ref_load(cell) == Int(bitPattern: payload))
            _ = __kk_atomic_ref_store(cell, runtimeNullSentinelInt)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 0)
            #expect(box != nil)
            #expect(kk_object_release(cell) == 1)
            #expect(box == nil)
            #expect(!runtimeStorage.withGCLock { $0.retainedAtomicReferenceHandles.contains(UInt(bitPattern: cell)) })
            #expect(kk_object_release(cell) == 0)
        }
    }

    @Test func retainedReferenceArrayProtectsEachCellAndDropsRemovedOwners() {
        withAtomicPayloadTypeInfo { info in
            let array = kk_atomic_ref_array_new(3)
            weak var box: AtomicRefArrayBox? = resolveRuntimeHandle(array, as: AtomicRefArrayBox.self)
            for index in 0 ..< 3 {
                _ = kk_atomic_ref_array_storeAt(array, index, Int(bitPattern: kk_alloc(32, info)))
            }
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 3)
            _ = kk_atomic_ref_array_storeAt(array, 1, runtimeNullSentinelInt)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 2)
            #expect(kk_object_release(array) == 1)
            #expect(box == nil)
            #expect(!runtimeStorage.withGCLock { $0.retainedAtomicReferenceHandles.contains(UInt(bitPattern: array)) })
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 0)
        }
    }

    @Test func failedCASDoesNotRootUpdateAndOldValueNeedsItsOwnExternalRoot() {
        withAtomicPayloadTypeInfo { info in
            let first = Int(bitPattern: kk_alloc(32, info))
            let cell = kk_atomic_ref_create(first)
            let rejected = Int(bitPattern: kk_alloc(32, info))
            #expect(__kk_atomic_ref_compareAndExchange(cell, runtimeNullSentinelInt, rejected) == first)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 1)
            let replacement = Int(bitPattern: kk_alloc(32, info))
            // The return value of exchange remains live only with a real root.
            kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: first))
            #expect(__kk_atomic_ref_exchange(cell, replacement) == first)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 2)
            kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: first))
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 1)
            #expect(kk_object_release(cell) == 1)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 0)
        }
    }

    @Test func atomicPayloadUsesExistingTypeInfoChildTracing() {
        let offset = UInt32(MemoryLayout<KKObjHeader>.stride)
        withAtomicPayloadTypeInfo(offsets: [offset]) { parentInfo in
            withAtomicPayloadTypeInfo { childInfo in
                let parent = kk_alloc(offset + UInt32(MemoryLayout<Int>.stride), parentInfo)
                let child = kk_alloc(32, childInfo)
                parent.advanced(by: Int(offset)).storeBytes(of: child, as: UnsafeMutableRawPointer.self)
                let cell = kk_atomic_ref_create(Int(bitPattern: parent))
                kk_gc_collect()
                #expect(kk_runtime_heap_object_count() == 2)
                _ = __kk_atomic_ref_store(cell, runtimeNullSentinelInt)
                kk_gc_collect()
                #expect(kk_runtime_heap_object_count() == 0)
                #expect(kk_object_release(cell) == 1)
            }
        }
    }

    @Test func concurrentCellMutationAndCollectionShareTheRootSnapshotLock() {
        withAtomicPayloadTypeInfo { info in
            let first = Int(bitPattern: kk_alloc(32, info))
            let second = Int(bitPattern: kk_alloc(32, info))
            kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: first))
            kk_register_coroutine_root(UnsafeMutableRawPointer(bitPattern: second))
            let cell = kk_atomic_ref_create(first)
            let ready = DispatchSemaphore(value: 0)
            let continueWriter = DispatchSemaphore(value: 0)
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                _ = __kk_atomic_ref_store(cell, second)
                ready.signal()
                _ = continueWriter.wait(timeout: .now() + 3)
                for index in 0 ..< 500 {
                    _ = __kk_atomic_ref_exchange(cell, index.isMultiple(of: 2) ? first : second)
                    Thread.sleep(forTimeInterval: 0.0001)
                }
                group.leave()
            }
            #expect(ready.wait(timeout: .now() + 3) == .success)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 2)
            continueWriter.signal()
            for _ in 0 ..< 100 {
                kk_gc_collect()
                Thread.sleep(forTimeInterval: 0.0001)
            }
            let completed = group.wait(timeout: .now() + 3) == .success
            #expect(completed)
            // Drain before isolation resets even on failure; the outer gate
            // has a finite process-group watchdog for a genuine deadlock.
            if !completed { group.wait() }
            #expect([first, second].contains(__kk_atomic_ref_load(cell)))
            kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: first))
            kk_unregister_coroutine_root(UnsafeMutableRawPointer(bitPattern: second))
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 1)
            #expect(kk_object_release(cell) == 1)
            kk_gc_collect()
            #expect(kk_runtime_heap_object_count() == 0)
        }
    }

    @Test func ownedSynchronizationKernelReleaseDropsARCButGCAloneDoesNot() {
        var thrown = 0
        let lock = __kk_atomicfu_lock_new(0)
        weak var lockBox: RuntimeAtomicfuRecursiveLock? = resolveRuntimeHandle(lock, as: RuntimeAtomicfuRecursiveLock.self)
        #expect(__kk_atomicfu_lock_lock(lock, &thrown) == 0 && thrown == 0)
        #expect(__kk_atomicfu_lock_unlock(lock, &thrown) == 0 && thrown == 0)
        let parker = __kk_atomicfu_parker_new()
        weak var parkerBox: RuntimeAtomicfuParker? = resolveRuntimeHandle(parker, as: RuntimeAtomicfuParker.self)
        #expect(__kk_atomicfu_parker_unpark(parker, &thrown) == 0 && thrown == 0)
        #expect(__kk_atomicfu_parker_wait(parker, 0, &thrown) == 0 && thrown == 0)
        kk_gc_collect()
        #expect(lockBox != nil && parkerBox != nil)
        #expect(kk_object_release(lock) == 1)
        #expect(kk_object_release(parker) == 1)
        #expect(lockBox == nil && parkerBox == nil)
    }
}

// PREPARED ONLY: append this helper and extension to the candidate Runtime test file.
// This is one test method / one case. No product source or hooks are required.
// Uses registered real cells, acquires strong Swift references BEFORE the GC lock,
// then invokes their actual mutation methods directly on the worker.
// Calling the exported raw-handle API here would test resolveRuntimeHandle's lock
// instead and could pass after deleting the mutation's own withGCLock.
private enum AtomicMutationPath: CaseIterable, Sendable {
    case scalarStore, scalarExchange, scalarCompareAndExchange
    case arrayStore, arrayExchange, arrayCompareAndSet, arrayCompareAndExchange
}

// This test-only holder crosses Dispatch's Sendable boundary. Its immutable
// references expose only the runtime's C11 atomic operations to the worker.
// No managed heap object, descriptor, user callback, or external root is involved.
private final class AtomicMutationExclusionProbe: @unchecked Sendable {
    let scalar: AtomicRefBox
    let array: AtomicRefArrayBox

    init(scalar: AtomicRefBox, array: AtomicRefArrayBox) {
        self.scalar = scalar
        self.array = array
    }

    func mutate(_ path: AtomicMutationPath) {
        switch path {
        case .scalarStore: scalar.store(200)
        case .scalarExchange: _ = scalar.exchange(200)
        case .scalarCompareAndExchange:
            _ = scalar.compareAndExchange(expect: 100, update: 200)
        case .arrayStore: array.store(at: 0, value: 200)
        case .arrayExchange: _ = array.exchange(at: 0, newValue: 200)
        case .arrayCompareAndSet:
            _ = array.compareAndSet(at: 0, expect: 100, update: 200)
        case .arrayCompareAndExchange:
            _ = array.compareAndExchange(at: 0, expect: 100, update: 200)
        }
    }

    func load(_ path: AtomicMutationPath) -> Int {
        switch path {
        case .scalarStore, .scalarExchange, .scalarCompareAndExchange:
            return scalar.load()
        case .arrayStore, .arrayExchange, .arrayCompareAndSet, .arrayCompareAndExchange:
            return array.load(at: 0)
        }
    }
}

extension RuntimeAtomicManagedPayloadTests {
    @Test func referenceCellMutationsWaitForCollectorSnapshotCriticalSection() throws {
        for path in AtomicMutationPath.allCases {
            let scalarRaw = kk_atomic_ref_create(100)
            let arrayRaw = kk_atomic_ref_array_new(1)
            let scalar = try #require(resolveRuntimeHandle(scalarRaw, as: AtomicRefBox.self))
            let array = try #require(resolveRuntimeHandle(arrayRaw, as: AtomicRefArrayBox.self))
            array.store(at: 0, value: 100)
            let probe = AtomicMutationExclusionProbe(scalar: scalar, array: array)
            var mayRelease = true
            defer {
                // A genuine worker deadlock is a FAIL/HANG for the finite outer
                // process-group watchdog. Never release its raw ownership while
                // it is still active. The failure-only drain below requires the finite outer watchdog.
                if mayRelease {
                    #expect(kk_object_release(scalarRaw) == 1)
                    #expect(kk_object_release(arrayRaw) == 1)
                }
            }

            let ready = DispatchSemaphore(value: 0)
            let group = DispatchGroup()
            let observation = runtimeStorage.withGCLock { _ in
                group.enter()
                DispatchQueue.global().async {
                    defer { group.leave() }
                    ready.signal()
                    probe.mutate(path)
                }
                let started = ready.wait(timeout: .now() + 3) == .success
                // This is a bounded exclusion observation, not a proof of OS
                // scheduler fairness. Ready is immediately before the real call.
                let finishedUnderLock = started && group.wait(timeout: .now() + .milliseconds(100)) == .success
                // load() is the real lock-free C11 read, avoiding recursive GC lock.
                return (started, finishedUnderLock, probe.load(path))
            }
            let drained = group.wait(timeout: .now() + 3) == .success
            #expect(observation.0, "Worker did not reach the mutation: \(path)")
            #expect(!observation.1, "Mutation escaped the GC snapshot lock: \(path)")
            #expect(observation.2 == 100, "Cell changed inside the GC snapshot lock: \(path)")
            #expect(drained, "Worker did not finish after GC unlock: \(path)")
            guard drained else {
                mayRelease = false
                // Keep this isolation scope open until the worker actually
                // drains. A true deadlock is stopped and reaped by the required
                // finite outer watchdog, never by resetting under a live worker.
                group.wait()
                mayRelease = true
                return
            }
            #expect(probe.load(path) == 200, "Mutation did not commit after GC unlock: \(path)")
        }
    }
}
