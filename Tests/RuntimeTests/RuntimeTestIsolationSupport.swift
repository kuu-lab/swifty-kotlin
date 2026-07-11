import Dispatch
import Foundation
@testable import Runtime
import XCTest

// MARK: - Fine-grained lock sets for test isolation

enum RuntimeLockSet {
    case none
    case gcOnly
    case metadataOnly
    case flowOnly
    case threadLocalOnly
    case delegateOnly
    case gcAndMetadata
    case gcAndFlow
    case gcAndThreadLocal
    case gcAndDelegate
    case all
}

// Per-state semaphores for fine-grained test isolation.
private let gcSemaphore = DispatchSemaphore(value: 1)
private let metadataSemaphore = DispatchSemaphore(value: 1)
private let flowSemaphore = DispatchSemaphore(value: 1)
private let threadLocalSemaphore = DispatchSemaphore(value: 1)
private let delegateSemaphore = DispatchSemaphore(value: 1)

private func semaphores(for lockSet: RuntimeLockSet) -> [DispatchSemaphore] {
    switch lockSet {
    case .none:
        return []
    case .gcOnly:
        return [gcSemaphore]
    case .metadataOnly:
        return [metadataSemaphore]
    case .flowOnly:
        return [flowSemaphore]
    case .threadLocalOnly:
        return [threadLocalSemaphore]
    case .delegateOnly:
        return [delegateSemaphore]
    case .gcAndMetadata:
        return [gcSemaphore, metadataSemaphore]
    case .gcAndFlow:
        return [gcSemaphore, flowSemaphore]
    case .gcAndThreadLocal:
        return [gcSemaphore, threadLocalSemaphore]
    case .gcAndDelegate:
        return [gcSemaphore, delegateSemaphore]
    case .all:
        return [gcSemaphore, metadataSemaphore, flowSemaphore, threadLocalSemaphore, delegateSemaphore]
    }
}

private func resetFunctions(for lockSet: RuntimeLockSet) -> [() -> Void] {
    switch lockSet {
    case .none:
        return []
    case .gcOnly:
        return [kk_runtime_reset_gc]
    case .metadataOnly:
        return [kk_runtime_reset_metadata]
    case .flowOnly:
        return [kk_runtime_reset_flow]
    case .threadLocalOnly:
        return [kk_runtime_reset_thread_local]
    case .delegateOnly:
        return [kk_runtime_reset_delegate]
    case .gcAndMetadata:
        return [kk_runtime_reset_gc, kk_runtime_reset_metadata]
    case .gcAndFlow:
        return [kk_runtime_reset_gc, kk_runtime_reset_flow]
    case .gcAndThreadLocal:
        return [kk_runtime_reset_gc, kk_runtime_reset_thread_local]
    case .gcAndDelegate:
        return [kk_runtime_reset_gc, kk_runtime_reset_delegate]
    case .all:
        return [{ kk_runtime_force_reset() }]
    }
}

/// Use this base class for runtime tests that mutate global runtime state or
/// observe file-global callback state.
class IsolatedRuntimeXCTestCase: XCTestCase {
    private var acquiredSemaphores: [DispatchSemaphore] = []

    /// Override to declare which lock set this test class requires.
    /// Default is `.all` for backward compatibility.
    class var requiredLockSet: RuntimeLockSet { .all }

    override final func setUp() {
        super.setUp()
        acquiredSemaphores = []

        let sems = semaphores(for: type(of: self).requiredLockSet)
        for sem in sems {
            let waitResult = sem.wait(timeout: .now() + .seconds(30))
            guard waitResult == .success else {
                for acquired in acquiredSemaphores { acquired.signal() }
                acquiredSemaphores = []
                XCTFail("Runtime test isolation lock timed out while waiting for available token")
                return
            }
            acquiredSemaphores.append(sem)
        }

        for reset in resetFunctions(for: type(of: self).requiredLockSet) {
            reset()
        }
        resetIsolatedRuntimeTestState()
    }

    override final func tearDown() {
        resetIsolatedRuntimeTestState()
        for reset in resetFunctions(for: type(of: self).requiredLockSet) {
            reset()
        }
        super.tearDown()
        for sem in acquiredSemaphores.reversed() {
            sem.signal()
        }
        acquiredSemaphores = []
    }

    func resetIsolatedRuntimeTestState() {}
}

/// Monotonic counters make launch/cancel assertions immune to stale signals
/// from prior tests while still supporting C-callable global entry points.
final class RuntimeCoroutineTestState: @unchecked Sendable {
    private let condition = NSCondition()
    private var launchEventCount = 0
    private var cancelLoopIterations = 0

