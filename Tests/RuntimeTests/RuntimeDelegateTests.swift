import Dispatch
import Foundation
@testable import Runtime
import Testing

private final class DelegateCallbackState: @unchecked Sendable {
    private let lock = NSLock()
    private var lazyCallCount = 0
    private var observableCapturedOld = -1
    private var observableCapturedNew = -1
    private var observableHandle: Int = 0
    private var observableValueInsideCallback = -1
    private var vetoableHandle: Int = 0
    private var vetoableValueInsideCallback = -1

    func reset() {
        lock.lock()
        lazyCallCount = 0
        observableCapturedOld = -1
        observableCapturedNew = -1
        observableHandle = 0
        observableValueInsideCallback = -1
        vetoableHandle = 0
        vetoableValueInsideCallback = -1
        lock.unlock()
    }

    func incrementLazyCallCount() {
        lock.lock()
        lazyCallCount += 1
        lock.unlock()
    }

    func lazyCallCountSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return lazyCallCount
    }

    func setObservableCaptured(old: Int, new: Int) {
        lock.lock()
        observableCapturedOld = old
        observableCapturedNew = new
        lock.unlock()
    }

    func observableCapturedOldSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return observableCapturedOld
    }

    func observableCapturedNewSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return observableCapturedNew
    }

    func setObservableHandle(_ value: Int) {
        lock.lock()
        observableHandle = value
        lock.unlock()
    }

    func observableHandleSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return observableHandle
    }

    func setObservableValueInsideCallback(_ value: Int) {
        lock.lock()
        observableValueInsideCallback = value
        lock.unlock()
    }

    func observableValueInsideCallbackSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return observableValueInsideCallback
    }

    func setVetoableHandle(_ value: Int) {
        lock.lock()
        vetoableHandle = value
        lock.unlock()
    }

    func vetoableHandleSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return vetoableHandle
    }

    func setVetoableValueInsideCallback(_ value: Int) {
        lock.lock()
        vetoableValueInsideCallback = value
        lock.unlock()
    }

    func vetoableValueInsideCallbackSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return vetoableValueInsideCallback
    }
}

private final class LazyPublicationCallbackState: @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private var enteredSemaphore = DispatchSemaphore(value: 0)
    private var releaseSemaphore = DispatchSemaphore(value: 0)
    private var initializedQueryCompleted = DispatchSemaphore(value: 0)
    private var initializedQueryResult = false

    func reset() {
        lock.lock()
        callCount = 0
        enteredSemaphore = DispatchSemaphore(value: 0)
        releaseSemaphore = DispatchSemaphore(value: 0)
        initializedQueryCompleted = DispatchSemaphore(value: 0)
        initializedQueryResult = false
        lock.unlock()
    }

    func recordInitializerEntry() {
        lock.lock()
        callCount += 1
        lock.unlock()
        enteredSemaphore.signal()
    }

    func waitForInitializerEntries(_ count: Int, timeout: DispatchTimeInterval = .seconds(5)) -> Bool {
        for _ in 0..<count {
            // swiftlint:disable:next for_where
            if enteredSemaphore.wait(timeout: .now() + timeout) != .success {
                return false
            }
        }
        return true
    }

    func releaseInitializers(_ count: Int) {
        for _ in 0..<count {
            releaseSemaphore.signal()
        }
    }

    func waitForRelease(timeout: DispatchTimeInterval = .seconds(5)) -> Bool {
        releaseSemaphore.wait(timeout: .now() + timeout) == .success
    }

    func callCountSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return callCount
    }

    func recordInitializedQuery(_ result: Bool) {
        lock.lock()
        initializedQueryResult = result
        lock.unlock()
        initializedQueryCompleted.signal()
    }

    func waitForInitializedQuery(timeout: DispatchTimeInterval = .seconds(5)) -> Bool {
        initializedQueryCompleted.wait(timeout: .now() + timeout) == .success
    }

    func initializedQueryResultSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return initializedQueryResult
    }
}

private final class AtomicIntArrayBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int]

    init(_ value: [Int]) {
        storage = value
    }

    var value: [Int] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storage = newValue
        }
    }

    func store(_ value: Int, at index: Int) {
        lock.lock()
        storage[index] = value
        lock.unlock()
    }
}

