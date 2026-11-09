@testable import Runtime

// Test-only shims for Map HOF runtime functions removed from the Runtime target
// by KSP-430. These keep RuntimeCollectionHOFTests/RuntimeCollectionHOFThrowTests
// compiling while the production compiler no longer emits calls to kk_map_* HOFs.

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
        _ = kk_mutable_map_put(destRaw, maybeUnbox(result), value, nil)
    }
    return destRaw
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
        _ = kk_mutable_map_put(destRaw, key, maybeUnbox(result), nil)
    }
    return destRaw
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
