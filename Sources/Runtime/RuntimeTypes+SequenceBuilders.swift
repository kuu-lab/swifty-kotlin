import Foundation

// MARK: - Sequence Types (STDLIB-003)

/// Represents a lazy operation in a sequence chain.
/// Each step stores its kind (source, map, filter, take) and a function pointer
/// for map/filter transformations. Lazy semantics: no evaluation until terminal.
enum SequenceStepKind {
    case source(elements: [Int])
    case valueSource(values: [RuntimeValue])
    case stringSource(source: String)
    case mapStep(fnPtr: Int, closureRaw: Int)
    case filterStep(fnPtr: Int, closureRaw: Int)
    case filterNotStep(fnPtr: Int, closureRaw: Int)
    case takeStep(count: Int)
    case builder(elements: [Int])
    case generator(seed: Int, fnPtr: Int, closureRaw: Int)
    /// STDLIB-SEQ-002: 1-arg form: `generateSequence { nextFunction() }`.
    /// Calls `nextFunction` (no-arg) repeatedly; each non-null return value is an element.
    case nullableGenerator(fnPtr: Int, closureRaw: Int)
    case dropStep(count: Int)
    case distinctStep
    case distinctByStep(fnPtr: Int, closureRaw: Int)
    case zipStep(otherElements: [Int])
    case takeWhileStep(fnPtr: Int, closureRaw: Int)
    case dropWhileStep(fnPtr: Int, closureRaw: Int)
    case onEachStep(fnPtr: Int, closureRaw: Int)
    case onEachIndexedStep(fnPtr: Int, closureRaw: Int)
    /// STDLIB-HOF-022: Additional lazy transformation steps
    case mapNotNullStep(fnPtr: Int, closureRaw: Int)
    case filterNotNullStep
    case requireNoNullsStep
    case mapIndexedStep(fnPtr: Int, closureRaw: Int)
    case mapIndexedNotNullStep(fnPtr: Int, closureRaw: Int)
    case filterIndexedStep(fnPtr: Int, closureRaw: Int)
    case withIndexStep
    case flatMapStep(fnPtr: Int, closureRaw: Int)
    case flatMapIndexedStep(fnPtr: Int, closureRaw: Int)
    case chunkedTransformStep(size: Int, fnPtr: Int, closureRaw: Int)
    /// STDLIB-SEQ-019: Random shuffle of the full upstream result. Each full iteration
    /// of the returned sequence re-shuffles (intermediate, stateful; matches Kotlin).
    case shuffledStep(randomRaw: Int?)
    /// STDLIB-563: Lazy continuation-based builder. CPS producers suspend by
    /// returning COROUTINE_SUSPENDED; legacy callbacks keep the thread-backed
    /// producer path.
    case lazyBuilder(coroutine: RuntimeSequenceCoroutine)
    /// STDLIB-IO-FN-040: Lazily pulls elements from a stateful producer until
    /// it returns nil — e.g. `useLines` streaming lines out of a live reader.
    case pullSource(produce: () -> Int?)
}

/// Runtime box for `Sequence<T>`.
/// Stores a chain of lazy steps that are only evaluated on terminal operations.
final class RuntimeSequenceConstrainOnceState {
    var consumed = false
}

final class RuntimeSequenceBox {
    var steps: [SequenceStepKind]
    let constrainOnceState: RuntimeSequenceConstrainOnceState?

    init(steps: [SequenceStepKind], constrainOnceState: RuntimeSequenceConstrainOnceState? = nil) {
        self.steps = steps
        self.constrainOnceState = constrainOnceState
    }
}

/// Runtime box for the `sequence { yield(x) }` builder.
/// Accumulates yielded elements during builder block execution.
/// Used as a fallback when the lazy coroutine path is not available.
final class RuntimeSequenceBuilderBox {
    var elements: [Int] = []
}

