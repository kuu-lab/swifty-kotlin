import Dispatch
import Foundation
@testable import Runtime
import RuntimeABI
import Testing

private final class AtomicfuTestValues: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int] = []
    func append(_ value: Int) { lock.lock(); values.append(value); lock.unlock() }
    var snapshot: [Int] { lock.lock(); defer { lock.unlock() }; return values }
}

// Worker waits are finite even when the kernel under test fails. No worker uses
// infinite acquisition, so a failed expectation cannot strand an owned thread.
private func atomicfuWaitUntil(_ condition: () -> Bool) -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
    while !condition() {
        if DispatchTime.now().uptimeNanoseconds >= deadline { return false }
        Thread.sleep(forTimeInterval: 0.001)
    }
    return true
}

// A recorded timeout must not let Runtime isolation reset while a worker is
// still using its old handles. One bounded drain is allowed; otherwise abort
// this test process and let the outer watchdog retain/reap its failure.
private func atomicfuDrain(_ group: DispatchGroup) {
    if group.wait(timeout: .now() + 3) == .success { return }
    Issue.record("Atomicfu worker missed its completion deadline; draining")
    guard group.wait(timeout: .now() + 3) == .success else {
        fatalError("Atomicfu worker did not drain; Runtime isolation must not reset")
    }
}

private func atomicfuFinish(_ thread: Thread) {
    if atomicfuWaitUntil({ thread.isFinished }) { return }
    Issue.record("Atomicfu thread missed its completion deadline; draining")
    guard atomicfuWaitUntil({ thread.isFinished }) else {
        fatalError("Atomicfu thread did not finish; Runtime isolation must not reset")
    }
}

private let atomicfuCacheFactoryCalls = AtomicfuTestValues()
private let atomicfuCacheFactory: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, thrown in
    thrown?.pointee = 0
    atomicfuCacheFactoryCalls.append(1)
    // Actual registered ordinary object allocation, not an atomicfu API mock.
    return kk_object_new(2, 0)
}
private let atomicfuThrowingFactory: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, thrown in
    thrown?.pointee = runtimeAllocateIllegalArgumentException(message: "factory failed")
    return runtimeExceptionCaughtSentinel
}

