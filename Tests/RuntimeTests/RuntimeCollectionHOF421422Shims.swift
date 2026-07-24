// Runtime shim for KSP-421/422.
// These entry points are no longer part of the Runtime module; they are kept in the test target so RuntimeCollectionHOFTests can still exercise the C ABI.
@testable import Runtime

@_cdecl("kk_list_map")
public func kk_list_map(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var thrown = 0
    let mapped = applyMapStep(list.elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_list_mapNotNull")
public func kk_list_mapNotNull(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var thrown = 0
    let mapped = applyMapNotNullStep(list.elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_list_mapTo")
public func kk_list_mapTo(_ listRaw: Int, _ destRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let elements = runtimeCollectionElements(from: listRaw) else {
        invalidContainerPanic(#function, "collection")
    }
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    for elem in elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        runtimeAppendToMutableCollection(destRaw, maybeUnbox(result))
    }
    return destRaw
}

@_cdecl("kk_list_mapNotNullTo")
public func kk_list_mapNotNullTo(_ listRaw: Int, _ destRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let elements = runtimeCollectionElements(from: listRaw) else {
        invalidContainerPanic(#function, "collection")
    }
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    for elem in elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        if result != runtimeNullSentinelInt {
            runtimeAppendToMutableCollection(destRaw, maybeUnbox(result))
        }
    }
    return destRaw
}

@_cdecl("kk_list_mapIndexed")
public func kk_list_mapIndexed(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var thrown = 0
    let mapped = applyMapIndexedStep(list.elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_list_mapIndexedTo")
public func kk_list_mapIndexedTo(_ listRaw: Int, _ destRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let elements = runtimeCollectionElements(from: listRaw) else {
        invalidContainerPanic(#function, "collection")
    }
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    for (index, elem) in elements.enumerated() {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: index, rhs: elem, outThrown: &thrown)
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        runtimeAppendToMutableCollection(destRaw, maybeUnbox(result))
    }
    return destRaw
}

@_cdecl("kk_list_mapIndexedNotNull")
public func kk_list_mapIndexedNotNull(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var thrown = 0
    let mapped = applyMapIndexedNotNullStep(list.elements, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_list_mapIndexedNotNullTo")
public func kk_list_mapIndexedNotNullTo(_ listRaw: Int, _ destRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let elements = runtimeCollectionElements(from: listRaw) else {
        invalidContainerPanic(#function, "collection")
    }
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    for (index, elem) in elements.enumerated() {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: index, rhs: elem, outThrown: &thrown)
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        if let normalized = runtimeMapNotNullResultValue(result) {
            runtimeAppendToMutableCollection(destRaw, normalized)
        }
    }
    return destRaw
}

@_cdecl("kk_list_flatMap")
public func kk_list_flatMap(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var result: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let subListRaw = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if let subList = runtimeListBox(from: subListRaw) {
            result.append(contentsOf: subList.elements)
        } else if let subArray = runtimeArrayBox(from: subListRaw) {
            result.append(contentsOf: subArray.elements)
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

@_cdecl("kk_list_flatMapIndexed")
public func kk_list_flatMapIndexed(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var result: [Int] = []
    for (index, elem) in list.elements.enumerated() {
        var thrown = 0
        let flattened = runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: index, rhs: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        guard let flattenedElements = runtimeCollectionElements(from: flattened) else {
            invalidContainerPanic(#function, "collection")
        }
        result.append(contentsOf: flattenedElements)
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

@_cdecl("kk_list_flatMapTo")
public func kk_list_flatMapTo(_ listRaw: Int, _ destRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let elements = runtimeCollectionElements(from: listRaw) else {
        invalidContainerPanic(#function, "collection")
    }
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    for elem in elements {
        var thrown = 0
        let flattened = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        guard let flattenedElements = runtimeCollectionElements(from: flattened) else {
            invalidContainerPanic(#function, "collection")
        }
        for flattenedElement in flattenedElements {
            runtimeAppendToMutableCollection(destRaw, flattenedElement)
        }
    }
    return destRaw
}

@_cdecl("kk_list_flatMapIndexedTo")
public func kk_list_flatMapIndexedTo(_ listRaw: Int, _ destRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let elements = runtimeCollectionElements(from: listRaw) else {
        invalidContainerPanic(#function, "collection")
    }
    guard runtimeMutableCollectionExists(destRaw) else {
        invalidContainerPanic(#function, "mutable collection")
    }
    for (index, elem) in elements.enumerated() {
        var thrown = 0
        let flattened = runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: index, rhs: elem, outThrown: &thrown)
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        guard let flattenedElements = runtimeCollectionElements(from: flattened) else {
            invalidContainerPanic(#function, "collection")
        }
        for flattenedElement in flattenedElements {
            runtimeAppendToMutableCollection(destRaw, flattenedElement)
        }
    }
    return destRaw
}

@_cdecl("kk_list_flatten")
public func kk_list_flatten(_ listRaw: Int) -> Int {
    guard let elements = runtimeCollectionElements(from: listRaw) else {
        invalidContainerPanic(#function, "collection")
    }
    var result: [Int] = []
    for subCollectionRaw in elements {
        guard let subElements = runtimeCollectionElements(from: subCollectionRaw) else {
            invalidContainerPanic(#function, "collection")
        }
        result.append(contentsOf: subElements)
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

@_cdecl("kk_list_fold")
public func kk_list_fold(
    _ listRaw: Int, _ initial: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let elements = runtimeCollectionElements(from: listRaw) else {
        invalidContainerPanic(#function, "collection")
    }
    var thrown = 0
    let result = runtimeFoldElements(elements, initial: initial, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    return result
}

@_cdecl("kk_list_foldIndexed")
public func kk_list_foldIndexed(_ listRaw: Int, _ initial: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let elements = runtimeCollectionElements(from: listRaw) else {
        invalidContainerPanic(#function, "collection")
    }
    var thrown = 0
    let result = runtimeFoldIndexedElements(elements, initial: initial, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    return result
}

@_cdecl("kk_list_foldRight")
public func kk_list_foldRight(
    _ listRaw: Int, _ initial: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    var thrown = 0
    let result = runtimeFoldRightElements(list.elements, initial: initial, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    return result
}

@_cdecl("kk_list_foldRightIndexed")
public func kk_list_foldRightIndexed(
    _ listRaw: Int, _ initial: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    var thrown = 0
    let result = runtimeFoldRightIndexedElements(list.elements, initial: initial, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    return result
}

@_cdecl("kk_list_reduceOrNull")
public func kk_list_reduceOrNull(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var thrown = 0
    let result = runtimeReduceElements(
        list.elements,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        emptyResult: runtimeNullSentinelInt,
        throwResult: 0,
        emptyMessage: nil,
        outThrown: &thrown
    )
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    return result
}

@_cdecl("kk_list_reduceIndexedOrNull")
public func kk_list_reduceIndexedOrNull(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    var thrown = 0
    let result = runtimeReduceIndexedElements(
        list.elements,
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        emptyResult: runtimeNullSentinelInt,
        throwResult: 0,
        emptyMessage: nil,
        outThrown: &thrown
    )
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    return result
}

@_cdecl("kk_list_scan")
public func kk_list_scan(
    _ listRaw: Int, _ initial: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    var acc = maybeUnbox(initial)
    var results: [Int] = []
    results.reserveCapacity(list.elements.count + 1)
    results.append(acc)
    for elem in list.elements {
        var thrown = 0
        let step = runtimeApplyFoldStep(accumulator: acc, element: elem, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
        if step.thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        acc = step.accumulator
        results.append(acc)
    }
    return registerRuntimeObject(RuntimeListBox(elements: results))
}

@_cdecl("kk_list_scanIndexed")
public func kk_list_scanIndexed(_ listRaw: Int, _ initial: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    var acc = maybeUnbox(initial)
    var results: [Int] = []
    results.reserveCapacity(list.elements.count + 1)
    results.append(acc)
    for (idx, elem) in list.elements.enumerated() {
        var thrown = 0
        let step = runtimeApplyFoldIndexedStep(
            index: idx,
            accumulator: acc,
            element: elem,
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            outThrown: &thrown
        )
        if step.thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        acc = step.accumulator
        results.append(acc)
    }
    return registerRuntimeObject(RuntimeListBox(elements: results))
}

// Deprecated: kk_list_scanReduce is a deprecated alias for kk_list_runningReduce.
// Kotlin renamed scanReduce to runningReduce; this entrypoint is kept for ABI compatibility.
@_cdecl("kk_list_scanReduce")
public func kk_list_scanReduce(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    return kk_list_runningReduce(listRaw, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_list_runningFold")
public func kk_list_runningFold(
    _ listRaw: Int, _ initial: Int, _ fnPtr: Int, _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return kk_list_scan(listRaw, initial, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_list_runningFoldIndexed")
public func kk_list_runningFoldIndexed(_ listRaw: Int, _ initial: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    return kk_list_scanIndexed(listRaw, initial, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_list_runningReduce")
public func kk_list_runningReduce(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard !list.elements.isEmpty else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    var acc = maybeUnbox(list.elements[0])
    var results: [Int] = []
    results.reserveCapacity(list.elements.count)
    results.append(acc)
    for idx in 1 ..< list.elements.count {
        var thrown = 0
        let step = runtimeApplyFoldStep(accumulator: acc, element: list.elements[idx], fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
        if step.thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        acc = step.accumulator
        results.append(acc)
    }
    return registerRuntimeObject(RuntimeListBox(elements: results))
}

@_cdecl("kk_list_runningReduceIndexed")
public func kk_list_runningReduceIndexed(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    guard !list.elements.isEmpty else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    var acc = maybeUnbox(list.elements[0])
    var results: [Int] = []
    results.reserveCapacity(list.elements.count)
    results.append(acc)
    for idx in 1 ..< list.elements.count {
        var thrown = 0
        let step = runtimeApplyFoldIndexedStep(
            index: idx,
            accumulator: acc,
            element: list.elements[idx],
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            outThrown: &thrown
        )
        if step.thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        acc = step.accumulator
        results.append(acc)
    }
    return registerRuntimeObject(RuntimeListBox(elements: results))
}
