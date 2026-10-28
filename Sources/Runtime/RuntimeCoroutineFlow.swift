import Dispatch
import Foundation

// swiftlint:disable file_length

private let runtimeFlowCollectStackPthreadKey: pthread_key_t = makePthreadKey()

/// Wrapper class so the flow collect stack can be stored as a single AnyObject
/// in the pthread thread-local slot.
private final class RuntimeFlowCollectStackBox {
    var stack: [RuntimeFlowCollectStackEntry] = []
}

private struct RuntimeFlowCollectStackEntry {
    // A worker can be reused while a coroutine is suspended; only the task
    // that pushed this thread-local entry may treat it as the active context.
    let taskKey: RuntimeTaskKey
    let context: RuntimeFlowCollectContext
}

/// Runtime flow op tags must be aligned with the lowering/codegen enums in
/// `CoroutineLoweringPass+Flow.swift` and `FlowLoweringPass.swift`.
private enum RuntimeFlowTag: Int {
    case emit = 0
    case map = 1
    case filter = 2
    case take = 3
    case onEach = 4
    case distinctUntilChanged = 5
    case catchHandler = 6
    case retry = 7
    case retryWhen = 8
    // KUU-1351: tags 9/10 (onErrorReturn/onErrorResume) and 19 (delayEach) are
    // retired — they backed Flow operators that do not exist in
    // kotlinx-coroutines, and the compiler no longer emits them.
    case transform = 11
    case takeWhile = 12
    case dropWhile = 13
    case buffer = 14
    case conflate = 15
    case flowOn = 16
    case debounce = 17
    case sample = 18
    case onCompletion = 20
}

struct RuntimeFlowEvent {
    let value: Int
    let timestamp: UInt64
}

private struct RuntimeFlowOp {
    let kind: RuntimeFlowTag
    let argument: Int
}

/// The template continuation is kept alive only to retain captured values;
/// every collection receives a fresh continuation and channel.
private final class RuntimeChannelProducer {
    let emitterFnPtr: Int
    let functionID: Int
    let templateState: RuntimeContinuationState?

    init(emitterFnPtr: Int, templateContinuation: Int) {
        self.emitterFnPtr = emitterFnPtr
        let state = runtimeContinuationState(from: templateContinuation)
        self.templateState = state
        self.functionID = state.map { Int($0.functionID) } ?? 0

        // The producer flow owns the state through `templateState`; release
        // the opaque continuation's original runtime retain now that it is
        // no longer used as an executable continuation.
        if state != nil, templateContinuation != 0 {
            _ = kk_coroutine_state_exit(templateContinuation, 0)
        }
    }

    func start(collectorJob: RuntimeJobHandle? = nil) -> Int {
        let continuation = kk_coroutine_continuation_new(functionID)
        if let templateState,
           let state = runtimeContinuationState(from: continuation)
        {
            templateState.withRetainedLauncherArgs { args in
                state.replaceLauncherArgs(args.filter { $0.key != 0 })
            }
        }
        return runtimeKxMiniProduceWithCont(
            emitterFnPtr,
            continuation,
            channelCapacity: 64,
            failureDeliveredByCollector: true, collectorJob: collectorJob
        )
    }
}

/// A normal manual close can precede a body failure, so the Job's terminal
/// exception is authoritative even when the channel's first close had no cause.
private func runtimeFlowFinishChannelProducer(
    _ channelHandle: Int,
    stopped: Bool,
    downstreamFailure: Int = 0,
    collectorJob: RuntimeJobHandle? = nil
) -> Int {
    let channelCause = runtimeChannelHandleObject(from: channelHandle)?.closeCauseSnapshot() ?? 0
    guard let scope = runtimeProducerScopeForChannelHandle(channelHandle), let job = scope.job else {
        return downstreamFailure != 0 ? downstreamFailure : channelCause
    }
    let initialCompletion = job.completionSnapshot(handoff: .exception)
    let observedRoot = downstreamFailure != 0 && kk_is_cancellation_exception(downstreamFailure) == 0
        ? downstreamFailure
        : (initialCompletion.exception != 0 && kk_is_cancellation_exception(initialCompletion.exception) == 0
            ? initialCompletion.exception : (!stopped ? channelCause : 0))
    if observedRoot != 0, kk_is_cancellation_exception(observedRoot) == 0 {
        // Fix the collecting Job's first cause before producer finally blocks
        // can fail with a later cleanup exception.
        _ = collectorJob?.cancel(cause: observedRoot)
    }
    let cancelledByCollector = !initialCompletion.completed && !job.isFinalizingProducerChannelSnapshot()
    if cancelledByCollector {
        // Wake blocked sends before joining; plain close would synthesize a
        // ClosedSendChannelException during successful take/takeWhile cleanup.
        _ = kk_channel_cancel(channelHandle)
        scope.cancel(message: "Flow collection finished", cause: 0)
    }
    _ = job.join()
    let producerFailure = job.completionSnapshot(handoff: .exception).exception
    if downstreamFailure != 0, kk_is_cancellation_exception(downstreamFailure) == 0 {
        return downstreamFailure
    }
    if initialCompletion.exception != 0, kk_is_cancellation_exception(initialCompletion.exception) == 0 {
        return initialCompletion.exception
    }
    if !stopped, channelCause != 0, kk_is_cancellation_exception(channelCause) == 0 {
        return channelCause
    }
    if producerFailure != 0, kk_is_cancellation_exception(producerFailure) == 0 {
        return producerFailure
    }
    if downstreamFailure != 0 { return downstreamFailure }
    if !stopped, !cancelledByCollector, producerFailure != 0 { return producerFailure }
    return stopped ? 0 : channelCause
}

/// Buffer/flowOn preserve event order in this runtime. They need not drain
/// the producer before take/takeWhile can observe their stopping condition.
private func runtimeFlowChannelNeedsEventBatch(_ ops: [RuntimeFlowOp]) -> Bool {
    ops.contains { $0.kind == .conflate || $0.kind == .debounce || $0.kind == .sample }
}

private enum RuntimeFlowSource {
    case emitter(fnPtr: Int, templateState: RuntimeContinuationState?)
    case channelProducer(RuntimeChannelProducer)
    case fixed([RuntimeFlowEvent])
    case merge([Int])
    case zip(Int, Int, Int)
    case combine(Int, Int, Int)
    case flatMapConcat(Int, Int)
    case flatMapMerge(Int, Int)
    case flatMapLatest(Int, Int)
}

private enum RuntimeFlowErrorHandlerKind {
    case catchHandler(Int)
    case retry(Int)
    case retryWhen(Int)
}

private struct RuntimeFlowStage {
    let normalOps: [RuntimeFlowOp]
    let handler: RuntimeFlowErrorHandlerKind?
}

private struct RuntimeFlowExecutionResult {
    let values: [Int]
    let failure: Int?
    private let gcRootStorage: RuntimeCoroutineRootStorage

    init(values: [Int], failure: Int?) {
        self.values = values
        self.failure = failure
        let storage = RuntimeCoroutineRootStorage()
        gcRootStorage = storage
        runtimeStorage.withGCLock { state in
            runtimeRecordCoroutineHeapRootsLocked(
                values + (failure.map { [$0] } ?? []), storage: storage, state: &state
            )
        }
    }

    func rootedFailure() -> Int? {
        guard let failure else { return nil }
        return withExtendedLifetime(gcRootStorage) {
            let threadID = ObjectIdentifier(Thread.current)
            runtimeStorage.withGCLock { state in
                runtimeRecordShadowHandoffLocked(failure, threadID: threadID, state: &state)
            }
            return failure
        }
    }
}

final class RuntimeFlowCollectContext {
    // A resumed selector can emit on a worker with no thread-local collect
    // stack. Retain the enclosing builder so collector forwarding still
    // reaches that builder instead of re-entering this collect context.
    let parentEmitContext: RuntimeFlowCollectContext?
    let startedAt = DispatchTime.now().uptimeNanoseconds
    var emittedValues: [Int] = []
    var emittedEvents: [RuntimeFlowEvent] = []
    var cancelled = false
    var failure = 0 {
        didSet { failureRoot = failure == 0 ? nil : RuntimeGCRootedValue(failure) }
    }
    private var failureRoot: RuntimeGCRootedValue?

    func rootedFailure() -> Int {
        failureRoot?.rootedValue() ?? failure
    }
    // A collector may synchronously collect another flow and emit into its
    // enclosing builder. In that case `kk_flow_emit(0, ...)` must skip this
    // context and target the nearest enclosing emitter context, otherwise the
    // collector is invoked recursively until the stack overflows.
    var invokingCollector = false
    var emitHandler: ((Int) -> Int)?
    // Restore the enclosing builder when this context is popped after a nested collect.
    var previousContinuationContext: RuntimeFlowCollectContext?

    init() {
        parentEmitContext = runtimeFlowCurrentEmitContext()
    }
}

/// Immutable operation chain; source emitter is re-executed
/// for every collect to guarantee cold-stream semantics.
private final class RuntimeFlowHandle {
    let source: RuntimeFlowSource
    let opChain: [RuntimeFlowOp]
    let fixedValues: [Int]?

    var emitterFnPtr: Int {
        if case let .emitter(emitterFnPtr, _) = source {
            return emitterFnPtr
        }
        return 0
    }

    var emitterTemplateState: RuntimeContinuationState? {
        if case let .emitter(_, templateState) = source {
            return templateState
        }
        return nil
    }

    init(source: RuntimeFlowSource, opChain: [RuntimeFlowOp] = [], fixedValues: [Int]? = nil) {
        self.source = source
        self.opChain = opChain
        self.fixedValues = fixedValues
    }

    convenience init(
        emitterFnPtr: Int,
        emitterContinuation: Int = 0,
        opChain: [RuntimeFlowOp] = [],
        fixedValues: [Int]? = nil
    ) {
        if let fixedValues {
            let fixedEvents = fixedValues.enumerated().map { index, value in
                RuntimeFlowEvent(value: value, timestamp: UInt64(index))
            }
            self.init(source: .fixed(fixedEvents), opChain: opChain, fixedValues: fixedValues)
        } else {
            let templateState = runtimeContinuationState(from: emitterContinuation)
            self.init(
                source: .emitter(fnPtr: emitterFnPtr, templateState: templateState),
                opChain: opChain,
                fixedValues: nil
            )
            if templateState != nil {
                _ = kk_coroutine_state_exit(emitterContinuation, 0)
            }
        }
    }
}

/// A capturing `flow { }` builder is lowered to a launcher thunk plus a
/// continuation whose launcher-arg slots hold the captured values; the runtime
/// seeds a fresh continuation for each invocation so the emitter receives its
/// captures. Non-capturing builders keep the direct `(outThrown)` ABI.
private func runtimeFlowInvokeEmitter(_ flow: RuntimeFlowHandle, outThrown: inout Int) {
    let callerTaskKey = RuntimeCoroutineScopeTaskKey.currentTaskKey
    let callerJob = RuntimeJobHandle.current
    defer {
        RuntimeCoroutineScopeTaskKey.installKey(callerTaskKey)
        RuntimeJobHandle.current = callerJob
    }
    if let template = flow.emitterTemplateState {
        let continuation = kk_coroutine_continuation_new(Int(template.functionID))
        if let state = runtimeContinuationState(from: continuation) {
            template.withRetainedLauncherArgs { args in
                state.replaceLauncherArgs(args)
            }
            state.scope = RuntimeContinuationState.current?.scope ?? RuntimeCoroutineScope.current
            state.jobHandle = RuntimeContinuationState.current?.jobHandle
        }
        if let context = runtimeFlowCurrentCollectContext() {
            runtimeContinuationState(from: continuation)?.flowCollectContext = context
        }
        _ = runSuspendEntryLoopWithContinuation(
            entryPointRaw: flow.emitterFnPtr,
            continuation: continuation,
            outThrown: &outThrown
        )
    } else {
        // The direct-ABI emitter entry is a suspend wrapper that relays
        // COROUTINE_SUSPENDED through the ambient continuation
        // (kk_coroutine_call_suspend_wrapper). This collect call site is
        // synchronous and has no resumable suspend point, so a relayed
        // sentinel would surface as the emitter's result and end the
        // collection after the builder's first suspension. Detach the
        // ambient continuation for the duration of the call so the wrapper
        // takes its blocking-drive fallback (kk_kxmini_run_blocking_with_cont).
        let ambientState = RuntimeContinuationState.current
        RuntimeContinuationState.current = nil
        defer {
            RuntimeContinuationState.current = ambientState
        }
        let emitter = unsafeBitCast(
            flow.emitterFnPtr,
            to: (@convention(c) (UnsafeMutablePointer<Int>?) -> Int).self
        )
        _ = emitter(&outThrown)
    }
}

private func runtimeRegisterFlowHandle(_ flow: RuntimeFlowHandle) -> Int {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(flow).toOpaque())
    let key = UInt(bitPattern: ptr)
    runtimeStorage.withFlowAndGCLocks { flowState, gcState in
        flowState.flowHandles[key] = flow
        flowState.flowRetainCounts[key] = 1
        gcState.objectPointers.insert(key)
        gcState.borrowedObjectPointers.insert(key)
    }
    return Int(bitPattern: ptr)
}

private func runtimeFlowHandle(from rawValue: Int) -> RuntimeFlowHandle? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let key = UInt(bitPattern: ptr)
    return runtimeStorage.withFlowLock { state in
        state.flowHandles[key] as? RuntimeFlowHandle
    }
}

