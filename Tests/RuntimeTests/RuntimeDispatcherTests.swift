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

private extension AtomicBox where T == Int {
    @discardableResult
    func add(_ delta: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        _value += delta
        return _value
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
    @Test func dispatcherNamesPreserveNumericValues() {
        for (kind, name, tag) in [
            (0, "Dispatchers.Default", kk_dispatcher_default()),
            (1, "Dispatchers.IO", kk_dispatcher_io()),
            (2, "Dispatchers.Unconfined", kk_dispatcher_default()),
        ] {
            let handle = kk_dispatcher_named(kind)
            #expect(handle == kk_dispatcher_named(kind))
            #expect(runtimeElementToString(handle) == name)
            #expect(runtimeRenderAnyForPrint(handle) == name)
            #expect(extractString(from: kk_any_to_string(handle, 1)) == name)
            #expect(kk_context_get_dispatcher(handle) == tag)
            #expect(resolveToCoroutineContext(handle).dispatcher == tag)
            #expect(resolveToCoroutineContext(handle).dispatcherElementHandle == handle)
            let state = RuntimeContinuationState(functionID: 1300)
            state.builderContext = resolveToCoroutineContext(handle)
            #expect(state.makeContinuationContext().dispatcherElementHandle == handle)
            let combined = kk_context_plus(kk_dispatcher_named(0), handle)
            #expect(resolveToCoroutineContext(combined).dispatcherElementHandle == handle)
            #expect(kk_context_get(combined, handle) == handle)
            #expect(resolveToCoroutineContext(kk_context_minusKey(combined, handle)).dispatcherElementHandle == 0)
            #expect(runtimeResolveDispatcher(from: handle).tag == tag)
            #expect(kk_is_native_dispatcher(handle) == 1)
            #expect(kk_object_release(handle) == 0)
        }
        #expect(Set((0...2).map(kk_dispatcher_named)).count == 3)
        // KUU-2687: dispatcher *objects* render their kotlinx names —
        // `kk_dispatcher_main` returns the registered object.
        #expect(runtimeElementToString(kk_dispatcher_main()) == "Dispatchers.Main")
        #expect(runtimeRenderAnyForPrint(kk_dispatcher_main()) == "Dispatchers.Main")
        // Bare scheduler tags are bit-identical to Int literals at the print
        // layer (a Kotlin `1263223810.toString()` must stay numeric — see
        // diff_cases/dispatchers_to_string.kt), so they render as numbers.
        for tag in [
            RuntimeDispatcherTag.mainDispatcher,
            RuntimeDispatcherTag.mainImmediateDispatcher,
            kk_dispatcher_default(),
            kk_dispatcher_io(),
        ] {
            #expect(extractString(from: kk_any_to_string(tag, 1)) == String(tag))
            #expect(runtimeElementToString(tag) == String(tag))
            #expect(runtimeRenderAnyForPrint(tag) == String(tag))
        }
        for number in [0x4B4B_4405, 0x4B4B_4406, 0x4B4B_4407] {
            #expect(extractString(from: kk_any_to_string(number, 1)) == String(number))
            #expect(runtimeElementToString(number) == String(number))
            #expect(runtimeRenderAnyForPrint(number) == String(number))
            let boxed = kk_box_int(number)
            #expect(runtimeElementToString(boxed) == String(number))
        }
    }

    @Test func sourceEmptyContextPreservesRunBlockingEventLoop() {
        let empty = kk_object_new(0, Int(runtimeStableNominalTypeID(
            fqName: "kotlin.coroutines.EmptyCoroutineContext"
        )))
        let context = resolveToCoroutineContext(empty)
        #expect(context.dispatcherElementHandle == 0)
        let loop = RuntimeEventLoop()
        #expect(runtimeBlockingScheduler(context: context, fallbackLoop: loop).eventLoop === loop)

        // A default child context must preserve its parent's event-loop element.
        let parent = RuntimeCoroutineContext(dispatcherHandleRaw: loop.elementHandle())
        let child = parent.plus(context)
        #expect(runtimeBlockingScheduler(context: child, fallbackLoop: loop).eventLoop === loop)
    }

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
        // KUU-2687: `kk_dispatcher_main` returns the dispatcher *object*
        // (upstream `Dispatchers.Main` singleton), not the bare scheduler tag.
        let d = runtimeResolveDispatcher(from: kk_dispatcher_main())
        #expect(d.tag == 0x4B4B_4403, "Main dispatcher tag should be KKD\\x03")
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
        #expect(d.tag == RuntimeDispatcherTag.mainDispatcher)
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

    // MARK: - KUU-2687: limitedParallelism views

    private final class ConcurrencyProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var running = 0
        private(set) var maxRunning = 0
        private(set) var order: [Int] = []

        func taskStart(_ id: Int) {
            lock.lock()
            running += 1
            maxRunning = max(maxRunning, running)
            order.append(id)
            lock.unlock()
        }

        func taskEnd() {
            lock.lock()
            running -= 1
            lock.unlock()
        }
    }

