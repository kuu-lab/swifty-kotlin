#if canImport(Testing)
import Foundation
import Testing
@testable import Runtime

private let synchronizedCapturedClosureRawLock = NSLock()
nonisolated(unsafe) private var _synchronizedCapturedClosureRaw = 0

private var synchronizedCapturedClosureRaw: Int {
    get {
        synchronizedCapturedClosureRawLock.lock()
        defer { synchronizedCapturedClosureRawLock.unlock() }
        return _synchronizedCapturedClosureRaw
    }
    set {
        synchronizedCapturedClosureRawLock.lock()
        defer { synchronizedCapturedClosureRawLock.unlock() }
        _synchronizedCapturedClosureRaw = newValue
    }
}

private let synchronizedNestedFnPtrLock = NSLock()
nonisolated(unsafe) private var _synchronizedNestedFnPtr = 0

private var synchronizedNestedFnPtr: Int {
    get {
        synchronizedNestedFnPtrLock.lock()
        defer { synchronizedNestedFnPtrLock.unlock() }
        return _synchronizedNestedFnPtr
    }
    set {
        synchronizedNestedFnPtrLock.lock()
        defer { synchronizedNestedFnPtrLock.unlock() }
        _synchronizedNestedFnPtr = newValue
    }
}

private let synchronizedNestedClosureRawLock = NSLock()
nonisolated(unsafe) private var _synchronizedNestedClosureRaw = 0

private var synchronizedNestedClosureRaw: Int {
    get {
        synchronizedNestedClosureRawLock.lock()
        defer { synchronizedNestedClosureRawLock.unlock() }
        return _synchronizedNestedClosureRaw
    }
    set {
        synchronizedNestedClosureRawLock.lock()
        defer { synchronizedNestedClosureRawLock.unlock() }
        _synchronizedNestedClosureRaw = newValue
    }
}

@_cdecl("runtime_synchronized_success_lambda")
private func runtime_synchronized_success_lambda(
    _: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    return 123
}

@_cdecl("runtime_synchronized_failure_lambda")
private func runtime_synchronized_failure_lambda(
    _: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = runtimeAllocateThrowable(message: "synchronized failure")
    return 0
}

@_cdecl("runtime_synchronized_capture_lambda")
private func runtime_synchronized_capture_lambda(
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    synchronizedCapturedClosureRaw = closureRaw
    outThrown?.pointee = 0
    return 77
}

@_cdecl("runtime_synchronized_reentrant_lambda")
private func runtime_synchronized_reentrant_lambda(
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let result = kk_synchronized(closureRaw, synchronizedNestedFnPtr, synchronizedNestedClosureRaw, outThrown)
    if outThrown?.pointee ?? 0 != 0 {
        return 0
    }
    return result + 1
}

@Suite(.serialized)
struct RuntimeSynchronizedTests {
    init() {
        synchronizedCapturedClosureRaw = 0
        synchronizedNestedFnPtr = 0
        synchronizedNestedClosureRaw = 0
    }

    @Test
    func testSynchronizedReturnsBlockResult() {
        let lease = RuntimeTestIsolationLease(lockSet: .all)
        defer { lease.release() }
        defer {
            kk_runtime_force_reset()
        }

        let fn = unsafeBitCast(
            runtime_synchronized_success_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        var thrown = 0
        let result = kk_synchronized(101, fn, 0, &thrown)

        #expect(thrown == 0)
        #expect(result == 123)
    }

    @Test
    func testSynchronizedPropagatesThrownValue() {
        let lease = RuntimeTestIsolationLease(lockSet: .all)
        defer { lease.release() }
        defer {
            kk_runtime_force_reset()
        }

        let fn = unsafeBitCast(
            runtime_synchronized_failure_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        var thrown = 0
        let result = kk_synchronized(202, fn, 0, &thrown)

        #expect(result == 0)
        #expect(thrown != 0)
    }

    @Test
    func testSynchronizedPassesClosureRawToThunk() {
        let lease = RuntimeTestIsolationLease(lockSet: .all)
        defer { lease.release() }
        defer {
            kk_runtime_force_reset()
        }

        synchronizedCapturedClosureRaw = 0
        let fn = unsafeBitCast(
            runtime_synchronized_capture_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        var thrown = 0
        let sentinel = 4242
        let result = kk_synchronized(303, fn, sentinel, &thrown)

        #expect(thrown == 0)
        #expect(result == 77)
        #expect(synchronizedCapturedClosureRaw == sentinel)
    }

    @Test
    func testSynchronizedSupportsReentrantLocking() {
        let lease = RuntimeTestIsolationLease(lockSet: .all)
        defer { lease.release() }
        defer {
            kk_runtime_force_reset()
        }

        let nestedFn = unsafeBitCast(
            runtime_synchronized_success_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        synchronizedNestedFnPtr = nestedFn
        synchronizedNestedClosureRaw = 0

        let outerFn = unsafeBitCast(
            runtime_synchronized_reentrant_lambda as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        var thrown = 0
        let lockKey = 404
        let result = kk_synchronized(lockKey, outerFn, lockKey, &thrown)

        #expect(thrown == 0)
        #expect(result == 124)
    }
}
#endif