private func runtimeFlowCollectStackBox() -> RuntimeFlowCollectStackBox {
    if let existing: RuntimeFlowCollectStackBox = pthreadGetValue(runtimeFlowCollectStackPthreadKey) {
        return existing
    }
    let box = RuntimeFlowCollectStackBox()
    pthreadSetValue(runtimeFlowCollectStackPthreadKey, box)
    return box
}

private func runtimeFlowPushCollectContext(_ context: RuntimeFlowCollectContext) {
    if let state = RuntimeContinuationState.current {
        context.previousContinuationContext = state.flowCollectContext
        state.flowCollectContext = context
    }
    runtimeFlowCollectStackBox().stack.append(
        RuntimeFlowCollectStackEntry(
            taskKey: RuntimeCoroutineScopeTaskKey.currentTaskKey,
            context: context
        )
    )
}

private func runtimeFlowPopCollectContext(_ context: RuntimeFlowCollectContext) {
    let box = runtimeFlowCollectStackBox()
    if let index = box.stack.lastIndex(where: { $0.context === context }) {
        box.stack.remove(at: index)
    }
    if let state = RuntimeContinuationState.current, state.flowCollectContext === context {
        state.flowCollectContext = context.previousContinuationContext
    }
}

func runtimeFlowCurrentCollectContext() -> RuntimeFlowCollectContext? {
    if let context = RuntimeContinuationState.current?.flowCollectContext {
        return context
    }
    let taskKey = RuntimeCoroutineScopeTaskKey.currentTaskKey
    return runtimeFlowCollectStackBox().stack.reversed()
        .first(where: { $0.taskKey == taskKey })?.context
}

private func runtimeFlowWithContinuationContext<T>(
    _ context: RuntimeFlowCollectContext,
    _ body: () -> T
) -> T {
    let previous = RuntimeContinuationState.current?.flowCollectContext
    RuntimeContinuationState.current?.flowCollectContext = context
    defer { RuntimeContinuationState.current?.flowCollectContext = previous }
    return body()
}

/// A flow collector can collect a nested source, so the top stack frame may
/// belong to the source being consumed rather than to the builder that is
/// currently executing `emit`.
private func runtimeFlowCurrentEmitContext() -> RuntimeFlowCollectContext? {
    var context = RuntimeContinuationState.current?.flowCollectContext
    if context != nil {
        while let current = context, current.invokingCollector {
            context = current.parentEmitContext
        }
        return context
    }
    let taskKey = RuntimeCoroutineScopeTaskKey.currentTaskKey
    return runtimeFlowCollectStackBox().stack.reversed()
        .first(where: { $0.taskKey == taskKey && !$0.context.invokingCollector })?.context
}

private func runtimeFlowSortEvents(_ events: [RuntimeFlowEvent]) -> [RuntimeFlowEvent] {
    events.enumerated().sorted { lhs, rhs in
        if lhs.element.timestamp == rhs.element.timestamp {
            return lhs.offset < rhs.offset
        }
        return lhs.element.timestamp < rhs.element.timestamp
    }.map(\.element)
}

private func runtimeFlowIsStreamLevelOp(_ kind: RuntimeFlowTag) -> Bool {
    switch kind {
    case .conflate, .flowOn, .debounce, .sample, .buffer:
        return true
    default:
        return false
    }
}

private func runtimeFlowApplyConflate(_ events: [RuntimeFlowEvent]) -> [RuntimeFlowEvent] {
    guard !events.isEmpty else { return [] }
    var conflated: [RuntimeFlowEvent] = []
    conflated.reserveCapacity(events.count)
    var pending = events[0]
    let bucketSizeNs: UInt64 = 1_000_000
    for event in events.dropFirst() {
        if event.timestamp / bucketSizeNs == pending.timestamp / bucketSizeNs {
            pending = event
        } else {
            conflated.append(pending)
            pending = event
        }
    }
    conflated.append(pending)
    return conflated
}

private func runtimeFlowApplyDebounce(_ events: [RuntimeFlowEvent], intervalMs: Int) -> [RuntimeFlowEvent] {
    guard !events.isEmpty else { return [] }
    let intervalNs = UInt64(max(0, intervalMs)) * 1_000_000
    guard intervalNs > 0 else { return events }
    var debounced: [RuntimeFlowEvent] = []
    debounced.reserveCapacity(events.count)
    for index in events.indices {
        let current = events[index]
        let nextTimestamp = index + 1 < events.count ? events[index + 1].timestamp : nil
        if let nextTimestamp, nextTimestamp <= current.timestamp + intervalNs {
            continue
        }
        debounced.append(RuntimeFlowEvent(value: current.value, timestamp: current.timestamp + intervalNs))
    }
    return debounced
}

private func runtimeFlowApplySample(_ events: [RuntimeFlowEvent], intervalMs: Int) -> [RuntimeFlowEvent] {
    guard !events.isEmpty else { return [] }
    let intervalNs = UInt64(max(1, intervalMs)) * 1_000_000
    let finalTimestamp = events.last!.timestamp
    var sampled: [RuntimeFlowEvent] = []
    var tick = intervalNs
    var startIndex = 0
    while tick <= finalTimestamp {
        var latest: RuntimeFlowEvent?
        var index = startIndex
        while index < events.count, events[index].timestamp <= tick {
            latest = events[index]
            index += 1
        }
        if let latest {
            sampled.append(RuntimeFlowEvent(value: latest.value, timestamp: tick))
            startIndex = index
        }
        tick += intervalNs
    }
    if let lastEvent = events.last, sampled.last?.value != lastEvent.value {
        sampled.append(RuntimeFlowEvent(value: lastEvent.value, timestamp: max(lastEvent.timestamp, sampled.last?.timestamp ?? 0)))
    }
    return sampled
}

private func runtimeFlowApplyStreamOps(
    _ events: [RuntimeFlowEvent],
    ops: [RuntimeFlowOp]
) -> [RuntimeFlowEvent]? {
    var currentEvents = runtimeFlowSortEvents(events)
    for op in ops {
        switch op.kind {
        case .conflate:
            currentEvents = runtimeFlowApplyConflate(currentEvents)
        case .debounce:
            currentEvents = runtimeFlowApplyDebounce(currentEvents, intervalMs: runtimeFlowMaybeUnbox(op.argument))
        case .sample:
            currentEvents = runtimeFlowApplySample(currentEvents, intervalMs: runtimeFlowMaybeUnbox(op.argument))
        case .buffer, .flowOn, .emit:
            continue
        default:
            continue
        }
    }
    return runtimeFlowSortEvents(currentEvents)
}

private func runtimeFlowMaybeUnbox(_ value: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: value) else {
        return value
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return value
    }
    if let intBox = tryCast(ptr, to: RuntimeIntBox.self) {
        return intBox.value
    }
    if let boolBox = tryCast(ptr, to: RuntimeBoolBox.self) {
        return boolBox.value ? 1 : 0
    }
    return value
}

private enum FlowOpResult {
    case emit(Int)
    case filtered
    case thrown(Int)
    case done
}

private func runtimeFlowErrorHandler(for op: RuntimeFlowOp) -> RuntimeFlowErrorHandlerKind? {
    switch op.kind {
    case .catchHandler:
        return .catchHandler(op.argument)
    case .retry:
        return .retry(op.argument)
    case .retryWhen:
        return .retryWhen(op.argument)
    default:
        return nil
    }
}

private func runtimeFlowBuildStages(_ ops: [RuntimeFlowOp]) -> [RuntimeFlowStage] {
    var stages: [RuntimeFlowStage] = []
    var pendingNormalOps: [RuntimeFlowOp] = []

    for op in ops {
        if let handler = runtimeFlowErrorHandler(for: op) {
            stages.append(RuntimeFlowStage(normalOps: pendingNormalOps, handler: handler))
            pendingNormalOps.removeAll(keepingCapacity: true)
        } else {
            pendingNormalOps.append(op)
        }
    }

    if !pendingNormalOps.isEmpty || stages.isEmpty {
        stages.append(RuntimeFlowStage(normalOps: pendingNormalOps, handler: nil))
    }

    return stages
}

/// `takeCounters` tracks remaining elements for each take op index and is
/// mutated across successive calls within a single collect invocation.
private func runtimeFlowApplyOpsLazy(
    _ value: Int,
    ops: [RuntimeFlowOp],
    takeCounters: inout [Int: Int],
    lastValues: inout [Int: RuntimeGCRootedValue]
) -> FlowOpResult {
    kk_gc_shadow_push()
    kk_gc_shadow_set(0, value)
    let result = runtimeFlowApplyOpsInFrame(
        value, ops: ops, takeCounters: &takeCounters, lastValues: &lastValues
    )
    switch result {
    case let .emit(value):
        runtimePopNativeGCShadowFrame(value, 0)
    case let .thrown(failure):
        runtimePopNativeGCShadowFrame(0, failure)
    case .filtered, .done:
        runtimePopNativeGCShadowFrame(0, 0)
    }
    return result
}

private func runtimeFlowApplyOpsInFrame(
    _ value: Int,
    ops: [RuntimeFlowOp],
    takeCounters: inout [Int: Int],
    lastValues: inout [Int: RuntimeGCRootedValue]
) -> FlowOpResult {
    var current = value
    for (index, op) in ops.enumerated() {
        switch op.kind {
        case .emit:
            // Emit ops are handled during flow construction; skip.
            continue

        case .map:
            guard op.argument != 0 else {
                return .filtered
            }
            let transform = unsafeBitCast(
                op.argument,
                to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
            )
            var thrown = 0
            let transformed = transform(0, current, &thrown)
            if thrown != 0 {
                return .thrown(thrown)
            }
            current = runtimeFlowMaybeUnbox(transformed)
            kk_gc_shadow_set(0, current)

        case .filter:
            guard op.argument != 0 else {
                return .filtered
            }
            let predicate = unsafeBitCast(
                op.argument,
                to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
            )
            var thrown = 0
            let decision = predicate(0, current, &thrown)
            if thrown != 0 {
                return .thrown(thrown)
            }
            if runtimeFlowMaybeUnbox(decision) == 0 {
                return .filtered
            }

        case .take:
            let limit = max(0, runtimeFlowMaybeUnbox(op.argument))
            let remaining = takeCounters[index, default: limit]
            if remaining <= 0 {
                return .done
            }
            takeCounters[index] = remaining - 1
            // If this was the last allowed element, signal done after delivery.
            if remaining - 1 <= 0 {
                // Still emit the current value but mark context for cancellation
                // after this element is delivered.
            }

        case .onEach:
            guard op.argument != 0 else {
                continue
            }
            let action = unsafeBitCast(
                op.argument,
                to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
            )
            var thrown = 0
            _ = action(0, current, &thrown)
            if thrown != 0 {
                return .thrown(thrown)
            }

        case .distinctUntilChanged:
            if let last = lastValues[index], last.value == current {
                return .filtered
            }
            lastValues[index] = RuntimeGCRootedValue(current)

        case .transform:
            guard op.argument != 0 else {
                return .filtered
            }
            // transform blocks have ABI (value, outThrown) — two args, not three.
            // Push a temporary collect context so that emit() calls inside the
            // transform block are captured rather than leaking to the outer context.
            let transformFn = unsafeBitCast(
                op.argument,
                to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
            )
            let transformCtx = RuntimeFlowCollectContext()
            var transformedValues: [RuntimeGCRootedValue] = []
            transformCtx.emitHandler = { v in
                transformedValues.append(RuntimeGCRootedValue(runtimeFlowMaybeUnbox(v)))
                return v
            }
            runtimeFlowPushCollectContext(transformCtx)
            var thrown = 0
            _ = transformFn(current, &thrown)
            runtimeFlowPopCollectContext(transformCtx)
            if thrown != 0 {
                return .thrown(thrown)
            }
            // Use the first emitted value as `current` for the remainder of
            // the op chain.  Additional values are lost in this single-element
            // path.
            guard let first = transformedValues.first else {
                return .filtered
            }
            current = first.value
            kk_gc_shadow_set(0, current)
            withExtendedLifetime(transformedValues) {}

        case .takeWhile:
            guard op.argument != 0 else {
                return .done
            }
            let predicate = unsafeBitCast(
                op.argument,
                to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
            )
            var thrown = 0
            let decision = predicate(0, current, &thrown)
            if thrown != 0 {
                return .thrown(thrown)
            }
            if runtimeFlowMaybeUnbox(decision) == 0 {
                return .done
            }

        case .dropWhile:
            guard op.argument != 0 else {
                continue
            }
            let predicate = unsafeBitCast(
                op.argument,
                to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
            )
            var thrown = 0
            let decision = predicate(0, current, &thrown)
            if thrown != 0 {
                return .thrown(thrown)
            }
            if runtimeFlowMaybeUnbox(decision) != 0 {
                return .filtered
            }

        case .catchHandler, .retry, .retryWhen:
            continue

        case .onCompletion:
            // onCompletion is a completion-only handler; pass elements through unchanged.
            continue

        case .buffer, .conflate, .flowOn, .debounce, .sample:
            continue
        }
    }
    return .emit(current)
}

/// Called after delivering each element.
private func runtimeFlowTakeExhausted(
    ops: [RuntimeFlowOp],
    takeCounters: [Int: Int]
) -> Bool {
    for (index, op) in ops.enumerated() {
        guard op.kind == .take else { continue }
        if let remaining = takeCounters[index], remaining <= 0 {
            return true
        }
    }
    return false
}