@Suite(.runtimeIsolation(.gcAndMetadata))
struct RuntimeAtomicfuSynchronizationTests {
    @Test func recursiveOwnershipAndOwnerValidation() {
        let lock = RuntimeAtomicfuRecursiveLock()
        #expect(lock.acquire(timeoutNanos: 0))
        #expect(lock.acquire(timeoutNanos: 0))
        let values = AtomicfuTestValues()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            values.append(lock.acquire(timeoutNanos: 0) ? 1 : 0)
            values.append(lock.release() ? 1 : 0)
            group.leave()
        }
        atomicfuDrain(group)
        #expect(values.snapshot == [0, 0])
        #expect(lock.release())
        group.enter()
        DispatchQueue.global().async {
            let got = lock.acquire(timeoutNanos: 0)
            values.append(got ? 1 : 0)
            if got { _ = lock.release() }
            group.leave()
        }
        atomicfuDrain(group)
        #expect(values.snapshot == [0, 0, 0])
        #expect(lock.release())
        #expect(!lock.release())
        #expect(lock.acquire(timeoutNanos: 0))
        #expect(lock.release())
    }

    @Test func fifoWaitersAndTimedCancellation() {
        let lock = RuntimeAtomicfuRecursiveLock()
        #expect(lock.acquire(timeoutNanos: 0))
        let values = AtomicfuTestValues()
        let group = DispatchGroup()
        for index in 1...2 {
            group.enter()
            DispatchQueue.global().async {
                let got = lock.acquire(timeoutNanos: 2_000_000_000)
                values.append(got ? index : -index)
                if got { _ = lock.release() }
                group.leave()
            }
            #expect(atomicfuWaitUntil { lock.queuedWaiterCount == index })
        }
        #expect(lock.release())
        atomicfuDrain(group)
        #expect(values.snapshot == [1, 2])
        #expect(lock.acquire(timeoutNanos: 0))
        group.enter()
        DispatchQueue.global().async {
            let got = lock.acquire(timeoutNanos: 10_000_000)
            values.append(got ? 3 : 0)
            if got { _ = lock.release() }
            group.leave()
        }
        atomicfuDrain(group)
        #expect(values.snapshot == [1, 2, 0])
        #expect(lock.queuedWaiterCount == 0)
        #expect(lock.release())
        #expect(lock.acquire(timeoutNanos: 0))
        #expect(lock.release())
    }

    @Test func privateAbiReportsDistinctOfficialUnlockExceptionTypes() {
        for (argumentMode, expectedArgument) in [(1, true), (0, false)] {
            let kernel = __kk_atomicfu_lock_new(argumentMode)
            var thrown = 99
            #expect(__kk_atomicfu_lock_unlock(kernel, &thrown) == runtimeExceptionCaughtSentinel)
            if expectedArgument {
                #expect(runtimeBox(from: thrown, as: RuntimeIllegalArgumentExceptionBox.self) != nil)
            } else {
                #expect(runtimeBox(from: thrown, as: RuntimeIllegalStateExceptionBox.self) != nil)
            }
            thrown = 99
            #expect(__kk_atomicfu_lock_lock(kernel, &thrown) == 0)
            #expect(thrown == 0)
            #expect(__kk_atomicfu_lock_try_lock(kernel, 0, &thrown) == 1)
            #expect(__kk_atomicfu_lock_unlock(kernel, &thrown) == 0)
            #expect(__kk_atomicfu_lock_unlock(kernel, &thrown) == 0)
            #expect(thrown == 0)
        }
        var thrown = 0
        #expect(__kk_atomicfu_lock_lock(17, &thrown) == runtimeExceptionCaughtSentinel)
        #expect(runtimeBox(from: thrown, as: RuntimeIllegalArgumentExceptionBox.self) != nil)
    }

    @Test func parkerHasOnePermitAndHonorsItsOwner() {
        let parker = RuntimeAtomicfuParker()
        parker.unpark()
        parker.unpark()
        let firstStart = DispatchTime.now().uptimeNanoseconds
        #expect(parker.park(timeoutNanos: -1))
        #expect(DispatchTime.now().uptimeNanoseconds - firstStart < 100_000_000)
        // One permit was consumed. The second call must actually wait.
        let nextStart = DispatchTime.now().uptimeNanoseconds
        #expect(parker.park(timeoutNanos: 20_000_000))
        #expect(DispatchTime.now().uptimeNanoseconds - nextStart >= 10_000_000)
        let values = AtomicfuTestValues()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            values.append(parker.park(timeoutNanos: 0) ? 1 : 0)
            parker.unpark() // a different thread may unpark the owner
            group.leave()
        }
        atomicfuDrain(group)
        #expect(values.snapshot == [0])
        #expect(parker.park(timeoutNanos: 0))
    }

    @Test func parkerWakesAnActualWaitingOwner() {
        let parker = RuntimeAtomicfuParker()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 0.02)
            parker.unpark()
            group.leave()
        }
        let start = DispatchTime.now().uptimeNanoseconds
        #expect(parker.park(timeoutNanos: 1_000_000_000))
        #expect(DispatchTime.now().uptimeNanoseconds - start < 900_000_000)
        atomicfuDrain(group)
    }

    @Test func privateParkerAbiChecksWrongOwnerAndInvalidHandles() {
        let handle = __kk_atomicfu_parker_new()
        let values = AtomicfuTestValues()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            var thrown = 0
            let result = __kk_atomicfu_parker_wait(handle, 0, &thrown)
            values.append(result == runtimeExceptionCaughtSentinel ? 1 : 0)
            values.append(runtimeBox(from: thrown, as: RuntimeIllegalStateExceptionBox.self) != nil ? 1 : 0)
            group.leave()
        }
        atomicfuDrain(group)
        #expect(values.snapshot == [1, 1])
        var thrown = 0
        #expect(__kk_atomicfu_parker_unpark(17, &thrown) == runtimeExceptionCaughtSentinel)
        #expect(runtimeBox(from: thrown, as: RuntimeIllegalArgumentExceptionBox.self) != nil)
        #expect(__kk_atomicfu_parker_unpark(handle, &thrown) == 0)
        #expect(thrown == 0)
        // Negative finite duration consumes a pre-existing permit, then returns.
        #expect(__kk_atomicfu_parker_wait(handle, -7, &thrown) == 0)
        #expect(thrown == 0)
    }

    @Test func currentParkingHandleCachesAndInvalidatesOnlyOnReset() {
        runtimeResetAtomicfuParkingCaches()
        let before = atomicfuCacheFactoryCalls.snapshot.count
        let factory = unsafeBitCast(atomicfuCacheFactory, to: Int.self)
        var thrown = 0
        let first = __kk_atomicfu_current_parking_handle(factory, 0, &thrown)
        let second = __kk_atomicfu_current_parking_handle(factory, 0, &thrown)
        #expect(first == second)
        #expect(first != 0)
        #expect(thrown == 0)
        #expect(atomicfuCacheFactoryCalls.snapshot.count == before + 1)
        kk_gc_collect()
        // Registered boxes are retained independently of GC roots. This checks
        // cache identity through collection, not mark/sweep root protection.
        #expect(__kk_atomicfu_current_parking_handle(factory, 0, &thrown) == first)
        runtimeResetAtomicfuParkingCaches()
        let third = __kk_atomicfu_current_parking_handle(factory, 0, &thrown)
        #expect(first != third)
        #expect(atomicfuCacheFactoryCalls.snapshot.count == before + 2)
        runtimeResetAtomicfuParkingCaches()
    }

    @Test func parkingCacheRootIsPerThreadAndReleasedOnActualThreadExit() {
        runtimeResetAtomicfuParkingCaches()
        let rootsBefore = runtimeStorage.withGCLock { $0.globalRootSlots }
        let values = AtomicfuTestValues()
        let ready = DispatchSemaphore(value: 0)
        let allowExit = DispatchSemaphore(value: 0)
        let thread = Thread {
            let factory = unsafeBitCast(atomicfuCacheFactory, to: Int.self)
            var thrown = 0
            let first = __kk_atomicfu_current_parking_handle(factory, 0, &thrown)
            let second = __kk_atomicfu_current_parking_handle(factory, 0, &thrown)
            values.append(first)
            values.append(second)
            values.append(thrown)
            ready.signal()
            _ = allowExit.wait(timeout: .now() + 3)
            // No explicit cache clear: pthread TLS destructor must remove root.
        }
        thread.start()
        let becameReady = ready.wait(timeout: .now() + 3) == .success
        #expect(becameReady)
        let result = values.snapshot
        if becameReady {
            #expect(!thread.isFinished)
            let live = runtimeStorage.withGCLock { state -> (Set<UInt>, [Int]) in
                let slots = state.globalRootSlots.subtracting(rootsBefore)
                let handles = slots.map { address in
                    UnsafeMutablePointer<UnsafeMutableRawPointer?>(bitPattern: address)
                        .map { Int(bitPattern: $0.pointee) } ?? 0
                }
                return (state.globalRootSlots, handles)
            }
            #expect(live.0.isSuperset(of: rootsBefore))
            #expect(live.0.count == rootsBefore.count + 1)
            #expect(result.count == 3)
            if result.count == 3 {
                #expect(result[0] != 0 && result[0] == result[1] && result[2] == 0)
                #expect(live.1 == [result[0]])
            }
        }
        allowExit.signal()
        atomicfuFinish(thread) // must precede reset even when an expectation fails
        #expect(atomicfuWaitUntil { runtimeStorage.withGCLock { $0.globalRootSlots } == rootsBefore })
        let factory = unsafeBitCast(atomicfuCacheFactory, to: Int.self)
        var thrown = 0
        let own = __kk_atomicfu_current_parking_handle(factory, 0, &thrown)
        #expect(result.first != own)
        runtimeResetAtomicfuParkingCaches()
    }

    @Test func secondCompletedUnparkBeforeOwnerCleanupPreservesNextPermit() {
        let parker = RuntimeAtomicfuParker()
        let ownerAwake = DispatchSemaphore(value: 0)
        let secondUnparkComplete = DispatchSemaphore(value: 0)
        let values = AtomicfuTestValues()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            let waiting = atomicfuWaitUntil { parker.hasWaitingOwner }
            values.append(waiting ? 1 : 0)
            parker.unpark() // this wake has fully handed off before the next call
            let woke = ownerAwake.wait(timeout: .now() + 3) == .success
            values.append(woke ? 1 : 0)
            parker.unpark() // owner is still paused before old waiter cleanup
            secondUnparkComplete.signal()
            group.leave()
        }
        #expect(parker.park(timeoutNanos: 2_000_000_000, afterWaitBeforeCleanup: {
            ownerAwake.signal()
            #expect(secondUnparkComplete.wait(timeout: .now() + 3) == .success)
        }))
        atomicfuDrain(group)
        #expect(values.snapshot == [1, 1])
        let nextStart = DispatchTime.now().uptimeNanoseconds
        #expect(parker.park(timeoutNanos: 250_000_000))
        #expect(DispatchTime.now().uptimeNanoseconds - nextStart < 100_000_000)
        // Both unparks have now been consumed. This third park must wait.
        let thirdStart = DispatchTime.now().uptimeNanoseconds
        #expect(parker.park(timeoutNanos: 20_000_000))
        #expect(DispatchTime.now().uptimeNanoseconds - thirdStart >= 10_000_000)
    }

    @Test func failedParkingFactoryPropagatesAndDoesNotFillCache() {
        runtimeResetAtomicfuParkingCaches()
        let factory = unsafeBitCast(atomicfuThrowingFactory, to: Int.self)
        var thrown = 0
        #expect(__kk_atomicfu_current_parking_handle(factory, 0, &thrown) == runtimeExceptionCaughtSentinel)
        #expect(runtimeBox(from: thrown, as: RuntimeIllegalArgumentExceptionBox.self) != nil)
        let succeedingFactory = unsafeBitCast(atomicfuCacheFactory, to: Int.self)
        #expect(__kk_atomicfu_current_parking_handle(succeedingFactory, 0, &thrown) != runtimeExceptionCaughtSentinel)
        #expect(thrown == 0)
        runtimeResetAtomicfuParkingCaches()
    }

    @Test func allEightPrivateAbiEntriesHaveExactMachineContracts() {
        let specs = RuntimeABISpec.atomicfuSynchronizationFunctions
        #expect(specs.count == 8)
        #expect(Set(specs.map(\.name)).count == 8)
        #expect(specs.allSatisfy { $0.returnType == .intptr })
        #expect(specs.filter { !$0.isThrowing }.map(\.name).sorted() ==
            ["__kk_atomicfu_lock_new", "__kk_atomicfu_parker_new"])
        #expect(specs.filter(\.returnsRawBoolean).map(\.name) == ["__kk_atomicfu_lock_try_lock"])
        for spec in specs where spec.isThrowing {
            #expect(spec.parameters.last?.type == .nullableIntptrPointer)
            #expect(spec.parameters.last?.name == "outThrown")
        }
        #expect(specs.first { $0.name == "__kk_atomicfu_lock_new" }?.parameterTypeStrings == ["intptr_t"])
        #expect(specs.first { $0.name == "__kk_atomicfu_current_parking_handle" }?.parameterTypeStrings ==
            ["intptr_t", "intptr_t", "intptr_t * _Nullable"])
        #expect(specs.allSatisfy { spec in RuntimeABISpec.allFunctions.filter { $0.name == spec.name }.count == 1 })
    }
}
