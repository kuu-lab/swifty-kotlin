import Foundation
@testable import Runtime
import Testing

private final class RuntimeNativeUnhandledExceptionHookTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedThrowable = 0

    func reset() {
        lock.lock()
        capturedThrowable = 0
        lock.unlock()
    }

    func record(_ throwableRaw: Int) {
        lock.lock()
        capturedThrowable = throwableRaw
        lock.unlock()
    }

    func captured() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return capturedThrowable
    }
}

private let runtimeNativeUnhandledExceptionHookTestState = RuntimeNativeUnhandledExceptionHookTestState()

private func resetRuntimeNativeUnhandledExceptionHookTestState() {
    runtimeNativeUnhandledExceptionHookTestState.reset()
    _ = kk_native_setUnhandledExceptionHook(0)
}

private func runtimeNativeUnhandledExceptionHook(
    _ throwableRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeNativeUnhandledExceptionHookTestState.record(throwableRaw)
    outThrown?.pointee = 0
    return 0
}

private func runtimeNativeUnhandledExceptionThrowingHook(
    _ throwableRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = throwableRaw
    return 0
}

@Suite(
    .runtimeIsolation(
        .gcOnly,
        resetAdditionalState: resetRuntimeNativeUnhandledExceptionHookTestState
    )
)
struct RuntimeNativeUnhandledExceptionHookTests {
    @Test func getAndSetUnhandledExceptionHookRoundTrip() {
        let hookRaw = unsafeBitCast(
            runtimeNativeUnhandledExceptionHook as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )

        #expect(kk_native_getUnhandledExceptionHook() == runtimeNullSentinelInt)
        #expect(kk_native_setUnhandledExceptionHook(hookRaw) == 0)
        #expect(kk_native_getUnhandledExceptionHook() == hookRaw)
        #expect(kk_native_setUnhandledExceptionHook(runtimeNullSentinelInt) == 0)
        #expect(kk_native_getUnhandledExceptionHook() == runtimeNullSentinelInt)
    }

    @Test func processUnhandledExceptionInvokesRegisteredHook() {
        let hookRaw = unsafeBitCast(
            runtimeNativeUnhandledExceptionHook as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let throwableRaw = 0x1234

        _ = kk_native_setUnhandledExceptionHook(hookRaw)
        #expect(kk_native_processUnhandledException(throwableRaw, nil) == 0)

        #expect(runtimeNativeUnhandledExceptionHookTestState.captured() == throwableRaw)
    }

    @Test func processUnhandledExceptionPropagatesHookThrownChannel() {
        let hookRaw = unsafeBitCast(
            runtimeNativeUnhandledExceptionThrowingHook as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let throwableRaw = 0x5678
        var thrown = 0

        _ = kk_native_setUnhandledExceptionHook(hookRaw)
        #expect(kk_native_processUnhandledException(throwableRaw, &thrown) == 0)

        #expect(thrown == throwableRaw)
    }

    @Test func processUnhandledExceptionNoopsWithoutHook() {
        let throwableRaw = 0x9abc

        #expect(kk_native_processUnhandledException(throwableRaw, nil) == 0)
        #expect(runtimeNativeUnhandledExceptionHookTestState.captured() == 0)
    }
}
