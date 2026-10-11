import Dispatch
import Foundation

/// An opt-in scheduling policy owned by the source runBlocking builder.
/// Legacy suspend-value/launcher entry points keep their existing nil policy.
final class RuntimeBlockingScheduler: @unchecked Sendable {
    enum Destination {
        case eventLoop(RuntimeEventLoop)
        case dispatcher(RuntimeDispatcher)
        case unconfined(RuntimeDispatcher)
    }
    let destination: Destination
    init(_ destination: Destination) { self.destination = destination }

    var eventLoop: RuntimeEventLoop? {
        if case let .eventLoop(loop) = destination { return loop }
        return nil
    }
    var dispatcher: RuntimeDispatcher? {
        switch destination {
        case let .dispatcher(dispatcher), let .unconfined(dispatcher): return dispatcher
        case .eventLoop: return nil
        }
    }

    func enqueueResume(_ work: @escaping @Sendable () -> Void) {
        switch destination {
        case let .eventLoop(loop): loop.enqueue(work)
        case let .dispatcher(dispatcher): dispatcher.dispatchAsync(execute: work)
        case .unconfined: RuntimeUnconfinedRunQueue.enqueue(work)
        }
    }

    func scheduleChild(_ work: @escaping @Sendable () -> Void) {
        switch destination {
        case let .eventLoop(loop): loop.enqueue(work)
        case let .dispatcher(dispatcher): dispatcher.queue.async(execute: work)
        case .unconfined: RuntimeUnconfinedRunQueue.startInline(work)
        }
    }

    func start(_ work: @escaping @Sendable () -> Void) {
        switch destination {
        case let .eventLoop(loop):
            if RuntimeEventLoop.current === loop { work() } else { loop.enqueue(work) }
        case let .dispatcher(dispatcher): dispatcher.queue.async(execute: work)
        case .unconfined: RuntimeUnconfinedRunQueue.startInline(work)
        }
    }
}

/// Unconfined starts/resumes on the invoking thread without recursively
/// reentering a burst whose pending resumption has just been installed.
/// A nested blocking wait can drain ready work on the same thread.
private final class RuntimeUnconfinedRunQueue: @unchecked Sendable {
    private static let key = makePthreadKey()
    private var pending: [@Sendable () -> Void] = []
    private var index = 0
    private static var current: RuntimeUnconfinedRunQueue? {
        get { pthreadGetValue(key) }
        set { pthreadSetValue(key, newValue) }
    }

    static func startInline(_ work: @escaping @Sendable () -> Void) {
        if current != nil { work(); return }
        let queue = RuntimeUnconfinedRunQueue()
        current = queue
        defer { current = nil }
        work()
        queue.drain()
    }

    static func enqueue(_ work: @escaping @Sendable () -> Void) {
        if let queue = current { queue.pending.append(work) }
        else { startInline(work) }
    }

    static func drainReady() { current?.drain() }

    private func drain() {
        while index < pending.count {
            let work = pending[index]
            index += 1
            work()
        }
        pending.removeAll(keepingCapacity: true)
        index = 0
    }
}

func runtimeDrainBlockingUnconfinedTasks() { RuntimeUnconfinedRunQueue.drainReady() }

func runtimeBlockingScheduler(
    context: RuntimeCoroutineContext,
    fallbackLoop: RuntimeEventLoop
) -> RuntimeBlockingScheduler {
    let handle = context.dispatcherElementHandle
    guard handle != 0 else { return RuntimeBlockingScheduler(.eventLoop(fallbackLoop)) }
    let dispatcher = runtimeResolveDispatcher(from: handle)
    if let loop = dispatcher.blockingEventLoop {
        return RuntimeBlockingScheduler(.eventLoop(loop))
    }
    if dispatcher.isUnconfined {
        return RuntimeBlockingScheduler(.unconfined(dispatcher))
    }
    return RuntimeBlockingScheduler(.dispatcher(dispatcher))
}

private final class RuntimeBlockingOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var value: (result: Int, thrown: Int)?
    func complete(result: Int, thrown: Int) {
        lock.lock()
        precondition(value == nil, "runBlocking body completed twice")
        value = (result, thrown)
        lock.unlock()
    }
    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value != nil
    }
    func snapshot() -> (result: Int, thrown: Int) {
        lock.lock()
        defer { lock.unlock() }
        precondition(value != nil)
        return value!
    }
}