// STDLIB-563: Continuation-based lazy sequence coroutine.
//
// Compiler-generated builders use the CPS producer path: each `yield(value)`
// publishes a value, returns COROUTINE_SUSPENDED, and is resumed by the next
// consumer request through the stored continuation. Legacy tests/direct ABI
// callers keep the thread-backed path below for non-CPS raw callbacks.
//
// The coroutine is started lazily on the first call to `materializeAll()`.
//
// Producer protocol (DEBT-CORO-002 / CORO-004):
//   CPS producer (compiler-generated builders):
//     1. First consumer request starts runSuspendEntryLoopWithContinuation().
//     2. On yield(value): queue value, signal consumer, return COROUTINE_SUSPENDED.
//     3. Next consumer request resumes the stored continuation with Unit.
//     4. On completion: set finished flag, signal consumer.
//
//   Legacy producer (direct ABI tests / pre-CPS callbacks):
//     1. Waits on producerGate on a dedicated OS thread.
//     2. Runs builder lambda sequentially.
//     3. On yield(value): queue value, signal consumer, block on producerGate.
//     4. On completion: set finished flag, signal consumer.
//
//   Consumer thread — blocking path (non-coroutine callers):
//     1. Signals producerGate (starts or resumes producer), blocks on consumerGate.
//     2. Reads yielded value or observes finished flag.
//
//   Consumer thread — suspension path (CORO-004 Phase 2, coroutine callers):
//     1. Calls nextElementAsync(callerState:), which signals producerGate and
//        installs a resume continuation in consumerGate instead of blocking.
//     2. Returns COROUTINE_SUSPENDED; the GCD thread is released immediately.
//     3. When the producer yields, the continuation fires and calls
//        callerState.resume(with: element) or callerState.resume(with: doneSentinel).
//
// DEBT-CORO-002 status: compiler-generated producers use CPS and no longer
// allocate a dedicated producer thread. The thread-backed path remains for
// legacy non-CPS callbacks.
//
// CORO-004 Phase 3: CPS-transformed sequence builder lambdas call yield() as a
// real suspend point, so compiler-generated producers no longer need a
// dedicated thread. The legacy thread path remains only for pre-CPS callbacks.
final class RuntimeSequenceCoroutine: @unchecked Sendable {
    /// Legacy builder function pointer or CPS suspend entry point.
    let fnPtr: Int
    let closureRaw: Int
    private let functionID: Int
    private let usesCPSProducer: Bool

    /// Producer suspend gate — signalled by the consumer when it wants the next element.
    private let producerGate = RuntimeCoroutineSyncGate()

    /// Consumer suspend gate — signalled by the producer after yielding or finishing.
    private let consumerGate = RuntimeCoroutineSyncGate()

    /// Guard for mutable state access.
    private let stateLock = NSLock()

    /// Values published by the producer but not consumed yet.
    private var pendingYieldedValues: [Int] = []

    /// Iterator currently delegated by yieldAll(sequence).
    private var delegatedIterator: Int = 0
    /// The initial successful hasNext probe has already prepared the first value.
    private var delegatedIteratorReady = false
    /// A legacy producer's thrown channel remains live while yieldAll blocks.
    private var delegatedThrownPointer: UnsafeMutablePointer<Int>?

    /// Whether the producer has finished (either completed or threw).
    private var finished = false
    private var failure: Int = 0

    /// Whether the coroutine producer has been initialized.
    private var started = false

    /// Whether the CPS suspend-entry loop has been kicked off.
    private var cpsLoopStarted = false

    /// Continuation handle used to resume the CPS builder after yield().
    private var producerContinuationRaw: Int = 0

    /// All elements materialized so far (cache for re-iteration).
    private var materializedElements: [Int] = []

    /// Whether the coroutine has been fully exhausted.
    private var fullyMaterialized = false

    /// Registered handle for the builder proxy — stored here so that future
    /// CPS re-invocations can call invokeBuilderLambda() without recreating it.
    private var builderHandle: Int = 0

