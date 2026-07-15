// Shared materialized higher-order-function helpers for collection and sequence runtime paths.

let kEmptyCollectionCannotReduce = "Empty collection can't be reduced."

@inline(__always)
func runtimeApplyMapElement(
    _ element: Int,
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> (value: Int, thrown: Int) {
    var thrown = 0
    let result = runtimeInvokeCollectionLambda1(
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        value: element,
        outThrown: &thrown
    )
    if thrown != 0 {
        runtimeSetThrown(outThrown, thrown)
        return (0, thrown)
    }
    return (maybeUnbox(result), 0)
}

@inline(__always)
func runtimeApplyPredicateElement(
    _ element: Int,
    fnPtr: Int,
    closureRaw: Int,
    negated: Bool = false,
    outThrown: UnsafeMutablePointer<Int>?
) -> (keep: Bool, thrown: Int) {
    var thrown = 0
    let result = runtimeInvokeCollectionLambda1(
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        value: element,
        outThrown: &thrown
    )
    if thrown != 0 {
        runtimeSetThrown(outThrown, thrown)
        return (false, thrown)
    }
    let keep = runtimeCollectionBool(result)
    return (negated ? !keep : keep, 0)
}

func applyMapStep(
    _ elements: [Int],
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> [Int] {
    var mapped: [Int] = []
    mapped.reserveCapacity(elements.count)
    for elem in elements {
        let step = runtimeApplyMapElement(elem, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        if step.thrown != 0 { return [] }
        mapped.append(step.value)
    }
    return mapped
}

func applyFilterStep(
    _ elements: [Int],
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> [Int] {
    var filtered: [Int] = []
    for elem in elements {
        let step = runtimeApplyPredicateElement(elem, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
        if step.thrown != 0 { return [] }
        if step.keep {
            filtered.append(elem)
        }
    }
    return filtered
}

func applyFilterNotStep(
    _ elements: [Int],
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> [Int] {
    var filtered: [Int] = []
    for elem in elements {
        let step = runtimeApplyPredicateElement(
            elem,
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            negated: true,
            outThrown: outThrown
        )
        if step.thrown != 0 { return [] }
        if step.keep {
            filtered.append(elem)
        }
    }
    return filtered
}

func applyMapNotNullStep(
    _ elements: [Int],
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> [Int] {
    var mapped: [Int] = []
    mapped.reserveCapacity(elements.count)
    for elem in elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: elem,
            outThrown: &thrown
        )
        if thrown != 0 {
            runtimeSetThrown(outThrown, thrown)
            return []
        }
        if let normalized = runtimeMapNotNullResultValue(result) {
            mapped.append(normalized)
        }
    }
    return mapped
}

func applyFilterNotNullStep(_ elements: [Int]) -> [Int] {
    elements.filter { runtimeNormalizeNullableCollectionValue($0) != nil }
}

func applyFilterIsInstanceStep(_ elements: [Int], typeToken: Int) -> [Int] {
    elements.filter { kk_op_is($0, typeToken) != 0 }
}

func applyMapIndexedStep(
    _ elements: [Int],
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> [Int] {
    var mapped: [Int] = []
    mapped.reserveCapacity(elements.count)
    for (idx, elem) in elements.enumerated() {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            lhs: idx,
            rhs: elem,
            outThrown: &thrown
        )
        if thrown != 0 {
            runtimeSetThrown(outThrown, thrown)
            return []
        }
        mapped.append(maybeUnbox(result))
    }
    return mapped
}

func applyMapIndexedNotNullStep(
    _ elements: [Int],
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> [Int] {
    var mapped: [Int] = []
    mapped.reserveCapacity(elements.count)
    for (idx, elem) in elements.enumerated() {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            lhs: idx,
            rhs: elem,
            outThrown: &thrown
        )
        if thrown != 0 {
            runtimeSetThrown(outThrown, thrown)
            return []
        }
        if let normalized = runtimeMapNotNullResultValue(result) {
            mapped.append(normalized)
        }
    }
    return mapped
}

func applyFilterIndexedStep(
    _ elements: [Int],
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> [Int] {
    var filtered: [Int] = []
    filtered.reserveCapacity(elements.count)
    for (idx, elem) in elements.enumerated() {
        var thrown = 0
        let predicate = runtimeInvokeCollectionLambda2(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            lhs: idx,
            rhs: elem,
            outThrown: &thrown
        )
        if thrown != 0 {
            runtimeSetThrown(outThrown, thrown)
            return []
        }
        if runtimeCollectionBool(predicate) {
            filtered.append(elem)
        }
    }
    return filtered
}

@inline(__always)
func runtimeApplyFoldStep(
    accumulator: Int,
    element: Int,
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> (accumulator: Int, thrown: Int) {
    var thrown = 0
    let nextAcc = runtimeInvokeCollectionLambda2(
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        lhs: accumulator,
        rhs: element,
        outThrown: &thrown
    )
    if thrown != 0 {
        runtimeSetThrown(outThrown, thrown)
        return (accumulator, thrown)
    }
    return (maybeUnbox(nextAcc), 0)
}

@inline(__always)
func runtimeApplyFoldIndexedStep(
    index: Int,
    accumulator: Int,
    element: Int,
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> (accumulator: Int, thrown: Int) {
    var thrown = 0
    let nextAcc = runtimeInvokeCollectionLambda3(
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        arg1: index,
        arg2: accumulator,
        arg3: element,
        outThrown: &thrown
    )
    if thrown != 0 {
        runtimeSetThrown(outThrown, thrown)
        return (accumulator, thrown)
    }
    return (maybeUnbox(nextAcc), 0)
}

@inline(__always)
func runtimeApplyFoldRightStep(
    element: Int,
    accumulator: Int,
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> (accumulator: Int, thrown: Int) {
    var thrown = 0
    let nextAcc = runtimeInvokeCollectionLambda2(
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        lhs: element,
        rhs: accumulator,
        outThrown: &thrown
    )
    if thrown != 0 {
        runtimeSetThrown(outThrown, thrown)
        return (accumulator, thrown)
    }
    return (maybeUnbox(nextAcc), 0)
}

@inline(__always)
func runtimeApplyFoldRightIndexedStep(
    index: Int,
    element: Int,
    accumulator: Int,
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> (accumulator: Int, thrown: Int) {
    var thrown = 0
    let nextAcc = runtimeInvokeCollectionLambda3(
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        arg1: index,
        arg2: element,
        arg3: accumulator,
        outThrown: &thrown
    )
    if thrown != 0 {
        runtimeSetThrown(outThrown, thrown)
        return (accumulator, thrown)
    }
    return (maybeUnbox(nextAcc), 0)
}

func runtimeFoldElements(
    _ elements: [Int],
    initial: Int,
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var acc = initial
    for elem in elements {
        let step = runtimeApplyFoldStep(
            accumulator: acc,
            element: elem,
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            outThrown: outThrown
        )
        if step.thrown != 0 { return initial }
        acc = step.accumulator
    }
    return acc
}

func runtimeFoldIndexedElements(
    _ elements: [Int],
    initial: Int,
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var acc = initial
    for (idx, elem) in elements.enumerated() {
        let step = runtimeApplyFoldIndexedStep(
            index: idx,
            accumulator: acc,
            element: elem,
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            outThrown: outThrown
        )
        if step.thrown != 0 { return initial }
        acc = step.accumulator
    }
    return acc
}

func runtimeFoldRightElements(
    _ elements: [Int],
    initial: Int,
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    var acc = initial
    for elem in elements.reversed() {
        let step = runtimeApplyFoldRightStep(
            element: elem,
            accumulator: acc,
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            outThrown: outThrown
        )
        if step.thrown != 0 { return initial }
        acc = step.accumulator
    }
    return acc
}

func runtimeFoldRightIndexedElements(
    _ elements: [Int],
    initial: Int,
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard !elements.isEmpty else { return initial }
    var acc = initial
    for idx in stride(from: elements.count - 1, through: 0, by: -1) {
        let step = runtimeApplyFoldRightIndexedStep(
            index: idx,
            element: elements[idx],
            accumulator: acc,
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            outThrown: outThrown
        )
        if step.thrown != 0 { return initial }
        acc = step.accumulator
    }
    return acc
}

func runtimeReduceElements(
    _ elements: [Int],
    fnPtr: Int,
    closureRaw: Int,
    emptyResult: Int,
    throwResult: Int,
    emptyMessage: String?,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard !elements.isEmpty else {
        if let emptyMessage {
            runtimeSetThrown(outThrown, runtimeAllocateUnsupportedOperationException(message: emptyMessage))
        }
        return emptyResult
    }
    var acc = maybeUnbox(elements[0])
    for idx in 1 ..< elements.count {
        let step = runtimeApplyFoldStep(
            accumulator: acc,
            element: elements[idx],
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            outThrown: outThrown
        )
        if step.thrown != 0 { return throwResult }
        acc = step.accumulator
    }
    return acc
}

func runtimeReduceIndexedElements(
    _ elements: [Int],
    fnPtr: Int,
    closureRaw: Int,
    emptyResult: Int,
    throwResult: Int,
    emptyMessage: String?,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard !elements.isEmpty else {
        if let emptyMessage {
            runtimeSetThrown(outThrown, runtimeAllocateUnsupportedOperationException(message: emptyMessage))
        }
        return emptyResult
    }
    var acc = maybeUnbox(elements[0])
    for idx in 1 ..< elements.count {
        let step = runtimeApplyFoldIndexedStep(
            index: idx,
            accumulator: acc,
            element: elements[idx],
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            outThrown: outThrown
        )
        if step.thrown != 0 { return throwResult }
        acc = step.accumulator
    }
    return acc
}

func runtimeReduceRightElements(
    _ elements: [Int],
    fnPtr: Int,
    closureRaw: Int,
    emptyResult: Int,
    throwResult: Int,
    emptyMessage: String?,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let last = elements.last else {
        if let emptyMessage {
            runtimeSetThrown(outThrown, runtimeAllocateUnsupportedOperationException(message: emptyMessage))
        }
        return emptyResult
    }
    var acc = maybeUnbox(last)
    guard elements.count > 1 else { return acc }
    for idx in stride(from: elements.count - 2, through: 0, by: -1) {
        let step = runtimeApplyFoldRightStep(
            element: elements[idx],
            accumulator: acc,
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            outThrown: outThrown
        )
        if step.thrown != 0 { return throwResult }
        acc = step.accumulator
    }
    return acc
}

func runtimeReduceRightIndexedElements(
    _ elements: [Int],
    fnPtr: Int,
    closureRaw: Int,
    emptyResult: Int,
    throwResult: Int,
    emptyMessage: String?,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let last = elements.last else {
        if let emptyMessage {
            runtimeSetThrown(outThrown, runtimeAllocateUnsupportedOperationException(message: emptyMessage))
        }
        return emptyResult
    }
    var acc = maybeUnbox(last)
    guard elements.count > 1 else { return acc }
    for idx in stride(from: elements.count - 2, through: 0, by: -1) {
        let step = runtimeApplyFoldRightIndexedStep(
            index: idx,
            element: elements[idx],
            accumulator: acc,
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            outThrown: outThrown
        )
        if step.thrown != 0 { return throwResult }
        acc = step.accumulator
    }
    return acc
}
