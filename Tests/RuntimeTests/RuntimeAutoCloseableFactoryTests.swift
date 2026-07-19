import Foundation
@testable import Runtime
import Testing

private final class AutoCloseableFactoryTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var closeCount = 0
    private var lastClosureRaw = 0

    func reset() {
        lock.lock()
        closeCount = 0
        lastClosureRaw = 0
        lock.unlock()
    }

    func recordClose(closureRaw: Int) {
        lock.lock()
        closeCount += 1
        lastClosureRaw = closureRaw
        lock.unlock()
    }

    func snapshot() -> (count: Int, closureRaw: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (closeCount, lastClosureRaw)
    }
}

private let autoCloseableFactoryState = AutoCloseableFactoryTestState()
private let autoCloseableCloseMessage = "factory close failure"

private let autoCloseableCloseAction: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { closureRaw, _ in
    autoCloseableFactoryState.recordClose(closureRaw: closureRaw)
    return 0
}

private let autoCloseableThrowingCloseAction: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: autoCloseableCloseMessage)
    return runtimeExceptionCaughtSentinel
}

private let autoCloseableUseBody: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _ in
    99
}

private func autoCloseableThrowableBox(from handle: Int) -> RuntimeThrowableBox? {
    guard handle != 0,
          handle != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: handle)
    else {
        return nil
    }
    return tryCast(ptr, to: RuntimeThrowableBox.self)
}

private func resetAutoCloseableFactoryTestState() {
    autoCloseableFactoryState.reset()
}

@Suite(.runtimeIsolation(.gcOnly, resetAdditionalState: resetAutoCloseableFactoryTestState))
struct RuntimeAutoCloseableFactoryTests {
    @Test func factoryRegistersCloseMethod() {
        let resourceRaw = kk_auto_closeable_create(
            unsafeBitCast(autoCloseableCloseAction, to: Int.self),
            41
        )
        let closeFnPtr = kk_itable_lookup(resourceRaw, 0, 0)
        #expect(closeFnPtr != 0)

        let closeFn = unsafeBitCast(closeFnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var outThrown = 0
        let result = closeFn(resourceRaw, &outThrown)

        #expect(result == 0)
        #expect(outThrown == 0)
        let snapshot = autoCloseableFactoryState.snapshot()
        #expect(snapshot.count == 1)
        #expect(snapshot.closureRaw == 41)
    }

    @Test func useClosesFactoryResourceAfterBody() {
        let resourceRaw = kk_auto_closeable_create(
            unsafeBitCast(autoCloseableCloseAction, to: Int.self),
            77
        )

        var outThrown = 0
        let result = kk_use(
            resourceRaw,
            unsafeBitCast(autoCloseableUseBody, to: Int.self),
            0,
            &outThrown
        )

        #expect(result == 99)
        #expect(outThrown == 0)
        let snapshot = autoCloseableFactoryState.snapshot()
        #expect(snapshot.count == 1)
        #expect(snapshot.closureRaw == 77)
    }

    @Test func useAllowsNullResourceWithoutClose() {
        var outThrown = 0
        let result = kk_use(
            0,
            unsafeBitCast(autoCloseableUseBody, to: Int.self),
            0,
            &outThrown
        )

        #expect(result == 99)
        #expect(outThrown == 0)
        #expect(autoCloseableFactoryState.snapshot().count == 0)
    }

    @Test func usePropagatesFactoryCloseException() {
        let resourceRaw = kk_auto_closeable_create(
            unsafeBitCast(autoCloseableThrowingCloseAction, to: Int.self),
            0
        )

        var outThrown = 0
        let result = kk_use(
            resourceRaw,
            unsafeBitCast(autoCloseableUseBody, to: Int.self),
            0,
            &outThrown
        )

        #expect(result == runtimeExceptionCaughtSentinel)
        #expect(autoCloseableThrowableBox(from: outThrown)?.message == autoCloseableCloseMessage)
    }
}