    init(fnPtr: Int, closureRaw: Int, functionID: Int = 0, usesCPSProducer: Bool = false) {
        self.fnPtr = fnPtr
        self.closureRaw = closureRaw
        self.functionID = functionID
        self.usesCPSProducer = usesCPSProducer
    }

    func freshIterator() -> RuntimeSequenceCoroutine {
        RuntimeSequenceCoroutine(fnPtr: fnPtr, closureRaw: closureRaw, functionID: functionID, usesCPSProducer: usesCPSProducer)
    }

    /// Called by the producer to yield a value.
    func yieldValue(_ value: Int) -> Int {
        stateLock.lock()
        guard failure == 0 else {
            stateLock.unlock()
            return 0
        }
        pendingYieldedValues.append(value)
        stateLock.unlock()

        consumerGate.signal()
        if usesCPSProducer {
            return Int(bitPattern: kk_coroutine_suspended())
        }
        producerGate.wait()
        return 0
    }

    /// Delegates to an iterator and suspends the producer until the consumer
    /// has pulled every element from it.
    func yieldAll(_ iterator: Int, outThrown: UnsafeMutablePointer<Int>? = nil) -> Int {
        var thrown = 0
        let hasNext = kk_iterator_hasNext(iterator, &thrown)
        if thrown != 0 {
            // Before delegation begins, this probe still belongs to the
            // producer's catch scope. The consumer owns later failures.
            outThrown?.pointee = thrown
            return 0
        }
        guard hasNext != 0 else { return 0 }

        stateLock.lock()
        delegatedIterator = iterator
        delegatedIteratorReady = true
        delegatedThrownPointer = usesCPSProducer ? nil : outThrown
        stateLock.unlock()

        consumerGate.signal()
        if usesCPSProducer {
            return Int(bitPattern: kk_coroutine_suspended())
        }
        producerGate.wait()
        stateLock.lock()
        let delegatedFailure = failure
        delegatedThrownPointer = nil
        stateLock.unlock()
        if delegatedFailure != 0 {
            outThrown?.pointee = delegatedFailure
        }
        return 0
    }

    /// Called by the producer when it finishes (normally or via exception).
    func markFinished(thrown: Int = 0) {
        stateLock.lock()
        if failure == 0 { failure = thrown }
        finished = true
        stateLock.unlock()
        consumerGate.signal()
    }

    /// Preserve the first failure for the sequence consumer and a blocked
    /// legacy producer waiting to return from yieldAll.
    func recordFailure(_ thrown: Int) {
        stateLock.lock()
        if failure == 0 { failure = thrown }
        stateLock.unlock()
    }

    private func consumePendingValueLocked() -> Int? {
        guard !pendingYieldedValues.isEmpty else {
            return nil
        }
        return pendingYieldedValues.removeFirst()
    }

    /// Pulls one value from the active delegate. A nil result means the
    /// delegate is exhausted and the producer can resume after yieldAll.
    private func nextDelegatedElement(
        _ iterator: Int,
        outThrown: UnsafeMutablePointer<Int>?
    ) -> NextResult? {
        stateLock.lock()
        let alreadyReady = delegatedIterator == iterator && delegatedIteratorReady
        if alreadyReady { delegatedIteratorReady = false }
        stateLock.unlock()

        var thrown = 0
        let hasNext = alreadyReady ? 1 : kk_iterator_hasNext(iterator, &thrown)
        let value = hasNext != 0 && thrown == 0
            ? kk_iterator_next(iterator, &thrown)
            : 0

        if thrown != 0 {
            stateLock.lock()
            if failure == 0 { failure = thrown }
            let producerThrownPointer = delegatedThrownPointer
            delegatedThrownPointer = nil
            stateLock.unlock()
            outThrown?.pointee = thrown
            producerThrownPointer?.pointee = thrown
            if !usesCPSProducer { producerGate.signal() }
            return .done
        }
        guard hasNext != 0 else {
            stateLock.lock()
            if delegatedIterator == iterator { delegatedIterator = 0 }
            stateLock.unlock()
            return nil
        }

        stateLock.lock()
        materializedElements.append(value)
        consumptionIndex += 1
        stateLock.unlock()
        return .value(value)
    }