    func reset() {
        condition.lock()
        launchEventCount = 0
        cancelLoopIterations = 0
        condition.broadcast()
        condition.unlock()
    }

    func launchEventCountSnapshot() -> Int {
        condition.lock()
        defer { condition.unlock() }
        return launchEventCount
    }

    func recordLaunchEvent() {
        condition.lock()
        launchEventCount += 1
        condition.broadcast()
        condition.unlock()
    }

    func waitForLaunchEvent(after baseline: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while launchEventCount <= baseline {
            if !condition.wait(until: deadline) {
                return launchEventCount > baseline
            }
        }
        return true
    }

    func recordCancelLoopIteration() {
        condition.lock()
        cancelLoopIterations += 1
        condition.broadcast()
        condition.unlock()
    }

    func cancelLoopIterationsSnapshot() -> Int {
        condition.lock()
        defer { condition.unlock() }
        return cancelLoopIterations
    }

    func waitForCancelLoopIterations(atLeast minimum: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while cancelLoopIterations < minimum {
            if !condition.wait(until: deadline) {
                return cancelLoopIterations >= minimum
            }
        }
        return true
    }
}

// MARK: - Duration construction helpers (KSP-471)

// kk_duration_from_* per-unit factories were removed in favor of
// kk_duration_toDuration_int/long/double (unit-ordinal based). DurationUnit
// ordinals: 0=NANOSECONDS, 1=MICROSECONDS, 2=MILLISECONDS, 3=SECONDS,
// 4=MINUTES, 5=HOURS, 6=DAYS. These helpers preserve the original per-unit
// construction call shape for Runtime tests.
func durationFromNanoseconds(_ value: Int) -> Int { kk_duration_toDuration_int(value, 0) }
func durationFromMicroseconds(_ value: Int) -> Int { kk_duration_toDuration_int(value, 1) }
func durationFromMilliseconds(_ value: Int) -> Int { kk_duration_toDuration_int(value, 2) }
func durationFromSeconds(_ value: Int) -> Int { kk_duration_toDuration_int(value, 3) }
func durationFromMinutes(_ value: Int) -> Int { kk_duration_toDuration_int(value, 4) }
func durationFromHours(_ value: Int) -> Int { kk_duration_toDuration_int(value, 5) }
func durationFromDays(_ value: Int) -> Int { kk_duration_toDuration_int(value, 6) }

func durationFromNanosecondsLong(_ value: Int) -> Int { kk_duration_toDuration_long(value, 0) }
func durationFromMicrosecondsLong(_ value: Int) -> Int { kk_duration_toDuration_long(value, 1) }
func durationFromMillisecondsLong(_ value: Int) -> Int { kk_duration_toDuration_long(value, 2) }
func durationFromSecondsLong(_ value: Int) -> Int { kk_duration_toDuration_long(value, 3) }
func durationFromMinutesLong(_ value: Int) -> Int { kk_duration_toDuration_long(value, 4) }
func durationFromHoursLong(_ value: Int) -> Int { kk_duration_toDuration_long(value, 5) }
func durationFromDaysLong(_ value: Int) -> Int { kk_duration_toDuration_long(value, 6) }

func durationFromSecondsDouble(_ valueBits: Int) -> Int { kk_duration_toDuration_double(valueBits, 3) }
func durationFromDaysDouble(_ valueBits: Int) -> Int { kk_duration_toDuration_double(valueBits, 6) }

// kk_duration_inWholeMilliseconds/Microseconds/Seconds/Minutes/Hours/Days were
// removed (now Kotlin-source extension properties built on inWholeNanoseconds,
// which stays native). These helpers recompute the same scaling directly from
// kk_duration_inWholeNanoseconds to preserve the original Runtime test assertions.
func durationInWholeMilliseconds(_ handle: Int) -> Int { kk_duration_inWholeNanoseconds(handle) / 1_000_000 }
func durationInWholeMicroseconds(_ handle: Int) -> Int { kk_duration_inWholeNanoseconds(handle) / 1_000 }
func durationInWholeSeconds(_ handle: Int) -> Int { kk_duration_inWholeNanoseconds(handle) / 1_000_000_000 }
func durationInWholeMinutes(_ handle: Int) -> Int { kk_duration_inWholeNanoseconds(handle) / 60_000_000_000 }
func durationInWholeHours(_ handle: Int) -> Int { kk_duration_inWholeNanoseconds(handle) / 3_600_000_000_000 }
func durationInWholeDays(_ handle: Int) -> Int { kk_duration_inWholeNanoseconds(handle) / 86_400_000_000_000 }