    @Test func limitedDispatcherIsUnconfinedCheck() {
        #expect(kk_dispatcher_is_unconfined(kk_dispatcher_named(2)) == 1,
                "Dispatchers.Unconfined must report isUnconfined")
        #expect(kk_dispatcher_is_unconfined(kk_dispatcher_named(0)) == 0)
        #expect(kk_dispatcher_is_unconfined(kk_dispatcher_default()) == 0)
        let view = kk_dispatcher_limited_parallelism(kk_dispatcher_named(1), 1, 0)
        #expect(kk_dispatcher_is_unconfined(view) == 0)
    }

    @Test func limitedDispatcherSerializesAtParallelismOne() {
        let viewHandle = kk_dispatcher_limited_parallelism(kk_dispatcher_default(), 1, 0)
        let view = runtimeResolveDispatcher(from: viewHandle)
        #expect(viewHandle != kk_dispatcher_default(),
                "limitedParallelism must return a distinct view handle")
        #expect((view as? RuntimeLimitedDispatcher)?.parallelismLimit == 1)
        let probe = ConcurrencyProbe()
        let group = DispatchGroup()
        for id in 0..<3 {
            group.enter()
            view.dispatchAsync {
                probe.taskStart(id)
                Thread.sleep(forTimeInterval: 0.02)
                probe.taskEnd()
                group.leave()
            }
        }
        #expect(group.wait(timeout: .now() + 10.0) == .success)
        #expect(probe.maxRunning == 1,
                "parallelism=1 must serialize work, observed \(probe.maxRunning)")
        #expect(probe.order == [0, 1, 2],
                "pending queue must be FIFO, observed \(probe.order)")
    }

    @Test func limitedDispatcherAllowsTwoConcurrentAtParallelismTwo() {
        let view = runtimeResolveDispatcher(from:
            kk_dispatcher_limited_parallelism(kk_dispatcher_default(), 2, 0))
        let probe = ConcurrencyProbe()
        // Block the first two tasks until both hold a permit: only a real
        // second permit lets the pair rendezvous.
        let pairEntered = DispatchSemaphore(value: 0)
        let releasePair = DispatchSemaphore(value: 0)
        let enteredCount = AtomicBox(0)
        for _ in 0..<2 {
            view.dispatchAsync {
                probe.taskStart(0)
                if enteredCount.add(1) == 2 { pairEntered.signal() }
                releasePair.wait()
                probe.taskEnd()
            }
        }
        #expect(pairEntered.wait(timeout: .now() + 10.0) == .success,
                "parallelism=2 must run two tasks concurrently")
        releasePair.signal()
        releasePair.signal()
        // A third task only runs once a permit frees.
        let thirdDone = DispatchSemaphore(value: 0)
        view.dispatchAsync {
            probe.taskStart(2)
            probe.taskEnd()
            thirdDone.signal()
        }
        #expect(thirdDone.wait(timeout: .now() + 10.0) == .success)
        #expect(probe.maxRunning == 2)
    }

    @Test func nestedLimitedViewsFollowUpstreamNamedOrThis() {
        let parent = kk_dispatcher_limited_parallelism(kk_dispatcher_default(), 2, 0)
        // Not tighter → upstream returns `namedOrThis`: the same view object.
        let wider = kk_dispatcher_limited_parallelism(parent, 4, 0)
        #expect(wider == parent)
        // Tighter → a new view enqueuing through the parent gate.
        let tighter = kk_dispatcher_limited_parallelism(parent, 1, 0)
        #expect(tighter != parent)
        #expect(tighter != 0)
        let tighterView = runtimeResolveDispatcher(from: tighter) as? RuntimeLimitedDispatcher
        #expect(tighterView?.parallelismLimit == 1)
        let probe = ConcurrencyProbe()
        let group = DispatchGroup()
        for id in 0..<2 {
            group.enter()
            runtimeResolveDispatcher(from: tighter).dispatchAsync {
                probe.taskStart(id)
                Thread.sleep(forTimeInterval: 0.01)
                probe.taskEnd()
                group.leave()
            }
        }
        #expect(group.wait(timeout: .now() + 10.0) == .success)
        #expect(probe.maxRunning == 1,
                "nested parallelism=1 view must serialize through the parent")
    }

    @Test func limitedDispatcherGatesConcurrentProducers() {
        let view = runtimeResolveDispatcher(from:
            kk_dispatcher_limited_parallelism(kk_dispatcher_default(), 1, 0))
        let probe = ConcurrencyProbe()
        let group = DispatchGroup()
        // Dispatch from several producer threads; the view must still cap at 1.
        DispatchQueue.concurrentPerform(iterations: 4) { _ in
            group.enter()
            view.dispatchAsync {
                probe.taskStart(0)
                Thread.sleep(forTimeInterval: 0.01)
                probe.taskEnd()
                group.leave()
            }
        }
        #expect(group.wait(timeout: .now() + 10.0) == .success)
        #expect(probe.maxRunning == 1)
    }

    @Test func limitedDispatcherReentrantDispatchIsNotInline() {
        let view = runtimeResolveDispatcher(from:
            kk_dispatcher_limited_parallelism(kk_dispatcher_default(), 1, 0))
        let probe = ConcurrencyProbe()
        let done = DispatchSemaphore(value: 0)
        view.dispatchAsync {
            probe.taskStart(0)
            // Nested dispatch must queue behind the running task, not reenter.
            view.dispatchAsync {
                probe.taskStart(1)
                probe.taskEnd()
                done.signal()
            }
            probe.taskEnd()
        }
        #expect(done.wait(timeout: .now() + 10.0) == .success)
        #expect(probe.maxRunning == 1)
        #expect(probe.order == [0, 1])
    }

    @Test func cancelledViewWorkReleasesPermitForWaiters() {
        let view = runtimeResolveDispatcher(from:
            kk_dispatcher_limited_parallelism(kk_dispatcher_default(), 1, 0))
        let blocker = DispatchSemaphore(value: 0)
        let unblock = DispatchSemaphore(value: 0)
        let cancelledRan = AtomicBox(false)
        let waitedRan = AtomicBox(false)
        view.dispatchAsync {
            blocker.signal()
            unblock.wait()
        }
        #expect(blocker.wait(timeout: .now() + 10.0) == .success)
        // Queue a cancelled work item, then a live one: the cancelled task must
        // be skipped while still freeing the permit for the live task.
        let cancelledItem = DispatchWorkItem { cancelledRan.value = true }
        let cancelledBox = RuntimeWorkItemBox(cancelledItem)
        view.dispatchAsync {
            cancelledBox.performUnlessCancelled()
        }
        cancelledItem.cancel()
        view.dispatchAsync {
            waitedRan.value = true
        }
        unblock.signal()
        let deadline = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            while !waitedRan.value { Thread.sleep(forTimeInterval: 0.005) }
            deadline.signal()
        }
        #expect(deadline.wait(timeout: .now() + 10.0) == .success)
        #expect(waitedRan.value)
        #expect(!cancelledRan.value,
                "cancelled queued work must not run inside the view")
    }

    // MARK: - KUU-2687: immediate dispatch

    @Test func immediatePeerResolution() {
        let mainTag = kk_dispatcher_main()
        let immediateHandle = kk_dispatcher_immediate_or_self(mainTag)
        #expect(immediateHandle != mainTag,
                "Main.immediate must be a distinct dispatcher object")
        let immediate = runtimeResolveDispatcher(from: immediateHandle)
        #expect(immediate.tag == RuntimeDispatcherTag.mainImmediateDispatcher)
        #expect(immediate.supportsImmediateDispatch)
        // Upstream: `Dispatchers.Main.immediate === Dispatchers.Main.immediate`.
        #expect(kk_dispatcher_immediate_or_self(mainTag) == immediateHandle)
        // Non-Main dispatchers answer themselves.
        let ioHandle = kk_dispatcher_named(1)
        #expect(kk_dispatcher_immediate_or_self(ioHandle) == ioHandle)
        let view = kk_dispatcher_limited_parallelism(kk_dispatcher_named(0), 1, 0)
        #expect(kk_dispatcher_immediate_or_self(view) == view)
        // The immediate object itself is its own immediate peer.
        #expect(kk_dispatcher_immediate_or_self(immediateHandle) == immediateHandle)
    }

    @Test func immediateDispatcherRunsInlineOnItsThread() {
        let immediate = runtimeResolveDispatcher(
            from: kk_dispatcher_immediate_or_self(kk_dispatcher_main()))
        let saved = RuntimeDispatcher.current
        defer { RuntimeDispatcher.current = saved }
        // Pretend we are running on the immediate dispatcher.
        RuntimeDispatcher.current = immediate
        let ran = AtomicBox(false)
        let ranInlineThread = AtomicBox(false)
        let callingThread = mach_thread_self()
        immediate.dispatchAsync {
            ran.value = true
            ranInlineThread.value = mach_thread_self() == callingThread
        }
        #expect(ran.value, "immediate dispatch must run inline on its thread")
        #expect(ranInlineThread.value)
    }

    @Test func limitedViewOccupiesContextDispatcherSlot() {
        let view = kk_dispatcher_limited_parallelism(kk_dispatcher_named(1), 2, 0)
        let ctx = resolveToCoroutineContext(view)
        #expect(ctx.dispatcherElementHandle == view)
        #expect(resolveToCoroutineContext(kk_context_plus(0, view)).dispatcherElementHandle == view)
        #expect(kk_context_get(view, kk_continuation_interceptor_key()) == view)
        #expect(kk_context_get(view, kk_coroutine_dispatcher_key()) == view)
        #expect(kk_is_native_dispatcher(view) == 1)
        #expect(runtimeElementToString(view) == "Dispatchers.IO.limitedParallelism(2)")
    }

    @Test func mainLimitedParallelismIsNamedOrThis() {
        let mainTag = kk_dispatcher_main()
        // No name → upstream `namedOrThis` returns the dispatcher itself.
        #expect(kk_dispatcher_limited_parallelism(mainTag, 1, 0) == mainTag)
        // With a name → a named view wrapping Main.
        let nameRaw = Int(bitPattern: runtimeMakeStringPointer("main-limited"))
        let named = kk_dispatcher_limited_parallelism(mainTag, 1, nameRaw)
        #expect(named != mainTag)
        #expect(runtimeElementToString(named) == "main-limited")
        #expect(kk_is_native_dispatcher(named) == 1)
    }
}