    /// Consumer side: advance the producer one step and block until it yields or finishes.
    private func awaitProducerYield() {
        requestProducerStep()
        consumerGate.wait()
    }

    /// Non-blocking variant for coroutine callers (CORO-004 Phase 2).
    ///
    /// Signals the producer and installs `callerState` as a resume continuation
    /// in `consumerGate`.  When the producer yields or finishes, the continuation
    /// fires on a GCD thread: it reads the yielded value (or done flag), caches
    /// the element, and resumes `callerState` with either the element value or
    /// `kk_sequence_completed_sentinel()`.  Returns `true` when the caller must
    /// propagate COROUTINE_SUSPENDED; `false` when the result was already
    /// available and the blocking path has completed.
    private func awaitProducerYieldAsync(callerState: RuntimeContinuationState) -> Bool {
        requestProducerStep()
        let coroutine = self
        let didSuspend = consumerGate.wait(resumeContinuation: {
            guard let result = coroutine.nextElementAsync(callerState: callerState) else {
                return
            }
            switch result {
            case let .value(value):
                callerState.resume(with: value)
            case .done:
                let doneSentinel = Int(bitPattern:
                    UnsafeMutableRawPointer(
                        Unmanaged.passUnretained(runtimeStorage.sequenceCompletedBox).toOpaque()
                    )
                )
                callerState.resume(with: doneSentinel)
            }
        })
        return didSuspend
    }