/// Global state for callback testing (C function pointers cannot capture context).
private let gDelegateState = DelegateCallbackState()
private let gLazyPublicationState = LazyPublicationCallbackState()

private func lazyCountingInit() -> Int {
    gDelegateState.incrementLazyCallCount()
    return 99
}

private let lazyCountingInitCConv: KKThunkEntryPoint = { _ in lazyCountingInit() }

private let lazySimple42: KKThunkEntryPoint = { _ in 42 }
private let lazySimple77: KKThunkEntryPoint = { _ in 77 }
private let lazyPublicationValue: Int = 123

private func lazyPublicationInit() -> Int {
    gLazyPublicationState.recordInitializerEntry()
    guard gLazyPublicationState.waitForRelease() else {
        return 0
    }
    return lazyPublicationValue
}

private func lazyLockContentionInit() -> Int {
    gLazyPublicationState.recordInitializerEntry()
    guard gLazyPublicationState.waitForRelease() else {
        return 0
    }
    return 456
}

private let lazyLockContentionInitCConv: KKThunkEntryPoint = { _ in lazyLockContentionInit() }

private let lazyPublicationInitCConv: KKThunkEntryPoint = { _ in lazyPublicationInit() }

private let observableNoopCallback: KKFunctionEntryPoint3 = { _, _, _, _ in 0 }
private let observableCaptureCallback: KKFunctionEntryPoint3 = { _, old, new, _ in
    gDelegateState.setObservableCaptured(old: old, new: new)
    return 0
}

private let observableOrderCallback: KKFunctionEntryPoint3 = { _, _, _, _ in
    let handle = gDelegateState.observableHandleSnapshot()
    gDelegateState.setObservableValueInsideCallback(kk_observable_get_value(handle))
    return 0
}

private let vetoableAcceptCallback: KKFunctionEntryPoint3 = { _, _, _, _ in 1 }
private let vetoableRejectCallback: KKFunctionEntryPoint3 = { _, _, _, _ in 0 }
private let vetoableOrderCallback: KKFunctionEntryPoint3 = { _, _, _, _ in
    let handle = gDelegateState.vetoableHandleSnapshot()
    gDelegateState.setVetoableValueInsideCallback(kk_vetoable_get_value(handle))
    return 1
}

private func resetRuntimeDelegateTestState() {
    gDelegateState.reset()
    gLazyPublicationState.reset()
}

@Suite(.runtimeIsolation(.gcAndDelegate, resetAdditionalState: resetRuntimeDelegateTestState))
struct RuntimeDelegateTests {
    // MARK: - Lazy Delegate Tests

    @Test func lazyCreateReturnsNonZeroHandle() {
        let fnPtr = unsafeBitCast(lazySimple42, to: Int.self)
        let handle = kk_lazy_create(fnPtr, 1) // SYNCHRONIZED
        #expect(handle != 0)
    }

    @Test func lazyCreateWithLockReturnsValue() {
        let fnPtr = unsafeBitCast(lazySimple42, to: Int.self)
        let handle = kk_lazy_create_with_lock(fnPtr, 1, 0x4B5350373831)
        #expect(handle != 0)
        #expect(kk_lazy_get_value(handle) == 42)
    }

    @Test func lazyCreateWithLockSerializesInitializedQuery() {
        let fnPtr = unsafeBitCast(lazyLockContentionInitCConv, to: Int.self)
        let handle = kk_lazy_create_with_lock(fnPtr, 1, 0x4B5350373832)

        DispatchQueue.global().async {
            _ = kk_lazy_get_value(handle)
        }
        #expect(gLazyPublicationState.waitForInitializerEntries(1))

        DispatchQueue.global().async {
            gLazyPublicationState.recordInitializedQuery(kk_lazy_is_initialized(handle) == 1)
        }
        #expect(
            !gLazyPublicationState.waitForInitializedQuery(timeout: .milliseconds(100)),
            "isInitialized should wait for the lock-aware initializer"
        )

