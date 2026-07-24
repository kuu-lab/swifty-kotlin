#if canImport(Testing)
import Foundation
import Testing
@testable import Runtime

// KSP-425: List associate/group/zip runtime entry points retained as test shims.
// Product code now routes these calls through bundled Kotlin source in ListAssociationHOF.kt.

@_cdecl("kk_list_groupBy")
public func kk_list_groupBy(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var groupKeys: [Int] = []
    var groupElements: [[Int]] = []
    var keyToIndex: [RuntimeElementKey: Int] = [:]
    for elem in list.elements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let unboxedKey = maybeUnbox(key)
        let runtimeKey = RuntimeElementKey(value: unboxedKey)
        if let grpIdx = keyToIndex[runtimeKey] {
            groupElements[grpIdx].append(elem)
        } else {
            let newIndex = groupKeys.count
            keyToIndex[runtimeKey] = newIndex
            groupKeys.append(unboxedKey)
            groupElements.append([elem])
        }
    }
    let values = groupElements.map { registerRuntimeObject(RuntimeListBox(elements: $0)) }
    return registerRuntimeObject(RuntimeMapBox(keys: groupKeys, values: values))
}
@_cdecl("kk_list_groupByTransform")
public func kk_list_groupByTransform(_ listRaw: Int, _ keyFnPtr: Int, _ keyClosureRaw: Int, _ valueFnPtr: Int, _ valueClosureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var groupKeys: [Int] = []
    var groupElements: [[Int]] = []
    var keyToIndex: [RuntimeElementKey: Int] = [:]
    for elem in list.elements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: keyFnPtr, closureRaw: keyClosureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let unboxedKey = maybeUnbox(key)
        let runtimeKey = RuntimeElementKey(value: unboxedKey)
        var thrown2 = 0
        let transformedValue = runtimeInvokeCollectionLambda1(fnPtr: valueFnPtr, closureRaw: valueClosureRaw, value: elem, outThrown: &thrown2)
        if thrown2 != 0 { return handleCollectionLambdaThrow(thrown2, outThrown) }
        if let grpIdx = keyToIndex[runtimeKey] {
            groupElements[grpIdx].append(transformedValue)
        } else {
            let newIndex = groupKeys.count
            keyToIndex[runtimeKey] = newIndex
            groupKeys.append(unboxedKey)
            groupElements.append([transformedValue])
        }
    }
    let values = groupElements.map { registerRuntimeObject(RuntimeListBox(elements: $0)) }
    return registerRuntimeObject(RuntimeMapBox(keys: groupKeys, values: values))
}
@_cdecl("kk_list_associateBy")
public func kk_list_associateBy(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var keys: [Int] = []
    var values: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        keys.append(maybeUnbox(key))
        values.append(elem)
    }
    let normalized = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}
@_cdecl("kk_list_associateByTransform")
public func kk_list_associateByTransform(_ listRaw: Int, _ keyFnPtr: Int, _ keyClosureRaw: Int, _ valueFnPtr: Int, _ valueClosureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var keys: [Int] = []
    var values: [Int] = []
    for elem in list.elements {
        var keyThrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: keyFnPtr, closureRaw: keyClosureRaw, value: elem, outThrown: &keyThrown)
        if keyThrown != 0 { return handleCollectionLambdaThrow(keyThrown, outThrown) }
        var valueThrown = 0
        let value = runtimeInvokeCollectionLambda1(fnPtr: valueFnPtr, closureRaw: valueClosureRaw, value: elem, outThrown: &valueThrown)
        if valueThrown != 0 { return handleCollectionLambdaThrow(valueThrown, outThrown) }
        keys.append(maybeUnbox(key))
        values.append(maybeUnbox(value))
    }
    let normalized = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}
@_cdecl("kk_list_associateWith")
public func kk_list_associateWith(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var keys: [Int] = []
    var values: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let value = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        keys.append(elem)
        values.append(maybeUnbox(value))
    }
    let normalized = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}
@_cdecl("kk_list_associate")
public func kk_list_associate(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var keys: [Int] = []
    var values: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let pair = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        keys.append(kk_pair_first(pair))
        values.append(kk_pair_second(pair))
    }
    let normalized = runtimeNormalizeMapEntries(keys: keys, values: values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}