    /// Invokes the legacy non-CPS builder lambda on its producer thread.
    private func invokeBuilderLambda() {
        var thrown = 0
        let fn = unsafeBitCast(
            fnPtr,
            to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        _ = fn(closureRaw, builderHandle, &thrown)

        markFinished(thrown: thrown)
    }

    /// Result type for `nextElement()`: either a value or end-of-sequence.
    enum NextResult {
        case value(Int)
        case done
    }

    /// Request the next element from the coroutine, one at a time.
    ///
    /// If there are already-materialized elements beyond the current
    /// consumption index, return the cached element. Otherwise, resume the
    /// producer to compute the next value.
    ///
    /// Returns `.done` when the producer has finished and all cached
    /// elements have been consumed.
    private var consumptionIndex: Int = 0

    func nextElement(outThrown: UnsafeMutablePointer<Int>? = nil) -> NextResult {
        while true {
            stateLock.lock()
            if failure != 0 {
                outThrown?.pointee = failure
                stateLock.unlock()
                return .done
            }
            if consumptionIndex < materializedElements.count {
                let elem = materializedElements[consumptionIndex]
                consumptionIndex += 1
                stateLock.unlock()
                return .value(elem)
            }
            if let value = consumePendingValueLocked() {
                materializedElements.append(value)
                consumptionIndex += 1
                stateLock.unlock()
                return .value(value)
            }
            let delegate = delegatedIterator
            if delegate == 0 {
                if fullyMaterialized {
                    stateLock.unlock()
                    return .done
                }
                if finished {
                    fullyMaterialized = true
                    stateLock.unlock()
                    return .done
                }
            }
            stateLock.unlock()

            if delegate != 0 {
                if let result = nextDelegatedElement(delegate, outThrown: outThrown) {
                    return result
                }
                continue
            }

            awaitProducerYield()
        }
    }

    /// Suspension-aware element request for coroutine callers (CORO-004 Phase 2).
    ///
    /// Like `nextElement()` but uses `awaitProducerYieldAsync` so the calling
    /// GCD thread is not held while the producer computes the next element.
    ///
    /// Return convention:
    ///   - `nil`           — the coroutine was suspended; `callerState` will be
    ///                       resumed with the element value or with
    ///                       `kk_sequence_completed_sentinel()` when done.
    ///   - `.value(elem)`  — result was immediately available (cache hit).
    ///   - `.done`         — sequence already fully materialised.
    func nextElementAsync(callerState: RuntimeContinuationState) -> NextResult? {
        while true {
            stateLock.lock()
            if failure != 0 {
                stateLock.unlock()
                return .done
            }
            if consumptionIndex < materializedElements.count {
                let elem = materializedElements[consumptionIndex]
                consumptionIndex += 1
                stateLock.unlock()
                return .value(elem)
            }
            if let value = consumePendingValueLocked() {
                materializedElements.append(value)
                consumptionIndex += 1
                stateLock.unlock()
                return .value(value)
            }
            let delegate = delegatedIterator
            if delegate == 0 {
                if fullyMaterialized {
                    stateLock.unlock()
                    return .done
                }
                if finished {
                    fullyMaterialized = true
                    stateLock.unlock()
                    return .done
                }
            }
            stateLock.unlock()

            if delegate != 0 {
                if let result = nextDelegatedElement(delegate, outThrown: nil) {
                    return result
                }
                continue
            }

            if awaitProducerYieldAsync(callerState: callerState) {
                return nil
            }
            // A signal arrived before the continuation was installed. Recheck
            // producer, delegate, and cache state synchronously.
        }
    }


    /// Materialize all elements from the coroutine and return them.
    func materializeAll() -> [Int] {
        stateLock.lock()
        if fullyMaterialized {
            let elems = materializedElements
            stateLock.unlock()
            return elems
        }
        stateLock.unlock()

        while true {
            stateLock.lock()
            if let value = consumePendingValueLocked() {
                materializedElements.append(value)
                stateLock.unlock()
                continue
            }
            if finished {
                fullyMaterialized = true
                let elems = materializedElements
                stateLock.unlock()
                return elems
            }
            stateLock.unlock()

            awaitProducerYield()

            stateLock.lock()
            if let value = consumePendingValueLocked() {
                materializedElements.append(value)
                stateLock.unlock()
                continue
            }
            if finished {
                fullyMaterialized = true
                let elems = materializedElements
                stateLock.unlock()
                return elems
            }
            stateLock.unlock()
        }
    }

    private func requestProducerStep() {
        ensureStarted()
        if !usesCPSProducer {
            producerGate.signal()
            return
        }

        stateLock.lock()
        if finished {
            stateLock.unlock()
            return
        }
        let isFirstStep = !cpsLoopStarted
        cpsLoopStarted = true
        let continuation = producerContinuationRaw
        stateLock.unlock()

        if isFirstStep {
            let coroutine = self
            _ = runSuspendEntryLoopWithContinuation(
                entryPointRaw: fnPtr,
                continuation: continuation,
                onCompletion: { _, thrown in
                    coroutine.markFinished(thrown: thrown)
                }
            )
            return
        }

        guard let state = runtimeContinuationState(from: continuation) else {
            markFinished()
            return
        }
        if let doubleResume = state.resume(with: 0) {
            state.deliverDoubleResumeException(doubleResume)
        }
    }

    /// Initialize the producer. Compiler-generated CPS builders do not start a
    /// thread; legacy non-CPS callbacks keep the old dedicated-thread fallback.
    private func ensureStarted() {
        stateLock.lock()
        guard !started else {
            stateLock.unlock()
            return
        }
        started = true
        stateLock.unlock()

        let coroutine = self
        // builderHandle is written before the thread starts, so no lock needed:
        // Thread.detachNewThread provides the happens-before edge the reader relies on.
        coroutine.builderHandle = registerRuntimeObject(
            RuntimeSequenceCoroutineBuilderProxy(coroutine: coroutine)
        )

        if usesCPSProducer {
            let continuation = kk_coroutine_continuation_new(functionID)
            _ = kk_coroutine_launcher_arg_set(continuation, 0, Int64(closureRaw))
            _ = kk_coroutine_launcher_arg_set(continuation, 1, Int64(coroutine.builderHandle))
            stateLock.lock()
            producerContinuationRaw = continuation
            stateLock.unlock()
            return
        }

        Thread.detachNewThread {
            // Wait for the first consumer request before running the lambda.
            coroutine.producerGate.wait()
            coroutine.invokeBuilderLambda()
        }
    }
}

/// Proxy object passed to the builder lambda as the "builder" handle.
/// When `__kk_sequence_builder_yield` receives this handle, it delegates to the
/// coroutine's `yieldValue()`, returning COROUTINE_SUSPENDED for CPS producers
/// or blocking only for legacy non-CPS producers.
final class RuntimeSequenceCoroutineBuilderProxy {
    let coroutine: RuntimeSequenceCoroutine