private func runtimeFlowRunNormalStage(
    _ input: RuntimeFlowExecutionResult,
    ops: [RuntimeFlowOp]
) -> RuntimeFlowExecutionResult {
    var takeCounters = runtimeFlowInitTakeCounters(ops)
    var lastValues: [Int: RuntimeGCRootedValue] = [:]
    var emitted: [Int] = []
    var emittedRoots: [RuntimeGCRootedValue] = []
    defer { withExtendedLifetime(emittedRoots) {} }

    if runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters) {
        return RuntimeFlowExecutionResult(values: [], failure: nil)
    }

    for rawValue in input.values {
        let result = runtimeFlowApplyOpsLazy(
            rawValue,
            ops: ops,
            takeCounters: &takeCounters,
            lastValues: &lastValues
        )

        switch result {
        case .emit(let value):
            emittedRoots.append(RuntimeGCRootedValue(value))
            emitted.append(value)
            if runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters) {
                return RuntimeFlowExecutionResult(values: emitted, failure: nil)
            }
        case .filtered:
            continue
        case .thrown(let failure):
            return RuntimeFlowExecutionResult(values: emitted, failure: failure)
        case .done:
            return RuntimeFlowExecutionResult(values: emitted, failure: nil)
        }
    }

    return RuntimeFlowExecutionResult(values: emitted, failure: input.failure)
}

private func runtimeFlowRunSourceStage(
    _ flow: RuntimeFlowHandle,
    ops: [RuntimeFlowOp]
) -> RuntimeFlowExecutionResult {
    var takeCounters = runtimeFlowInitTakeCounters(ops)
    var lastValues: [Int: RuntimeGCRootedValue] = [:]
    var emitted: [Int] = []
    var emittedRoots: [RuntimeGCRootedValue] = []
    var failure: Int?
    var failureRoot: RuntimeGCRootedValue?
    defer { withExtendedLifetime((emittedRoots, failureRoot)) {} }

    if runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters) {
        return RuntimeFlowExecutionResult(values: [], failure: nil)
    }

    let processValue: (Int) -> Int = { rawValue in
        let valueForOperations = runtimeFlowMaybeUnbox(rawValue)
        let result = runtimeFlowApplyOpsLazy(
            valueForOperations,
            ops: ops,
            takeCounters: &takeCounters,
            lastValues: &lastValues
        )

        switch result {
        case .emit(let value):
            emittedRoots.append(RuntimeGCRootedValue(value))
            emitted.append(value)
            return runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters)
                ? runtimeFlowStopSentinel
                : value
        case .filtered:
            return rawValue
        case .thrown(let thrown):
            failureRoot = RuntimeGCRootedValue(thrown)
            failure = thrown
            return runtimeFlowStopSentinel
        case .done:
            return runtimeFlowStopSentinel
        }
    }

    if let fixedValues = flow.fixedValues {
        for value in fixedValues {
            // swiftlint:disable:next for_where
            if processValue(value) == runtimeFlowStopSentinel {
                break
            }
        }
        return RuntimeFlowExecutionResult(values: emitted, failure: failure)
    }

    if case let .channelProducer(producer) = flow.source {
        let channelHandle = producer.start()
        var stopped = false
        var receiveFailure = 0
        if runtimeFlowChannelNeedsEventBatch(ops) {
            var events: [RuntimeFlowEvent] = []
            while true {
                var value = 0
                var thrown = 0
                let status = kk_channel_receive(channelHandle, 0, &value, &thrown)
                guard status == kChannelResultSuccess else {
                    if status == kChannelResultCancelled { receiveFailure = thrown }
                    break
                }
                events.append(RuntimeFlowEvent(
                    value: runtimeFlowMaybeUnbox(value),
                    timestamp: DispatchTime.now().uptimeNanoseconds
                ))
            }
            let processedEvents = runtimeFlowApplyStreamOps(events, ops: ops) ?? events
            for event in processedEvents {
                if processValue(event.value) == runtimeFlowStopSentinel {
                    stopped = true
                    break
                }
            }
        } else {
            while true {
                var value = 0
                var thrown = 0
                let status = kk_channel_receive(channelHandle, 0, &value, &thrown)
                guard status == kChannelResultSuccess else {
                    if status == kChannelResultCancelled { receiveFailure = thrown }
                    break
                }
                if processValue(runtimeFlowMaybeUnbox(value)) == runtimeFlowStopSentinel {
                    stopped = true
                    break
                }
            }
        }
        let terminalFailure = runtimeFlowFinishChannelProducer(
            channelHandle, stopped: stopped, downstreamFailure: failure ?? receiveFailure
        )
        return RuntimeFlowExecutionResult(values: emitted, failure: terminalFailure == 0 ? nil : terminalFailure)
    }

    guard flow.emitterFnPtr != 0 else {
        return RuntimeFlowExecutionResult(values: emitted, failure: failure)
    }

    let context = RuntimeFlowCollectContext()
    context.emitHandler = processValue
    runtimeFlowPushCollectContext(context)

    var outThrown = 0
    runtimeFlowWithContinuationContext(context) {
        runtimeFlowInvokeEmitter(flow, outThrown: &outThrown)
    }
    runtimeFlowPopCollectContext(context)

    if failure == nil, outThrown != 0 {
        failureRoot = RuntimeGCRootedValue(outThrown)
        failure = outThrown
    }
    return RuntimeFlowExecutionResult(values: emitted, failure: failure)
}

private func runtimeFlowHasErrorHandlers(_ ops: [RuntimeFlowOp]) -> Bool {
    ops.contains { runtimeFlowErrorHandler(for: $0) != nil || $0.kind == .onCompletion }
}

