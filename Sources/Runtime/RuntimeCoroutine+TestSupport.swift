import Dispatch
import Foundation


final class RuntimeTestScheduler: @unchecked Sendable {
    private struct ScheduledTask {
        let timeMillis: Int64
        let order: UInt64
        let action: @Sendable () -> Void
    }

    private let lock = NSLock()
    private var _currentTimeMillis: Int64 = 0
    private var nextTaskOrder: UInt64 = 0
    private var scheduledTasks: [ScheduledTask] = []
    private weak var boundEventLoop: RuntimeEventLoop?
    /// KUU-2688: while a `runTest` run is in flight, virtual-time tasks pump
    /// themselves through the bound event loop's idle hook — the way
    /// upstream's TestDispatcher auto-advances when the queue would
    /// otherwise idle — so the test body's own `delay` completes without
    /// wall-clock waiting. The hook is consulted only when the loop is
    /// about to block on an empty queue, so a synchronous burst still
    /// observes tasks in ordinary FIFO order.
    private var autoPumpArmed = false

    init() {
        RuntimeLiveHandles.register(self)
    }

    deinit {
        RuntimeLiveHandles.unregister(self)
    }

    var currentTimeMillis: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _currentTimeMillis
    }

    func advanceTimeBy(_ millis: Int64) {
        guard millis > 0 else { return }
        drainReadyCoroutines()
        lock.lock()
        let target = _currentTimeMillis.addingReportingOverflow(millis)
        let targetTime = target.overflow ? Int64.max : target.partialValue
        lock.unlock()

        runScheduledTasks(before: targetTime, includingEndpoint: false)
        lock.lock()
        _currentTimeMillis = max(_currentTimeMillis, targetTime)
        lock.unlock()
    }

    func schedule(after millis: Int64, action: @escaping @Sendable () -> Void) {
        lock.lock()
        let delay = max(0, millis)
        let dueTime = _currentTimeMillis.addingReportingOverflow(delay)
        scheduledTasks.append(ScheduledTask(
            timeMillis: dueTime.overflow ? Int64.max : dueTime.partialValue,
            order: nextTaskOrder,
            action: action
        ))
        nextTaskOrder &+= 1
        let loop = boundEventLoop
        let armed = autoPumpArmed
        lock.unlock()
        // The bound loop's idle wait never wakes on scheduler work alone:
        // nudge it so the idle hook gets a chance to run the new task.
        if armed { loop?.wake() }
    }

    /// Arms/disarms the runTest auto-pump described on `autoPumpArmed`.
    func setAutoPump(_ armed: Bool) {
        lock.lock()
        autoPumpArmed = armed
        let loop = boundEventLoop
        lock.unlock()
        // Install on the bound loop so `run(until:)` consults the pump only
        // while it is actually draining.
        if armed {
            loop?.installIdleAction { [weak self] in self?.autoPumpStep() ?? false }
        } else {
            loop?.installIdleAction(nil)
        }
    }

    /// Idle hook: runs the earliest pending task — advancing virtual time to
    /// it — and reports whether progress was made. Only ever called from
    /// `RuntimeEventLoop.run(until:)` on an empty queue.
    private func autoPumpStep() -> Bool {
        lock.lock()
        let armed = autoPumpArmed
        lock.unlock()
        guard armed,
              let task = takeNextTask(through: Int64.max, includingEndpoint: true)
        else { return false }
        run(task.action)
        drainReadyCoroutines()
        return true
    }

    func bind(eventLoop: RuntimeEventLoop) {
        lock.lock()
        boundEventLoop = eventLoop
        lock.unlock()
    }

    func advanceUntilIdle() {
        drainReadyCoroutines()
        while let task = takeNextTask(through: Int64.max, includingEndpoint: true) {
            run(task.action)
            drainReadyCoroutines()
        }
    }

    func runCurrent() {
        drainReadyCoroutines()
        runScheduledTasks(before: currentTimeMillis, includingEndpoint: true)
    }

    private func runScheduledTasks(before limit: Int64, includingEndpoint: Bool) {
        while let task = takeNextTask(through: limit, includingEndpoint: includingEndpoint) {
            run(task.action)
            drainReadyCoroutines()
        }
    }

    private func run(_ action: @Sendable () -> Void) {
        let previous = RuntimeEventLoop.current
        let loop: RuntimeEventLoop?
        if let previous {
            loop = previous
        } else {
            lock.lock()
            loop = boundEventLoop
            lock.unlock()
        }
        if previous == nil, let loop {
            RuntimeEventLoop.current = loop
        }
        defer {
            if previous == nil, loop != nil {
                RuntimeEventLoop.current = nil
            }
        }
        action()
    }

    private func takeNextTask(through limit: Int64, includingEndpoint: Bool) -> ScheduledTask? {
        lock.lock()
        defer { lock.unlock() }
        guard let nextIndex = scheduledTasks.indices.min(by: { lhs, rhs in
            let left = scheduledTasks[lhs]
            let right = scheduledTasks[rhs]
            if left.timeMillis != right.timeMillis {
                return left.timeMillis < right.timeMillis
            }
            return left.order < right.order
        }) else {
            return nil
        }
        let next = scheduledTasks[nextIndex]
        guard includingEndpoint ? next.timeMillis <= limit : next.timeMillis < limit else {
            return nil
        }
        scheduledTasks.remove(at: nextIndex)
        _currentTimeMillis = max(_currentTimeMillis, next.timeMillis)
        return next
    }

    private func drainReadyCoroutines() {
        RuntimePendingLaunchQueue.flush()
        let loop: RuntimeEventLoop?
        if let current = RuntimeEventLoop.current {
            loop = current
        } else {
            lock.lock()
            loop = boundEventLoop
            lock.unlock()
        }
        loop?.runReadyTasks()
    }
}