/// The language signature is (context, block): T. Physical arguments are
/// (context, fnOrBox, env, outThrown): intptr. Preserve an opaque suspend
/// function box until invocation so its suspendEntryPoint is not lost.
/// The common source wrapper materializes the block before forwarding it.
@_cdecl("__kk_run_blocking_context")
public func __kk_run_blocking_context(
    _ contextRaw: Int,
    _ fnOrBox: Int,
    _ envRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    // plus(empty) copies the mutable runtime representation. Never mutate a
    // supplied context object or merge ambient Name/Job into a default call.
    let context = resolveToCoroutineContext(contextRaw).plus(RuntimeCoroutineContext())
    let parentCandidate = runtimeJobHandle(from: context.jobHandleRaw)
        ?? runtimeAsyncTask(from: context.jobHandleRaw)?.completionJob
    let parent = parentCandidate === runtimeJobHandle(from: kk_non_cancellable_instance()) ? nil : parentCandidate
    let oldLoop = RuntimeEventLoop.current
    let oldKey = RuntimeCoroutineScopeTaskKey.installedKey
    let oldJob = RuntimeJobHandle.current
    let oldDispatcher = RuntimeDispatcher.current
    let waitLoop = oldLoop ?? RuntimeEventLoop()
    let scheduler = runtimeBlockingScheduler(context: context, fallbackLoop: waitLoop)
    // No interceptor: expose the loop that actually executes the body.
    if context.dispatcherElementHandle == 0 {
        context.dispatcherHandleRaw = waitLoop.elementHandle()
    }
    let scope = RuntimeCoroutineScope(context: context)
    scope.blockingScheduler = scheduler
    let job = RuntimeJobHandle()
    job.debugName = "BlockingCoroutine"
    job.propagatesFailureToParent = false
    job.markStarted()
    let jobRaw = runtimeRegisterObject(job)
    context.jobHandleRaw = jobRaw
    scope.adoptJob(job)
    let invocation = RuntimeContinuationState(functionID: 0)
    invocation.scope = scope
    invocation.builderContext = context
    invocation.jobHandle = job
    invocation.blockingScheduler = scheduler
    invocation.eventLoop = scheduler.eventLoop
    job.continuationState = invocation
    // Cancellation links exist before parent registration, including the
    // already-cancelled-parent case. This builder never completes its parent.
    parent?.registerChild(jobRaw)
    RuntimeEventLoop.current = waitLoop
    defer {
        parent?.detachChild(jobRaw)
        RuntimeEventLoop.current = oldLoop
        RuntimeCoroutineScopeTaskKey.restoreKey(oldKey)
        RuntimeJobHandle.current = oldJob
        RuntimeDispatcher.current = oldDispatcher
    }
    let outcome = RuntimeBlockingOutcome()
    scheduler.start {
        let savedKey = RuntimeCoroutineScopeTaskKey.installedKey
        let savedJob = RuntimeJobHandle.current
        let savedLoop = RuntimeEventLoop.current
        let savedDispatcher = RuntimeDispatcher.current
        let invocationKey = RuntimeCoroutineScopeTaskKey.installFreshKey()
        RuntimeCoroutineScope.installScope(scope, forTask: invocationKey)
        RuntimeContinuationState.installState(invocation, forTask: invocationKey)
        RuntimeJobHandle.current = job
        RuntimeEventLoop.current = scheduler.eventLoop
        RuntimeDispatcher.current = scheduler.dispatcher
        var result = 0
        var thrown = 0
        defer {
            RuntimeCoroutineScope.removeScope(forTask: invocationKey)
            RuntimeContinuationState.removeState(forTask: invocationKey)
            RuntimeCoroutineScopeTaskKey.restoreKey(savedKey)
            RuntimeJobHandle.current = savedJob
            RuntimeEventLoop.current = savedLoop
            RuntimeDispatcher.current = savedDispatcher
            // Publish only after this invocation's ambient bindings restore.
            outcome.complete(result: result, thrown: thrown)
            waitLoop.wake()
        }
        if job.cancellationSnapshot() {
            thrown = kk_job_get_cancellation_exception(jobRaw)
            return
        }
        let scopeRaw = Int(bitPattern: Unmanaged.passUnretained(scope).toOpaque())
        if let box = runtimeFunctionValueBox(from: fnOrBox), box.suspendEntryPoint != 0 {
            result = runtimeInvokeSuspendFunction(
                fnOrBox, arguments: [scopeRaw], continuation: 0, outThrown: &thrown
            )
        } else {
            result = runtimeInvokeCollectionLambda1(
                fnPtr: fnOrBox, closureRaw: envRaw, value: scopeRaw, outThrown: &thrown
            )
        }
    }
    waitLoop.run(until: {
        RuntimeUnconfinedRunQueue.drainReady()
        return outcome.isFinished
    })
    let body = outcome.snapshot()
    let priorChildFailure = scope.childFailureSnapshot()
    if body.thrown != 0 { scope.cancel() }
    let childThrown = scope.waitForChildren(releaseOriginalHandles: false)
    var thrown = priorChildFailure != 0 ? priorChildFailure
        : (childThrown != 0 && (body.thrown == 0 || kk_is_cancellation_exception(body.thrown) != 0)
            ? childThrown : body.thrown)
    // Cancellation after the final body suspension still makes the scoped
    // BlockingCoroutine complete exceptionally, even if its body returned T.
    if thrown == 0 && job.cancellationSnapshot() {
        thrown = kk_job_get_cancellation_exception(jobRaw)
    }
    if thrown != 0 { _ = job.completeExceptionally(with: thrown) }
    else { _ = job.complete(with: body.result) }
    outThrown?.pointee = thrown
    return thrown == 0 ? body.result : 0
}
