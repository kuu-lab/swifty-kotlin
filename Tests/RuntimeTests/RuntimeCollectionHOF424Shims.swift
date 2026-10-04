// Runtime shims for KSP-424.
// These entry points are no longer part of the Runtime module; they are kept in the test target so RuntimeCollectionHOFTests can still exercise the C ABI.
@testable import Runtime

@_cdecl("kk_list_elementAt")
public func kk_list_elementAt(_ listRaw: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard list.elements.indices.contains(index) else {
        outThrown?.pointee = runtimeAllocateIndexOutOfBoundsException(
            message: "Index \(index) out of bounds for length \(list.elements.count)"
        )
        return 0
    }
    return list.elements[index]
}

@_cdecl("kk_list_elementAtOrNull")
public func kk_list_elementAtOrNull(_ listRaw: Int, _ index: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw),
          list.elements.indices.contains(index)
    else {
        return runtimeNullSentinelInt
    }
    return list.elements[index]
}

@_cdecl("kk_list_firstOrNull")
public func kk_list_firstOrNull(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw),
          !list.elements.isEmpty
    else {
        return runtimeNullSentinelInt
    }
    return list.elements[0]
}

@_cdecl("kk_list_lastOrNull")
public func kk_list_lastOrNull(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw),
          !list.elements.isEmpty
    else {
        return runtimeNullSentinelInt
    }
    return list.elements[list.elements.count - 1]
}

@_cdecl("kk_list_singleOrNull")
public func kk_list_singleOrNull(_ listRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw),
          list.elements.count == 1
    else {
        return runtimeNullSentinelInt
    }
    return list.elements[0]
}

@_cdecl("kk_list_first")
public func kk_list_first(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard !list.elements.isEmpty else {
        return handleCollectionLambdaThrow(runtimeAllocateNoSuchElementException(message: "Collection is empty."), outThrown)
    }
    if fnPtr == 0 {
        return list.elements[0]
    }
    for elem in list.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return elem }
    }
    outThrown?.pointee = runtimeAllocateNoSuchElementException(
        message: "Collection contains no element matching the predicate."
    )
    return handleCollectionLambdaThrow(outThrown!.pointee, outThrown)
}

@_cdecl("kk_list_last")
public func kk_list_last(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard !list.elements.isEmpty else {
        return handleCollectionLambdaThrow(runtimeAllocateNoSuchElementException(message: "Collection is empty."), outThrown)
    }
    if fnPtr == 0 {
        return list.elements.last!
    }
    var lastMatch: Int?
    for elem in list.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { lastMatch = elem }
    }
    if let match = lastMatch { return match }
    outThrown?.pointee = runtimeAllocateNoSuchElementException(
        message: "Collection contains no element matching the predicate."
    )
    return handleCollectionLambdaThrow(outThrown!.pointee, outThrown)
}

@_cdecl("kk_list_single")
public func kk_list_single(_ listRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard list.elements.count == 1 else {
        if list.elements.isEmpty {
            runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: "Collection is empty."))
        } else {
            runtimeSetThrown(outThrown, runtimeAllocateIllegalArgumentException(message: "Collection has more than one element."))
        }
        return 0
    }
    return list.elements[0]
}