/// `failure`: nil on success, non-zero exception pointer on error.
/// Returns the first exception thrown by a handler, or nil if all handlers completed normally.
@discardableResult
private func runtimeFlowFireCompletionHandlers(_ ops: [RuntimeFlowOp], failure: Int?) -> Int? {
    let failureRoot = failure.map(RuntimeGCRootedValue.init)
    var firstThrown: RuntimeGCRootedValue?
    defer { withExtendedLifetime(failureRoot) {} }
    for op in ops where op.kind == .onCompletion {
        guard op.argument != 0 else { continue }
        let handler = unsafeBitCast(
            op.argument,
            to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        var thrown = 0
        _ = handler(0, failure ?? 0, &thrown)
        if thrown != 0 && firstThrown == nil {
            firstThrown = RuntimeGCRootedValue(thrown)
        }
    }
    return firstThrown?.rootedValue()
}

private func runtimeFlowInvokeCatchHandler(_ handlerFnPtr: Int, failure: Int) -> Int? {
    guard handlerFnPtr != 0 else {
        return nil
    }
    let handler = unsafeBitCast(
        handlerFnPtr,
        to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    _ = handler(0, failure, &thrown)
    return thrown == 0 ? nil : thrown
}

private func runtimeFlowInvokeRetryWhenPredicate(
    _ predicateFnPtr: Int,
    failure: Int,
    attempt: Int
) -> (shouldRetry: Bool, failure: Int?) {
    guard predicateFnPtr != 0 else {
        return (false, failure)
    }
    let predicate = unsafeBitCast(
        predicateFnPtr,
        to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown = 0
    let decision = predicate(0, failure, attempt, &thrown)
    if thrown != 0 {
        return (false, thrown)
    }
    return (runtimeFlowMaybeUnbox(decision) != 0, nil)
}

private func runtimeFlowApplyErrorHandler(
    _ current: RuntimeFlowExecutionResult,
    handler: RuntimeFlowErrorHandlerKind,
    attemptProvider: () -> RuntimeFlowExecutionResult,
    stageOps: [RuntimeFlowOp]
) -> RuntimeFlowExecutionResult {
    guard let initialFailure = current.failure else {
        return current
    }

    switch handler {
    case .catchHandler(let handlerFnPtr):
        return RuntimeFlowExecutionResult(
            values: current.values,
            failure: runtimeFlowInvokeCatchHandler(handlerFnPtr, failure: initialFailure)
        )

    case .retry(let retryCountRaw):
        let retryCount = max(0, runtimeFlowMaybeUnbox(retryCountRaw))
        var aggregate = current.values
        var failure: Int? = initialFailure
        var attempt = 0

        while failure != nil, attempt < retryCount {
            let retried = runtimeFlowRunNormalStage(attemptProvider(), ops: stageOps)
            aggregate.append(contentsOf: retried.values)
            failure = retried.failure
            attempt += 1
        }

        return RuntimeFlowExecutionResult(values: aggregate, failure: failure)

    case .retryWhen(let predicateFnPtr):
        var aggregate = current.values
        var failure: Int? = initialFailure
        var attempt = 0

        while let currentFailure = failure {
            let decision = runtimeFlowInvokeRetryWhenPredicate(
                predicateFnPtr,
                failure: currentFailure,
                attempt: attempt
            )
            if let predicateFailure = decision.failure {
                return RuntimeFlowExecutionResult(values: aggregate, failure: predicateFailure)
            }
            guard decision.shouldRetry else {
                return RuntimeFlowExecutionResult(values: aggregate, failure: currentFailure)
            }

            let retried = runtimeFlowRunNormalStage(attemptProvider(), ops: stageOps)
            aggregate.append(contentsOf: retried.values)
            failure = retried.failure
            attempt += 1
        }

        return RuntimeFlowExecutionResult(values: aggregate, failure: nil)
    }
}

private func runtimeFlowRunAdvancedSource(
    _ flow: RuntimeFlowHandle,
    ops: [RuntimeFlowOp]
) -> RuntimeFlowExecutionResult? {
    switch flow.source {
    case .flatMapConcat(let srcHandle, let mapperFnPtr):
        return runtimeFlowEvaluateFlatMapConcat(sourceHandle: srcHandle, mapperFnPtr: mapperFnPtr, ops: ops)
    case .flatMapMerge(let srcHandle, let mapperFnPtr):
        return runtimeFlowEvaluateFlatMapMerge(sourceHandle: srcHandle, mapperFnPtr: mapperFnPtr, ops: ops)
    case .flatMapLatest(let srcHandle, let mapperFnPtr):
        return runtimeFlowEvaluateFlatMapLatest(sourceHandle: srcHandle, mapperFnPtr: mapperFnPtr, ops: ops)
    case .merge(let handles):
        return runtimeFlowEvaluateMerge(flowHandles: handles, ops: ops)
    case .zip(let left, let right, let combiner):
        return runtimeFlowEvaluateZip(leftHandle: left, rightHandle: right, combinerFnPtr: combiner, ops: ops)
    case .combine(let left, let right, let combiner):
        return runtimeFlowEvaluateCombine(leftHandle: left, rightHandle: right, combinerFnPtr: combiner, ops: ops)
    default:
        return nil
    }
}

private func runtimeFlowExecuteStages(
    flow: RuntimeFlowHandle,
    stages: [RuntimeFlowStage],
) -> RuntimeFlowExecutionResult {
    var current = RuntimeFlowExecutionResult(values: [], failure: nil)
    var stageAttemptProvider: () -> RuntimeFlowExecutionResult = { RuntimeFlowExecutionResult(values: [], failure: nil) }

    for (index, stage) in stages.enumerated() {
        if index == 0 {
            if let advancedResult = runtimeFlowRunAdvancedSource(flow, ops: stage.normalOps) {
                current = advancedResult
            } else {
                current = runtimeFlowRunSourceStage(flow, ops: stage.normalOps)
            }
            let capturedFlow = flow
            let capturedOps = stage.normalOps
            stageAttemptProvider = {
                if let advanced = runtimeFlowRunAdvancedSource(capturedFlow, ops: capturedOps) {
                    return advanced
                }
                return runtimeFlowRunSourceStage(capturedFlow, ops: capturedOps)
            }
        } else {
            current = runtimeFlowRunNormalStage(current, ops: stage.normalOps)
        }
        if let handler = stage.handler {
            current = runtimeFlowApplyErrorHandler(
                current,
                handler: handler,
                attemptProvider: stageAttemptProvider,
                stageOps: stage.normalOps
            )
        }
        let snapshot = current
        if index != 0 {
            stageAttemptProvider = { snapshot }
        }
    }

    return current
}

private func runtimeFlowEvaluate(flow: RuntimeFlowHandle) -> RuntimeFlowExecutionResult {
    runtimeFlowExecuteStages(flow: flow, stages: runtimeFlowBuildStages(flow.opChain))
}

/// Simple `.emitter` and `.fixed` sources can use the faster streaming path;
/// advanced sources must go through runtimeFlowEvaluate.
private func runtimeFlowHasAdvancedSource(_ flow: RuntimeFlowHandle) -> Bool {
    switch flow.source {
    case .emitter, .channelProducer, .fixed:
        return false
    default:
        return true
    }
}

private enum RuntimeChannelFlowDelivery {
    case more
    case stopped(Int)
    case failed(Int)

    var completionCause: Int {
        switch self {
        case .more: return 0
        case .stopped(let cause), .failed(let cause): return cause
        }
    }

    var failure: Int {
        if case let .failed(failure) = self { return failure }
        return 0
    }
}

/// Keep channel-backed error handlers at their operator boundary: deliver
/// values before handling an upstream exception, and never catch a failure
/// raised by an operator or collector downstream of that boundary.
private func runtimeFlowCollectChannelProducer(
    _ producer: RuntimeChannelProducer,
    ops: [RuntimeFlowOp],
    collectorFnPtr: Int,
    collectorEnvPtr: Int,
    continuation: Int
) -> Int {
    let collectorContext = RuntimeFlowCollectContext()

    func isCollectorCancellation(_ failure: Int) -> Bool {
        let job = runtimeContinuationState(from: continuation)?.jobHandle
            ?? RuntimeJobHandle.current ?? RuntimeCoroutineScope.current?.job
        guard let job, job.cancellationSnapshot(), kk_is_cancellation_exception(failure) != 0 else { return false }
        return failure == job.cancellationCauseSnapshot()
            || (runtimeThrowableBox(from: failure) as? RuntimeCancellationBox)?.cancellationJob === job
    }

    func invokeEmittingHandler(
        emit: @escaping (Int) -> RuntimeChannelFlowDelivery,
        failure: Int = 0,
        body: () -> Int?
    ) -> RuntimeChannelFlowDelivery {
        let context = RuntimeFlowCollectContext()
        var delivery = RuntimeChannelFlowDelivery.more
        context.emitHandler = { [weak context] value in
            guard let context else { return runtimeFlowStopSentinel }
            // While handing a value downstream, emit() inside that collector
            // belongs to its enclosing builder, not to this handler context.
            let wasInvokingCollector = context.invokingCollector
            context.invokingCollector = true
            defer { context.invokingCollector = wasInvokingCollector }
            delivery = failure == 0 ? emit(value) : .failed(failure)
            context.failure = delivery.completionCause
            switch delivery {
            case .more: return value
            case .stopped, .failed: return runtimeFlowStopSentinel
            }
        }
        runtimeFlowPushCollectContext(context)
        let thrown = runtimeFlowWithContinuationContext(context) { body() }
        let thrownRoot = thrown.flatMap { $0 == 0 ? nil : RuntimeGCRootedValue($0) }
        runtimeFlowPopCollectContext(context)
        _ = context.rootedFailure()
        if let thrown, thrown != 0 {
            if case .stopped = delivery, thrown == delivery.completionCause { return delivery }
            return .failed(thrownRoot?.rootedValue() ?? thrown)
        }
        return delivery
    }

    func collect(_ count: Int, emit: @escaping (Int) -> RuntimeChannelFlowDelivery) -> RuntimeChannelFlowDelivery {
        if count == 0 {
            // channelFlow collects inside coroutineScope: producer failure may
            // interrupt a suspended collector, while catch/retry execute after
            // this Job has settled and the caller's Job has been restored.
            let previousScope = RuntimeCoroutineScope.current
            let previousJob = RuntimeJobHandle.current
            let currentState = RuntimeContinuationState.current
            let previousStateScope = currentState?.scope
            let previousStateJob = currentState?.jobHandle
            let collectionScope = RuntimeCoroutineScope(context: previousScope?.context ?? RuntimeCoroutineContext())
            let collectionJob = collectionScope.installJob(defaultCancellationMessage: "ScopeCoroutine was cancelled")
            RuntimeCoroutineScope.current = collectionScope
            RuntimeJobHandle.current = collectionJob
            currentState?.scope = collectionScope
            currentState?.jobHandle = collectionJob
            func callerCancellation(_ failure: Int) -> Int {
                let caller = previousStateJob ?? previousJob ?? previousScope?.job
                guard let caller, caller.cancellationSnapshot(), kk_is_cancellation_exception(failure) != 0,
                      failure == collectionJob.cancellationCauseSnapshot()
                        || (runtimeThrowableBox(from: failure) as? RuntimeCancellationBox)?.cancellationJob === collectionJob
                else { return failure }
                return runtimeAllocateCancellationException(
                    message: caller.cancellationMessageSnapshot(forSuspensionPoint: true),
                    cause: caller.cancellationCauseSnapshot(), cancellationJob: caller
                )
            }
            defer {
                previousJob?.detachChild(collectionJob.identityHandle)
                currentState?.scope = previousStateScope
                currentState?.jobHandle = previousStateJob
                RuntimeCoroutineScope.current = previousScope
                RuntimeJobHandle.current = previousJob
            }
            func collectValues() -> RuntimeChannelFlowDelivery {
                let channel = producer.start(collectorJob: collectionJob)
                while true {
                    var value = 0
                    var thrown = 0
                    let status = kk_channel_receive(channel, 0, &value, &thrown)
                    if status != kChannelResultSuccess {
                        let failure = runtimeFlowFinishChannelProducer(
                            channel, stopped: false,
                            downstreamFailure: status == kChannelResultCancelled ? thrown : 0, collectorJob: collectionJob
                        )
                        return failure == 0 ? .more : .failed(failure)
                    }
                    let delivery = emit(runtimeFlowMaybeUnbox(value))
                    switch delivery {
                    case .more: continue
                    case .stopped, .failed:
                        let failure = runtimeFlowFinishChannelProducer(
                            channel, stopped: true, downstreamFailure: delivery.failure, collectorJob: collectionJob
                        )
                        return failure == 0 ? delivery : .failed(failure)
                    }
                }
            }
            let delivery = collectValues()
            if delivery.completionCause != 0 {
                collectionScope.recordBodyFailure(delivery.failure)
                collectionScope.cancel(message: "Flow collection finished", cause: delivery.completionCause)
            }
            _ = collectionScope.waitForChildren(releaseOriginalHandles: false)
            // CoroutineScope(currentCoroutineContext()) owns another Scope's
            // child list but registers its launches with this same Job. Drain
            // the Job hierarchy too, including descendants added while joining.
            var joinedChildren: Set<Int> = []
            while true {
                let children = collectionJob.registeredChildrenSnapshot().filter { !joinedChildren.contains($0) }
                if children.isEmpty { break }
                for child in children {
                    joinedChildren.insert(child)
                    guard let childJob = runtimeJobHandle(from: child) ?? runtimeAsyncTask(from: child)?.completionJob else { continue }
                    _ = childJob.join()
                    let failure = childJob.completionSnapshot(handoff: .exception).exception
                    if failure != 0, kk_is_cancellation_exception(failure) == 0 {
                        collectionScope.recordBodyFailure(failure)
                        collectionScope.cancel(message: "Flow child failed", cause: failure)
                    }
                }
            }
            let childFailure = collectionScope.childFailureSnapshot()
            var finalFailure = childFailure != 0 ? childFailure : delivery.failure
            if finalFailure == 0, collectionJob.cancellationSnapshot() {
                let caller = previousStateJob ?? previousJob ?? previousScope?.job
                let ownStop: Bool
                if case .stopped = delivery {
                    ownStop = delivery.completionCause == collectionJob.cancellationCauseSnapshot()
                        && caller?.cancellationSnapshot() != true
                } else { ownStop = false }
                if !ownStop { finalFailure = collectionJob.cancellationCauseSnapshot() }
            }
            if finalFailure != 0 { _ = collectionJob.completeExceptionally(with: finalFailure) }
            else { _ = collectionJob.complete(with: 0) }
            // Completion and parent cancellation race under the Job lock. Use
            // the state that actually won, rather than a pre-completion guess.
            let settledCause = collectionJob.completionSnapshot(handoff: .exception).exception
            if settledCause != 0 {
                let caller = previousStateJob ?? previousJob ?? previousScope?.job
                if case .stopped = delivery, settledCause == delivery.completionCause,
                   caller?.cancellationSnapshot() != true { return delivery }
                return .failed(callerCancellation(settledCause))
            }
            return delivery
        }
        let op = ops[count - 1]
        if let handler = runtimeFlowErrorHandler(for: op) {
            var downstreamFailure = 0
            var downstreamStopped = false
            let checkedEmit: (Int) -> RuntimeChannelFlowDelivery = { value in
                let delivery = emit(value)
                downstreamFailure = delivery.failure
                if case .stopped = delivery { downstreamStopped = true }
                return delivery
            }
            var delivery = collect(count - 1, emit: checkedEmit)
            var attempt = 0
            while case let .failed(failure) = delivery {
                guard downstreamFailure == 0, !downstreamStopped, !isCollectorCancellation(failure) else { return delivery }
                switch handler {
                case .catchHandler(let fn):
                    return invokeEmittingHandler(emit: checkedEmit) {
                        runtimeFlowInvokeCatchHandler(fn, failure: failure)
                    }
                case .retry(let retries):
                    guard attempt < max(0, runtimeFlowMaybeUnbox(retries)) else { return delivery }
                case .retryWhen(let predicate):
                    var shouldRetry = false
                    let predicateDelivery = invokeEmittingHandler(emit: checkedEmit) {
                        let decision = runtimeFlowInvokeRetryWhenPredicate(predicate, failure: failure, attempt: attempt)
                        shouldRetry = decision.shouldRetry
                        return decision.failure
                    }
                    switch predicateDelivery {
                    case .failed, .stopped: return predicateDelivery
                    case .more: break
                    }
                    guard shouldRetry else { return delivery }
                }
                attempt += 1
                delivery = collect(count - 1, emit: checkedEmit)
            }
            return delivery
        }
        if op.kind == .onCompletion {
            let delivery = collect(count - 1, emit: emit)
            let completion = invokeEmittingHandler(emit: emit, failure: delivery.completionCause) {
                runtimeFlowFireCompletionHandlers([op], failure: delivery.completionCause == 0 ? nil : delivery.completionCause)
            }
            return completion.failure != 0 ? completion : delivery
        }
        var takeCounters = runtimeFlowInitTakeCounters([op])
        var lastValues: [Int: RuntimeGCRootedValue] = [:]
        if runtimeFlowTakeExhausted(ops: [op], takeCounters: takeCounters) { return .more }
        var ownStopCause = 0
        func stopHere() -> RuntimeChannelFlowDelivery {
            if ownStopCause == 0 {
                ownStopCause = runtimeAllocateCancellationException(message: "Flow was aborted, no more elements needed")
            }
            return .stopped(ownStopCause)
        }
        let delivery = collect(count - 1) { value in
            if op.kind == .transform {
                guard op.argument != 0 else { return .more }
                return invokeEmittingHandler(emit: emit) {
                    let transform = unsafeBitCast(op.argument, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
                    var thrown = 0
                    _ = transform(value, &thrown)
                    return thrown == 0 ? nil : thrown
                }
            }
            switch runtimeFlowApplyOpsLazy(value, ops: [op], takeCounters: &takeCounters, lastValues: &lastValues) {
            case .emit(let value):
                let delivery = emit(value)
                if case .more = delivery, runtimeFlowTakeExhausted(ops: [op], takeCounters: takeCounters) {
                    return stopHere()
                }
                return delivery
            case .filtered: return .more
            case .done: return stopHere()
            case .thrown(let failure): return .failed(failure)
            }
        }
        if ownStopCause != 0, delivery.completionCause == ownStopCause { return .more }
        return delivery
    }

    let delivery = collect(ops.count) { value in
        runtimeFlowDeliverValue(
            value, collectorFnPtr: collectorFnPtr, collectorEnvPtr: collectorEnvPtr,
            continuation: continuation, owningContext: collectorContext
        ) ? .more : .failed(collectorContext.rootedFailure())
    }
    return delivery.failure
}

private func runtimeFlowCollectLazy(
    _ flow: RuntimeFlowHandle,
    collectorFnPtr: Int,
    collectorEnvPtr: Int,
    continuation: Int
) -> Int {
    kk_gc_shadow_push()
    kk_gc_shadow_set(0, Int(bitPattern: Unmanaged.passUnretained(flow).toOpaque()))
    kk_gc_shadow_set(1, collectorEnvPtr)
    kk_gc_shadow_set(2, continuation)
    let failure = runtimeFlowCollectInFrame(
        flow, collectorFnPtr: collectorFnPtr, collectorEnvPtr: collectorEnvPtr,
        continuation: continuation
    )
    runtimePopNativeGCShadowFrame(failure, failure)
    return failure
}

private func runtimeFlowCollectInFrame(
    _ flow: RuntimeFlowHandle,
    collectorFnPtr: Int,
    collectorEnvPtr: Int,
    continuation: Int
) -> Int {
    let hasOnCompletion = flow.opChain.contains { $0.kind == .onCompletion }
    if case let .channelProducer(producer) = flow.source,
       !runtimeFlowChannelNeedsEventBatch(flow.opChain)
    {
        return runtimeFlowCollectChannelProducer(
            producer, ops: flow.opChain, collectorFnPtr: collectorFnPtr,
            collectorEnvPtr: collectorEnvPtr, continuation: continuation
        )
    }
    // Advanced sources (flatMapConcat, flatMapMerge, merge, zip, combine, etc.)
    // are not handled by runtimeFlowCollectStreaming which only processes
    // .emitter and .fixed sources.  Route them through runtimeFlowEvaluate so
    // that they produce values correctly.
    if !runtimeFlowHasErrorHandlers(flow.opChain) && !runtimeFlowHasAdvancedSource(flow) {
        let retVal = runtimeFlowCollectStreaming(
            flow,
            collectorFnPtr: collectorFnPtr,
            collectorEnvPtr: collectorEnvPtr,
            continuation: continuation
        )
        if hasOnCompletion {
            let streamingFailure: Int? = retVal != 0 ? retVal : nil
            if let handlerException = runtimeFlowFireCompletionHandlers(flow.opChain, failure: streamingFailure) {
                return handlerException
            }
        }
        return retVal
    }
    let result = runtimeFlowEvaluate(flow: flow)
    let context = RuntimeFlowCollectContext()
    for value in result.values {
        let delivered = runtimeFlowDeliverValue(
            value,
            collectorFnPtr: collectorFnPtr,
            collectorEnvPtr: collectorEnvPtr,
            continuation: continuation,
            owningContext: context
        )
        if !delivered {
            if hasOnCompletion {
                if let handlerException = runtimeFlowFireCompletionHandlers(flow.opChain, failure: result.failure) {
                    return handlerException
                }
            }
            return context.rootedFailure()
        }
    }
    if hasOnCompletion {
        if let handlerException = runtimeFlowFireCompletionHandlers(flow.opChain, failure: result.failure) {
            return handlerException
        }
    }
    return result.rootedFailure() ?? 0
}

private func runtimeFlowCollectStreaming(
    _ flow: RuntimeFlowHandle,
    collectorFnPtr: Int,
    collectorEnvPtr: Int,
    continuation: Int
) -> Int {
    let ops = flow.opChain
    let hasStreamLevelOps = ops.contains(where: { runtimeFlowIsStreamLevelOp($0.kind) })
    var takeCounters = runtimeFlowInitTakeCounters(ops)
    var lastValues: [Int: RuntimeGCRootedValue] = [:]
    let context = RuntimeFlowCollectContext()

    if runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters) {
        return 0
    }

    let deliverValue: (Int) -> Bool = { value in
        let delivered = runtimeFlowDeliverValue(
            value,
            collectorFnPtr: collectorFnPtr,
            collectorEnvPtr: collectorEnvPtr,
            continuation: continuation,
            owningContext: context
        )
        return delivered && !runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters)
    }

    if let fixedValues = flow.fixedValues {
        if hasStreamLevelOps {
            let events = fixedValues.enumerated().map { index, value in
                RuntimeFlowEvent(value: value, timestamp: UInt64(index))
            }
            let processedEvents = runtimeFlowApplyStreamOps(events, ops: ops) ?? events
            for event in processedEvents {
                let result = runtimeFlowApplyOpsLazy(
                    event.value,
                    ops: ops,
                    takeCounters: &takeCounters,
                    lastValues: &lastValues
                )
                switch result {
                case .emit(let value):
                    if !deliverValue(value) {
                        return context.rootedFailure()
                    }
                case .filtered:
                    continue
                case let .thrown(failure):
                    return failure
                case .done:
                    return 0
                }
            }
            return 0
        }

        for value in fixedValues {
            let result = runtimeFlowApplyOpsLazy(
                value,
                ops: ops,
                takeCounters: &takeCounters,
                lastValues: &lastValues
            )

            switch result {
            case .emit(let value):
                if !deliverValue(value) {
                    return context.rootedFailure()
                }
            case .filtered:
                continue
            case let .thrown(failure):
                return failure
            case .done:
                return 0
            }
        }
        return 0
    }

    if case let .channelProducer(producer) = flow.source {
        let channelHandle = producer.start()
        let finish: (Bool, Int) -> Int = { stopped, failure in
            runtimeFlowFinishChannelProducer(channelHandle, stopped: stopped, downstreamFailure: failure)
        }
        var receiveFailure = 0
        if runtimeFlowChannelNeedsEventBatch(ops) {
            var events: [RuntimeFlowEvent] = []
            while true {
                var value = 0
                var thrown = 0
                let status = kk_channel_receive(channelHandle, 0, &value, &thrown)
                guard status == kChannelResultSuccess else {
                    if status == kChannelResultCancelled { receiveFailure = thrown }
                    break
                }
                events.append(RuntimeFlowEvent(
                    value: runtimeFlowMaybeUnbox(value),
                    timestamp: DispatchTime.now().uptimeNanoseconds
                ))
            }
            let processedEvents = runtimeFlowApplyStreamOps(events, ops: ops) ?? events
            for event in processedEvents {
                let result = runtimeFlowApplyOpsLazy(
                    event.value,
                    ops: ops,
                    takeCounters: &takeCounters,
                    lastValues: &lastValues
                )
                switch result {
                case .emit(let value):
                    if !deliverValue(value) { return finish(true, context.rootedFailure()) }
                case .filtered:
                    continue
                case let .thrown(failure):
                    return finish(true, failure)
                case .done:
                    return finish(true, 0)
                }
            }
            return finish(false, receiveFailure)
        }

        while true {
            var value = 0
            var thrown = 0
            let status = kk_channel_receive(channelHandle, 0, &value, &thrown)
            guard status == kChannelResultSuccess else {
                if status == kChannelResultCancelled { receiveFailure = thrown }
                break
            }
            switch runtimeFlowApplyOpsLazy(
                runtimeFlowMaybeUnbox(value),
                ops: ops,
                takeCounters: &takeCounters,
                lastValues: &lastValues
            ) {
            case .emit(let value):
                if !deliverValue(value) { return finish(true, context.rootedFailure()) }
            case .filtered:
                continue
            case let .thrown(failure):
                return finish(true, failure)
            case .done:
                return finish(true, 0)
            }
        }
        return finish(false, receiveFailure)
    }

    guard flow.emitterFnPtr != 0 else {
        return 0
    }

    if hasStreamLevelOps {
        runtimeFlowPushCollectContext(context)

        var outThrown = 0
        runtimeFlowWithContinuationContext(context) {
            runtimeFlowInvokeEmitter(flow, outThrown: &outThrown)
        }
        runtimeFlowPopCollectContext(context)

        if outThrown == 0 {
            let processedEvents = runtimeFlowApplyStreamOps(context.emittedEvents, ops: ops) ?? context.emittedEvents
            for event in processedEvents {
                let result = runtimeFlowApplyOpsLazy(
                    event.value,
                    ops: ops,
                    takeCounters: &takeCounters,
                    lastValues: &lastValues
                )
                switch result {
                case .emit(let value):
                    if !deliverValue(value) {
                        return context.rootedFailure()
                    }
                case .filtered:
                    continue
                case let .thrown(failure):
                    return failure
                case .done:
                    return 0
                }
            }
        }
        return outThrown
    }

    // If the op chain contains a transform op, use a specialised path that
    // correctly fans out the 1-to-many transform semantics.
    let transformIndex = ops.firstIndex(where: { $0.kind == .transform })
    let preOps = transformIndex.map { Array(ops[..<$0]) } ?? []
    let postOps = transformIndex.map { Array(ops[($0 + 1)...]) } ?? []
    var preTakeCounters = runtimeFlowInitTakeCounters(preOps)
    var postTakeCounters = runtimeFlowInitTakeCounters(postOps)
    var preLastValues: [Int: RuntimeGCRootedValue] = [:]

    context.emitHandler = { emittedValue in
        let rawValue = runtimeFlowMaybeUnbox(emittedValue)
        if let transformIdx = transformIndex {
            let transformFnPtr = ops[transformIdx].argument

            let preResult = runtimeFlowApplyOpsLazy(
                rawValue, ops: preOps,
                takeCounters: &preTakeCounters,
                lastValues: &preLastValues
            )
            guard case .emit(let preValue) = preResult else {
                switch preResult {
                case .filtered:
                    return runtimeFlowTakeExhausted(ops: preOps, takeCounters: preTakeCounters)
                        ? runtimeFlowStopSentinel : rawValue
                case .thrown(let e):
                    context.failure = e
                    return runtimeFlowStopSentinel
                case .done: return runtimeFlowStopSentinel
                case .emit: break
                }
                return rawValue
            }

            // Call the transform block with the correct 2-arg ABI and collect
            // all values it emits.
            guard transformFnPtr != 0 else { return rawValue }
            let transformFn = unsafeBitCast(
                transformFnPtr,
                to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
            )
            var transformedValues: [RuntimeGCRootedValue] = []
            let transformCtx = RuntimeFlowCollectContext()
            transformCtx.emitHandler = { v in
                transformedValues.append(RuntimeGCRootedValue(runtimeFlowMaybeUnbox(v)))
                return v
            }
            runtimeFlowPushCollectContext(transformCtx)
            var thrown = 0
            _ = transformFn(preValue, &thrown)
            runtimeFlowPopCollectContext(transformCtx)

            if thrown != 0 {
                context.failure = thrown
                return runtimeFlowStopSentinel
            }

            var stop = false
            for tv in transformedValues {
                let result = runtimeFlowApplyOpsLazy(
                    tv.value, ops: postOps,
                    takeCounters: &postTakeCounters,
                    lastValues: &lastValues
                )
                switch result {
                case .emit(let value):
                    let delivered = runtimeFlowDeliverValue(
                        value,
                        collectorFnPtr: collectorFnPtr,
                        collectorEnvPtr: collectorEnvPtr,
                        continuation: continuation,
                        owningContext: context
                    )
                    if !delivered || runtimeFlowTakeExhausted(ops: postOps, takeCounters: postTakeCounters) {
                        stop = true
                    }
                case .filtered:
                    stop = runtimeFlowTakeExhausted(ops: postOps, takeCounters: postTakeCounters)
                case let .thrown(failure):
                    context.failure = failure
                    stop = true
                case .done:
                    stop = true
                }
                if stop { break }
            }
            if runtimeFlowTakeExhausted(ops: preOps, takeCounters: preTakeCounters) { stop = true }
            withExtendedLifetime(transformedValues) {}
            return stop ? runtimeFlowStopSentinel : rawValue
        }

        let result = runtimeFlowApplyOpsLazy(
            rawValue,
            ops: ops,
            takeCounters: &takeCounters,
            lastValues: &lastValues
        )

        switch result {
        case .emit(let value):
            let deliveredValue = ops.contains(where: { $0.kind == .map }) ? value : emittedValue
            let delivered = runtimeFlowDeliverValue(
                deliveredValue,
                collectorFnPtr: collectorFnPtr,
                collectorEnvPtr: collectorEnvPtr,
                continuation: continuation,
                owningContext: context
            )
            if !delivered || runtimeFlowTakeExhausted(ops: ops, takeCounters: takeCounters) {
                return runtimeFlowStopSentinel
            }
            return deliveredValue
        case .filtered:
            return rawValue
        case let .thrown(failure):
            context.failure = failure
            return runtimeFlowStopSentinel
        case .done:
            return runtimeFlowStopSentinel
        }
    }
    runtimeFlowPushCollectContext(context)

    var outThrown = 0
    runtimeFlowWithContinuationContext(context) {
        runtimeFlowInvokeEmitter(flow, outThrown: &outThrown)
    }
    runtimeFlowPopCollectContext(context)
    let failure = outThrown != 0 ? outThrown : context.rootedFailure()
    context.emitHandler = nil
    return failure
}

/// Runs one suspend collector invocation as a child coroutine. The initial
/// burst runs inline, while any later resume is delivered asynchronously.
private func runtimeFlowLatestCollectorBody(
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else { return 0 }
    return state.withRetainedLauncherArgs { args in
        let collector = unsafeBitCast(
            Int(args[0] ?? 0),
            to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        return collector(Int(args[1] ?? 0), Int(args[2] ?? 0), continuation, outThrown)
    }
}

private final class RuntimeFlowLatestCollectState: @unchecked Sendable {
    private let lock = NSLock()
    private let collectorFnPtr: Int
    private let collectorEnvPtr: Int
    private let continuation: Int
    private let collectionScope: RuntimeCoroutineScope
    private let collectionJob: RuntimeJobHandle
    private var activeJob: RuntimeJobHandle?
    private var failure = 0

    init(
        collectorFnPtr: Int,
        collectorEnvPtr: Int,
        continuation: Int,
        collectionScope: RuntimeCoroutineScope,
        collectionJob: RuntimeJobHandle
    ) {
        self.collectorFnPtr = collectorFnPtr
        self.collectorEnvPtr = collectorEnvPtr
        self.continuation = continuation
        self.collectionScope = collectionScope
        self.collectionJob = collectionJob
    }

    private func failureSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return failure
    }

    private func takeActiveJob() -> RuntimeJobHandle? {
        lock.lock()
        let job = activeJob
        activeJob = nil
        lock.unlock()
        return job
    }

    private func recordFailure(_ exception: Int) {
        guard exception != 0, kk_is_cancellation_exception(exception) == 0 else { return }
        lock.lock()
        if failure == 0 { failure = exception }
        lock.unlock()
    }

    func receive(_ value: Int) -> Int {
        if continuation == 0 {
            let context = RuntimeFlowCollectContext()
            return runtimeFlowDeliverValue(
                value,
                collectorFnPtr: collectorFnPtr,
                collectorEnvPtr: collectorEnvPtr,
                continuation: 0,
                owningContext: context
            ) ? 0 : context.rootedFailure()
        }

        if let previous = takeActiveJob() {
            if !previous.completedSnapshot() {
                _ = previous.cancel(message: "Latest value was received")
            }
            _ = previous.join()
        }
        let currentFailure = failureSnapshot()
        if currentFailure != 0 { return currentFailure }
        if collectionJob.cancellationSnapshot() {
            return collectionJob.cancellationCauseSnapshot()
        }

        let actionScope = RuntimeCoroutineScope(context: collectionScope.context)
        actionScope.blockingScheduler = collectionScope.blockingScheduler
        let actionJob = actionScope.installJob(defaultCancellationMessage: "Latest collector was cancelled")
        actionJob.debugName = "FlowLatestCollector"
        actionJob.propagatesFailureToParent = false
        let actionHandle = actionJob.identityHandle
        collectionJob.registerChild(actionHandle)
        let actionContinuationRaw = kk_coroutine_continuation_new(continuation)
        guard let actionContinuation = runtimeContinuationState(from: actionContinuationRaw) else {
            _ = actionJob.complete(with: 0)
            _ = runtimeReleaseObject(actionHandle)
            return 0
        }
        actionJob.continuationState = actionContinuation
        actionContinuation.replaceLauncherArgs([
            0: Int64(collectorFnPtr),
            1: Int64(collectorEnvPtr),
            2: Int64(value),
        ])
        actionContinuation.scope = actionScope
        actionContinuation.jobHandle = actionJob
        actionContinuation.flowCollectContext = runtimeFlowCurrentEmitContext()

        lock.lock()
        activeJob = actionJob
        lock.unlock()
        actionJob.markStarted()

        let entryPointRaw = unsafeBitCast(
            runtimeFlowLatestCollectorBody as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        runtimeStartLaunchedBody(
            entryPointRaw: entryPointRaw,
            continuation: actionContinuationRaw,
            scope: actionScope,
            job: actionJob
        ) { [weak self, actionScope, actionJob, actionHandle] result, thrown in
            let nestedFailure = actionScope.waitForChildren()
            let finalThrown = thrown != 0 ? thrown : nestedFailure
            if finalThrown != 0, kk_is_cancellation_exception(finalThrown) == 0 {
                self?.recordFailure(finalThrown)
            }
            if finalThrown != 0 {
                _ = actionJob.completeExceptionally(with: finalThrown)
            } else {
                _ = actionJob.complete(with: result)
            }
            self?.collectionJob.detachChild(actionHandle)
            _ = runtimeReleaseObject(actionHandle)
            if finalThrown != 0, kk_is_cancellation_exception(finalThrown) == 0 {
                _ = self?.collectionJob.cancel(cause: finalThrown)
            }
            self?.lock.lock()
            if self?.activeJob === actionJob { self?.activeJob = nil }
            self?.lock.unlock()
        }
        return failureSnapshot()
    }

    func finish(upstreamFailure: Int) -> Int {
        if let active = takeActiveJob() {
            if upstreamFailure != 0, !active.completedSnapshot() {
                _ = active.cancel(cause: upstreamFailure)
            }
            _ = active.join()
        }
        let nestedFailure = collectionScope.waitForChildren()
        let actionFailure = failureSnapshot()
        let cancellation = collectionJob.cancellationSnapshot()
            ? collectionJob.cancellationCauseSnapshot() : 0
        let finalFailure = actionFailure != 0 ? actionFailure
            : (upstreamFailure != 0 ? upstreamFailure
                : (nestedFailure != 0 ? nestedFailure : cancellation))
        if finalFailure != 0 {
            _ = collectionJob.completeExceptionally(with: finalFailure)
        } else {
            _ = collectionJob.complete(with: 0)
        }
        return finalFailure
    }
}

private func runtimeFlowLatestCollectorReceiver(
    _ stateHandle: Int,
    _ value: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: stateHandle) else { return 0 }
    let state = Unmanaged<RuntimeFlowLatestCollectState>.fromOpaque(pointer).takeUnretainedValue()
    let failure = state.receive(value)
    outThrown?.pointee = failure
    return value
}

/// Returns true on success, false if the collector threw (signalling the flow
/// should stop).
private func runtimeFlowDeliverValue(
    _ value: Int,
    collectorFnPtr: Int,
    collectorEnvPtr: Int,
    continuation: Int,
    owningContext: RuntimeFlowCollectContext? = nil
) -> Bool {
    guard collectorFnPtr != 0 else {
        return true
    }
    let currentContext = owningContext ?? runtimeFlowCurrentCollectContext()
    let wasInvokingCollector = currentContext?.invokingCollector ?? false
    currentContext?.invokingCollector = true
    defer { currentContext?.invokingCollector = wasInvokingCollector }

    if continuation == 0 {
        // Non-suspend collector ABI: (closureRaw, value, outThrown)
        let collector = unsafeBitCast(
            collectorFnPtr,
            to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        var thrown = 0
        _ = collector(collectorEnvPtr, value, &thrown)
        if thrown != 0 {
            currentContext?.failure = thrown
            currentContext?.cancelled = true
        }
        return thrown == 0
    } else {
        let cont = kk_coroutine_continuation_new(continuation)
        if let state = runtimeContinuationState(from: cont) {
            state.replaceLauncherArgs([0: Int64(collectorFnPtr), 1: Int64(collectorEnvPtr), 2: Int64(value)])
            state.scope = RuntimeContinuationState.current?.scope ?? RuntimeCoroutineScope.current
            state.jobHandle = RuntimeContinuationState.current?.jobHandle
            state.flowCollectContext = runtimeFlowCurrentEmitContext()
        }
        // Install the collector's continuation during every burst so nested
        // suspend wrappers resume the collector, not its enclosing emitter.
        let entry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { continuation, outThrown in
            guard let state = runtimeContinuationState(from: continuation) else { return 0 }
            return state.withRetainedLauncherArgs { args in
                let collector = unsafeBitCast(
                    Int(args[0] ?? 0),
                    to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
                )
                return collector(Int(args[1] ?? 0), Int(args[2] ?? 0), continuation, outThrown)
            }
        }
        var thrown = 0
        _ = runSuspendEntryLoopWithContinuation(
            entryPointRaw: unsafeBitCast(entry, to: Int.self),
            continuation: cont,
            outThrown: &thrown
        )
        if thrown != 0 {
            currentContext?.failure = thrown
            currentContext?.cancelled = true
        }
        return thrown == 0
    }
}

@_cdecl("kk_flow_create")
public func kk_flow_create(_ emitterFnPtr: Int, _ emitterContinuation: Int) -> Int {
    runtimeRegisterFlowHandle(
        RuntimeFlowHandle(emitterFnPtr: emitterFnPtr, emitterContinuation: emitterContinuation)
    )
}

@_cdecl("kk_channel_flow_create")
public func kk_channel_flow_create(_ emitterFnPtr: Int, _ emitterContinuation: Int) -> Int {
    return runtimeRegisterFlowHandle(
        RuntimeFlowHandle(
            source: .channelProducer(
                RuntimeChannelProducer(
                    emitterFnPtr: emitterFnPtr,
                    templateContinuation: emitterContinuation
                )
            )
        )
    )
}

/// `callbackFlow` shares the channel-backed implementation with `channelFlow`;
/// the distinct entry point preserves the public ABI surface.
@_cdecl("kk_callback_flow_create")
public func kk_callback_flow_create(_ emitterFnPtr: Int, _ emitterContinuation: Int) -> Int {
    kk_channel_flow_create(emitterFnPtr, emitterContinuation)
}

/// Return the flow-stop sentinel pointer. This is a unique object pointer that
/// cannot collide with any legitimate `Int` value (unlike the previous `Int.min`
/// approach). Emitters should compare the return value of `kk_flow_emit` against
/// `__kk_flow_stopped()` to detect pipeline termination.
@_cdecl("__kk_flow_stopped")
public func __kk_flow_stopped() -> Int {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(runtimeStorage.flowStopSentinelBox).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
        state.borrowedObjectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

/// Sentinel value returned by `kk_flow_emit` to signal that the pipeline has
/// terminated (e.g. a `.take` counter was exhausted or the collector threw).
/// This uses a unique heap-allocated object pointer so it cannot collide with
/// any legitimate emitted `Int` value (including `Int.min`).
/// Cached as a static let to avoid repeated lock acquisition and dictionary
/// insertion on every access.
private let runtimeFlowStopSentinel: Int = __kk_flow_stopped()

@_cdecl("kk_flow_emit")
public func kk_flow_emit(_ flowHandle: Int, _ value: Int, _ tag: Int, _ outThrown: UnsafeMutablePointer<Int>? = nil) -> Int {
    outThrown?.pointee = 0
    if tag == RuntimeFlowTag.emit.rawValue {
        let context = runtimeFlowCurrentEmitContext()
        if context?.cancelled == true {
            outThrown?.pointee = context?.rootedFailure() ?? 0
            return runtimeFlowStopSentinel
        }
        if let context, !context.cancelled {
            let unboxed = runtimeFlowMaybeUnbox(value)
            let timestamp = DispatchTime.now().uptimeNanoseconds - context.startedAt
            context.emittedValues.append(unboxed)
            context.emittedEvents.append(RuntimeFlowEvent(value: unboxed, timestamp: timestamp))
            if let emitHandler = context.emitHandler {
                let result = emitHandler(value)
                outThrown?.pointee = context.rootedFailure()
                return result
            }
        }
        return value
    }
    guard let opKind = RuntimeFlowTag(rawValue: tag) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_flow_emit received unknown op tag \(tag)")
    }
    guard let flow = runtimeFlowHandle(from: flowHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_flow_emit received invalid flow handle")
    }
    let derived = RuntimeFlowHandle(
        source: flow.source,
        opChain: flow.opChain + [RuntimeFlowOp(kind: opKind, argument: value)],
        fixedValues: flow.fixedValues
    )
    return runtimeRegisterFlowHandle(derived)
}

// (a) RF-DEAD-002: Internal compatibility helpers for the bundled Flow source.
public func __kk_flow_emit_with_timestamp(_ flowHandle: Int, _ value: Int, _ tag: Int, _ timestamp: UInt64) -> Int {
    if tag == RuntimeFlowTag.emit.rawValue {
        let context = runtimeFlowCurrentEmitContext()
        if let context, !context.cancelled {
            let unboxed = runtimeFlowMaybeUnbox(value)
            context.emittedValues.append(unboxed)
            context.emittedEvents.append(RuntimeFlowEvent(value: unboxed, timestamp: timestamp))
            if let emitHandler = context.emitHandler {
                return emitHandler(value)
            }
        }
        return value
    }
    return kk_flow_emit(flowHandle, value, tag)
}

@_cdecl("kk_flow_collect")
public func kk_flow_collect(_ flowHandle: Int, _ collectorFnPtr: Int, _ collectorEnvPtr: Int, _ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>? = nil) -> Int {
    outThrown?.pointee = 0
    guard let flow = runtimeFlowHandle(from: flowHandle) else {
        return 0
    }

    let callerState = RuntimeContinuationState.current
    let failure = runtimeFlowCollectLazy(flow, collectorFnPtr: collectorFnPtr, collectorEnvPtr: collectorEnvPtr, continuation: continuation)
    if outThrown == nil {
        callerState?.thrownException = failure
    }
    outThrown?.pointee = failure
    return failure
}

// Runs each `collectLatest` action in its own child Job so a new upstream value
// can cancel a suspended collector before waiting for the last action at EOF.
@_cdecl("__kk_flow_collectLatest")
public func __kk_flow_collectLatest(_ flowHandle: Int, _ collectorFnPtr: Int, _ collectorEnvPtr: Int, _ continuation: Int, _ outThrown: UnsafeMutablePointer<Int>? = nil) -> Int {
    outThrown?.pointee = 0
    guard let flow = runtimeFlowHandle(from: flowHandle), collectorFnPtr != 0 else { return 0 }

    let callerState = RuntimeContinuationState.current
    let previousScope = RuntimeCoroutineScope.current
    let previousJob = RuntimeJobHandle.current
    let parentJob = callerState?.jobHandle ?? previousJob ?? previousScope?.job
    let parentStateScope = callerState?.scope
    let parentStateJob = callerState?.jobHandle
    let collectionScope = RuntimeCoroutineScope(
        context: previousScope?.context ?? callerState?.makeContinuationContext() ?? RuntimeCoroutineContext()
    )
    collectionScope.blockingScheduler = previousScope?.blockingScheduler
    RuntimeJobHandle.current = parentJob
    let collectionJob = collectionScope.installJob(defaultCancellationMessage: "Flow collection was cancelled")
    RuntimeCoroutineScope.current = collectionScope
    RuntimeJobHandle.current = collectionJob
    callerState?.scope = collectionScope
    callerState?.jobHandle = collectionJob
    defer {
        callerState?.scope = parentStateScope
        callerState?.jobHandle = parentStateJob
        RuntimeCoroutineScope.current = previousScope
        RuntimeJobHandle.current = previousJob
        parentJob?.detachChild(collectionJob.identityHandle)
        _ = runtimeReleaseObject(collectionJob.identityHandle)
    }

    let latestState = RuntimeFlowLatestCollectState(
        collectorFnPtr: collectorFnPtr,
        collectorEnvPtr: collectorEnvPtr,
        continuation: continuation,
        collectionScope: collectionScope,
        collectionJob: collectionJob
    )
    let stateHandle = Int(bitPattern: Unmanaged.passUnretained(latestState).toOpaque())
    let receiverRaw = unsafeBitCast(
        runtimeFlowLatestCollectorReceiver as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int,
        to: Int.self
    )
    let upstreamFailure = runtimeFlowCollectLazy(
        flow,
        collectorFnPtr: receiverRaw,
        collectorEnvPtr: stateHandle,
        continuation: 0
    )
    let failure = latestState.finish(upstreamFailure: upstreamFailure)
    outThrown?.pointee = failure
    return failure
}

@_cdecl("__kk_flow_retain")
public func __kk_flow_retain(_ flowHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: flowHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_flow_retain received invalid flow handle")
    }
    let key = UInt(bitPattern: ptr)
    return runtimeStorage.withFlowLock { state in
        guard state.flowHandles[key] != nil else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_flow_retain received unregistered flow handle")
        }
        state.flowRetainCounts[key, default: 0] += 1
        return flowHandle
    }
}

@_cdecl("__kk_flow_release")
public func __kk_flow_release(_ flowHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: flowHandle) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_flow_release received invalid flow handle")
    }
    let key = UInt(bitPattern: ptr)
    runtimeStorage.withFlowAndGCLocks { flowState, gcState in
        guard let count = flowState.flowRetainCounts[key] else {
            return
        }
        let nextCount = count - 1
        if nextCount <= 0 {
            gcState.objectPointers.remove(key)
            gcState.borrowedObjectPointers.remove(key)
            gcState.retainedObjectHeapFields.removeValue(forKey: key)
            flowState.flowRetainCounts.removeValue(forKey: key)
            flowState.flowHandles.removeValue(forKey: key)
        } else {
            flowState.flowRetainCounts[key] = nextCount
        }
    }
    return 0
}