        gLazyPublicationState.releaseInitializers(1)
        #expect(gLazyPublicationState.waitForInitializedQuery())
        #expect(gLazyPublicationState.initializedQueryResultSnapshot())
    }

    @Test func lazyCreateWithNullLockUsesIndependentSynchronization() {
        let fnPtr = unsafeBitCast(lazyLockContentionInitCConv, to: Int.self)
        let firstHandle = kk_lazy_create_with_lock(fnPtr, 1, runtimeNullSentinelInt)
        let secondHandle = kk_lazy_create_with_lock(fnPtr, 1, runtimeNullSentinelInt)

        DispatchQueue.global().async {
            _ = kk_lazy_get_value(firstHandle)
        }
        DispatchQueue.global().async {
            _ = kk_lazy_get_value(secondHandle)
        }
        #expect(
            gLazyPublicationState.waitForInitializerEntries(2),
            "lazy(null) instances should not share one global synchronization lock"
        )
        gLazyPublicationState.releaseInitializers(2)
    }

    @Test func lazyGetValueInvokesInitializerOnce() {
        let fnPtr = unsafeBitCast(lazyCountingInitCConv, to: Int.self)
        let handle = kk_lazy_create(fnPtr, 1) // SYNCHRONIZED

        let firstRead = kk_lazy_get_value(handle)
        #expect(firstRead == 99)
        #expect(gDelegateState.lazyCallCountSnapshot() == 1)

        let secondRead = kk_lazy_get_value(handle)
        #expect(secondRead == 99)
        #expect(gDelegateState.lazyCallCountSnapshot() == 1, "Initializer should only be called once")
    }

    @Test func lazyNoneModeAlsoWorks() {
        let fnPtr = unsafeBitCast(lazySimple77, to: Int.self)
        let handle = kk_lazy_create(fnPtr, 0) // NONE

        let value = kk_lazy_get_value(handle)
        #expect(value == 77)
    }

    @Test func lazyGetValueWithInvalidHandleReturnsZero() {
        let value = kk_lazy_get_value(0)
        #expect(value == 0)
    }

    @Test func lazyIsInitializedReturnsFalseBeforeAccess() {
        let fnPtr = unsafeBitCast(lazySimple42, to: Int.self)
        let handle = kk_lazy_create(fnPtr, 1)
        #expect(kk_lazy_is_initialized(handle) == 0,
                "Lazy should not be initialized before first access")
    }

    @Test func lazyIsInitializedReturnsTrueAfterAccess() {
        let fnPtr = unsafeBitCast(lazySimple42, to: Int.self)
        let handle = kk_lazy_create(fnPtr, 1)
        _ = kk_lazy_get_value(handle)
        #expect(kk_lazy_is_initialized(handle) != 0,
                "Lazy should be initialized after first access")
    }

    @Test func lazyIsInitializedWithInvalidHandleReturnsZero() {
        #expect(kk_lazy_is_initialized(0) == 0)
    }

    @Test func lazyPublicationModeAllowsConcurrentInitializationButPublishesOneValue() {
        let fnPtr = unsafeBitCast(lazyPublicationInitCConv, to: Int.self)
        let handle = kk_lazy_create(fnPtr, 2) // PUBLICATION

        let group = DispatchGroup()
        let values = AtomicIntArrayBox(Array(repeating: 0, count: 2))

        for index in 0..<2 {
            group.enter()
            DispatchQueue.global().async {
                let value = kk_lazy_get_value(handle)
                values.store(value, at: index)
                group.leave()
            }
        }

        let didObserveInitializers = gLazyPublicationState.waitForInitializerEntries(2)
        gLazyPublicationState.releaseInitializers(2)
        #expect(didObserveInitializers)
        #expect(group.wait(timeout: .now() + .seconds(5)) == .success)

        #expect(values.value == [lazyPublicationValue, lazyPublicationValue])
        #expect(gLazyPublicationState.callCountSnapshot() == 2)
        #expect(kk_lazy_is_initialized(handle) == 1)
    }

    // MARK: - Observable Delegate Tests

    @Test func observableCreateAndGetValue() {
        let cbPtr = unsafeBitCast(observableNoopCallback, to: Int.self)
        let handle = kk_observable_create(10, cbPtr)
        #expect(handle != 0)

        let value = kk_observable_get_value(handle)
        #expect(value == 10)
    }

    @Test func observableSetValueInvokesCallbackAfterChange() {
        let cbPtr = unsafeBitCast(observableCaptureCallback, to: Int.self)
        let handle = kk_observable_create(10, cbPtr)

        let result = kk_observable_set_value(handle, 20)
        #expect(result == 20)

        // Callback should have been invoked with old=10, new=20
        #expect(gDelegateState.observableCapturedOldSnapshot() == 10)
        #expect(gDelegateState.observableCapturedNewSnapshot() == 20)

        let current = kk_observable_get_value(handle)
        #expect(current == 20)
    }

    @Test func observableCallbackOrderMatchesKotlinc() {
        // In kotlinc, observable callback fires AFTER the value is already changed.
        let cbPtr = unsafeBitCast(observableOrderCallback, to: Int.self)
        let handle = kk_observable_create(5, cbPtr)
        gDelegateState.setObservableHandle(handle)

        _ = kk_observable_set_value(handle, 15)
        #expect(gDelegateState.observableValueInsideCallbackSnapshot() == 15,
                "Value should be updated before callback is invoked")
    }

    @Test func observableGetValueWithInvalidHandleReturnsZero() {
        let value = kk_observable_get_value(0)
        #expect(value == 0)
    }

    // MARK: - Vetoable Delegate Tests

    @Test func vetoableCreateAndGetValue() {
        let cbPtr = unsafeBitCast(vetoableAcceptCallback, to: Int.self)
        let handle = kk_vetoable_create(100, cbPtr)
        #expect(handle != 0)

        let value = kk_vetoable_get_value(handle)
        #expect(value == 100)
    }

    @Test func vetoableAcceptsChangeWhenCallbackReturnsNonZero() {
        let cbPtr = unsafeBitCast(vetoableAcceptCallback, to: Int.self)
        let handle = kk_vetoable_create(100, cbPtr)

        let result = kk_vetoable_set_value(handle, 200)
        #expect(result == 200)

        let current = kk_vetoable_get_value(handle)
        #expect(current == 200)
    }

    @Test func vetoableRejectsChangeWhenCallbackReturnsZero() {
        let cbPtr = unsafeBitCast(vetoableRejectCallback, to: Int.self)
        let handle = kk_vetoable_create(100, cbPtr)

        let result = kk_vetoable_set_value(handle, 200)
        #expect(result == 100, "Value should remain unchanged when vetoed")

        let current = kk_vetoable_get_value(handle)
        #expect(current == 100)
    }

    @Test func vetoableCallbackOrderMatchesKotlinc() {
        // In kotlinc, vetoable callback fires BEFORE the value is changed.
        let cbPtr = unsafeBitCast(vetoableOrderCallback, to: Int.self)
        let handle = kk_vetoable_create(50, cbPtr)
        gDelegateState.setVetoableHandle(handle)

        _ = kk_vetoable_set_value(handle, 60)
        #expect(gDelegateState.vetoableValueInsideCallbackSnapshot() == 50,
                "Value should NOT be updated before vetoable callback")
    }

    @Test func vetoableGetValueWithInvalidHandleReturnsZero() {
        let value = kk_vetoable_get_value(0)
        #expect(value == 0)
    }

    // MARK: - NotNull Delegate Tests

    @Test func notNullSetThenGetReturnsAssignedValue() {
        let handle = kk_notNull_create()
        #expect(handle != 0)

        let written = kk_notNull_set_value(handle, 321)
        #expect(written == 321)

        let current = kk_notNull_get_value(handle)
        #expect(current == 321)
    }

    // STDLIB-PROP-ABI-001: reads-before-assignment must terminate with a helpful message.
    // The compiler currently lowers notNull delegate gets as non-throwing (one-arg) calls,
    // so kk_notNull_get_value calls fatalError rather than setting outThrown.
    // Integration-level verification (subprocess exit code + stderr message) is in
    // DelegatePropertyKIRTests.testNotNullDelegateReadBeforeAssignmentTrapsWithHelpfulMessage.
    // Future: when the compiler lowers notNull gets as throwing calls, add a unit test here
    // that passes an outThrown pointer and verifies an IllegalStateException is set.
    @Test func notNullHandleIsNonZeroAfterCreate() {
        let handle = kk_notNull_create()
        #expect(handle != 0, "kk_notNull_create must return a non-zero handle")
    }
}
