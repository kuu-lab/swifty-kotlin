import Foundation

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
    case nullableGenerator(fnPtr: Int, closureRaw: Int)
    case dropStep(count: Int)
    case distinctStep
    case distinctByStep(fnPtr: Int, closureRaw: Int)
    case takeWhileStep(fnPtr: Int, closureRaw: Int)
    case dropWhileStep(fnPtr: Int, closureRaw: Int)
    case onEachStep(fnPtr: Int, closureRaw: Int)
    case onEachIndexedStep(fnPtr: Int, closureRaw: Int)
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
    case shuffledStep(randomRaw: Int?)
    case lazyBuilder(coroutine: RuntimeSequenceCoroutine)
    case pullSource(produce: () -> Int?)
}

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

final class RuntimeSequenceBuilderBox {
    var elements: [Int] = []
}

final class RuntimeSequenceCoroutine: @unchecked Sendable {
    let fnPtr: Int
    let closureRaw: Int
    private let functionID: Int
    private let usesCPSProducer: Bool

    private let producerGate = RuntimeCoroutineSyncGate()

    private let consumerGate = RuntimeCoroutineSyncGate()

    private let stateLock = NSLock()

    private var pendingYieldedValues: [Int] = []

    private var delegatedIterator: Int = 0
    private var delegatedIteratorReady = false
    private var delegatedThrownPointer: UnsafeMutablePointer<Int>?

    private var finished = false
    private var failure: Int = 0

    private var started = false

    private var cpsLoopStarted = false

    private var producerContinuationRaw: Int = 0

    private var materializedElements: [Int] = []

    private var fullyMaterialized = false

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

    func yieldAll(_ iterator: Int, outThrown: UnsafeMutablePointer<Int>? = nil) -> Int {
        var thrown = 0
        let hasNext = kk_iterator_hasNext(iterator, &thrown)
        if thrown != 0 {
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

    func markFinished(thrown: Int = 0) {
        stateLock.lock()
        if failure == 0 { failure = thrown }
        finished = true
        stateLock.unlock()
        consumerGate.signal()
    }

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

    private func awaitProducerYield() {
        requestProducerStep()
        consumerGate.wait()
    }

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

    private func invokeBuilderLambda() {
        var thrown = 0
        let fn = unsafeBitCast(
            fnPtr,
            to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        _ = fn(closureRaw, builderHandle, &thrown)

        markFinished(thrown: thrown)
    }

    enum NextResult {
        case value(Int)
        case done
    }

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
                onCompletion: { _, thrown, _ in
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

    private func ensureStarted() {
        stateLock.lock()
        guard !started else {
            stateLock.unlock()
            return
        }
        started = true
        stateLock.unlock()

        let coroutine = self
        coroutine.builderHandle = registerRuntimeObject(
            RuntimeSequenceCoroutineBuilderProxy(coroutine: coroutine)
        )

        if usesCPSProducer {
            let continuation = kk_coroutine_continuation_new(functionID)
            // A lazy builder producer has no dispatcher, scheduler, or event
            // loop of its own: each consumer request resumes it on the global
            // queue, paying a cross-thread handoff plus a semaphore wait for
            // every element. Driving the resume inline on the consumer thread
            // matches the restricted-builder contract (the first CPS step
            // already runs synchronously in requestProducerStep) and leaves
            // consumerGate pre-signalled before wait() runs.
            runtimeContinuationState(from: continuation)?.resumesInline = true
            _ = kk_coroutine_launcher_arg_set(continuation, 0, Int64(closureRaw))
            _ = kk_coroutine_launcher_arg_set(continuation, 1, Int64(coroutine.builderHandle))
            stateLock.lock()
            producerContinuationRaw = continuation
            stateLock.unlock()
            return
        }

        Thread.detachNewThread {
            coroutine.producerGate.wait()
            coroutine.invokeBuilderLambda()
        }
    }
}

final class RuntimeSequenceCoroutineBuilderProxy {
    let coroutine: RuntimeSequenceCoroutine

    init(coroutine: RuntimeSequenceCoroutine) {
        self.coroutine = coroutine
    }
}

final class RuntimeIteratorBuilderBox: @unchecked Sendable {
    private let fnPtr: Int
    private let closureRaw: Int
    private let functionID: Int
    private let usesCPSProducer: Bool
    private var builderHandle: Int = 0

    private let producerGate = RuntimeCoroutineSyncGate()
    private let consumerGate = RuntimeCoroutineSyncGate()
    private let stateLock = NSLock()
    private var started = false
    private var cpsLoopStarted = false
    private var producerContinuationRaw: Int = 0
    private var delegatedIterator: Int = 0
    private var failure: Int = 0
    private var failureReported = false

    private(set) var yieldedValue: Int = 0
    private(set) var state: IteratorState = .initial

    enum IteratorState {
        case initial
        case hasValue
        case delegating
        case delegateReady
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
                    runtimePropagateThrownOrTrap(thrown, outThrown: outThrown, context: #function)
                    return false
                }
                stateLock.lock()
                state = hasNext != 0 ? .delegateReady : .initial
                if hasNext == 0 { delegatedIterator = 0 }
                stateLock.unlock()
                if hasNext != 0 { return true }
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
            return probeHasNext() ? 1 : 0
        }
    }

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
                onCompletion: { _, thrown, _ in
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
            runtimeContinuationState(from: continuation)?.resumesInline = true
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
            box.producerGate.wait()
            box.invokeBuilderLambda()
        }
    }
}