private func runtimeFlowInitTakeCounters(_ ops: [RuntimeFlowOp]) -> [Int: Int] {
    var takeCounters: [Int: Int] = [:]
    for (index, op) in ops.enumerated() where op.kind == .take {
        takeCounters[index] = max(0, runtimeFlowMaybeUnbox(op.argument))
    }
    return takeCounters
}

@_cdecl("__kk_flow_to_list")
public func __kk_flow_to_list(_ flowHandle: Int, _: Int) -> Int {
    guard let flow = runtimeFlowHandle(from: flowHandle) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let result = runtimeFlowEvaluate(flow: flow)
    runtimeFlowFireCompletionHandlers(flow.opChain, failure: result.failure)
    return registerRuntimeObject(RuntimeListBox(elements: result.values))
}

@_cdecl("__kk_flow_first")
public func __kk_flow_first(_ flowHandle: Int, _: Int) -> Int {
    guard let flow = runtimeFlowHandle(from: flowHandle) else {
        return 0
    }
    let result = runtimeFlowEvaluate(flow: flow)
    runtimeFlowFireCompletionHandlers(flow.opChain, failure: result.failure)
    return result.values.first ?? 0
}

@_cdecl("__kk_flow_single")
public func __kk_flow_single(_ flowHandle: Int, _: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let flow = runtimeFlowHandle(from: flowHandle) else {
        return 0
    }
    let result = runtimeFlowEvaluate(flow: flow)
    runtimeFlowFireCompletionHandlers(flow.opChain, failure: result.failure)
    guard result.values.count == 1 else {
        if result.values.isEmpty {
            outThrown?.pointee = runtimeAllocateNoSuchElementException(message: "Flow is empty.")
        } else {
            outThrown?.pointee = runtimeAllocateIllegalArgumentException(
                message: "Flow has more than one element."
            )
        }
        return 0
    }
    return result.values[0]
}