@_cdecl("kk_test_scheduler_new")
public func kk_test_scheduler_new() -> Int {
    return runtimeRegisterObject(RuntimeTestScheduler())
}

@_cdecl("kk_test_scope_scheduler")
public func kk_test_scope_scheduler(_ scopeHandle: Int) -> Int {
    guard let scope = runtimeCoroutineScope(from: scopeHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_test_scope_scheduler received invalid scope handle")
    }
    return scope.schedulerForTest()
}

@_cdecl("kk_test_scope_current_time")
public func kk_test_scope_current_time(_ scopeHandle: Int) -> Int {
    guard let scope = runtimeCoroutineScope(from: scopeHandle) else {
        return 0
    }
    guard let scheduler = resolveLiveRuntimeHandle(scope.schedulerForTest(), as: RuntimeTestScheduler.self) else {
        return 0
    }
    return Int(scheduler.currentTimeMillis)
}

@_cdecl("kk_test_scheduler_current_time")
public func kk_test_scheduler_current_time(_ schedulerHandle: Int) -> Int {
    guard let scheduler = resolveLiveRuntimeHandle(schedulerHandle, as: RuntimeTestScheduler.self) else {
        return 0
    }
    return Int(scheduler.currentTimeMillis)
}

@_cdecl("kk_test_scheduler_advance_time_by")
public func kk_test_scheduler_advance_time_by(_ schedulerHandle: Int, _ delayTimeMillis: Int) -> Int {
    guard let scheduler = resolveLiveRuntimeHandle(schedulerHandle, as: RuntimeTestScheduler.self) else {
        return 0
    }
    scheduler.advanceTimeBy(Int64(delayTimeMillis))
    return 0
}

@_cdecl("kk_test_scheduler_advance_until_idle")
public func kk_test_scheduler_advance_until_idle(_ schedulerHandle: Int) -> Int {
    resolveLiveRuntimeHandle(schedulerHandle, as: RuntimeTestScheduler.self)?.advanceUntilIdle()
    return 0
}

@_cdecl("kk_test_scheduler_run_current")
public func kk_test_scheduler_run_current(_ schedulerHandle: Int) -> Int {
    resolveLiveRuntimeHandle(schedulerHandle, as: RuntimeTestScheduler.self)?.runCurrent()
    return 0
}

/// KUU-2688: the error `runTest` reports through `outThrown` when its
/// `timeout` budget elapses. Upstream's `UncompletedCoroutinesError` is a
/// `kotlin.AssertionError` subtype in package `kotlinx.coroutines.test`.
final class RuntimeUncompletedCoroutinesErrorBox: RuntimeThrowableBox {
    override var exceptionFQName: String {
        "kotlinx.coroutines.test.UncompletedCoroutinesError"
    }

