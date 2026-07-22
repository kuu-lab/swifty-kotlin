import Dispatch
import Foundation
@testable import Runtime
import Testing
import XCTest

// MARK: - Fine-grained lock sets for test isolation

enum RuntimeLockSet: Sendable {
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

/// Applies the same process-wide runtime isolation to Swift Testing suites that
/// `IsolatedRuntimeXCTestCase` provides to XCTest classes.
struct RuntimeIsolationTrait: SuiteTrait, TestTrait, TestScoping {
    let lockSet: RuntimeLockSet
    private let resetAdditionalState: @Sendable () -> Void

    init(
        _ lockSet: RuntimeLockSet = .all,
        resetAdditionalState: @escaping @Sendable () -> Void = {}
    ) {
        self.lockSet = lockSet
        self.resetAdditionalState = resetAdditionalState
    }

    /// Propagate the trait from a suite to every test case in that suite.
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        // A suite itself has no case to isolate. Its recursive children do.
        guard testCase != nil else {
            try await function()
            return
        }

        let acquiredSemaphores = try await acquireSemaphores(
            for: lockSet,
            testName: test.name
        )
        resetRuntimeState(for: lockSet)
        resetAdditionalState()

        defer {
            resetAdditionalState()
            resetRuntimeState(for: lockSet)
            releaseSemaphores(acquiredSemaphores)
        }

        try await function()
    }
}

extension SuiteTrait where Self == RuntimeIsolationTrait {
    static func runtimeIsolation(
        _ lockSet: RuntimeLockSet = .all,
        resetAdditionalState: @escaping @Sendable () -> Void = {}
    ) -> RuntimeIsolationTrait {
        RuntimeIsolationTrait(lockSet, resetAdditionalState: resetAdditionalState)
    }
}

// Per-state semaphores for fine-grained test isolation.
private let gcSemaphore = DispatchSemaphore(value: 1)
private let metadataSemaphore = DispatchSemaphore(value: 1)
private let flowSemaphore = DispatchSemaphore(value: 1)
private let threadLocalSemaphore = DispatchSemaphore(value: 1)
private let delegateSemaphore = DispatchSemaphore(value: 1)

private struct RuntimeIsolationLockTimeoutError: Error, CustomStringConvertible {
    let testName: String

    var description: String {
        "Runtime test isolation lock timed out for \(testName)"
    }
}

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

private func acquireSemaphores(
    for lockSet: RuntimeLockSet,
    testName: String
) async throws -> [DispatchSemaphore] {
    try await acquireSemaphores(
        semaphores(for: lockSet),
        testName: testName
    )
}

/// Wait for runtime locks on a libdispatch worker instead of a cooperative
/// Swift Concurrency thread. Blocking the cooperative pool here can deadlock
/// when multiple Swift Testing cases contend for the same process-wide lock.
private func acquireSemaphores(
    _ semaphores: [DispatchSemaphore],
    testName: String
) async throws -> [DispatchSemaphore] {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                continuation.resume(
                    returning: try acquireSemaphoresBlocking(semaphores, testName: testName)
                )
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private func acquireSemaphoresBlocking(
    _ semaphores: [DispatchSemaphore],
    testName: String
) throws -> [DispatchSemaphore] {
    var acquiredSemaphores: [DispatchSemaphore] = []

    for semaphore in semaphores {
        let waitResult = semaphore.wait(timeout: .now() + .seconds(30))
        guard waitResult == .success else {
            releaseSemaphores(acquiredSemaphores)
            throw RuntimeIsolationLockTimeoutError(testName: testName)
        }
        acquiredSemaphores.append(semaphore)
    }

    return acquiredSemaphores
}

private func releaseSemaphores(_ semaphores: [DispatchSemaphore]) {
    for semaphore in semaphores.reversed() {
        semaphore.signal()
    }
}

private func resetRuntimeState(for lockSet: RuntimeLockSet) {
    for reset in resetFunctions(for: lockSet) {
        reset()
    }
}

@Test
func runtimeIsolationSemaphoreWaitRunsOffCooperativePool() async throws {
    let semaphore = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
        semaphore.signal()
    }

    let acquired = try await acquireSemaphores(
        [semaphore],
        testName: "runtimeIsolationSemaphoreWaitRunsOffCooperativePool"
    )
    #expect(acquired.count == 1)
    releaseSemaphores(acquired)
}

/// Use this base class for runtime tests that mutate global runtime state or
/// observe file-global callback state.
final class RuntimeTestIsolationLease {
    private let lockSet: RuntimeLockSet
    private var acquiredSemaphores: [DispatchSemaphore] = []

    init(lockSet: RuntimeLockSet) {
        self.lockSet = lockSet
        for semaphore in semaphores(for: lockSet) {
            guard semaphore.wait(timeout: .now() + .seconds(30)) == .success else {
                for acquired in acquiredSemaphores.reversed() {
                    acquired.signal()
                }
                preconditionFailure("Runtime test isolation lock timed out while waiting for available token")
            }
            acquiredSemaphores.append(semaphore)
        }
    }

    func release() {
        for semaphore in acquiredSemaphores.reversed() {
            semaphore.signal()
        }
        acquiredSemaphores = []
    }

    deinit {
        release()
    }
}

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

func durationFromMicrosecondsLong(_ value: Int) -> Int { kk_duration_toDuration_long(value, 1) }
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