    init(coroutine: RuntimeSequenceCoroutine) {
        self.coroutine = coroutine
    }
}

// Runtime box for the `iterator { yield(x) }` builder (STDLIB-331/564).
//
// Implements lazy iteration using a cooperative producer-consumer pattern.
// Compiler-generated builders use the CPS producer path, where yield() returns
// COROUTINE_SUSPENDED and the consumer resumes the stored continuation. Legacy
// direct ABI callers keep the thread-backed path for non-CPS callbacks.
//
// Protocol:
//   1. `__kk_iterator_builder_build_coro(entryPointRaw, functionID, closureRaw)`
//      creates the CPS box for compiler-generated builders.
//   2. First `hasNext` / `next` call starts the suspend-entry loop.
//   3. Producer yield(value) transitions to .hasValue, signals consumer, and
//      returns COROUTINE_SUSPENDED. The next consumer request resumes it.
//   4. On completion: transitions to .done, signals consumer.
//
// DEBT-CORO-002: compiler-generated producers no longer occupy a dedicated
// thread. Legacy `__kk_iterator_builder_build(fnPtr)` callbacks keep the old
// dedicated-thread fallback.
//
// CORO-004 Phase 2 (consumer suspension, IN PROGRESS):
//   probeHasNextAsync(callerState:) wires consumerGate to a resume continuation
//   so the calling GCD thread is released immediately.  C entry points
//   __kk_iterator_builder_hasNext_coro / __kk_iterator_builder_next_coro expose
//   this for future coroutine-aware compiler output.  Existing entry points
//   (__kk_iterator_builder_hasNext / _next) remain unchanged.
//
// CORO-004 Phase 3: CPS-transformed iterator builder lambdas call yield() as a
// real suspend point, so compiler-generated producers no longer need a
// dedicated thread. The legacy thread path remains only for pre-CPS callbacks.
final class RuntimeIteratorBuilderBox: @unchecked Sendable {
    private let fnPtr: Int
    private let closureRaw: Int
    private let functionID: Int
    private let usesCPSProducer: Bool
    private var builderHandle: Int = 0

    /// Producer suspend gate — signalled by the consumer (`hasNext` / `next`).
    private let producerGate = RuntimeCoroutineSyncGate()
    /// Consumer suspend gate — signalled by the producer (`yield` or completion).
    private let consumerGate = RuntimeCoroutineSyncGate()
    private let stateLock = NSLock()
    private var started = false
    private var cpsLoopStarted = false
    private var producerContinuationRaw: Int = 0
    private var delegatedIterator: Int = 0
    private var failure: Int = 0
    private var failureReported = false

    /// The most recently yielded value, valid when `state == .hasValue`.
    private(set) var yieldedValue: Int = 0
    /// Current state of the iterator.
    private(set) var state: IteratorState = .initial

    enum IteratorState {
        /// Producer has not yet been advanced.
        case initial
        /// Producer yielded a value; `yieldedValue` is valid.
        case hasValue
        case delegating
        case delegateReady
        /// Producer finished (lambda returned).
        case done
    }

    init(fnPtr: Int, closureRaw: Int = 0, functionID: Int = 0, usesCPSProducer: Bool = false) {
        self.fnPtr = fnPtr
        self.closureRaw = closureRaw
        self.functionID = functionID
        self.usesCPSProducer = usesCPSProducer
    }

