// Runtime shim for KSP-423.
// These entry points are no longer part of the Runtime module; they are kept in the test target so RuntimeCollectionHOFTests can still exercise the C ABI.
@testable import Runtime

@_cdecl("kk_list_any")
public func kk_list_any(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    if fnPtr == 0 {
        return list.elements.isEmpty ? 0 : 1
    }
    for elem in list.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return 1 }
    }
    return 0
}
@_cdecl("kk_list_none")
public func kk_list_none(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    if fnPtr == 0 {
        return list.elements.isEmpty ? 1 : 0
    }
    for elem in list.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return 0 }
    }
    return 1
}
@_cdecl("kk_list_all")
public func kk_list_all(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    for elem in list.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) == 0 { return 0 }
    }
    return 1
}
@_cdecl("kk_list_count")
public func kk_list_count(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    if fnPtr == 0 {
        return list.elements.count
    }
    var count = 0
    for elem in list.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { count += 1 }
    }
    return count
}

@_cdecl("kk_list_find")
public func kk_list_find(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    if fnPtr == 0 {
        return list.elements.first ?? runtimeNullSentinelInt
    }
    for elem in list.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return elem }
    }
    return runtimeNullSentinelInt
}
@_cdecl("kk_list_findLast")
public func kk_list_findLast(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    if fnPtr == 0 {
        return list.elements.last ?? runtimeNullSentinelInt
    }
    for elem in list.elements.reversed() {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return elem }
    }
    return runtimeNullSentinelInt
}

@_cdecl("kk_list_indexOf")
public func kk_list_indexOf(_ listRaw: Int, _ element: Int) -> Int {
    if let ptr = UnsafeMutableRawPointer(bitPattern: listRaw),
       runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: ptr)) }),
       tryCast(ptr, to: RuntimeStringBox.self) != nil
    {
        if let elementPtr = UnsafeMutableRawPointer(bitPattern: element),
           runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: elementPtr)) }),
           tryCast(elementPtr, to: RuntimeStringBox.self) != nil
        {
            return runtimeStringIndexOfRaw(listRaw, element)
        }
        let stringListRaw = runtimeStringToCharListRaw(runtimeStringFromRawOrPanic(listRaw, caller: #function))
        return kk_list_indexOf(stringListRaw, element)
    }
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    for (index, elem) in list.elements.enumerated() where runtimeCompareValues(elem, element) == 0 {
        return index
    }
    return -1
}
@_cdecl("kk_list_lastIndexOf")
public func kk_list_lastIndexOf(_ listRaw: Int, _ element: Int) -> Int {
    if let ptr = UnsafeMutableRawPointer(bitPattern: listRaw),
       runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: ptr)) }),
       tryCast(ptr, to: RuntimeStringBox.self) != nil
    {
        if let elementPtr = UnsafeMutableRawPointer(bitPattern: element),
           runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: elementPtr)) }),
           tryCast(elementPtr, to: RuntimeStringBox.self) != nil
        {
            return runtimeStringLastIndexOfRaw(listRaw, element)
        }
        let stringListRaw = runtimeStringToCharListRaw(runtimeStringFromRawOrPanic(listRaw, caller: #function))
        return kk_list_lastIndexOf(stringListRaw, element)
    }
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    var lastIdx = -1
    for (index, elem) in list.elements.enumerated() where runtimeCompareValues(elem, element) == 0 {
        lastIdx = index
    }
    return lastIdx
}
@_cdecl("kk_list_indexOfFirst")
public func kk_list_indexOfFirst(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if let ptr = UnsafeMutableRawPointer(bitPattern: listRaw),
       runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: ptr)) }),
       tryCast(ptr, to: RuntimeStringBox.self) != nil
    {
        return runtimeStringIndexOfFirstFromRaw(listRaw, fnPtr, closureRaw, outThrown)
    }
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    for (index, elem) in list.elements.enumerated() {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return index }
    }
    return -1
}
@_cdecl("kk_list_indexOfLast")
public func kk_list_indexOfLast(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if let ptr = UnsafeMutableRawPointer(bitPattern: listRaw),
       runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: ptr)) }),
       tryCast(ptr, to: RuntimeStringBox.self) != nil
    {
        return runtimeStringIndexOfLastFromRaw(listRaw, fnPtr, closureRaw, outThrown)
    }
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    var lastIdx = -1
    for (index, elem) in list.elements.enumerated() {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { lastIdx = index }
    }
    return lastIdx
}
@_cdecl("kk_list_contains")
public func kk_list_contains(_ listRaw: Int, _ element: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(list.elements.contains(where: { runtimeValuesEqual($0, element) }) ? 1 : 0)
}