    override var exceptionHierarchyFQNames: [String] {
        [
            "kotlinx.coroutines.test.UncompletedCoroutinesError",
            "UncompletedCoroutinesError",
            "kotlin.AssertionError",
            "kotlin.Error",
            "kotlin.Throwable",
        ]
    }

    override var renderedMessage: String {
        runtimeRenderedExceptionMessage("UncompletedCoroutinesError", message)
    }
}

func runtimeAllocateUncompletedCoroutinesError(message: String, suppressed: [Int] = []) -> Int {
    let box = RuntimeUncompletedCoroutinesErrorBox(message: message)
    box.suppressed.append(contentsOf: suppressed)
    return runtimeRegisterThrowable(box)
}

/// KUU-2688: real-time watchdog enforcing `runTest`'s `timeout` argument.
///
/// Upstream `TestScopeImpl.runTest` wraps its scope join in
/// `withTimeout(timeout)`: the budget is wall-clock, so virtual scheduler
/// time does not consume it. On expiry the test scope is cancelled with
/// `CancellationException("The test timed out")` and the caller receives an
/// `UncompletedCoroutinesError` in place of the body's outcome; the message
/// distinguishes "the test body did not run to completion" from a body that
/// finished while children were still active.
///
/// Upstream `withTimeout` raises a TimeoutCancellationException immediately
/// for a non-positive duration — before runTest's completion handler that
/// would record the timeout is installed — so the scope is never cancelled
/// and the join simply finishes the body: a non-positive (or effectively
/// infinite, e.g. `Duration.INFINITE`) timeout is never enforced. Both are
/// modelled by leaving the watchdog disarmed.
///
/// Internal (not private) so RuntimeTests can drive the budget decode and
/// the fire/disarm lifecycle directly.
final class RuntimeTestRunTimeout {
    private let lock = NSLock()
    private var workItem: DispatchWorkItem?
    private var disarmed = false
    private var bodyFinished = false
    private(set) var fired = false
    private(set) var bodyFinishedAtFire = false
    private(set) var activeChildrenAtFire: [String] = []

    /// Millisecond budgets above this bound never fire upstream
    /// (`Duration.INFINITE` clamps `inWholeMilliseconds` to `Long.MAX`);
    /// arming a real timer would overflow `DispatchTime` math.
    static let maxArmableMillis: Int64 = Int64.max / 1_000_000

    func arm(millis: Int64, scope: RuntimeCoroutineScope) {
        let item = DispatchWorkItem { [weak self, weak scope] in
            self?.fire(scope: scope)
        }
        workItem = item
        DispatchQueue.global().asyncAfter(
            deadline: .now() + .milliseconds(Int(millis)),
            execute: item
        )
    }

    private func fire(scope: RuntimeCoroutineScope?) {
        lock.lock()
        if disarmed || fired {
            lock.unlock()
            return
        }
        fired = true
        bodyFinishedAtFire = bodyFinished
        lock.unlock()
        // Snapshot the active children before the cancel below unwinds them:
        // the error message lists what was still running at fire time.
        let activeChildren = scope?.activeChildDescriptions() ?? []
        lock.lock()
        activeChildrenAtFire = activeChildren
        lock.unlock()
        scope?.cancel(
            message: "The test timed out",
            cause: runtimeAllocateCancellationException(message: "The test timed out")
        )
    }

    /// Records that the test body reached a terminal state (returned or
    /// threw), mirroring upstream's `testBodyFinished` flag.
    func markBodyFinished() {
        lock.lock()
        bodyFinished = true
        lock.unlock()
    }

    func disarm() {
        lock.lock()
        disarmed = true
        let item = workItem
        workItem = nil
        lock.unlock()
        item?.cancel()
    }
}

