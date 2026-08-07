import Dispatch
import Foundation
import XCTest

/// Use this base class for XCTest runtime tests that mutate global runtime
/// state or observe file-global callback state. Swift Testing suites use
/// `RuntimeIsolationTrait` from `RuntimeTestIsolationSupport.swift` instead;
/// both share the same process-wide semaphores.
class IsolatedRuntimeXCTestCase: XCTestCase {
    private var acquiredSemaphores: [DispatchSemaphore] = []

    /// Override to declare which lock set this test class requires.
    /// Default is `.all` for backward compatibility.
    class var requiredLockSet: RuntimeLockSet { .all }

    override final func setUp() {
        super.setUp()
        acquiredSemaphores = []

        let sems = runtimeIsolationSemaphores(for: type(of: self).requiredLockSet)
        for sem in sems {
            let waitResult = sem.wait(timeout: .now() + runtimeIsolationLockWaitTimeout)
            guard waitResult == .success else {
                for acquired in acquiredSemaphores { acquired.signal() }
                acquiredSemaphores = []
                XCTFail("Runtime test isolation lock timed out while waiting for available token")
                return
            }
            acquiredSemaphores.append(sem)
        }

        for reset in runtimeIsolationResetFunctions(for: type(of: self).requiredLockSet) {
            reset()
        }
        resetIsolatedRuntimeTestState()
    }

    override final func tearDown() {
        resetIsolatedRuntimeTestState()
        for reset in runtimeIsolationResetFunctions(for: type(of: self).requiredLockSet) {
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
