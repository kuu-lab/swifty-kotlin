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
