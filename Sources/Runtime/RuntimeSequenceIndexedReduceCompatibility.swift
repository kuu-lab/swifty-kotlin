// Compatibility exports for synthetic Iterable dispatch that still lowers to
// the historical sequence indexed-reduce entry points.

@_cdecl("kk_sequence_reduceIndexed")
public func kk_sequence_reduceIndexed(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var hasAccumulator = false
    var acc = 0
    var index = 0
    let visit: (Int) -> Bool = { elem in
        if !hasAccumulator {
            hasAccumulator = true
            acc = elem
            index += 1
            return true
        }
        let step = runtimeApplyFoldIndexedStep(
            index: index,
            accumulator: acc,
            element: elem,
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            outThrown: outThrown
        )
        if step.thrown != 0 { return false }
        acc = step.accumulator
        index += 1
        return true
    }

    let traversalState = runtimeTraverseSequenceSource(
        seqRaw,
        caller: #function,
        outThrown: outThrown,
        yield: visit
    )

    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    if !hasAccumulator {
        outThrown?.pointee = runtimeAllocateUnsupportedOperationException(message: kEmptySequenceCannotReduce)
        return 0
    }
    return acc
}

@_cdecl("kk_sequence_reduceIndexedOrNull")
public func kk_sequence_reduceIndexedOrNull(
    _ seqRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var hasAccumulator = false
    var acc = 0
    var index = 0
    let visit: (Int) -> Bool = { elem in
        if !hasAccumulator {
            hasAccumulator = true
            acc = maybeUnbox(elem)
            index += 1
            return true
        }
        let step = runtimeApplyFoldIndexedStep(
            index: index,
            accumulator: acc,
            element: elem,
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            outThrown: outThrown
        )
        if step.thrown != 0 { return false }
        acc = step.accumulator
        index += 1
        return true
    }

    let traversalState = runtimeTraverseSequenceSource(
        seqRaw,
        caller: #function,
        outThrown: outThrown,
        yield: visit
    )

    if let outThrown, outThrown.pointee != 0 { return 0 }
    if let traversalState, traversalState.limitReached {
        outThrown?.pointee = runtimeAllocateThrowable(message: kSequenceGeneratorLimitReached)
        return 0
    }
    if !hasAccumulator {
        return runtimeNullSentinelInt
    }
    return acc
}