/// Decodes the `timeout: Duration` argument into a wall-clock millisecond
/// budget plus the Kotlin `Duration.toString()` text used in diagnostics.
/// A nil budget means upstream never enforces it (non-positive or
/// effectively-infinite durations).
func runtimeRunTestTimeoutBudget(_ timeoutRaw: Int) -> (millis: Int64?, text: String) {
    let text = extractString(from: UnsafeMutableRawPointer(bitPattern: kk_duration_toString(timeoutRaw)))
        ?? "\(kk_duration_inWholeMilliseconds(timeoutRaw))ms"
    // Upstream `Duration.toDelayMillis()` clamps a positive duration to at
    // least one millisecond; non-positive durations are never armed.
    let nanos = runtimeDurationNanosecondsValue(from: timeoutRaw) ?? 0
    guard nanos > 0 else {
        return (nil, text)
    }
    let millis = max(1, Int64(kk_duration_inWholeMilliseconds(timeoutRaw)))
    guard millis < RuntimeTestRunTimeout.maxArmableMillis else {
        return (nil, text)
    }
    return (millis, text)
}

/// Builds the `UncompletedCoroutinesError` upstream's completion handler
/// produces when the timeout fires: the message branch depends on whether
/// the body finished and whether child jobs were still active at fire time.
func runtimeRunTestTimeoutError(
    watchdog: RuntimeTestRunTimeout,
    timeoutText: String,
    suppressed: [Int]
) -> Int {
    let detail: String
    if watchdog.bodyFinishedAtFire, !watchdog.activeChildrenAtFire.isEmpty {
        detail = "there were active child jobs: \(watchdog.activeChildrenAtFire). "
            + "Use `TestScope.backgroundScope` to launch the coroutines that need "
            + "to be cancelled when the test body finishes"
    } else if watchdog.bodyFinishedAtFire {
        detail = "the test completed, but only after the timeout"
    } else {
        detail = "the test body did not run to completion"
    }
    return runtimeAllocateUncompletedCoroutinesError(
        message: "After waiting for \(timeoutText), \(detail)",
        suppressed: suppressed
    )
}

