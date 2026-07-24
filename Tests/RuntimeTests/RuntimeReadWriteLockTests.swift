#if canImport(Testing)
import Foundation
import Testing
@testable import Runtime

private let runtimeReadWriteLockStateLock = NSLock()
nonisolated(unsafe) private var _runtimeReadWriteLockActiveReaders = 0
nonisolated(unsafe) private var _runtimeReadWriteLockMaxReaders = 0
nonisolated(unsafe) private var runtimeReadWriteLockReadEnteredSemaphore = DispatchSemaphore(value: 0)
nonisolated(unsafe) private var runtimeReadWriteLockReadReleaseSemaphore = DispatchSemaphore(value: 0)
nonisolated(unsafe) private var runtimeReadWriteLockWriterEnteredSemaphore = DispatchSemaphore(value: 0)



@_cdecl("runtime_read_write_lock_passthrough")
private func runtime_read_write_lock_passthrough(
    _: Int
) -> Int {
    return 123
}

@_cdecl("runtime_read_write_lock_reader")
private func runtime_read_write_lock_reader(
    _: Int
) -> Int {
    runtimeReadWriteLockStateLock.lock()
    _runtimeReadWriteLockActiveReaders += 1
    _runtimeReadWriteLockMaxReaders = max(_runtimeReadWriteLockMaxReaders, _runtimeReadWriteLockActiveReaders)
    runtimeReadWriteLockStateLock.unlock()

    runtimeReadWriteLockReadEnteredSemaphore.signal()
    guard runtimeReadWriteLockReadReleaseSemaphore.wait(timeout: .now() + .seconds(5)) == .success else {
        return 0
    }

    runtimeReadWriteLockStateLock.lock()
    _runtimeReadWriteLockActiveReaders -= 1
    runtimeReadWriteLockStateLock.unlock()
    return 77
}

@_cdecl("runtime_read_write_lock_writer")
private func runtime_read_write_lock_writer(
    _: Int
) -> Int {
    runtimeReadWriteLockWriterEnteredSemaphore.signal()
    return 99
}

@Suite(.serialized)
struct RuntimeReadWriteLockTests {
    init() {}

    @Test
    func testReadWriteLockReturnsActionResult() {
        beginRuntimeReadWriteLockTest()
        defer {
            endRuntimeReadWriteLockTest()
        }

        let lock = kk_read_write_lock_create()
        let fn = unsafeBitCast(
            runtime_read_write_lock_passthrough as @convention(c) (Int) -> Int,
            to: Int.self
        )

        #expect(kk_read_write_lock_read(lock, fn, 0) == 123)
        #expect(kk_read_write_lock_write(lock, fn, 0) == 123)
    }

    @Test
    func testReadWriteLockAllowsConcurrentReaders() {
        beginRuntimeReadWriteLockTest()
        defer {
            endRuntimeReadWriteLockTest()
        }

        let lock = kk_read_write_lock_create()
        let fn = unsafeBitCast(
            runtime_read_write_lock_reader as @convention(c) (Int) -> Int,
            to: Int.self
        )
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            _ = kk_read_write_lock_read(lock, fn, 0)
            group.leave()
        }

        group.enter()
        DispatchQueue.global().async {
            _ = kk_read_write_lock_read(lock, fn, 0)
            group.leave()
        }

        #expect(runtimeReadWriteLockReadEnteredSemaphore.wait(timeout: .now() + .seconds(2)) == .success)
        #expect(runtimeReadWriteLockReadEnteredSemaphore.wait(timeout: .now() + .seconds(2)) == .success)
        runtimeReadWriteLockStateLock.lock()
        let maxReaders = _runtimeReadWriteLockMaxReaders
        runtimeReadWriteLockStateLock.unlock()
        #expect(maxReaders >= 2)

        runtimeReadWriteLockReadReleaseSemaphore.signal()
        runtimeReadWriteLockReadReleaseSemaphore.signal()
        #expect(group.wait(timeout: .now() + .seconds(2)) == .success)
    }

    @Test
    func testReadWriteLockBlocksWriterWhileReaderIsHeld() {
        beginRuntimeReadWriteLockTest()
        defer {
            endRuntimeReadWriteLockTest()
        }

        let lock = kk_read_write_lock_create()
        let readerFn = unsafeBitCast(
            runtime_read_write_lock_reader as @convention(c) (Int) -> Int,
            to: Int.self
        )
        let writerFn = unsafeBitCast(
            runtime_read_write_lock_writer as @convention(c) (Int) -> Int,
            to: Int.self
        )
        let readerGroup = DispatchGroup()
        let writerGroup = DispatchGroup()

        readerGroup.enter()
        DispatchQueue.global().async {
            _ = kk_read_write_lock_read(lock, readerFn, 0)
            readerGroup.leave()
        }

        #expect(runtimeReadWriteLockReadEnteredSemaphore.wait(timeout: .now() + .seconds(2)) == .success)

        writerGroup.enter()
        DispatchQueue.global().async {
            _ = kk_read_write_lock_write(lock, writerFn, 0)
            writerGroup.leave()
        }

        #expect(runtimeReadWriteLockWriterEnteredSemaphore.wait(timeout: .now() + .milliseconds(200)) == .timedOut)

        runtimeReadWriteLockReadReleaseSemaphore.signal()
        #expect(runtimeReadWriteLockWriterEnteredSemaphore.wait(timeout: .now() + .seconds(2)) == .success)
        #expect(readerGroup.wait(timeout: .now() + .seconds(2)) == .success)
        #expect(writerGroup.wait(timeout: .now() + .seconds(2)) == .success)
    }
}

private let runtimeReadWriteLockIsolationLeaseKey = "RuntimeReadWriteLockTests.isolationLease"

// Must not call kk_runtime_force_reset() here: Swift Testing suites run
// concurrently in one process, and a global reset deallocates handles owned
// by other suites. Leaked lock handles are reclaimed at process exit.
private func resetReadWriteLockHarness() {
    runtimeReadWriteLockStateLock.lock()
    _runtimeReadWriteLockActiveReaders = 0
    _runtimeReadWriteLockMaxReaders = 0
    runtimeReadWriteLockStateLock.unlock()
    runtimeReadWriteLockReadEnteredSemaphore = DispatchSemaphore(value: 0)
    runtimeReadWriteLockReadReleaseSemaphore = DispatchSemaphore(value: 0)
    runtimeReadWriteLockWriterEnteredSemaphore = DispatchSemaphore(value: 0)
}

private func beginRuntimeReadWriteLockTest() {
    precondition(Thread.current.threadDictionary[runtimeReadWriteLockIsolationLeaseKey] == nil)
    Thread.current.threadDictionary[runtimeReadWriteLockIsolationLeaseKey] = RuntimeTestIsolationLease(lockSet: .all)
    resetReadWriteLockHarness()
}

private func endRuntimeReadWriteLockTest() {
    resetReadWriteLockHarness()
    Thread.current.threadDictionary.removeObject(forKey: runtimeReadWriteLockIsolationLeaseKey)
}

#endif