public func __kk_flow_count(_ flowHandle: Int, _: Int) -> Int {
    guard let flow = runtimeFlowHandle(from: flowHandle) else {
        return 0
    }
    let result = runtimeFlowEvaluate(flow: flow)
    runtimeFlowFireCompletionHandlers(flow.opChain, failure: result.failure)
    return result.values.count
}

/// operation ABI: (closureRaw, accumulator, value, outThrown) -> newAccumulator
public func __kk_flow_fold(_ flowHandle: Int, _ initial: Int, _ operationFnPtr: Int, _: Int) -> Int {
    guard let flow = runtimeFlowHandle(from: flowHandle) else {
        return initial
    }

    guard operationFnPtr != 0 else {
        return initial
    }
    let operation = unsafeBitCast(
        operationFnPtr,
        to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )

    let result = runtimeFlowEvaluate(flow: flow)
    var accumulator = initial
    for value in result.values {
        var thrown = 0
        accumulator = runtimeFlowMaybeUnbox(operation(0, accumulator, value, &thrown))
        if thrown != 0 {
            runtimeFlowFireCompletionHandlers(flow.opChain, failure: thrown)
            return accumulator
        }
    }
    runtimeFlowFireCompletionHandlers(flow.opChain, failure: result.failure)
    return accumulator
}