/// Backing for `kotlinx.coroutines.test.runTest` — mints a `TestScope` (a
/// real RuntimeCoroutineScope over `context`) and invokes `testBody` with
/// `this` bound to it. Two block shapes reach this boundary, mirroring
/// `__kk_produce_launch`:
///  - A suspend *literal* the call-site rewrite resolves routes to
///    `kk_test_run_blocking_with_cont` instead (launcher-continuation
///    convention; the scope lands in launcherArgs[0]).
///  - A suspend function *value* that does not resolve to a known suspend
///    symbol (e.g. an opaque boxed `Function` object) crosses as the
///    (entryPointRaw, closureRaw) pair suspend function values use at the
///    ABI boundary, invoked under `__kk_produce_launch`'s convention: env
///    expands to the leading slots and the scope handle passes as the
///    trailing receiver (`(cap0..capN, receiver, outThrown)`). Blocks
///    that DO resolve — literals and variable-held lambdas alike — route
///    to `kk_test_run_blocking_with_cont` instead, which seeds the scope
///    into the receiver launcher slot. `timeoutRaw` is enforced as a
///    wall-clock budget by `RuntimeTestRunTimeout`.
@_cdecl("kk_test_run_blocking")
public func kk_test_run_blocking(
    _ contextRaw: Int,
    _ timeoutRaw: Int,
    _ entryPointRaw: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard entryPointRaw != 0 else {
        outThrown?.pointee = 0
        return 0
    }
    let scopeHandle = kk_coroutine_scope_new_with_context(contextRaw)
    guard let scope = runtimeCoroutineScope(from: scopeHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_test_run_blocking failed to create test scope")
    }
    _ = scope.schedulerForTest()
    // KUU-2688: the TestScope's own Job is the element `coroutineContext.job`
    // resolves to inside the body and the handle the watchdog cancels. A Job
    // element the context carried was adopted as `scope.job` — upstream it
    // becomes the scope job's parent, so re-seat it that way rather than
    // letting a timeout cancel a caller-supplied Job directly.
    let contextJob = scope.job
    let scopeJob = scope.installJob(defaultCancellationMessage: "TestScope was cancelled")
    contextJob?.registerChild(runtimeRegisterObject(scopeJob))

    let (timeoutMillis, timeoutText) = runtimeRunTestTimeoutBudget(timeoutRaw)
    let watchdog = RuntimeTestRunTimeout()
    if let timeoutMillis {
        watchdog.arm(millis: timeoutMillis, scope: scope)
    }
    defer { watchdog.disarm() }

    // Children launched inside the test body discover the test scope as
    // their parent (upstream runTest semantics), so install it as ambient
    // for the duration of the blocking run. An event loop is installed the
    // same way: children queue on it (the thunk's nested blocking run
    // reuses the current loop), and `waitForChildren`'s joins keep
    // draining it until they complete.
    let previousScope = RuntimeCoroutineScope.current
    RuntimeCoroutineScope.current = scope
    defer { RuntimeCoroutineScope.current = previousScope }
    let previousLoop = RuntimeEventLoop.current
    let loop = previousLoop ?? RuntimeEventLoop()
    RuntimeEventLoop.current = loop
    scope.testSchedulerIfPresent()?.bind(eventLoop: loop)
    scope.testSchedulerIfPresent()?.setAutoPump(true)
    defer {
        scope.testSchedulerIfPresent()?.setAutoPump(false)
        RuntimeEventLoop.current = previousLoop
    }

    var thrown = 0
    let result: Int
    if let box = runtimeFunctionValueBox(from: entryPointRaw), box.suspendEntryPoint != 0 {
        // A boxed suspend function value (`kk_suspend_function_create`)
        // carries its own suspend entry point and env: invoke it through the
        // suspend-value ABI so the env reaches the adapter's leading closure
        // parameter and the minted TestScope lands as the trailing receiver.
        // The positional launcher-thunk convention below only fits raw
        // (fnPtr, closure) pairs.
        result = runtimeInvokeSuspendFunction(
            entryPointRaw,
            arguments: [scopeHandle],
            continuation: 0,
            outThrown: &thrown
        )
    } else {
        // Expand the env slot into the thunk's positional captures, the same
        // packed-shape expansion `__kk_produce_launch` performs: 0 → none, a
        // packed env object (kk_object_new(2+N, classID: 0), captures at
        // slots 2..) → N captures, anything else → a single raw capture.
        let captures: [Int]
        if closureRaw == 0 {
            captures = []
        } else if let envBox = resolveRuntimeHandle(closureRaw, as: RuntimeObjectBox.self),
                  envBox.classID == 0,
                  envBox.elements.count > 2
        {
            captures = Array(envBox.elements.dropFirst(2))
        } else {
            captures = [closureRaw]
        }
        result = runtimeInvokeSuspendLauncherThunk(
            entryPointRaw: entryPointRaw,
            receiver: scopeHandle,
            captures: captures,
            outThrown: &thrown
        )
    }
    watchdog.markBodyFinished()
    var suppressed: [Int] = []
    // Upstream suppresses the body's completion exception only when it is
    // not the CancellationException the timeout itself installed; a body
    // unwinding with exactly that exception adds nothing.
    if thrown != 0, thrown != scope.cancellationCause {
        suppressed.append(thrown)
    }
    if thrown != 0 {
        // runTest semantics: a body failure cancels the scope's children.
        scope.cancel()
    }
    // Children launched inside the body parent to the test scope — join
    // them the way a blocking runBlocking scope would. First advance the
    // test scheduler so delayed children can complete without wall-clock
    // waits, then surface the first child failure to the runTest caller.
    if thrown == 0 {
        scope.testSchedulerIfPresent()?.advanceUntilIdle()
    }
    let childThrown = scope.waitForChildren(releaseOriginalHandles: false)
    if childThrown != 0 {
        suppressed.append(childThrown)
    }
    if watchdog.fired {
        // Timeout precedence: the UncompletedCoroutinesError replaces the
        // body's own outcome; whatever the body/children completed with
        // becomes a suppressed exception on it.
        outThrown?.pointee = runtimeRunTestTimeoutError(
            watchdog: watchdog, timeoutText: timeoutText, suppressed: suppressed
        )
        _ = scopeJob.complete(with: 0)
        return 0
    }
    if thrown != 0 {
        outThrown?.pointee = thrown
        _ = scopeJob.completeExceptionally(with: thrown)
        return 0
    }
    if childThrown != 0 {
        outThrown?.pointee = childThrown
        _ = scopeJob.completeExceptionally(with: childThrown)
        return 0
    }
    outThrown?.pointee = 0
    _ = scopeJob.complete(with: result)
    return result
}

