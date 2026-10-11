import Dispatch
import Foundation

// MARK: - KSP-1583: kotlinx.coroutines.test

/// Virtual-clock backing for `kotlinx.coroutines.test.TestCoroutineScheduler`.
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
        lock.unlock()
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

/// Standalone `TestCoroutineScheduler()` construction (e.g. for the
/// `StandardTestDispatcher(scheduler:)` factory's default).
@_cdecl("kk_test_scheduler_new")
public func kk_test_scheduler_new() -> Int {
    return runtimeRegisterObject(RuntimeTestScheduler())
}

/// Lazily minted per-scope scheduler handle backing `TestScope.testScheduler`.
@_cdecl("kk_test_scope_scheduler")
public func kk_test_scope_scheduler(_ scopeHandle: Int) -> Int {
    guard let scope = runtimeCoroutineScope(from: scopeHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_test_scope_scheduler received invalid scope handle")
    }
    return scope.schedulerForTest()
}

/// `TestScope.currentTime`: the scope's scheduler's virtual clock, lazily
/// minting the scheduler on first read.
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

/// Advances virtual time and resumes tasks scheduled before the target time.
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
///    into the receiver launcher slot. `timeoutRaw` is accepted for
///    signature compatibility but not enforced (degraded phase-1
///    contract).
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
    defer { RuntimeEventLoop.current = previousLoop }

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

    var thrown = 0
    let result = runtimeInvokeSuspendLauncherThunk(
        entryPointRaw: entryPointRaw,
        receiver: scopeHandle,
        captures: captures,
        outThrown: &thrown
    )
    if thrown != 0 {
        outThrown?.pointee = thrown
        // runTest semantics: a body failure cancels the scope's children.
        scope.cancel()
        _ = scope.waitForChildren(releaseOriginalHandles: false)
        return 0
    }
    // Children launched inside the body parent to the test scope — join
    // them the way a blocking runBlocking scope would. First advance the
    // test scheduler so delayed children can complete without wall-clock
    // waits, then surface the first child failure to the runTest caller.
    scope.testSchedulerIfPresent()?.advanceUntilIdle()
    let childThrown = scope.waitForChildren(releaseOriginalHandles: false)
    if childThrown != 0 {
        outThrown?.pointee = childThrown
        return 0
    }
    outThrown?.pointee = 0
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
    contState.launcherArgs[Int64(scopeSlotRaw)] = Int64(scopeHandle)
    contState.scope = scope

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
    defer { RuntimeEventLoop.current = previousLoop }

    let result = runtimeRunBlockingOnEventLoop(
        entryPointRaw: entryPointRaw,
        continuation: continuation,
        outThrown: outThrown
    )
    // `contState.scope` being preset means the event-loop run treats the
    // scope as borrowed and skips its own waitForChildren — so join the
    // test scope's children here instead. runTest semantics: a body
    // failure cancels the children; a child failure surfaces to the caller.
    let bodyFailed = (outThrown?.pointee ?? 0) != 0
    if bodyFailed {
        scope.cancel()
    } else {
        scope.testSchedulerIfPresent()?.advanceUntilIdle()
    }
    let childThrown = scope.waitForChildren(releaseOriginalHandles: false)
    if !bodyFailed, childThrown != 0 {
        outThrown?.pointee = childThrown
        return 0
    }
    return result
}
