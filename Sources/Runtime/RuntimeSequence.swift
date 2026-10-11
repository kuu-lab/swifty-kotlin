// MARK: - Sequence Functions (STDLIB-003)

func runtimeSequenceBox(from rawValue: Int) -> RuntimeSequenceBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeSequenceBox.self)
}

func runtimeSequenceBuilderBox(from rawValue: Int) -> RuntimeSequenceBuilderBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeSequenceBuilderBox.self)
}

private let runtimeSequenceInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.sequences.Sequence")
private let runtimeIteratorInterfaceTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.collections.Iterator")

/// Runtime box that pulls lazy sources on demand and materializes other sources
/// on first use. This lets source-implemented `Sequence<T>` and
/// `Iterator<T>` wrappers chain with runtime-backed lazy sequences through the
/// normal `Sequence`/`Iterator` itable dispatch path.
final class RuntimeSequenceIteratorBox {
    let seq: RuntimeSequenceBox
    fileprivate var elements: [Int] = []
    fileprivate var index: Int = 0
    fileprivate var materialized: Bool = false
    fileprivate var pullCursor: RuntimeSequencePullIteratorCursor?

    init(seq: RuntimeSequenceBox) {
        self.seq = seq
        if let firstStep = seq.steps.first {
            switch firstStep {
            case let .generator(seed, fnPtr, closureRaw):
                pullCursor = RuntimeSequencePullIteratorCursor(
                    seq: seq,
                    source: .seeded(seed: seed, fnPtr: fnPtr, closureRaw: closureRaw)
                )
            case let .nullableGenerator(fnPtr, closureRaw):
                pullCursor = RuntimeSequencePullIteratorCursor(
                    seq: seq,
                    source: .nullable(fnPtr: fnPtr, closureRaw: closureRaw)
                )
            case let .lazyBuilder(coroutine):
                pullCursor = RuntimeSequencePullIteratorCursor(
                    seq: seq,
                    source: .builder(coroutine.freshIterator())
                )
            default:
                break
            }
        }
    }

    func materialize(outThrown: UnsafeMutablePointer<Int>?) {
        guard !materialized else { return }
        guard pullCursor == nil else { return }
        elements = evaluateSequence(seq, outThrown: outThrown, markConsumption: true)
        materialized = true
    }

    func hasNext(outThrown: UnsafeMutablePointer<Int>?) -> Bool {
        if let pullCursor {
            return pullCursor.hasNext(outThrown: outThrown)
        }
        materialize(outThrown: outThrown)
        return index < elements.count
    }

    func next(outThrown: UnsafeMutablePointer<Int>?) -> Int {
        if let pullCursor {
            return pullCursor.next(outThrown: outThrown)
        }
        materialize(outThrown: outThrown)
        if (outThrown?.pointee ?? 0) != 0 { return 0 }
        guard index < elements.count else { return runtimeThrowIteratorExhausted(outThrown) }
        let value = elements[index]
        index += 1
        return value
    }
}

/// Pulls generator and builder elements on demand for Iterator.hasNext()/next().
/// Transforms are applied before another source element is requested.
fileprivate final class RuntimeSequencePullIteratorCursor {
    fileprivate enum Source {
        case seeded(seed: Int, fnPtr: Int, closureRaw: Int)
        case nullable(fnPtr: Int, closureRaw: Int)
        case builder(RuntimeSequenceCoroutine)
    }

    private let seq: RuntimeSequenceBox
    private let source: Source
    private let transformSteps: [SequenceStepKind]
    private let state = SequenceTraversalState()
    private var seededPending = true
    private var current: Int?
    private var bufferedElements: [Int] = []
    private var bufferedIndex = 0
    private var exhausted = false
    private var builderFailed = false
    private var started = false

    init(seq: RuntimeSequenceBox, source: Source) {
        self.seq = seq
        self.source = source
        transformSteps = seq.steps.filter {
            switch $0 {
            case .source, .valueSource, .stringSource, .builder, .generator, .nullableGenerator, .lazyBuilder, .pullSource:
                false
            default:
                true
            }
        }
    }

    func hasNext(outThrown: UnsafeMutablePointer<Int>?) -> Bool {
        if builderFailed {
            outThrown?.pointee = runtimeAllocateIllegalStateException(message: "Iterator has failed.")
            return false
        }
        if bufferedIndex < bufferedElements.count { return true }
        guard !exhausted else { return false }
        if !started {
            started = true
            guard runtimeSequenceBeginTraversal(seq, outThrown: outThrown) else {
                exhausted = true
                return false
            }
        }

        while bufferedIndex >= bufferedElements.count, !exhausted, !state.stop {
            bufferedElements.removeAll(keepingCapacity: true)
            bufferedIndex = 0
            guard let element = nextSourceElement(outThrown: outThrown) else {
                if (outThrown?.pointee ?? 0) != 0 { return false }
                exhausted = true
                runtimeSequenceFlushChunkedTransforms(
                    transformSteps,
                    state: state,
                    outThrown: outThrown,
                    yield: { [weak self] value in
                        self?.bufferedElements.append(value)
                        return true
                    }
                )
                break
            }
            runtimeSequenceTransformElement(
                element,
                steps: transformSteps,
                stepIndex: 0,
                state: state,
                outThrown: outThrown,
                yield: { [weak self] value in
                    self?.bufferedElements.append(value)
                    return true
                }
            )
            if (outThrown?.pointee ?? 0) != 0 {
                exhausted = true
                return false
            }
        }
        return bufferedIndex < bufferedElements.count
    }

    func next(outThrown: UnsafeMutablePointer<Int>?) -> Int {
        let hasElement = hasNext(outThrown: outThrown)
        if (outThrown?.pointee ?? 0) != 0 { return 0 }
        guard hasElement, bufferedIndex < bufferedElements.count else {
            return runtimeThrowIteratorExhausted(outThrown)
        }
        let value = bufferedElements[bufferedIndex]
        bufferedIndex += 1
        return value
    }

    private func nextSourceElement(outThrown: UnsafeMutablePointer<Int>?) -> Int? {
        switch source {
        case let .builder(coroutine):
            var thrown = 0
            let next = coroutine.nextElement(outThrown: &thrown)
            if thrown != 0 {
                builderFailed = true
                outThrown?.pointee = thrown
                return nil
            }
            switch next {
            case let .value(value): return value
            case .done: return nil
            }
        case let .seeded(seed, fnPtr, closureRaw):
            if seededPending {
                seededPending = false
                current = seed
                return seed
            }
            guard let previous = current else {
                exhausted = true
                return nil
            }
            let nextFn = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
            var thrown = 0
            let nextValue = nextFn(closureRaw, previous, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return nil
            }
            guard nextValue != runtimeNullSentinelInt else {
                exhausted = true
                return nil
            }
            current = nextValue
            return nextValue
        case let .nullable(fnPtr, closureRaw):
            let nextFn = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
            var thrown = 0
            let nextValue = nextFn(closureRaw, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                return nil
            }
            guard nextValue != runtimeNullSentinelInt else {
                exhausted = true
                return nil
            }
            return nextValue
        }
    }
}