/// operation ABI: (closureRaw, accumulator, value, outThrown) -> newAccumulator
public func __kk_flow_reduce(_ flowHandle: Int, _ operationFnPtr: Int, _: Int) -> Int {
    guard let flow = runtimeFlowHandle(from: flowHandle) else {
        return 0
    }

    guard operationFnPtr != 0 else {
        return 0
    }
    let operation = unsafeBitCast(
        operationFnPtr,
        to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )

    let values = runtimeFlowEvaluate(flow: flow).values
    guard let first = values.first else {
        return 0
    }

    var accumulator = first
    var thrownOnReduce: Int?
    for value in values.dropFirst() {
        var thrown = 0
        accumulator = runtimeFlowMaybeUnbox(operation(0, accumulator, value, &thrown))
        if thrown != 0 {
            thrownOnReduce = thrown
            break
        }
    }
    runtimeFlowFireCompletionHandlers(flow.opChain, failure: thrownOnReduce)
    return accumulator
}

// KSP-674: kk_flow_of / kk_flow_empty / kk_flow_as_flow removed. flowOf /
// emptyFlow / Iterable.asFlow are now Kotlin source (kotlinx.coroutines.flow)
// composed from `flow { }` (kk_flow_create) + `emit` (kk_flow_emit).

// KSP-676: StateFlow / MutableStateFlow and Flow.stateIn are now Kotlin source
// (Stdlib/kotlinx/coroutines/flow/StateFlow.kt), so the runtime handle and
// kk_mutable_state_flow_* / kk_state_flow_value / kk_flow_state_in C bridges
// have been removed.

private func runtimeFlowEvaluateFlatMapConcat(
    sourceHandle: Int,
    mapperFnPtr: Int,
    ops: [RuntimeFlowOp]
) -> RuntimeFlowExecutionResult {
    guard let sourceFlow = runtimeFlowHandle(from: sourceHandle) else {
        return RuntimeFlowExecutionResult(values: [], failure: nil)
    }
    guard mapperFnPtr != 0 else {
        return runtimeFlowEvaluate(flow: sourceFlow)
    }
    let mapper = unsafeBitCast(
        mapperFnPtr,
        to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    let sourceResult = runtimeFlowEvaluate(flow: sourceFlow)
    if let failure = sourceResult.failure {
        return RuntimeFlowExecutionResult(values: [], failure: failure)
    }
    var all: [Int] = []
    for value in sourceResult.values {
        var thrown = 0
        let innerHandle = mapper(0, value, &thrown)
        if thrown != 0 {
            return RuntimeFlowExecutionResult(values: all, failure: thrown)
        }
        if let innerFlow = runtimeFlowHandle(from: innerHandle) {
            let inner = runtimeFlowEvaluate(flow: innerFlow)
            all.append(contentsOf: inner.values)
            if let f = inner.failure {
                return RuntimeFlowExecutionResult(values: all, failure: f)
            }
        }
    }
    return runtimeFlowRunNormalStage(RuntimeFlowExecutionResult(values: all, failure: nil), ops: ops)
}

private func runtimeFlowEvaluateFlatMapMerge(
    sourceHandle: Int,
    mapperFnPtr: Int,
    ops: [RuntimeFlowOp]
) -> RuntimeFlowExecutionResult {
    // In the synchronous cold-stream model, merge degenerates to concat.
    runtimeFlowEvaluateFlatMapConcat(sourceHandle: sourceHandle, mapperFnPtr: mapperFnPtr, ops: ops)
}

private func runtimeFlowEvaluateFlatMapLatest(
    sourceHandle: Int,
    mapperFnPtr: Int,
    ops: [RuntimeFlowOp]
) -> RuntimeFlowExecutionResult {
    guard let sourceFlow = runtimeFlowHandle(from: sourceHandle) else {
        return RuntimeFlowExecutionResult(values: [], failure: nil)
    }
    guard mapperFnPtr != 0 else {
        return runtimeFlowEvaluate(flow: sourceFlow)
    }
    let callerState = RuntimeContinuationState.current
    let previousScope = RuntimeCoroutineScope.current
    let previousJob = RuntimeJobHandle.current
    let parentJob = callerState?.jobHandle ?? previousJob ?? previousScope?.job
    let parentStateScope = callerState?.scope
    let parentStateJob = callerState?.jobHandle
    let collectionScope = RuntimeCoroutineScope(
        context: previousScope?.context ?? callerState?.makeContinuationContext() ?? RuntimeCoroutineContext()
    )
    collectionScope.blockingScheduler = previousScope?.blockingScheduler
    RuntimeJobHandle.current = parentJob
    let collectionJob = collectionScope.installJob(defaultCancellationMessage: "flatMapLatest collection was cancelled")
    RuntimeCoroutineScope.current = collectionScope
    RuntimeJobHandle.current = collectionJob
    callerState?.scope = collectionScope
    callerState?.jobHandle = collectionJob
    defer {
        callerState?.scope = parentStateScope
        callerState?.jobHandle = parentStateJob
        RuntimeCoroutineScope.current = previousScope
        RuntimeJobHandle.current = previousJob
        parentJob?.detachChild(collectionJob.identityHandle)
        _ = runtimeReleaseObject(collectionJob.identityHandle)
    }

    let latestState = RuntimeFlowLatestFlatMapState(
        mapperFnPtr: mapperFnPtr,
        collectionScope: collectionScope,
        collectionJob: collectionJob
    )
    let stateHandle = Int(bitPattern: Unmanaged.passUnretained(latestState).toOpaque())
    let receiverRaw = unsafeBitCast(
        runtimeFlowLatestFlatMapReceiver as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int,
        to: Int.self
    )
    let upstreamFailure = runtimeFlowCollectLazy(
        sourceFlow,
        collectorFnPtr: receiverRaw,
        collectorEnvPtr: stateHandle,
        continuation: 0
    )
    let latestResult = latestState.finish(upstreamFailure: upstreamFailure)
    return runtimeFlowRunNormalStage(latestResult, ops: ops)
}

/// Collects each flatMapLatest inner flow in a child Job so a newer upstream
/// value can cancel it while preserving values emitted before cancellation.
private final class RuntimeFlowLatestFlatMapState: @unchecked Sendable {
    static let innerFlowArgument = Int64.min
    static let stateArgument = Int64.min + 1

    private let lock = NSLock()
    private let mapperFnPtr: Int
    private let collectionScope: RuntimeCoroutineScope
    private let collectionJob: RuntimeJobHandle
    private var activeJob: RuntimeJobHandle?
    private var values: [Int] = []
    private var failure = 0

    init(
        mapperFnPtr: Int,
        collectionScope: RuntimeCoroutineScope,
        collectionJob: RuntimeJobHandle
    ) {
        self.mapperFnPtr = mapperFnPtr
        self.collectionScope = collectionScope
        self.collectionJob = collectionJob
    }

    func append(_ value: Int) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    private func failureSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return failure
    }

    private func recordFailure(_ exception: Int) {
        guard exception != 0, kk_is_cancellation_exception(exception) == 0 else { return }
        lock.lock()
        if failure == 0 { failure = exception }
        lock.unlock()
    }

    private func takeActiveJob() -> RuntimeJobHandle? {
        lock.lock()
        let job = activeJob
        activeJob = nil
        lock.unlock()
        return job
    }

    func receive(_ value: Int) -> Int {
        if let previous = takeActiveJob() {
            if !previous.completedSnapshot() {
                _ = previous.cancel(message: "Latest outer value was received")
            }
            _ = previous.join()
        }
        let previousFailure = failureSnapshot()
        if previousFailure != 0 { return previousFailure }
        if collectionJob.cancellationSnapshot() {
            return collectionJob.cancellationCauseSnapshot()
        }

        var mapperFailure = 0
        let innerHandle: Int
        if runtimeFunctionValueBox(from: mapperFnPtr) != nil {
            innerHandle = runtimeInvokeSuspendFunction(
                mapperFnPtr,
                arguments: [value],
                continuation: 0,
                outThrown: &mapperFailure
            )
        } else {
            let mapper = unsafeBitCast(
                mapperFnPtr,
                to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
            )
            innerHandle = mapper(0, value, &mapperFailure)
        }
        if mapperFailure != 0 {
            recordFailure(mapperFailure)
            return mapperFailure
        }
        guard innerHandle != 0, runtimeFlowHandle(from: innerHandle) != nil else {
            return 0
        }

        let actionScope = RuntimeCoroutineScope(context: collectionScope.context)
        actionScope.blockingScheduler = collectionScope.blockingScheduler
        let previousJob = RuntimeJobHandle.current
        RuntimeJobHandle.current = collectionJob
        let actionJob = actionScope.installJob(defaultCancellationMessage: "Latest inner flow was cancelled")
        RuntimeJobHandle.current = previousJob
        actionJob.debugName = "FlowLatestInner"
        actionJob.propagatesFailureToParent = false
        let actionHandle = actionJob.identityHandle
        collectionJob.registerChild(actionHandle)

        let innerFlow = runtimeFlowHandle(from: innerHandle)!
        let template = innerFlow.emitterTemplateState
        let continuationRaw = kk_coroutine_continuation_new(template.map { Int($0.functionID) } ?? 0)
        guard let continuationState = runtimeContinuationState(from: continuationRaw) else {
            _ = actionJob.complete(with: 0)
            _ = runtimeReleaseObject(actionHandle)
            return 0
        }
        actionJob.continuationState = continuationState
        template?.withRetainedLauncherArgs { args in
            continuationState.replaceLauncherArgs(args)
        }
        continuationState.setLauncherArg(Self.innerFlowArgument, value: Int64(innerHandle))
        continuationState.setLauncherArg(Self.stateArgument, value: Int64(Int(bitPattern: Unmanaged.passUnretained(self).toOpaque())))
        continuationState.scope = actionScope
        continuationState.jobHandle = actionJob
        continuationState.flowCollectContext = runtimeFlowLatestInnerCollectContext(innerFlow, state: self)

        lock.lock()
        activeJob = actionJob
        lock.unlock()
        actionJob.markStarted()

        let entryPointRaw: Int
        if case let .emitter(emitterFnPtr, emitterTemplate) = innerFlow.source,
           emitterTemplate != nil
        {
            entryPointRaw = emitterFnPtr
        } else {
            entryPointRaw = unsafeBitCast(
                runtimeFlowLatestFlatMapInnerBody as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
                to: Int.self
            )
        }
        runtimeStartLaunchedBody(
            entryPointRaw: entryPointRaw,
            continuation: continuationRaw,
            scope: actionScope,
            job: actionJob
        ) { [weak self, actionScope, actionJob, actionHandle] result, thrown in
            let nestedFailure = actionScope.waitForChildren()
            let finalThrown = thrown != 0 ? thrown : nestedFailure
            if finalThrown != 0, kk_is_cancellation_exception(finalThrown) == 0 {
                self?.recordFailure(finalThrown)
                _ = self?.collectionJob.cancel(cause: finalThrown)
                _ = actionJob.completeExceptionally(with: finalThrown)
            } else {
                _ = actionJob.complete(with: result)
            }
            self?.collectionJob.detachChild(actionHandle)
            _ = runtimeReleaseObject(actionHandle)
            self?.lock.lock()
            if self?.activeJob === actionJob { self?.activeJob = nil }
            self?.lock.unlock()
        }
        return failureSnapshot()
    }

    func finish(upstreamFailure: Int) -> RuntimeFlowExecutionResult {
        if let active = takeActiveJob() {
            if upstreamFailure != 0, kk_is_cancellation_exception(upstreamFailure) == 0,
               !active.completedSnapshot()
            {
                _ = active.cancel(cause: upstreamFailure)
            }
            _ = active.join()
        }
        let nestedFailure = collectionScope.waitForChildren()
        let actionFailure = failureSnapshot()
        let cancellation = collectionJob.cancellationSnapshot()
            ? collectionJob.cancellationCauseSnapshot() : 0
        let finalFailure = actionFailure != 0 ? actionFailure
            : (upstreamFailure != 0 ? upstreamFailure
                : (nestedFailure != 0 ? nestedFailure : cancellation))
        if finalFailure != 0 {
            _ = collectionJob.completeExceptionally(with: finalFailure)
        } else {
            _ = collectionJob.complete(with: 0)
        }
        lock.lock()
        let resultValues = values
        lock.unlock()
        return RuntimeFlowExecutionResult(values: resultValues, failure: finalFailure == 0 ? nil : finalFailure)
    }
}