@_cdecl("kk_list_containsAll")
public func kk_list_containsAll(_ listRaw: Int, _ collectionRaw: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        return kk_box_bool(0)
    }
    let otherElements: [Int]
    if let otherList = runtimeListBox(from: collectionRaw) {
        otherElements = otherList.elements
    } else if let otherSet = runtimeSetBox(from: collectionRaw) {
        otherElements = otherSet.elements
    } else {
        return kk_box_bool(0)
    }
    for element in otherElements {
        // swiftlint:disable:next for_where
        if !list.elements.contains(where: { runtimeValuesEqual($0, element) }) {
            return kk_box_bool(0)
        }
    }
    return kk_box_bool(1)
}

@_cdecl("kk_list_binarySearch")
public func kk_list_binarySearch(_ listRaw: Int, _ element: Int) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { return -1 }
    return runtimeBinarySearch(
        elements: list.elements,
        element: element,
        fromIndex: 0,
        toIndex: list.elements.count,
        compare: runtimeCompareValues
    )
}

@_cdecl("kk_list_binarySearch_compare")
public func kk_list_binarySearch_compare(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    var low = 0
    var high = list.elements.count - 1
    while low <= high {
        let mid = low + (high - low) / 2
        var thrown = 0
        let cmp = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: list.elements[mid], outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let cmpVal = maybeUnbox(cmp)
        if cmpVal < 0 {
            low = mid + 1
        } else if cmpVal > 0 {
            high = mid - 1
        } else {
            return mid
        }
    }
    return -(low + 1)
}

@_cdecl("kk_list_binarySearch_comparator")
public func kk_list_binarySearch_comparator(_ listRaw: Int, _ element: Int, _ fnPtr: Int, _ closureRaw: Int, _ fromIndex: Int, _ toIndex: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let size = list.elements.count
    if fromIndex > toIndex {
        runtimeSetThrown(outThrown, runtimeAllocateIllegalArgumentException(message: "fromIndex \(fromIndex) must not be greater than toIndex \(toIndex)"))
        return 0
    }
    if fromIndex < 0 || toIndex < 0 || fromIndex > size || toIndex > size {
        runtimeSetThrown(outThrown, runtimeAllocateIndexOutOfBoundsException(message: "fromIndex=\(fromIndex), toIndex=\(toIndex), size=\(size)"))
        return 0
    }

    let comparatorInvoke = runtimeSortedWithComparatorInvoke(fnPtr: fnPtr, closureRaw: closureRaw)
    var low = fromIndex
    var high = toIndex - 1
    while low <= high {
        let mid = low + (high - low) / 2
        var thrown = 0
        let cmp = comparatorInvoke(list.elements[mid], element, &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let cmpVal = maybeUnbox(cmp)
        if cmpVal < 0 {
            low = mid + 1
        } else if cmpVal > 0 {
            high = mid - 1
        } else {
            return mid
        }
    }
    return -(low + 1)
}

@inline(__always)
private func shimListBinarySearchBy(
    _ list: RuntimeListBox,
    key: Int,
    fromIndex: Int,
    toIndex: Int,
    fnPtr: Int,
    closureRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let size = list.elements.count
    let from = max(0, min(fromIndex, size))
    let to = max(from, min(toIndex, size))
    var low = from
    var high = to - 1
    while low <= high {
        let mid = low + (high - low) / 2
        var thrown = 0
        let selectorValue = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: list.elements[mid], outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let cmp = runtimeCompareValues(selectorValue, key)
        if cmp < 0 {
            low = mid + 1
        } else if cmp > 0 {
            high = mid - 1
        } else {
            return mid
        }
    }
    return -(low + 1)
}

@_cdecl("kk_list_binarySearchBy")
public func kk_list_binarySearchBy(_ listRaw: Int, _ key: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    return shimListBinarySearchBy(list, key: key, fromIndex: 0, toIndex: list.elements.count, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
}

@_cdecl("kk_list_binarySearchBy_fromIndex")
public func kk_list_binarySearchBy_fromIndex(_ listRaw: Int, _ key: Int, _ fromIndex: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    return shimListBinarySearchBy(list, key: key, fromIndex: fromIndex, toIndex: list.elements.count, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
}

@_cdecl("kk_list_binarySearchBy_range")
public func kk_list_binarySearchBy_range(_ listRaw: Int, _ key: Int, _ fromIndex: Int, _ toIndex: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    return shimListBinarySearchBy(list, key: key, fromIndex: fromIndex, toIndex: toIndex, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
}