/// Literal-lambda counterpart to `kk_test_run_blocking`: the call-site
/// rewrite built a launcher continuation holding the block's captures in
/// launcherArgs; `scopeSlotRaw` names the suspend-entry receiver slot —
/// 0 for launcher-marked (receiver-first) lambdas, `params.count - 1`
/// for unmarked (captures-first) suspend values — and the freshly minted
/// test scope lands there so `this` inside the body binds to the real
/// RuntimeCoroutineScope. The nested runBlocking drains the suspend entry
/// loop on this thread, matching `runTest`'s blocking contract.
@_cdecl("kk_test_run_blocking_with_cont")
public func kk_test_run_blocking_with_cont(
    _ contextRaw: Int,
    _ timeoutRaw: Int,
    _ entryPointRaw: Int,
    _ continuation: Int,
    _ scopeSlotRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let scopeHandle = kk_coroutine_scope_new_with_context(contextRaw)
    guard let scope = runtimeCoroutineScope(from: scopeHandle),
          let contState = runtimeContinuationState(from: continuation),
          scopeSlotRaw >= 0
    else {
        outThrown?.pointee = 0
        return 0
    }
    _ = scope.schedulerForTest()
    contState.setLauncherArg(Int64(scopeSlotRaw), value: Int64(scopeHandle))
    contState.scope = scope
    // Binding the body to the test scope's Job is what lets the watchdog's
    // cancel wake a suspended body: the suspend-entry loop registers its
    // cancellation handler on `jobHandle`, so `scope.cancel()` signalling
    // the job resumes the body with a CancellationException. A context Job
    // element becomes the scope job's parent, matching upstream TestScope.
    let contextJob = scope.job
    let scopeJob = scope.installJob(defaultCancellationMessage: "TestScope was cancelled")
    contextJob?.registerChild(runtimeRegisterObject(scopeJob))
    contState.jobHandle = scopeJob

    let (timeoutMillis, timeoutText) = runtimeRunTestTimeoutBudget(timeoutRaw)
    let watchdog = RuntimeTestRunTimeout()
    if let timeoutMillis {
        watchdog.arm(millis: timeoutMillis, scope: scope)
    }
    defer { watchdog.disarm() }

    let previousScope = RuntimeCoroutineScope.current
    RuntimeCoroutineScope.current = scope
    defer { RuntimeCoroutineScope.current = previousScope }
    // Install the event loop the nested blocking run will reuse; it stays
    // current after that run returns so `waitForChildren`'s joins can keep
    // draining children that are still queued on it.
    let previousLoop = RuntimeEventLoop.current
    let loop = previousLoop ?? RuntimeEventLoop()
    RuntimeEventLoop.current = loop
    scope.testSchedulerIfPresent()?.bind(eventLoop: loop)
    scope.testSchedulerIfPresent()?.setAutoPump(true)
    defer {
        scope.testSchedulerIfPresent()?.setAutoPump(false)
        RuntimeEventLoop.current = previousLoop
    }

    let result = runtimeRunBlockingOnEventLoop(
        entryPointRaw: entryPointRaw,
        continuation: continuation,
        outThrown: outThrown
    )
    watchdog.markBodyFinished()
    // `contState.scope` being preset means the event-loop run treats the
    // scope as borrowed and skips its own waitForChildren — so join the
    // test scope's children here instead. runTest semantics: a body
    // failure cancels the children; a child failure surfaces to the caller.
    let bodyThrown = outThrown?.pointee ?? 0
    var suppressed: [Int] = []
    if bodyThrown != 0, bodyThrown != scope.cancellationCause {
        suppressed.append(bodyThrown)
    }
    if bodyThrown != 0 {
        scope.cancel()
    } else {
        scope.testSchedulerIfPresent()?.advanceUntilIdle()
    }
    let childThrown = scope.waitForChildren(releaseOriginalHandles: false)
    if childThrown != 0 {
        suppressed.append(childThrown)
    }
    if watchdog.fired {
        outThrown?.pointee = runtimeRunTestTimeoutError(
            watchdog: watchdog, timeoutText: timeoutText, suppressed: suppressed
        )
        _ = scopeJob.complete(with: 0)
        return 0
    }
    if bodyThrown == 0, childThrown != 0 {
        outThrown?.pointee = childThrown
        _ = scopeJob.completeExceptionally(with: childThrown)
        return 0
    }
    if bodyThrown != 0 {
        _ = scopeJob.completeExceptionally(with: bodyThrown)
    } else {
        _ = scopeJob.complete(with: result)
    }
    return result
}
