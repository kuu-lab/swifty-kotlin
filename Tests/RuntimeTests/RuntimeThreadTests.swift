import Foundation
@testable import Runtime
import Testing

private final class RuntimeThreadLaunchState: @unchecked Sendable {
    private let condition = NSCondition()
    private var launchCount = 0
    private var lastThreadName: String?
    private var lastThreadPriority: Double?

    func reset() {
        condition.lock()
        launchCount = 0
        lastThreadName = nil
        lastThreadPriority = nil
        condition.broadcast()
        condition.unlock()
    }

    func record(_ thread: Thread) {
        condition.lock()
        launchCount += 1
        lastThreadName = thread.name
        #if canImport(ObjectiveC)
        lastThreadPriority = thread.threadPriority
        #else
        lastThreadPriority = nil
        #endif
        condition.broadcast()
        condition.unlock()
    }

    func snapshot() -> (launchCount: Int, lastThreadName: String?, lastThreadPriority: Double?) {
        condition.lock()
        defer { condition.unlock() }
        return (launchCount, lastThreadName, lastThreadPriority)
    }

    func waitForLaunch(after baseline: Int, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while launchCount <= baseline {
            if !condition.wait(until: deadline) {
                return launchCount > baseline
            }
        }
        return true
    }
}

private let runtimeThreadLaunchState = RuntimeThreadLaunchState()

private let runtimeThreadThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in
    runtimeThreadLaunchState.record(Thread.current)
    return 0
}

private let runtimeThreadThunkPtr = unsafeBitCast(runtimeThreadThunk, to: Int.self)

private func resetRuntimeThreadTestState() {
    runtimeThreadLaunchState.reset()
}

@Suite(.runtimeIsolation(.gcOnly, resetAdditionalState: resetRuntimeThreadTestState))
struct RuntimeThreadTests {
    private func stringRaw(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
            }
        }
    }

    private func threadObject(from raw: Int) -> RuntimeManagedThread {
        let pointer = UnsafeMutableRawPointer(bitPattern: raw)
        return Unmanaged<RuntimeManagedThread>.fromOpaque(pointer!).takeUnretainedValue()
    }

    @Test func threadCreateStartsImmediatelyWhenRequested() throws {
        let baseline = runtimeThreadLaunchState.snapshot().launchCount
        let raw = kk_thread_create(
            1,
            1,
            runtimeNullSentinelInt,
            stringRaw("worker"),
            7,
            runtimeThreadThunkPtr,
            0
        )
        let createdThread = threadObject(from: raw)

        #expect(createdThread.name == "worker")
        #expect(createdThread.threadPriority > 0.6)
        #expect(createdThread.threadPriority < 0.8)

        #expect(runtimeThreadLaunchState.waitForLaunch(after: baseline))
        let snapshot = runtimeThreadLaunchState.snapshot()
        #expect(snapshot.launchCount == baseline + 1)
        #if canImport(ObjectiveC)
        #expect(snapshot.lastThreadName == "worker")
        let lastThreadPriority = try #require(snapshot.lastThreadPriority)
        #expect(abs(lastThreadPriority - createdThread.threadPriority) <= 0.0001)
        #endif

        let launchBox = try #require(createdThread.launchBox)
        #expect(launchBox.isDaemon)
        #expect(launchBox.contextClassLoaderRaw == runtimeNullSentinelInt)
        #expect(launchBox.priority == 7)
    }

    @Test func threadCreateDefersExecutionUntilStart() throws {
        let baseline = runtimeThreadLaunchState.snapshot().launchCount
        let raw = kk_thread_create(
            0,
            0,
            runtimeNullSentinelInt,
            stringRaw("manual"),
            5,
            runtimeThreadThunkPtr,
            0
        )
        let createdThread = threadObject(from: raw)

        #expect(createdThread.name == "manual")
        #expect(createdThread.threadPriority > 0.4)
        #expect(createdThread.threadPriority < 0.6)

        let launchBox = try #require(createdThread.launchBox)
        #expect(!launchBox.isDaemon)
        #expect(launchBox.contextClassLoaderRaw == runtimeNullSentinelInt)
        #expect(launchBox.priority == 5)

        #expect(runtimeThreadLaunchState.snapshot().launchCount == baseline)

        createdThread.start()

        #expect(runtimeThreadLaunchState.waitForLaunch(after: baseline))
        let snapshot = runtimeThreadLaunchState.snapshot()
        #expect(snapshot.launchCount == baseline + 1)
        #if canImport(ObjectiveC)
        #expect(snapshot.lastThreadName == "manual")
        let lastThreadPriority = try #require(snapshot.lastThreadPriority)
        #expect(abs(lastThreadPriority - createdThread.threadPriority) <= 0.0001)
        #endif
    }
}