func runtimeSequenceIteratorBox(from rawValue: Int) -> RuntimeSequenceIteratorBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeSequenceIteratorBox.self)
}


/// Dispatches an `Iterator` method on a source-implemented `Iterator` object by
/// looking up the `kotlin.collections.Iterator` itable dynamically.
private func runtimeIteratorMethodCall(
    _ iterRaw: Int,
    methodSlot: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let fnPtr = kk_itable_lookup_dynamic(iterRaw, Int(runtimeIteratorInterfaceTypeID), methodSlot)
    guard fnPtr != 0 else {
        return 0
    }
    let fn = unsafeBitCast(
        fnPtr,
        to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    return fn(iterRaw, outThrown)
}

/// Iterates a source-implemented `Sequence` object (created by Kotlin `object`
/// expressions implementing `kotlin.sequences.Sequence`) by dispatching through
/// the Sequence itable to obtain an `Iterator`, then driving that iterator with
/// the `Iterator` itable directly so thrown exceptions can be propagated.
/// Returns `true` if `rawValue` is a source `Sequence` and was iterated (or an
/// exception was recorded in `outThrown`). Returns `false` if it is not a source
/// `Sequence` so callers can fall back to runtime box handling.
func runtimeTraverseSourceSequenceObject(
    _ rawValue: Int,
    outThrown: UnsafeMutablePointer<Int>?,
    iterator: ((Int) -> Void)? = nil,
    yield: (Int) -> Bool
) -> Bool {
    let iteratorFnPtr = kk_itable_lookup_dynamic(rawValue, Int(runtimeSequenceInterfaceTypeID), 0)
    guard iteratorFnPtr != 0 else {
        return false
    }
    let iteratorFn = unsafeBitCast(
        iteratorFnPtr,
        to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
    )
    var thrown: Int = 0
    let iterRaw = iteratorFn(rawValue, &thrown)
    iterator?(iterRaw)
    if thrown != 0 {
        if let outThrown {
            outThrown.pointee = thrown
        } else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: source Sequence iterator() threw an exception")
        }
        return true
    }
    while true {
        var hasNextThrown: Int = 0
        let hasNext = runtimeIteratorMethodCall(iterRaw, methodSlot: 0, outThrown: &hasNextThrown)
        if hasNextThrown != 0 {
            if let outThrown {
                outThrown.pointee = hasNextThrown
            } else {
                fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: source Sequence Iterator.hasNext() threw an exception")
            }
            return true
        }
        if hasNext == 0 { break }
        var nextThrown: Int = 0
        let element = runtimeIteratorMethodCall(iterRaw, methodSlot: 1, outThrown: &nextThrown)
        if nextThrown != 0 {
            if let outThrown {
                outThrown.pointee = nextThrown
            } else {
                fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: source Sequence Iterator.next() threw an exception")
            }
            return true
        }
        if !yield(element) { break }
    }
    return true
}

private func runtimeObjectBox(from rawValue: Int) -> RuntimeObjectBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeObjectBox.self)
}

func runtimeArrayBoxExcludingObjects(from rawValue: Int) -> RuntimeArrayBox? {
    guard let array = runtimeArrayBox(from: rawValue),
          type(of: array) == RuntimeArrayBox.self
    else {
        return nil
    }
    return array
}

func runtimeSequenceSourceElements(from rawValue: Int) -> [Int]? {
    if let seq = runtimeSequenceBox(from: rawValue) {
        return evaluateSequence(seq)
    }
    if let list = runtimeListBox(from: rawValue) {
        return list.elements
    }
    if let set = runtimeSetBox(from: rawValue) {
        return set.elements
    }
    if runtimeObjectBox(from: rawValue) != nil {
        var elements: [Int] = []
        if runtimeTraverseSourceSequenceObject(rawValue, outThrown: nil, yield: { elem in
            elements.append(elem)
            return true
        }) {
            return elements
        }
        return nil
    }
    if let array = runtimeArrayBoxExcludingObjects(from: rawValue) {
        return array.elements
    }
    return nil
}

func runtimeSequenceSourceValues(from rawValue: Int) -> [RuntimeValue]? {
    if let seq = runtimeSequenceBox(from: rawValue) {
        return evaluateSequenceValues(seq)
    }
    if let list = runtimeListBox(from: rawValue) {
        return list.values
    }
    if let set = runtimeSetBox(from: rawValue) {
        return set.values
    }
    if runtimeObjectBox(from: rawValue) != nil {
        var values: [RuntimeValue] = []
        var iteratorRaw = 0
        if runtimeTraverseSourceSequenceObject(
            rawValue,
            outThrown: nil,
            iterator: { iteratorRaw = $0 },
            yield: { elem in
                values.append(runtimeSourceIteratorValue(elem, iteratorRaw: iteratorRaw))
                return true
            }
        ) {
            return values
        }
        return nil
    }
    if let array = runtimeArrayBoxExcludingObjects(from: rawValue) {
        return array.values
    }
    return nil
}

