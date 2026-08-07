import Dispatch
import Foundation
@testable import Runtime
import Testing

/// Thread-safe box for capturing a value from an async closure in Swift 6.
private final class AtomicBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    init(_ value: T) {
        self._value = value
    }

    var value: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
}

/// Minimal suspend entry that records which dispatcher was active when it ran,
/// then immediately completes with the dispatcher tag (or 0 if none).
@_cdecl("runtime_test_dispatcher_observe_entry")
func runtime_test_dispatcher_observe_entry(
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let tag = RuntimeDispatcher.current?.tag ?? 0
    return kk_coroutine_state_exit(continuation, tag)
}

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeDispatcherTests {
    // MARK: - Dispatcher tag identity

    @Test func defaultDispatcherReturnsKnownTag() {
        let tag = kk_dispatcher_default()
        #expect(tag == 0x4B4B_4401, "Default dispatcher tag should be KKD\\x01")
    }

    @Test func ioDispatcherReturnsKnownTag() {
        let tag = kk_dispatcher_io()
        #expect(tag == 0x4B4B_4402, "IO dispatcher tag should be KKD\\x02")
    }

    @Test func mainDispatcherReturnsKnownTag() {
        let tag = kk_dispatcher_main()
        #expect(tag == 0x4B4B_4403, "Main dispatcher tag should be KKD\\x03")
    }

    @Test func dispatcherTagsAreDistinct() {
        let tags = [kk_dispatcher_default(), kk_dispatcher_io(), kk_dispatcher_main()]
        #expect(Set(tags).count == 3, "All dispatcher tags should be distinct")
    }

    // MARK: - Resolve dispatcher

    @Test func resolveDispatcherDefault() {
        let d = runtimeResolveDispatcher(from: kk_dispatcher_default())
        #expect(d.tag == kk_dispatcher_default())
    }

    @Test func resolveDispatcherIO() {
        let d = runtimeResolveDispatcher(from: kk_dispatcher_io())
        #expect(d.tag == kk_dispatcher_io())
    }

    @Test func resolveDispatcherMain() {
        let d = runtimeResolveDispatcher(from: kk_dispatcher_main())
        #expect(d.tag == kk_dispatcher_main())
    }

    @Test func resolveDispatcherUnknownFallsBackToDefault() {
        let d = runtimeResolveDispatcher(from: 0xDEAD)
        #expect(d.tag == kk_dispatcher_default(),
                "Unknown dispatcher should resolve to Default")
    }

    // MARK: - RuntimeDispatcher.current thread-local

    @Test func currentDispatcherIsNilByDefault() {
        // On the test thread, no dispatcher should be active unless set.
        // Clear to be sure (tests may inherit state from prior tests).
        let saved = RuntimeDispatcher.current
        RuntimeDispatcher.current = nil
        #expect(RuntimeDispatcher.current == nil)
        RuntimeDispatcher.current = saved
    }

    @Test func dispatchSyncSetsCurrentDispatcher() {
        let dispatcher = runtimeResolveDispatcher(from: kk_dispatcher_io())
        let observedTag: Int? = dispatcher.dispatchSync {
            RuntimeDispatcher.current?.tag
        }
        #expect(observedTag == kk_dispatcher_io(),
                "dispatchSync should set RuntimeDispatcher.current")
    }

    @Test func dispatchSyncRestoresCurrentDispatcherAfterCompletion() {
        let saved = RuntimeDispatcher.current
        RuntimeDispatcher.current = nil

        let dispatcher = runtimeResolveDispatcher(from: kk_dispatcher_io())
        dispatcher.dispatchSync { /* no-op */ }

        #expect(RuntimeDispatcher.current == nil,
                "dispatchSync should restore previous dispatcher on completion")
        RuntimeDispatcher.current = saved
    }

    @Test func dispatchAsyncSetsCurrentDispatcher() {
        let dispatcher = runtimeResolveDispatcher(from: kk_dispatcher_io())
        let done = DispatchSemaphore(value: 0)
        let observedTag = AtomicBox<Int?>(nil)

        dispatcher.dispatchAsync {
            observedTag.value = RuntimeDispatcher.current?.tag
            done.signal()
        }
        #expect(done.wait(timeout: .now() + 2.0) == .success,
                "async block should execute")
        #expect(observedTag.value == kk_dispatcher_io(),
                "dispatchAsync should set RuntimeDispatcher.current")
    }

    // MARK: - withContext actual dispatch

    @Test func withContextExecutesOnIODispatcher() {
        typealias SuspendEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
        let entryRaw = unsafeBitCast(
            runtime_test_dispatcher_observe_entry as SuspendEntry,
            to: Int.self
        )
        let continuation = kk_coroutine_continuation_new(7001)
        let result = kk_with_context(kk_dispatcher_io(), entryRaw, continuation)
        #expect(result == kk_dispatcher_io(),
                "withContext(IO) should execute with IO dispatcher active")
    }

    @Test func withContextExecutesOnDefaultDispatcher() {
        typealias SuspendEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
        let entryRaw = unsafeBitCast(
            runtime_test_dispatcher_observe_entry as SuspendEntry,
            to: Int.self
        )
        let continuation = kk_coroutine_continuation_new(7002)
        let result = kk_with_context(kk_dispatcher_default(), entryRaw, continuation)
        #expect(result == kk_dispatcher_default(),
                "withContext(Default) should execute with Default dispatcher active")
    }

    @Test func withContextFallsBackToDefaultForUnknownTag() {
        typealias SuspendEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
        let entryRaw = unsafeBitCast(
            runtime_test_dispatcher_observe_entry as SuspendEntry,
            to: Int.self
        )
        let continuation = kk_coroutine_continuation_new(7003)
        let result = kk_with_context(0xBEEF, entryRaw, continuation)
        #expect(result == kk_dispatcher_default(),
                "withContext(unknown) should fall back to Default dispatcher")
    }

    @Test func withContextInvalidEntryDoesNotCrash() {
        // Note: kk_with_context now releases the continuation on the invalid-entry
        // early-return path, so no manual cleanup is needed here.
        let continuation = kk_coroutine_continuation_new(7004)
        let result = kk_with_context(kk_dispatcher_default(), 0, continuation)
        #expect(result == 0, "Invalid entry should return 0 without crash")
    }

    // MARK: - KxMiniRuntime.launch with dispatcher

    @Test func launchOnDispatcherExecutesBlock() {
        let dispatcher = runtimeResolveDispatcher(from: kk_dispatcher_io())
        let done = DispatchSemaphore(value: 0)
        let observedTag = AtomicBox<Int?>(nil)

        KxMiniRuntime.launch(on: dispatcher) {
            observedTag.value = RuntimeDispatcher.current?.tag
            done.signal()
        }
        #expect(done.wait(timeout: .now() + 2.0) == .success,
                "block should execute on IO dispatcher")
        #expect(observedTag.value == kk_dispatcher_io())
    }

    // MARK: - Nested dispatcher context

    @Test func nestedWithContextSwitchesAndRestores() {
        typealias SuspendEntry = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
        let entryRaw = unsafeBitCast(
            runtime_test_dispatcher_observe_entry as SuspendEntry,
            to: Int.self
        )
        // Outer: IO dispatcher
        let ioDispatcher = runtimeResolveDispatcher(from: kk_dispatcher_io())
        let (outerTag, innerTag): (Int, Int) = ioDispatcher.dispatchSync {
            let outer = RuntimeDispatcher.current?.tag ?? 0

            // Inner: Default dispatcher
            let continuation = kk_coroutine_continuation_new(7005)
            let inner = kk_with_context(kk_dispatcher_default(), entryRaw, continuation)
            return (outer, inner)
        }
        #expect(outerTag == kk_dispatcher_io(),
                "Outer context should be IO")
        #expect(innerTag == kk_dispatcher_default(),
                "Inner withContext should switch to Default")
    }
}