@_cdecl("kk_list_associateTo")
public func kk_list_associateTo(_ listRaw: Int, _ destRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let elements = runtimeCollectionElements(from: listRaw) else {
        invalidContainerPanic(#function, "collection")
    }
    guard runtimeMapBox(from: destRaw) != nil else {
        invalidContainerPanic(#function, "map")
    }
    for elem in elements {
        var thrown = 0
        let pair = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        _ = kk_mutable_map_put(destRaw, kk_pair_first(pair), kk_pair_second(pair))
    }
    return destRaw
}
func buildKeyIndex(from dest: RuntimeMapBox) -> [Int: Int] {
    var keyIndex: [Int: Int] = [:]
    for (i, k) in dest.keys.enumerated() {
        keyIndex[k] = i
    }
    return keyIndex
}
@_cdecl("kk_list_associateByTo")
public func kk_list_associateByTo(_ listRaw: Int, _ destRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard let dest = runtimeMapBox(from: destRaw) else {
        invalidContainerPanic(#function, "map")
    }
    var keyIndex = buildKeyIndex(from: dest)
    for elem in list.elements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let unboxedKey = maybeUnbox(key)
        mapInsertOrUpdate(dest: dest, keyIndex: &keyIndex, key: unboxedKey, value: elem)
    }
    return destRaw
}
@_cdecl("kk_list_associateWithTo")
public func kk_list_associateWithTo(_ listRaw: Int, _ destRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard let dest = runtimeMapBox(from: destRaw) else {
        invalidContainerPanic(#function, "map")
    }
    var keyIndex = buildKeyIndex(from: dest)
    for elem in list.elements {
        var thrown = 0
        let value = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let unboxedKey = maybeUnbox(elem)
        let unboxedValue = maybeUnbox(value)
        mapInsertOrUpdate(dest: dest, keyIndex: &keyIndex, key: unboxedKey, value: unboxedValue)
    }
    return destRaw
}
@_cdecl("kk_list_groupByTo")
public func kk_list_groupByTo(_ listRaw: Int, _ destRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    guard let dest = runtimeMapBox(from: destRaw) else {
        invalidContainerPanic(#function, "map")
    }
    var keyIndex = buildKeyIndex(from: dest)
    var cachedLists: [Int: RuntimeListBox] = [:]
    for i in dest.keys.indices {
        if let existingList = runtimeListBox(from: dest.values[i]) {
            cachedLists[i] = existingList
        }
    }
    for elem in list.elements {
        var thrown = 0
        let key = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        let unboxedKey = maybeUnbox(key)
        if let index = keyIndex[unboxedKey] {
            if let existingList = cachedLists[index] {
                existingList.elements.append(elem)
            } else {
                guard let existingList = runtimeListBox(from: dest.values[index]) else {
                    invalidContainerPanic(#function, "MutableList")
                }
                cachedLists[index] = existingList
                existingList.elements.append(elem)
            }
        } else {
            let newIndex = dest.keys.count
            let newList = RuntimeListBox(elements: [elem])
            dest.keys.append(unboxedKey)
            dest.values.append(registerRuntimeObject(newList))
            keyIndex[unboxedKey] = newIndex
            cachedLists[newIndex] = newList
        }
    }
    return destRaw
}
@_cdecl("kk_list_unzip")
public func kk_list_unzip(_ listRaw: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    var firstValues: [Int] = []
    var secondValues: [Int] = []
    firstValues.reserveCapacity(elements.count)
    secondValues.reserveCapacity(elements.count)
    for pairRaw in elements {
        firstValues.append(kk_pair_first(pairRaw))
        secondValues.append(kk_pair_second(pairRaw))
    }
    let firstList = registerRuntimeObject(RuntimeListBox(elements: firstValues))
    let secondList = registerRuntimeObject(RuntimeListBox(elements: secondValues))
    return kk_pair_new(firstList, secondList)
}
@_cdecl("kk_list_withIndex")
public func kk_list_withIndex(_ listRaw: Int) -> Int {
    let box = RuntimeIndexingIterableBox(listRaw: listRaw)
    return registerRuntimeObject(box)
}
@_cdecl("kk_indexing_iterable_iterator")
public func kk_indexing_iterable_iterator(_ iterableRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: iterableRaw),
          let box = tryCast(ptr, to: RuntimeIndexingIterableBox.self),
          let list = runtimeListBox(from: box.listRaw)
    else {
        return 0
    }
    return registerRuntimeObject(RuntimeIndexingIteratorBox(values: list.values))
}
@_cdecl("kk_indexing_iterable_hasNext")
public func kk_indexing_iterable_hasNext(_ iterRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: iterRaw),
          let iter = tryCast(ptr, to: RuntimeIndexingIteratorBox.self) else {
        return 0
    }
    return iter.index < iter.values.count ? 1 : 0
}
@_cdecl("kk_indexing_iterable_next")
public func kk_indexing_iterable_next(_ iterRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: iterRaw),
          let iter = tryCast(ptr, to: RuntimeIndexingIteratorBox.self),
          iter.index < iter.values.count
    else {
        return 0
    }
    let idx = iter.index
    let elem = iter.values[idx]
    iter.index += 1
    return runtimeIndexedValueNew(index: idx, value: elem)
}
@_cdecl("kk_list_onEach")
public func kk_list_onEach(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for elem in list.elements {
        var thrown = 0
        _ = lambda(closureRaw, elem, &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    }
    return listRaw
}
@_cdecl("kk_list_onEachIndexed")
public func kk_list_onEachIndexed(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for (idx, elem) in list.elements.enumerated() {
        var thrown = 0
        _ = lambda(closureRaw, idx, elem, &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    }
    return listRaw
}
@_cdecl("kk_list_partition")
public func kk_list_partition(_ listRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let list = runtimeListBox(from: listRaw) else {
        invalidContainerPanic(#function, "list")
    }
    var matching: [Int] = []
    var nonMatching: [Int] = []
    for elem in list.elements {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: elem, outThrown: &thrown)
        if thrown != 0 {
            return handleCollectionLambdaThrow(thrown, outThrown)
        }
        if maybeUnbox(result) != 0 {
            matching.append(elem)
        } else {
            nonMatching.append(elem)
        }
    }
    let matchingList = registerRuntimeObject(RuntimeListBox(elements: matching))
    let nonMatchingList = registerRuntimeObject(RuntimeListBox(elements: nonMatching))
    return kk_pair_new(matchingList, nonMatchingList)
}
#endif