func runtimeSequenceSourceElementsOrThrow(
    from rawValue: Int,
    caller: StaticString,
    outThrown: UnsafeMutablePointer<Int>?
) -> [Int]? {
    if let seq = runtimeSequenceBox(from: rawValue) {
        let elements = evaluateSequence(seq, outThrown: outThrown)
        if let outThrown, outThrown.pointee != 0 {
            return nil
        }
        return elements
    }
    if let list = runtimeListBox(from: rawValue) {
        return list.elements
    }
    if let set = runtimeSetBox(from: rawValue) {
        return set.elements
    }
    if runtimeObjectBox(from: rawValue) != nil {
        var elements: [Int] = []
        if runtimeTraverseSourceSequenceObject(rawValue, outThrown: outThrown, yield: { elem in
            elements.append(elem)
            return true
        }) {
            return elements
        }
    }
    if let array = runtimeArrayBoxExcludingObjects(from: rawValue) {
        return array.elements
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid sequence handle")
}

func runtimeSequenceSourceValuesOrThrow(
    from rawValue: Int,
    caller: StaticString,
    outThrown: UnsafeMutablePointer<Int>?
) -> [RuntimeValue]? {
    if let seq = runtimeSequenceBox(from: rawValue) {
        let values = evaluateSequenceValues(seq, outThrown: outThrown)
        if let outThrown, outThrown.pointee != 0 {
            return nil
        }
        return values
    }
    if let list = runtimeListBox(from: rawValue) {
        return list.values
    }
    if let set = runtimeSetBox(from: rawValue) {
        return set.values
    }
    if runtimeObjectBox(from: rawValue) != nil {
        var values: [RuntimeValue] = []
        var iteratorRaw = 0
        if runtimeTraverseSourceSequenceObject(
            rawValue,
            outThrown: outThrown,
            iterator: { iteratorRaw = $0 },
            yield: { elem in
                values.append(runtimeSourceIteratorValue(elem, iteratorRaw: iteratorRaw))
                return true
            }
        ) {
            return values
        }
    }
    if let array = runtimeArrayBoxExcludingObjects(from: rawValue) {
        return array.values
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid sequence handle")
}

/// Fail-fast variant that panics on invalid handles instead of returning nil.
/// Use this instead of `runtimeSequenceSourceElements(from:) ?? []` to distinguish
/// invalid handles from legitimately empty sequences.
func runtimeSequenceSourceElementsOrPanic(from rawValue: Int, caller: StaticString) -> [Int] {
    if let elements = runtimeSequenceSourceElements(from: rawValue) {
        return elements
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid sequence handle")
}

func runtimeSequenceSourceValuesOrPanic(from rawValue: Int, caller: StaticString) -> [RuntimeValue] {
    if let values = runtimeSequenceSourceValues(from: rawValue) {
        return values
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid sequence handle")
}

final class SequenceTraversalState {
    var stop = false
    var stopByDownstream = false
    var takeCounts: [Int: Int] = [:]
    var dropCounts: [Int: Int] = [:]
    var distinctSeen: [Int: Set<RuntimeElementKey>] = [:]
    var distinctBySeen: [Int: Set<RuntimeElementKey>] = [:]
    var zipIndices: [Int: Int] = [:]
    var chunkedBuffers: [Int: [Int]] = [:]
}

// MARK: - Shared constants

/// Error message for `first()` / `last()` on an empty sequence.
let kEmptySequenceNoSuchElement = "Sequence is empty."
let kSequenceNoNonNullTransformResult = "No element of the sequence was transformed to a non-null value."
/// Error message for `reduce` on an empty sequence.
let kEmptySequenceCannotReduce = "Empty sequence can't be reduced."
private let kSequenceConstrainedOnceConsumed = "This sequence can be consumed only once."
/// Error message for `Sequence.requireNoNulls()` when a null element is encountered.
private let kSequenceRequireNoNullsFoundNull = "null element found in sequence."

private func runtimeSequenceBeginTraversal(
    _ seq: RuntimeSequenceBox,
    outThrown: UnsafeMutablePointer<Int>?
) -> Bool {
    guard let state = seq.constrainOnceState else {
        return true
    }
    if state.consumed {
        if let outThrown {
            outThrown.pointee = runtimeAllocateIllegalStateException(message: kSequenceConstrainedOnceConsumed)
            return false
        }
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: IllegalStateException: \(kSequenceConstrainedOnceConsumed)")
    }
    state.consumed = true
    return true
}

private func runtimeSequenceTransformElement(
    _ element: Int,
    steps: [SequenceStepKind],
    stepIndex: Int,
    state: SequenceTraversalState,
    outThrown: UnsafeMutablePointer<Int>?,
    yield: @escaping (Int) -> Bool
) {
    if state.stop { return }
    if stepIndex >= steps.count {
        state.stop = !yield(element)
        state.stopByDownstream = state.stop
        return
    }

    switch steps[stepIndex] {
    case let .mapStep(fnPtr, closureRaw):
        let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        let mapped = lambda(closureRaw, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        // Keep the transform's already-boxed result as-is.
        runtimeSequenceTransformElement(
            mapped,
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case let .filterStep(fnPtr, closureRaw):
        let predicate = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        let predicateResult = predicate(closureRaw, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        if runtimeCollectionBool(predicateResult) {
            runtimeSequenceTransformElement(
                element,
                steps: steps,
                stepIndex: stepIndex + 1,
                state: state,
                outThrown: outThrown,
                yield: yield
            )
        }
    case let .filterNotStep(fnPtr, closureRaw):
        let predicate = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        let predicateResult = predicate(closureRaw, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        if !runtimeCollectionBool(predicateResult) {
            runtimeSequenceTransformElement(
                element,
                steps: steps,
                stepIndex: stepIndex + 1,
                state: state,
                outThrown: outThrown,
                yield: yield
            )
        }
    case let .takeStep(count):
        let emitted = state.takeCounts[stepIndex, default: 0]
        if emitted >= count {
            state.stop = true
            return
        }
        runtimeSequenceTransformElement(
            element,
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: { value in
                let currentCount = state.takeCounts[stepIndex, default: 0]
                if currentCount >= count {
                    state.stop = true
                    return false
                }
                state.takeCounts[stepIndex] = currentCount + 1
                let shouldContinue = yield(value)
                if state.takeCounts[stepIndex, default: 0] >= count {
                    state.stop = true
                }
                return shouldContinue && !state.stop
            }
        )
    case let .dropStep(count):
        let skipped = state.dropCounts[stepIndex, default: 0]
        if skipped < count {
            state.dropCounts[stepIndex] = skipped + 1
            return
        }
        runtimeSequenceTransformElement(
            element,
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case .distinctStep:
        // Mutating through the dictionary subscript avoids a COW copy of the
        // stored set on every element.
        guard state.distinctSeen[stepIndex, default: []]
            .insert(RuntimeElementKey(value: element)).inserted
        else {
            return
        }
        runtimeSequenceTransformElement(
            element,
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case let .distinctByStep(fnPtr, closureRaw):
        let selector = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        let key = maybeUnbox(selector(closureRaw, element, &thrown))
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        guard state.distinctBySeen[stepIndex, default: []]
            .insert(RuntimeElementKey(value: key)).inserted
        else {
            return
        }
        runtimeSequenceTransformElement(
            element,
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case let .zipStep(otherElements):
        let index = state.zipIndices[stepIndex, default: 0]
        if index >= otherElements.count {
            state.stop = true
            return
        }
        state.zipIndices[stepIndex] = index + 1
        runtimeSequenceTransformElement(
            kk_pair_new(element, otherElements[index]),
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case let .takeWhileStep(fnPtr, closureRaw):
        let predicate = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        let predicateResult = predicate(closureRaw, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        if maybeUnbox(predicateResult) != 0 {
            runtimeSequenceTransformElement(
                element,
                steps: steps,
                stepIndex: stepIndex + 1,
                state: state,
                outThrown: outThrown,
                yield: yield
            )
        } else {
            state.stop = true
        }
    case let .dropWhileStep(fnPtr, closureRaw):
        let dropping = state.dropCounts[stepIndex, default: 1] != 0
        if dropping {
            let predicate = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
            var thrown = 0
            let predicateResult = predicate(closureRaw, element, &thrown)
            if thrown != 0 {
                outThrown?.pointee = thrown
                state.stop = true
                return
            }
            if maybeUnbox(predicateResult) == 0 {
                state.dropCounts[stepIndex] = 0
                runtimeSequenceTransformElement(
                    element,
                    steps: steps,
                    stepIndex: stepIndex + 1,
                    state: state,
                    outThrown: outThrown,
                    yield: yield
                )
            }
        } else {
            runtimeSequenceTransformElement(
                element,
                steps: steps,
                stepIndex: stepIndex + 1,
                state: state,
                outThrown: outThrown,
                yield: yield
            )
        }
    case let .onEachStep(fnPtr, closureRaw):
        let action = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        _ = action(closureRaw, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        runtimeSequenceTransformElement(
            element,
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case let .onEachIndexedStep(fnPtr, closureRaw):
        let action = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        let index = state.takeCounts[stepIndex, default: 0]
        state.takeCounts[stepIndex] = index + 1
        var thrown = 0
        _ = action(closureRaw, index, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        runtimeSequenceTransformElement(
            element,
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case let .mapNotNullStep(fnPtr, closureRaw):
        let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        let mapped = lambda(closureRaw, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        if let unboxed = runtimeMapNotNullResultValue(mapped) {
            runtimeSequenceTransformElement(
                unboxed,
                steps: steps,
                stepIndex: stepIndex + 1,
                state: state,
                outThrown: outThrown,
                yield: yield
            )
        }
    case .filterNotNullStep:
        if runtimeNormalizeNullableCollectionValue(element) != nil {
            runtimeSequenceTransformElement(
                element,
                steps: steps,
                stepIndex: stepIndex + 1,
                state: state,
                outThrown: outThrown,
                yield: yield
            )
        }
    case .requireNoNullsStep:
        if runtimeNormalizeNullableCollectionValue(element) == nil {
            outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: kSequenceRequireNoNullsFoundNull)
            state.stop = true
            return
        }
        runtimeSequenceTransformElement(
            element,
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case let .mapIndexedStep(fnPtr, closureRaw):
        let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        let index = state.takeCounts[stepIndex, default: 0]
        state.takeCounts[stepIndex] = index + 1
        var thrown = 0
        let mapped = lambda(closureRaw, index, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        // Keep the transform's already-boxed result as-is.
        runtimeSequenceTransformElement(
            mapped,
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case let .mapIndexedNotNullStep(fnPtr, closureRaw):
        let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        let index = state.takeCounts[stepIndex, default: 0]
        state.takeCounts[stepIndex] = index + 1
        var thrown = 0
        let mapped = lambda(closureRaw, index, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        if let unboxed = runtimeMapNotNullResultValue(mapped) {
            runtimeSequenceTransformElement(
                unboxed,
                steps: steps,
                stepIndex: stepIndex + 1,
                state: state,
                outThrown: outThrown,
                yield: yield
            )
        }
    case let .filterIndexedStep(fnPtr, closureRaw):
        let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        let index = state.takeCounts[stepIndex, default: 0]
        state.takeCounts[stepIndex] = index + 1
        var thrown = 0
        let keep = lambda(closureRaw, index, element, &thrown) != 0
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        if keep {
            runtimeSequenceTransformElement(
                element,
                steps: steps,
                stepIndex: stepIndex + 1,
                state: state,
                outThrown: outThrown,
                yield: yield
            )
        }
    case .withIndexStep:
        let index = state.takeCounts[stepIndex, default: 0]
        state.takeCounts[stepIndex] = index + 1
        runtimeSequenceTransformElement(
            runtimeIndexedValueNew(index: index, value: element),
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case let .flatMapStep(fnPtr, closureRaw):
        let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        let subRaw = lambda(closureRaw, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        // Handle the sub-collection/sequence, including source-implemented Sequences.
        guard let subElements = runtimeSequenceSourceElementsOrThrow(from: subRaw, caller: #function, outThrown: outThrown) else {
            return
        }
        for subElem in subElements {
            runtimeSequenceTransformElement(
                subElem,
                steps: steps,
                stepIndex: stepIndex + 1,
                state: state,
                outThrown: outThrown,
                yield: yield
            )
            if state.stop { return }
        }
    case let .flatMapIndexedStep(fnPtr, closureRaw):
        let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        let index = state.takeCounts[stepIndex, default: 0]
        state.takeCounts[stepIndex] = index + 1
        var thrown = 0
        let subRaw = lambda(closureRaw, index, element, &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        // Handle the sub-collection/sequence, including source-implemented Sequences.
        guard let subElements = runtimeSequenceSourceElementsOrThrow(from: subRaw, caller: #function, outThrown: outThrown) else {
            return
        }
        for subElem in subElements {
            runtimeSequenceTransformElement(
                subElem,
                steps: steps,
                stepIndex: stepIndex + 1,
                state: state,
                outThrown: outThrown,
                yield: yield
            )
            if state.stop { return }
        }
    case .shuffledStep:
        return
    case .source, .valueSource, .stringSource, .builder, .generator, .nullableGenerator, .lazyBuilder, .pullSource:
        runtimeSequenceTransformElement(
            element,
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    case let .chunkedTransformStep(size, fnPtr, closureRaw):
        let chunkSize = max(1, size)
        var buffer = state.chunkedBuffers[stepIndex, default: []]
        buffer.append(element)
        if buffer.count < chunkSize {
            state.chunkedBuffers[stepIndex] = buffer
            return
        }

        state.chunkedBuffers[stepIndex] = []
        let chunk = RuntimeListBox(elements: buffer)
        let chunkRaw = registerRuntimeObject(chunk)
        var thrown = 0
        let transformed = runtimeInvokeCollectionLambda1MaybeWrapped(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: chunkRaw,
            outThrown: &thrown
        )
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        runtimeSequenceTransformElement(
            maybeUnbox(transformed),
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    }
}

private func runtimeSequenceFlushChunkedTransforms(
    _ steps: [SequenceStepKind],
    state: SequenceTraversalState,
    outThrown: UnsafeMutablePointer<Int>?,
    yield: @escaping (Int) -> Bool
) {
    for stepIndex in steps.indices {
        if state.stopByDownstream { return }
        guard case let .chunkedTransformStep(_, fnPtr, closureRaw) = steps[stepIndex] else {
            continue
        }
        guard let buffer = state.chunkedBuffers.removeValue(forKey: stepIndex), !buffer.isEmpty else { continue }

        let chunk = RuntimeListBox(elements: buffer)
        let chunkRaw = registerRuntimeObject(chunk)
        var thrown = 0
        let transformed = runtimeInvokeCollectionLambda1MaybeWrapped(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: chunkRaw,
            outThrown: &thrown
        )
        if thrown != 0 {
            outThrown?.pointee = thrown
            state.stop = true
            return
        }
        runtimeSequenceTransformElement(
            maybeUnbox(transformed),
            steps: steps,
            stepIndex: stepIndex + 1,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    }
}

/// Traverse a sequence box lazily, allowing the caller to supply its own
/// `SequenceTraversalState` to track transforms and short-circuiting.
func runtimeTraverseSequenceWithState(
    _ seq: RuntimeSequenceBox,
    state: SequenceTraversalState,
    outThrown: UnsafeMutablePointer<Int>?,
    markConsumption: Bool = true,
    yield: @escaping (Int) -> Bool
) {
    if markConsumption, !runtimeSequenceBeginTraversal(seq, outThrown: outThrown) {
        return
    }

    if let shuffledIndex = seq.steps.firstIndex(where: { step in
        if case .shuffledStep = step { return true }
        return false
    }) {
        let prefix = Array(seq.steps[..<shuffledIndex])
        let rest: [SequenceStepKind] =
            (shuffledIndex + 1) < seq.steps.endIndex
            ? Array(seq.steps[(shuffledIndex + 1)...])
            : []
        guard case let .shuffledStep(randomOpt) = seq.steps[shuffledIndex] else {
            return
        }
        let prefixBox = RuntimeSequenceBox(steps: prefix)
        var materialized = evaluateSequence(prefixBox)
        materialized = runtimeShuffleElementHandles(materialized, randomRaw: randomOpt)
        var newSteps: [SequenceStepKind] = [.source(elements: materialized)]
        newSteps.append(contentsOf: rest)
        return runtimeTraverseSequenceWithState(
            RuntimeSequenceBox(steps: newSteps),
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    }
    let transformSteps = seq.steps.filter {
        switch $0 {
        case .source, .valueSource, .stringSource, .builder, .generator, .nullableGenerator, .lazyBuilder, .pullSource:
            false
        default:
            true
        }
    }
    let emit: (Int) -> Void = { element in
        runtimeSequenceTransformElement(
            element,
            steps: transformSteps,
            stepIndex: 0,
            state: state,
            outThrown: outThrown,
            yield: yield
        )
    }

    for step in seq.steps {
        switch step {
        case let .source(sourceElements), let .builder(sourceElements):
            for element in sourceElements {
                emit(element)
                if state.stop { break }
            }
            if (outThrown?.pointee ?? 0) == 0 {
                runtimeSequenceFlushChunkedTransforms(
                    transformSteps,
                    state: state,
                    outThrown: outThrown,
                    yield: yield
                )
            }
            return
        case let .valueSource(sourceValues):
            for value in sourceValues {
                emit(value.legacyRawValue)
                if state.stop { break }
            }
            if (outThrown?.pointee ?? 0) == 0 {
                runtimeSequenceFlushChunkedTransforms(
                    transformSteps,
                    state: state,
                    outThrown: outThrown,
                    yield: yield
                )
            }
            return
        case let .pullSource(produce):
            // Lazy pull-source (e.g. `useLines` lines from a live reader):
            // draw one element at a time so short-circuiting operations only
            // pull what they need and memory stays bounded.
            while true {
                if state.stop { break }
                guard let element = produce() else { break }
                emit(element)
                if state.stop { break }
            }
            if (outThrown?.pointee ?? 0) == 0 {
                runtimeSequenceFlushChunkedTransforms(
                    transformSteps,
                    state: state,
                    outThrown: outThrown,
                    yield: yield
                )
            }
            return
        case let .lazyBuilder(coroutine):
            // STDLIB-563: Lazy element-by-element iteration.
            // Request one element at a time from the coroutine so that
            // short-circuiting operations (take, first, etc.) only
            // compute the elements they actually need.
            let coroutine = coroutine.freshIterator()
            var done = false
            while true {
                if state.stop || done { break }
                let next = coroutine.nextElement(outThrown: outThrown)
                switch next {
                case let .value(element):
                    emit(element)
                case .done:
                    done = true
                }
                if state.stop { break }
            }
            if (outThrown?.pointee ?? 0) == 0 {
                runtimeSequenceFlushChunkedTransforms(
                    transformSteps,
                    state: state,
                    outThrown: outThrown,
                    yield: yield
                )
            }
            return
        case let .stringSource(source):
            // Lazy: iterate string characters on demand without pre-materializing.
            // NOTE: Kotlin Char is a UTF-16 code unit (16-bit). Iterating unicodeScalars
            // produces values > 0xFFFF for supplementary characters (e.g. emoji),
            // which do not fit in a Kotlin Char. We iterate utf16 code units instead to
            // match Kotlin's Char semantics correctly. Supplementary characters are split
            // into two surrogate code units, which is the expected Kotlin behaviour.
            for codeUnit in runtimeKotlinStringUTF16CodeUnits(source) {
                emit(Int(codeUnit))
                if state.stop { break }
            }
            if (outThrown?.pointee ?? 0) == 0 {
                runtimeSequenceFlushChunkedTransforms(
                    transformSteps,
                    state: state,
                    outThrown: outThrown,
                    yield: yield
                )
            }
            return
        case let .generator(seed, fnPtr, closureRaw):
            let nextFn = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
            var current = seed
            emit(current)
            if state.stop { return }

            while !state.stop {
                var thrown = 0
                let next = nextFn(closureRaw, current, &thrown)
                if thrown != 0 {
                    outThrown?.pointee = thrown
                    state.stop = true
                    return
                }
                // KSP-500: don't unbox here. The compiler wraps nextFunction in
                // a boxing adapter (CallLowerer+ClosureAdapters.swift's
                // makeGenerateSequenceBoxingAdapter) whenever the element type
                // is a primitive, so `next` already comes back boxed — the
                // element must stay boxed to be distinguishable by later
                // `is`/filterIsInstance checks on a Sequence<Any>. The callee
                // unboxes `current` itself on entry (kk_unbox_int et al. are
                // idempotent), so feeding a boxed value back in is safe.
                if next == runtimeNullSentinelInt { break }
                emit(next)
                current = next
            }
            if (outThrown?.pointee ?? 0) == 0 {
                runtimeSequenceFlushChunkedTransforms(
                    transformSteps,
                    state: state,
                    outThrown: outThrown,
                    yield: yield
                )
            }
            return
        case let .nullableGenerator(fnPtr, closureRaw):
            // STDLIB-SEQ-002: 1-arg form — calls no-arg nextFunction repeatedly until null.
            let noArgFn = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
            while !state.stop {
                var thrown = 0
                let next = noArgFn(closureRaw, &thrown)
                if thrown != 0 {
                    outThrown?.pointee = thrown
                    state.stop = true
                    return
                }
                // KSP-500: see the .generator case above — the compiler's
                // boxing adapter already boxed this closure's return value, so
                // don't strip that here.
                if next == runtimeNullSentinelInt { break }
                emit(next)
            }
            if (outThrown?.pointee ?? 0) == 0 {
                runtimeSequenceFlushChunkedTransforms(
                    transformSteps,
                    state: state,
                    outThrown: outThrown,
                    yield: yield
                )
            }
            return
        case .mapStep, .filterStep, .filterNotStep, .takeStep, .dropStep, .distinctStep,
             .distinctByStep, .zipStep, .takeWhileStep, .dropWhileStep, .onEachStep,
             .onEachIndexedStep, .mapNotNullStep, .filterNotNullStep,
             .filterIndexedStep, .requireNoNullsStep, .mapIndexedStep, .mapIndexedNotNullStep, .withIndexStep, .flatMapStep,
             .flatMapIndexedStep, .chunkedTransformStep, .shuffledStep:
            continue
        }
    }
}

/// Convenience wrapper that creates its own `SequenceTraversalState`.
func runtimeTraverseSequence(
    _ seq: RuntimeSequenceBox,
    outThrown: UnsafeMutablePointer<Int>?,
    markConsumption: Bool = true,
    yield: @escaping (Int) -> Bool
) {
    let state = SequenceTraversalState()
    runtimeTraverseSequenceWithState(
        seq,
        state: state,
        outThrown: outThrown,
        markConsumption: markConsumption,
        yield: yield
    )
}

@discardableResult
func runtimeTraverseSequenceSource(
    _ rawValue: Int,
    caller: StaticString,
    outThrown: UnsafeMutablePointer<Int>?,
    yield: @escaping (Int) -> Bool
) -> SequenceTraversalState? {
    if let seq = runtimeSequenceBox(from: rawValue) {
        let state = SequenceTraversalState()
        runtimeTraverseSequenceWithState(seq, state: state, outThrown: outThrown, yield: yield)
        return state
    }
    if runtimeTraverseSourceSequenceObject(rawValue, outThrown: outThrown, yield: yield) {
        return nil
    }
    for elem in runtimeSequenceSourceElementsOrPanic(from: rawValue, caller: caller) {
        // swiftlint:disable:next for_where
        if !yield(elem) { break }
    }
    return nil
}

/// Extracts source elements from a sequence step, if applicable.
/// `.stringSource` is NOT extracted here — it is handled lazily in evaluateSequence
/// and runtimeTraverseSequence to avoid eager materialization.
private func extractSourceElements(from step: SequenceStepKind, outThrown: UnsafeMutablePointer<Int>? = nil) -> [Int]? {
    switch step {
    case let .source(sourceElements):
        return sourceElements
    case let .valueSource(sourceValues):
        return sourceValues.map(\.legacyRawValue)
    case let .builder(builderElements):
        return builderElements
    case let .lazyBuilder(coroutine):
        // STDLIB-563: Materialize the lazy coroutine into an element array.
        let iterator = coroutine.freshIterator()
        var elements: [Int] = []
        while case let .value(element) = iterator.nextElement(outThrown: outThrown) {
            elements.append(element)
        }
        return elements
    case let .pullSource(produce):
        var elements: [Int] = []
        while let element = produce() {
            elements.append(element)
        }
        return elements
    default:
        return nil
    }
}

/// Applies a takeWhile transformation: takes elements while predicate returns true.
private func applyTakeWhileStep(_ elements: [Int], fnPtr: Int, closureRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> [Int] {
    let predicate = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var result: [Int] = []
    for elem in elements {
        var thrown = 0
        let predicateResult = predicate(closureRaw, elem, &thrown)
        if thrown != 0 {
            if let outThrown = outThrown {
                outThrown.pointee = thrown
            }
            return []
        }
        if maybeUnbox(predicateResult) == 0 {
            break
        }
        result.append(elem)
    }
    return result
}

/// Applies a dropWhile transformation: drops elements while predicate returns true, then takes the rest.
private func applyDropWhileStep(_ elements: [Int], fnPtr: Int, closureRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> [Int] {
    let predicate = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var dropping = true
    var result: [Int] = []
    for elem in elements {
        if dropping {
            var thrown = 0
            let predicateResult = predicate(closureRaw, elem, &thrown)
            if thrown != 0 {
                if let outThrown = outThrown {
                    outThrown.pointee = thrown
                }
                return []
            }
            if maybeUnbox(predicateResult) == 0 {
                dropping = false
                result.append(elem)
            }
        } else {
            result.append(elem)
        }
    }
    return result
}

/// Applies a requireNoNulls transformation: fails on the first null element.
private func applyRequireNoNullsStep(_ elements: [Int], outThrown: UnsafeMutablePointer<Int>?) -> [Int] {
    for elem in elements where runtimeNormalizeNullableCollectionValue(elem) == nil {
        let thrown = runtimeAllocateIllegalArgumentException(message: kSequenceRequireNoNullsFoundNull)
        if let outThrown {
            outThrown.pointee = thrown
        } else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Sequence.requireNoNulls encountered null but no outThrown was available.")
        }
        return []
    }
    return elements
}

private func applyOnEachIndexedStep(_ elements: [Int], fnPtr: Int, closureRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> [Int] {
    for (idx, elem) in elements.enumerated() {
        var thrown = 0
        _ = runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: idx, rhs: elem, outThrown: &thrown)
        if thrown != 0 {
            if let outThrown = outThrown {
                outThrown.pointee = thrown
            }
            return []
        }
    }
    return elements
}

/// Applies a withIndex transformation: creates pairs of (index, element).
private func applyWithIndexStep(_ elements: [Int]) -> [Int] {
    var pairs: [Int] = []
    pairs.reserveCapacity(elements.count)
    for (idx, elem) in elements.enumerated() {
        pairs.append(runtimeIndexedValueNew(index: idx, value: elem))
    }
    return pairs
}

/// Applies a flatMap transformation: maps each element to a collection and flattens the result.
private func applyFlatMapStep(_ elements: [Int], fnPtr: Int, closureRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> [Int] {
    var result: [Int] = []
    for elem in elements {
        var thrown = 0
        let subRaw = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 {
            if let outThrown = outThrown {
                outThrown.pointee = thrown
            }
            return []
        }
        if let subElements = runtimeCollectionElements(from: subRaw) {
            result.append(contentsOf: subElements)
        } else if let subSeq = runtimeSequenceBox(from: subRaw) {
            result.append(contentsOf: evaluateSequence(subSeq, outThrown: outThrown))
            if let outThrown, outThrown.pointee != 0 { return [] }
        }
    }
    return result
}

/// Applies a flatMapIndexed transformation: maps each indexed element to a collection or sequence and flattens it.
private func applyFlatMapIndexedStep(_ elements: [Int], fnPtr: Int, closureRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> [Int] {
    var result: [Int] = []
    for (index, elem) in elements.enumerated() {
        var thrown = 0
        let subRaw = runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: index, rhs: elem, outThrown: &thrown)
        if thrown != 0 {
            if let outThrown = outThrown {
                outThrown.pointee = thrown
            }
            return []
        }
        if let subElements = runtimeCollectionElements(from: subRaw) {
            result.append(contentsOf: subElements)
        } else if let subSeq = runtimeSequenceBox(from: subRaw) {
            result.append(contentsOf: evaluateSequence(subSeq, outThrown: outThrown))
            if let outThrown, outThrown.pointee != 0 { return [] }
        }
    }
    return result
}

/// Applies a chunked transform step eagerly by grouping elements, applying the transform,
/// and including any trailing partial chunk.
private func applyChunkedTransformStep(
    _ elements: [Int],
    size: Int,
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> [Int] {
    guard !elements.isEmpty else { return [] }

    let chunkSize = max(1, size)
    let expectedChunkCount = elements.count / chunkSize + (elements.count % chunkSize == 0 ? 0 : 1)
    var result: [Int] = []
    result.reserveCapacity(expectedChunkCount)

    var buffer: [Int] = []
    buffer.reserveCapacity(min(chunkSize, elements.count))

    for element in elements {
        buffer.append(element)
        if buffer.count != chunkSize { continue }

        let chunk = RuntimeListBox(elements: buffer)
        let chunkRaw = registerRuntimeObject(chunk)
        var thrown = 0
        let transformed = runtimeInvokeCollectionLambda1MaybeWrapped(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: chunkRaw,
            outThrown: &thrown
        )
        if thrown != 0 {
            if let outThrown = outThrown {
                outThrown.pointee = thrown
            }
            return []
        }
        result.append(maybeUnbox(transformed))
        buffer = []
    }

    if !buffer.isEmpty {
        let chunk = RuntimeListBox(elements: buffer)
        let chunkRaw = registerRuntimeObject(chunk)
        var thrown = 0
        let transformed = runtimeInvokeCollectionLambda1MaybeWrapped(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: chunkRaw,
            outThrown: &thrown
        )
        if thrown != 0 {
            if let outThrown = outThrown {
                outThrown.pointee = thrown
            }
            return []
        }
        result.append(maybeUnbox(transformed))
    }

    return result
}

/// Shuffles a snapshot of element handles. `randomRaw == nil` uses the same
/// default behaviour as [Int].`shuffled()`.
private func runtimeShuffleElementHandles(_ elements: [Int], randomRaw: Int?) -> [Int] {
    guard elements.count > 1 else { return elements }
    if let randomRaw {
        var out = elements
        for i in stride(from: out.count - 1, through: 1, by: -1) {
            let j = runtimeRandomNextIntBelow(randomRaw, i + 1)
            out.swapAt(i, j)
        }
        return out
    }
    return elements.shuffled()
}

/// Evaluates the lazy sequence chain and returns the materialized elements.
/// This is the core of lazy semantics: steps are only executed here.
func evaluateSequence(
    _ seq: RuntimeSequenceBox,
    outThrown: UnsafeMutablePointer<Int>? = nil,
    markConsumption: Bool = true
) -> [Int] {
    if markConsumption, !runtimeSequenceBeginTraversal(seq, outThrown: outThrown) {
        return []
    }

    let hasTransformSteps = seq.steps.contains {
        switch $0 {
        case .source, .valueSource, .stringSource, .builder, .generator, .nullableGenerator, .lazyBuilder, .pullSource:
            return false
        default:
            return true
        }
    }
    // Preserve Kotlin sequence laziness even for source-backed sequences.
    // Without the traversal path, intermediate steps like onEachIndexed would
    // eagerly touch every source element before downstream take()/first()
    // short-circuits, which is observably incorrect.
    if hasTransformSteps {
        var result: [Int] = []
        runtimeTraverseSequence(seq, outThrown: outThrown, markConsumption: false) { elem in
            result.append(elem)
            return true
        }
        if let outThrown, outThrown.pointee != 0 { return [] }
        return result
    }

    // Find the source elements
    var elements: [Int] = []
    for step in seq.steps {
        if let source = extractSourceElements(from: step, outThrown: outThrown) {
            elements = source
            break
        }
        if case let .valueSource(values) = step {
            elements = values.map(\.legacyRawValue)
            break
        }
        if case let .stringSource(source) = step {
            // Materialize string characters at terminal evaluation only.
            // Use utf16 code units (not unicodeScalars) so that supplementary characters
            // (emoji, etc. with scalar value > 0xFFFF) are represented as surrogate pairs,
            // matching Kotlin's UTF-16 Char semantics.
            elements = runtimeKotlinStringUTF16CodeUnits(source).map { Int($0) }
            break
        }
        if case let .generator(seed, fnPtr, closureRaw) = step {
            // KSP-500: don't unbox `next` — see runtimeTraverseSequenceWithState's
            // .generator case for why the closure's boxed return must survive.
            var current = seed
            var generated: [Int] = [current]
            while true {
                var thrown = 0
                let next = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: current, outThrown: &thrown)
                if thrown != 0 {
                    outThrown?.pointee = thrown
                    return []
                }
                if next == runtimeNullSentinelInt { break }
                generated.append(next)
                current = next
            }
            elements = generated
            break
        }
        if case let .nullableGenerator(fnPtr, closureRaw) = step {
            // STDLIB-SEQ-002: 1-arg form — no seed, call no-arg function until null.
            // KSP-500: don't unbox `next` — see runtimeTraverseSequenceWithState's
            // .nullableGenerator case for why the closure's boxed return must survive.
            let noArgFn = unsafeBitCast(fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
            var generated: [Int] = []
            while true {
                var thrown = 0
                let next = noArgFn(closureRaw, &thrown)
                if thrown != 0 {
                    outThrown?.pointee = thrown
                    return []
                }
                if next == runtimeNullSentinelInt { break }
                generated.append(next)
            }
            elements = generated
            break
        }
    }

    // Apply transformation steps in order
    for step in seq.steps {
        switch step {
        case .source, .valueSource, .stringSource, .builder, .generator, .nullableGenerator, .lazyBuilder, .pullSource:
            break
        case let .mapStep(fnPtr, closureRaw):
            elements = applyMapStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: nil)
        case let .filterStep(fnPtr, closureRaw):
            elements = applyFilterStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: nil)
        case let .filterNotStep(fnPtr, closureRaw):
            elements = applyFilterNotStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: nil)
        case let .takeStep(count):
            if count >= 0, count < elements.count {
                elements = Array(elements.prefix(count))
            }
        case let .dropStep(count):
            if count >= 0, count < elements.count {
                elements = Array(elements.dropFirst(count))
            } else if count >= elements.count {
                elements = []
            }
        case .distinctStep:
            var seen = Set<RuntimeElementKey>()
            seen.reserveCapacity(elements.count)
            elements = elements.filter { seen.insert(RuntimeElementKey(value: $0)).inserted }
        case let .distinctByStep(fnPtr, closureRaw):
            let selector = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
            var seen = Set<RuntimeElementKey>()
            seen.reserveCapacity(elements.count)
            var distinct: [Int] = []
            for elem in elements {
                var thrown = 0
                let key = maybeUnbox(selector(closureRaw, elem, &thrown))
                if thrown != 0 {
                    outThrown?.pointee = thrown
                    return []
                }
                if seen.insert(RuntimeElementKey(value: key)).inserted {
                    distinct.append(elem)
                }
            }
            elements = distinct
        case let .zipStep(otherElements):
            let minCount = min(elements.count, otherElements.count)
            var zipped: [Int] = []
            zipped.reserveCapacity(minCount)
            for i in 0 ..< minCount {
                zipped.append(kk_pair_new(elements[i], otherElements[i]))
            }
            elements = zipped
        case let .takeWhileStep(fnPtr, closureRaw):
            elements = applyTakeWhileStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        case let .dropWhileStep(fnPtr, closureRaw):
            elements = applyDropWhileStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        case let .onEachStep(fnPtr, closureRaw):
            let action = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
            for elem in elements {
                var thrown = 0
                _ = action(closureRaw, elem, &thrown)
                if thrown != 0 {
                    if let outThrown {
                        outThrown.pointee = thrown
                        return []
                    }
                    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: sequence onEach lambda threw but no outThrown available")
                }
            }
        case let .onEachIndexedStep(fnPtr, closureRaw):
            elements = applyOnEachIndexedStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        case let .mapNotNullStep(fnPtr, closureRaw):
            elements = applyMapNotNullStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        case .filterNotNullStep:
            elements = applyFilterNotNullStep(elements)
        case .requireNoNullsStep:
            elements = applyRequireNoNullsStep(elements, outThrown: outThrown)
        case let .mapIndexedStep(fnPtr, closureRaw):
            elements = applyMapIndexedStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        case let .mapIndexedNotNullStep(fnPtr, closureRaw):
            elements = applyMapIndexedNotNullStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        case let .filterIndexedStep(fnPtr, closureRaw):
            elements = applyFilterIndexedStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        case .withIndexStep:
            elements = applyWithIndexStep(elements)
        case let .flatMapStep(fnPtr, closureRaw):
            elements = applyFlatMapStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        case let .flatMapIndexedStep(fnPtr, closureRaw):
            elements = applyFlatMapIndexedStep(elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        case let .chunkedTransformStep(size, fnPtr, closureRaw):
            elements = applyChunkedTransformStep(elements, size: size, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        case let .shuffledStep(randomOpt):
            elements = runtimeShuffleElementHandles(elements, randomRaw: randomOpt)
        }
        if let outThrown, outThrown.pointee != 0 { return [] }
    }

    return elements
}

private func evaluateSequenceValues(
    _ seq: RuntimeSequenceBox,
    outThrown: UnsafeMutablePointer<Int>? = nil,
    markConsumption: Bool = true
) -> [RuntimeValue] {
    if markConsumption, !runtimeSequenceBeginTraversal(seq, outThrown: outThrown) {
        return []
    }

    let hasTransformSteps = seq.steps.contains {
        switch $0 {
        case .source, .valueSource, .stringSource, .builder, .generator, .nullableGenerator, .lazyBuilder, .pullSource:
            return false
        default:
            return true
        }
    }
    if hasTransformSteps {
        return evaluateSequence(seq, outThrown: outThrown, markConsumption: false).map { RuntimeValue(raw: $0) }
    }

    for step in seq.steps {
        switch step {
        case let .valueSource(values):
            return values
        case let .stringSource(source):
            return runtimeKotlinStringUTF16CodeUnits(source).map { RuntimeValue(charScalar: Int($0)) }
        case .generator, .nullableGenerator:
            return evaluateSequence(seq, outThrown: outThrown, markConsumption: false).map { RuntimeValue(raw: $0) }
        default:
            if let source = extractSourceElements(from: step, outThrown: outThrown) {
                return source.map { RuntimeValue(raw: $0) }
            }
        }
    }
    return []
}

// maybeUnbox() is defined in RuntimeCollectionHelpers.swift

// MARK: - Runtime-backed Sequence/Iterator itable support

/// `Sequence.iterator()` implementation for `RuntimeSequenceBox`.
/// Returns a `RuntimeSequenceIteratorBox` handle registered with the
/// `kotlin.collections.Iterator` itable so source `Sequence` wrappers can call
/// `hasNext()` / `next()` through normal interface dispatch.
@_cdecl("kk_sequence_box_iterator")
public func kk_sequence_box_iterator(_ seqRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let seq = runtimeSequenceBox(from: seqRaw) else {
        return 0
    }
    guard runtimeSequenceBeginTraversal(seq, outThrown: outThrown) else {
        return 0
    }
    let iteratorSource = seq.constrainOnceState == nil ? seq : RuntimeSequenceBox(steps: seq.steps)
    let iterator = RuntimeSequenceIteratorBox(seq: iteratorSource)
    return registerRuntimeObject(iterator)
}

@_cdecl("kk_sequence_iterator_hasNext")
public func kk_sequence_iterator_hasNext(_ iterRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let iter = runtimeSequenceIteratorBox(from: iterRaw) else {
        return 0
    }
    return iter.hasNext(outThrown: outThrown) ? 1 : 0
}

@_cdecl("kk_sequence_iterator_next")
public func kk_sequence_iterator_next(_ iterRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let iter = runtimeSequenceIteratorBox(from: iterRaw) else {
        return 0
    }
    return iter.next(outThrown: outThrown)
}

func registerRuntimeSequenceItable(raw: Int) {
    _ = kk_object_register_itable_iface(raw, Int(runtimeSequenceInterfaceTypeID), 0)
    let iteratorPtr = unsafeBitCast(
        kk_sequence_box_iterator as @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int,
        to: Int.self
    )
    _ = kk_object_register_itable_method(raw, 0, 0, iteratorPtr)
}
