@testable import Runtime

// Test-only shims for Map HOF runtime functions removed from the Runtime target
// by KSP-430. These keep RuntimeCollectionHOFTests/RuntimeCollectionHOFThrowTests
// compiling while the production compiler no longer emits calls to kk_map_* HOFs.

@_cdecl("kk_map_all")
public func kk_map_all(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = lambda(closureRaw, runtimeMapEntryNew(key: key, value: value), &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) == 0 { return 0 }
    }
    return 1
}

@_cdecl("kk_map_any")
public func kk_map_any(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = lambda(closureRaw, runtimeMapEntryNew(key: key, value: value), &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return 1 }
    }
    return 0
}

@_cdecl("kk_map_count")
public func kk_map_count(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var count = 0
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = lambda(closureRaw, runtimeMapEntryNew(key: key, value: value), &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { count += 1 }
    }
    return count
}

@_cdecl("kk_map_filter")
public func kk_map_filter(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    var filteredKeys: [Int] = []
    var filteredValues: [Int] = []
    filteredKeys.reserveCapacity(min(map.keys.count, map.values.count))
    filteredValues.reserveCapacity(min(map.keys.count, map.values.count))
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: runtimeMapEntryNew(key: key, value: value), outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 {
            filteredKeys.append(key)
            filteredValues.append(value)
        }
    }
    return registerRuntimeObject(RuntimeMapBox(keys: filteredKeys, values: filteredValues))
}

@_cdecl("kk_map_filterKeys")
public func kk_map_filterKeys(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    var filteredKeys: [Int] = []
    var filteredValues: [Int] = []
    filteredKeys.reserveCapacity(min(map.keys.count, map.values.count))
    filteredValues.reserveCapacity(min(map.keys.count, map.values.count))
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: key, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 {
            filteredKeys.append(key)
            filteredValues.append(value)
        }
    }
    return registerRuntimeObject(RuntimeMapBox(keys: filteredKeys, values: filteredValues))
}

@_cdecl("kk_map_filterNot")
public func kk_map_filterNot(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    var filteredKeys: [Int] = []
    var filteredValues: [Int] = []
    filteredKeys.reserveCapacity(min(map.keys.count, map.values.count))
    filteredValues.reserveCapacity(min(map.keys.count, map.values.count))
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: runtimeMapEntryNew(key: key, value: value), outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) == 0 {
            filteredKeys.append(key)
            filteredValues.append(value)
        }
    }
    return registerRuntimeObject(RuntimeMapBox(keys: filteredKeys, values: filteredValues))
}

@_cdecl("kk_map_filterValues")
public func kk_map_filterValues(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    var filteredKeys: [Int] = []
    var filteredValues: [Int] = []
    filteredKeys.reserveCapacity(min(map.keys.count, map.values.count))
    filteredValues.reserveCapacity(min(map.keys.count, map.values.count))
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: value, outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 {
            filteredKeys.append(key)
            filteredValues.append(value)
        }
    }
    return registerRuntimeObject(RuntimeMapBox(keys: filteredKeys, values: filteredValues))
}

@_cdecl("kk_map_flatMap")
public func kk_map_flatMap(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        invalidContainerPanic(#function, "map")
    }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    var result: [Int] = []
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let subListRaw = lambda(closureRaw, runtimeMapEntryNew(key: key, value: value), &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if let subList = runtimeListBox(from: subListRaw) {
            result.append(contentsOf: subList.elements)
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: result))
}

@_cdecl("kk_map_forEach")
public func kk_map_forEach(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        _ = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: runtimeMapEntryNew(key: key, value: value), outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    }
    return 0
}

@_cdecl("kk_map_map")
public func kk_map_map(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    var mapped: [Int] = []
    mapped.reserveCapacity(min(map.keys.count, map.values.count))
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: runtimeMapEntryNew(key: key, value: value), outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        mapped.append(maybeUnbox(result))
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_map_mapKeys")
public func kk_map_mapKeys(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    var mappedKeys: [Int] = []
    mappedKeys.reserveCapacity(min(map.keys.count, map.values.count))
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: runtimeMapEntryNew(key: key, value: value), outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        mappedKeys.append(maybeUnbox(result))
    }
    let normalized = runtimeNormalizeMapEntries(keys: mappedKeys, values: map.values)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}

@_cdecl("kk_map_mapKeysTo")
public func kk_map_mapKeysTo(
    _ mapRaw: Int,
    _ destRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    guard runtimeMapBox(from: destRaw) != nil else { invalidContainerPanic(#function, "mutable map") }
    let entries = Array(zip(map.keys, map.values))
    for (key, value) in entries {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: runtimeMapEntryNew(key: key, value: value),
            outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        _ = kk_mutable_map_put(destRaw, maybeUnbox(result), value)
    }
    return destRaw
}

@_cdecl("kk_map_mapNotNull")
public func kk_map_mapNotNull(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    var mapped: [Int] = []
    mapped.reserveCapacity(min(map.keys.count, map.values.count))
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: runtimeMapEntryNew(key: key, value: value), outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if let normalized = runtimeMapNotNullResultValue(result) {
            mapped.append(normalized)
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: mapped))
}

@_cdecl("kk_map_mapValues")
public func kk_map_mapValues(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    var mappedValues: [Int] = []
    mappedValues.reserveCapacity(min(map.keys.count, map.values.count))
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: runtimeMapEntryNew(key: key, value: value), outThrown: &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        mappedValues.append(maybeUnbox(result))
    }
    let normalized = runtimeNormalizeMapEntries(keys: map.keys, values: mappedValues)
    return registerRuntimeObject(RuntimeMapBox(keys: normalized.0, values: normalized.1))
}