private func runtimeFlowLatestFlatMapInnerBody(
    _ continuation: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else { return 0 }
    return state.withRetainedLauncherArgs { args in
        guard let innerFlow = runtimeFlowHandle(from: Int(args[RuntimeFlowLatestFlatMapState.innerFlowArgument] ?? 0))
        else { return 0 }
        if case let .emitter(emitterFnPtr, template) = innerFlow.source, template == nil {
            let emitter = unsafeBitCast(
                emitterFnPtr,
                to: (@convention(c) (UnsafeMutablePointer<Int>?) -> Int).self
            )
            return emitter(outThrown)
        }

        let stateHandle = Int(args[RuntimeFlowLatestFlatMapState.stateArgument] ?? 0)
        let receiver = unsafeBitCast(
            runtimeFlowLatestFlatMapInnerReceiver as @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int,
            to: Int.self
        )
        let failure = runtimeFlowCollectLazy(
            innerFlow,
            collectorFnPtr: receiver,
            collectorEnvPtr: stateHandle,
            continuation: 0
        )
        outThrown?.pointee = failure
        return failure
    }
}

private func runtimeFlowLatestInnerCollectContext(
    _ flow: RuntimeFlowHandle,
    state: RuntimeFlowLatestFlatMapState
) -> RuntimeFlowCollectContext {
    let context = RuntimeFlowCollectContext()
    var takeCounters = runtimeFlowInitTakeCounters(flow.opChain)
    var lastValues: [Int: RuntimeGCRootedValue] = [:]
    context.emitHandler = { [weak context] emittedValue in
        guard let context else { return runtimeFlowStopSentinel }
        let result = runtimeFlowApplyOpsLazy(
            runtimeFlowMaybeUnbox(emittedValue),
            ops: flow.opChain,
            takeCounters: &takeCounters,
            lastValues: &lastValues
        )
        switch result {
        case let .emit(value):
            state.append(value)
            if runtimeFlowTakeExhausted(ops: flow.opChain, takeCounters: takeCounters) {
                context.cancelled = true
                return runtimeFlowStopSentinel
            }
            return value
        case .filtered:
            return emittedValue
        case let .thrown(failure):
            context.failure = failure
            context.cancelled = true
            return runtimeFlowStopSentinel
        case .done:
            context.cancelled = true
            return runtimeFlowStopSentinel
        }
    }
    return context
}

private func runtimeFlowLatestFlatMapInnerReceiver(
    _ stateHandle: Int,
    _ value: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: stateHandle) else { return 0 }
    let state = Unmanaged<RuntimeFlowLatestFlatMapState>.fromOpaque(pointer).takeUnretainedValue()
    state.append(runtimeFlowMaybeUnbox(value))
    outThrown?.pointee = 0
    return value
}

private func runtimeFlowLatestFlatMapReceiver(
    _ stateHandle: Int,
    _ value: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: stateHandle) else { return 0 }
    let state = Unmanaged<RuntimeFlowLatestFlatMapState>.fromOpaque(pointer).takeUnretainedValue()
    let failure = state.receive(value)
    outThrown?.pointee = failure
    return value
}

private func runtimeFlowEvaluateMerge(
    flowHandles: [Int],
    ops: [RuntimeFlowOp]
) -> RuntimeFlowExecutionResult {
    var all: [Int] = []
    for handle in flowHandles {
        guard let flow = runtimeFlowHandle(from: handle) else { continue }
        let result = runtimeFlowEvaluate(flow: flow)
        all.append(contentsOf: result.values)
        if let f = result.failure {
            return runtimeFlowRunNormalStage(RuntimeFlowExecutionResult(values: all, failure: f), ops: ops)
        }
    }
    return runtimeFlowRunNormalStage(RuntimeFlowExecutionResult(values: all, failure: nil), ops: ops)
}

private func runtimeFlowEvaluateZip(
    leftHandle: Int,
    rightHandle: Int,
    combinerFnPtr: Int,
    ops: [RuntimeFlowOp]
) -> RuntimeFlowExecutionResult {
    guard let leftFlow = runtimeFlowHandle(from: leftHandle),
          let rightFlow = runtimeFlowHandle(from: rightHandle) else {
        return RuntimeFlowExecutionResult(values: [], failure: nil)
    }
    let leftResult  = runtimeFlowEvaluate(flow: leftFlow)
    let rightResult = runtimeFlowEvaluate(flow: rightFlow)
    if let f = leftResult.failure  { return RuntimeFlowExecutionResult(values: [], failure: f) }
    if let f = rightResult.failure { return RuntimeFlowExecutionResult(values: [], failure: f) }
    guard combinerFnPtr != 0 else { return runtimeFlowRunNormalStage(leftResult, ops: ops) }
    let combiner = unsafeBitCast(
        combinerFnPtr,
        to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    let count = min(leftResult.values.count, rightResult.values.count)
    var all: [Int] = []
    all.reserveCapacity(count)
    for i in 0 ..< count {
        var thrown = 0
        let combined = combiner(0, leftResult.values[i], rightResult.values[i], &thrown)
        if thrown != 0 {
            return RuntimeFlowExecutionResult(values: all, failure: thrown)
        }
        all.append(runtimeFlowMaybeUnbox(combined))
    }
    return runtimeFlowRunNormalStage(RuntimeFlowExecutionResult(values: all, failure: nil), ops: ops)
}

private func runtimeFlowEvaluateCombine(
    leftHandle: Int,
    rightHandle: Int,
    combinerFnPtr: Int,
    ops: [RuntimeFlowOp]
) -> RuntimeFlowExecutionResult {
    guard let leftFlow = runtimeFlowHandle(from: leftHandle),
          let rightFlow = runtimeFlowHandle(from: rightHandle) else {
        return RuntimeFlowExecutionResult(values: [], failure: nil)
    }
    let leftResult  = runtimeFlowEvaluate(flow: leftFlow)
    let rightResult = runtimeFlowEvaluate(flow: rightFlow)
    if let f = leftResult.failure  { return RuntimeFlowExecutionResult(values: [], failure: f) }
    if let f = rightResult.failure { return RuntimeFlowExecutionResult(values: [], failure: f) }
    guard combinerFnPtr != 0 else { return runtimeFlowRunNormalStage(leftResult, ops: ops) }
    guard !leftResult.values.isEmpty, !rightResult.values.isEmpty else {
        return RuntimeFlowExecutionResult(values: [], failure: nil)
    }
    let combiner = unsafeBitCast(
        combinerFnPtr,
        to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    let count = max(leftResult.values.count, rightResult.values.count)
    var all: [Int] = []
    all.reserveCapacity(count)
    for i in 0 ..< count {
        let lv = leftResult.values[min(i, leftResult.values.count - 1)]
        let rv = rightResult.values[min(i, rightResult.values.count - 1)]
        var thrown = 0
        let combined = combiner(0, lv, rv, &thrown)
        if thrown != 0 {
            return RuntimeFlowExecutionResult(values: all, failure: thrown)
        }
        all.append(runtimeFlowMaybeUnbox(combined))
    }
    return runtimeFlowRunNormalStage(RuntimeFlowExecutionResult(values: all, failure: nil), ops: ops)
}

/// mapperFnPtr: (closureRaw, value, outThrown) -> innerFlowHandle
@_cdecl("__kk_flow_flat_map_concat")
public func __kk_flow_flat_map_concat(_ flowHandle: Int, _ mapperFnPtr: Int, _: Int) -> Int {
    let derived = RuntimeFlowHandle(
        source: .flatMapConcat(flowHandle, mapperFnPtr),
        opChain: []
    )
    return runtimeRegisterFlowHandle(derived)
}

@_cdecl("__kk_flow_flat_map_merge")
public func __kk_flow_flat_map_merge(_ flowHandle: Int, _ mapperFnPtr: Int, _: Int) -> Int {
    let derived = RuntimeFlowHandle(
        source: .flatMapMerge(flowHandle, mapperFnPtr),
        opChain: []
    )
    return runtimeRegisterFlowHandle(derived)
}

@_cdecl("__kk_flow_flat_map_latest")
public func __kk_flow_flat_map_latest(_ flowHandle: Int, _ mapperFnPtr: Int, _: Int) -> Int {
    let derived = RuntimeFlowHandle(
        source: .flatMapLatest(flowHandle, mapperFnPtr),
        opChain: []
    )
    return runtimeRegisterFlowHandle(derived)
}

// Kotlin external calls carry an `outThrown` pointer; the non-throwing
// compiler intrinsic above keeps its existing dummy-argument ABI.
// The suspend transform arrives as a single boxed function-value handle:
// RuntimeFlowLatestFlatMapState.receive resolves it through
// runtimeFunctionValueBox and drives it via runtimeInvokeSuspendFunction.
@_cdecl("__kk_flow_flat_map_latest_external")
public func __kk_flow_flat_map_latest_external(
    _ flowHandle: Int,
    _ mapperFnPtr: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    return __kk_flow_flat_map_latest(flowHandle, mapperFnPtr, 0)
}

/// flowArrayHandle: handle to an array of flow handles; count: element count.
@_cdecl("__kk_flow_merge")
public func __kk_flow_merge(_ flowArrayHandle: Int, _ count: Int, _: Int) -> Int {
    var handles: [Int] = []
    handles.reserveCapacity(count)
    for i in 0 ..< count {
        let h = runtimeReadArrayElement(arrayRaw: flowArrayHandle, index: i)
        if h != 0 { handles.append(h) }
    }
    let derived = RuntimeFlowHandle(
        source: .merge(handles),
        opChain: []
    )
    return runtimeRegisterFlowHandle(derived)
}

/// combinerFnPtr: (closureRaw, lhs, rhs, outThrown) -> result
@_cdecl("__kk_flow_zip")
public func __kk_flow_zip(_ leftHandle: Int, _ rightHandle: Int, _ combinerFnPtr: Int, _: Int) -> Int {
    let derived = RuntimeFlowHandle(
        source: .zip(leftHandle, rightHandle, combinerFnPtr),
        opChain: []
    )
    return runtimeRegisterFlowHandle(derived)
}

/// combinerFnPtr: (closureRaw, lhs, rhs, outThrown) -> result
@_cdecl("__kk_flow_combine")
public func __kk_flow_combine(_ leftHandle: Int, _ rightHandle: Int, _ combinerFnPtr: Int, _: Int) -> Int {
    let derived = RuntimeFlowHandle(
        source: .combine(leftHandle, rightHandle, combinerFnPtr),
        opChain: []
    )
    return runtimeRegisterFlowHandle(derived)
}