    func bindRegisteredHandle(_ handle: Int) {
        builderHandle = handle
    }

    func yieldValue(_ value: Int) -> Int {
        stateLock.lock()
        yieldedValue = value
        state = .hasValue
        stateLock.unlock()

        consumerGate.signal()
        if usesCPSProducer {
            return Int(bitPattern: kk_coroutine_suspended())
        }
        producerGate.wait()
        return 0
    }

    /// Probe once in the producer's catch scope, then suspend until the consumer
    /// has exhausted the delegate. Never loop over CPS yieldValue calls here.
    func yieldAll(_ iterator: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        var thrown = 0
        let hasNext = kk_iterator_hasNext(iterator, &thrown)
        outThrown?.pointee = thrown
        if thrown != 0 || hasNext == 0 { return 0 }
        stateLock.lock()
        delegatedIterator = iterator
        state = .delegateReady
        stateLock.unlock()
        consumerGate.signal()
        if usesCPSProducer { return Int(bitPattern: kk_coroutine_suspended()) }
        producerGate.wait()
        return 0
    }

    func probeHasNext(outThrown: UnsafeMutablePointer<Int>? = nil) -> Bool {
        outThrown?.pointee = 0
        while true {
            stateLock.lock()
            let current = state
            let delegate = delegatedIterator
            stateLock.unlock()

            switch current {
            case .hasValue, .delegateReady:
                return true
            case .done:
                stateLock.lock()
                let thrown = failureForProbeLocked()
                stateLock.unlock()
                outThrown?.pointee = thrown
                return false
            case .delegating:
                var thrown = 0
                let hasNext = kk_iterator_hasNext(delegate, &thrown)
                if thrown != 0 {
                    // Keep the delegate for retry, as Kotlin's ManyNotReady does.
                    runtimePropagateThrownOrTrap(thrown, outThrown: outThrown, context: #function)
                    return false
                }
                stateLock.lock()
                state = hasNext != 0 ? .delegateReady : .initial
                if hasNext == 0 { delegatedIterator = 0 }
                stateLock.unlock()
                if hasNext != 0 { return true }
                // The next producer step resumes after yieldAll, exactly once.
                awaitProducerYield()
            case .initial:
                awaitProducerYield()
            }
        }
    }

    private func failureForProbeLocked() -> Int {
        guard failure != 0 else { return 0 }
        if failureReported {
            return runtimeAllocateIllegalStateException(message: "Iterator has failed.")
        }
        failureReported = true
        return failure
    }

    func consumeNext(outThrown: UnsafeMutablePointer<Int>? = nil) -> Int {
        guard probeHasNext(outThrown: outThrown) else {
            if (outThrown?.pointee ?? 0) != 0 { return 0 }
            return runtimeThrowIteratorExhausted(outThrown)
        }
        stateLock.lock()
        let current = state
        stateLock.unlock()

        if current == .delegateReady {
            stateLock.lock()
            let delegate = delegatedIterator
            state = .delegating
            stateLock.unlock()
            var thrown = 0
            let value = kk_iterator_next(delegate, &thrown)
            if thrown != 0 {
                runtimePropagateThrownOrTrap(thrown, outThrown: outThrown, context: #function)
                return 0
            }
            return value
        }

        stateLock.lock()
        guard state == .hasValue else {
            stateLock.unlock()
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: NoSuchElementException: Iterator has no more elements.")
        }
        let value = yieldedValue
        state = .initial
        stateLock.unlock()
        return value
    }

    private func awaitProducerYield() {
        requestProducerStep()
        consumerGate.wait()
    }

    /// Suspension-aware hasNext for coroutine callers (CORO-004 Phase 2).
    ///
    /// When state is already known (`.hasValue` / `.done`), returns 1 / 0
    /// synchronously without touching any gate.  When state is `.initial`,
    /// signals the producer and installs `callerState` as a resume continuation
    /// in `consumerGate`.  On producer yield the continuation fires on a GCD
    /// thread: it reads the new state and calls `callerState.resume(with: 1/0)`.
    ///
    /// Returns 1 (hasNext), 0 (done), or `Int(bitPattern: kk_coroutine_suspended())`
    /// when the caller must propagate COROUTINE_SUSPENDED up the call stack.
    /// The `__kk_iterator_builder_hasNext_coro` C entry point wraps this method.
    func probeHasNextAsync(callerState: RuntimeContinuationState) -> Int {
        stateLock.lock()
        let current = state
        stateLock.unlock()

        switch current {
        case .hasValue, .delegateReady:
            return 1
        case .delegating:
            return probeHasNext() ? 1 : 0
        case .done:
            return 0
        case .initial:
            let box = self
            requestProducerStep()
            let didSuspend = consumerGate.wait(resumeContinuation: {
                callerState.resume(with: box.probeHasNext() ? 1 : 0)
            })
            if didSuspend {
                return Int(bitPattern: kk_coroutine_suspended())
            }
            // Signal was pending before the continuation could be installed —
            // the producer already yielded, read the result directly.
            return probeHasNext() ? 1 : 0
        }
    }

    /// Invokes the legacy non-CPS builder lambda on its producer thread.
    private func invokeBuilderLambda() {
        var thrown = 0
        _ = runtimeInvokeClosureThunk(
            fnPtr: fnPtr,
            closureRaw: builderHandle,
            outThrown: &thrown
        )
        stateLock.lock()
        failure = thrown
        state = .done
        stateLock.unlock()
        consumerGate.signal()
    }

    private func requestProducerStep() {
        ensureStarted()
        if !usesCPSProducer {
            producerGate.signal()
            return
        }

        stateLock.lock()
        if state == .done {
            stateLock.unlock()
            return
        }
        let isFirstStep = !cpsLoopStarted
        cpsLoopStarted = true
        let continuation = producerContinuationRaw
        stateLock.unlock()

        if isFirstStep {
            let box = self
            _ = runSuspendEntryLoopWithContinuation(
                entryPointRaw: fnPtr,
                continuation: continuation,
                onCompletion: { _, thrown in
                    box.stateLock.lock()
                    box.failure = thrown
                    box.state = .done
                    box.stateLock.unlock()
                    box.consumerGate.signal()
                }
            )
            return
        }

        guard let state = runtimeContinuationState(from: continuation) else {
            stateLock.lock()
            self.state = .done
            stateLock.unlock()
            consumerGate.signal()
            return
        }
        if let doubleResume = state.resume(with: 0) {
            state.deliverDoubleResumeException(doubleResume)
        }
    }

    /// Initialize the producer. Compiler-generated CPS builders do not start a
    /// thread; legacy non-CPS callbacks keep the old dedicated-thread fallback.
    private func ensureStarted() {
        stateLock.lock()
        guard !started else {
            stateLock.unlock()
            return
        }
        started = true
        stateLock.unlock()

        if usesCPSProducer {
            let continuation = kk_coroutine_continuation_new(functionID)
            // Suspend-entry launcher ABI is (closureRaw, receiver): the launcher
            // thunk binds slot 0 to the builder lambda's closure environment and
            // slot 1 to the SequenceScope receiver, matching
            // RuntimeSequenceCoroutine and runtimeInvokeSuspendFunction.
            _ = kk_coroutine_launcher_arg_set(continuation, 0, Int64(closureRaw))
            _ = kk_coroutine_launcher_arg_set(continuation, 1, Int64(builderHandle))
            stateLock.lock()
            producerContinuationRaw = continuation
            stateLock.unlock()
            return
        }

        let box = self
        Thread.detachNewThread {
            // Wait for the first consumer signal before running the lambda.
            box.producerGate.wait()
            box.invokeBuilderLambda()
        }
    }
}