@_cdecl("kk_map_mapValuesTo")
public func kk_map_mapValuesTo(
    _ mapRaw: Int,
    _ destRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    guard runtimeMapBox(from: destRaw) != nil else { invalidContainerPanic(#function, "mutable map") }
    let entries = Array(zip(map.keys, map.values))
    for (key, value) in entries {
        var thrown = 0
        let result = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: runtimeMapEntryNew(key: key, value: value),
            outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        _ = kk_mutable_map_put(destRaw, key, maybeUnbox(result))
    }
    return destRaw
}

@_cdecl("kk_map_maxByOrNull")
public func kk_map_maxByOrNull(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        invalidContainerPanic(#function, "map")
    }
    let pairCount = min(map.keys.count, map.values.count)
    guard pairCount > 0 else {
        return runtimeNullSentinelInt
    }
    var bestKey = map.keys[0]
    var bestValue = map.values[0]
    var thrown = 0
    var bestSelector = runtimeInvokeCollectionLambda1(
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        value: runtimeMapEntryNew(key: bestKey, value: bestValue),
        outThrown: &thrown
    )
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    for idx in 1 ..< pairCount {
        let key = map.keys[idx]
        let value = map.values[idx]
        thrown = 0
        let selector = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: runtimeMapEntryNew(key: key, value: value),
            outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if runtimeCompareValues(selector, bestSelector) > 0 {
            bestKey = key
            bestValue = value
            bestSelector = selector
        }
    }
    return runtimeMapEntryNew(key: bestKey, value: bestValue)
}

@_cdecl("kk_map_minByOrNull")
public func kk_map_minByOrNull(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        invalidContainerPanic(#function, "map")
    }
    let pairCount = min(map.keys.count, map.values.count)
    guard pairCount > 0 else {
        return runtimeNullSentinelInt
    }
    var bestKey = map.keys[0]
    var bestValue = map.values[0]
    var thrown = 0
    var bestSelector = runtimeInvokeCollectionLambda1(
        fnPtr: fnPtr,
        closureRaw: closureRaw,
        value: runtimeMapEntryNew(key: bestKey, value: bestValue),
        outThrown: &thrown
    )
    if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
    for idx in 1 ..< pairCount {
        let key = map.keys[idx]
        let value = map.values[idx]
        thrown = 0
        let selector = runtimeInvokeCollectionLambda1(
            fnPtr: fnPtr,
            closureRaw: closureRaw,
            value: runtimeMapEntryNew(key: key, value: value),
            outThrown: &thrown
        )
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if runtimeCompareValues(selector, bestSelector) < 0 {
            bestKey = key
            bestValue = value
            bestSelector = selector
        }
    }
    return runtimeMapEntryNew(key: bestKey, value: bestValue)
}

@_cdecl("kk_map_minus")
public func kk_map_minus(_ mapRaw: Int, _ key: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []))
    }
    let (normalizedKeys, normalizedValues) = runtimeNormalizeMapEntries(keys: map.keys, values: map.values)
    var keys: [Int] = []
    var values: [Int] = []
    for (idx, mapKey) in normalizedKeys.enumerated() {
        // swiftlint:disable:next for_where
        if !runtimeValuesEqual(mapKey, key) {
            keys.append(mapKey)
            if idx < normalizedValues.count {
                values.append(normalizedValues[idx])
            }
        }
    }
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: values))
}

@_cdecl("kk_map_none")
public func kk_map_none(_ mapRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else { invalidContainerPanic(#function, "map") }
    let lambda = unsafeBitCast(fnPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
    for (key, value) in zip(map.keys, map.values) {
        var thrown = 0
        let result = lambda(closureRaw, runtimeMapEntryNew(key: key, value: value), &thrown)
        if thrown != 0 { return handleCollectionLambdaThrow(thrown, outThrown) }
        if maybeUnbox(result) != 0 { return 0 }
    }
    return 1
}

@_cdecl("kk_map_plus")
public func kk_map_plus(_ mapRaw: Int, _ pairRaw: Int) -> Int {
    var keys: [Int] = []
    var values: [Int] = []
    if let map = runtimeMapBox(from: mapRaw) {
        (keys, values) = runtimeNormalizeMapEntries(keys: map.keys, values: map.values)
    }
    if let pointer = UnsafeMutableRawPointer(bitPattern: pairRaw),
       let pairBox = tryCast(pointer, to: RuntimePairBox.self)
    {
        let key = pairBox.first
        let value = pairBox.second
        if let index = keys.firstIndex(where: { runtimeValuesEqual($0, key) }) {
            values[index] = value
        } else {
            keys.append(key)
            values.append(value)
        }
    }
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: values))
}
