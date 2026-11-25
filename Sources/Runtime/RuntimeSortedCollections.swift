
struct RuntimeSortedRange {
    let lowerBoundRaw: Int?
    let upperBoundRaw: Int?

    func contains(_ rawValue: Int, using compare: (Int, Int) -> Int) -> Bool {
        if let lowerBoundRaw, compare(rawValue, lowerBoundRaw) < 0 { return false }
        if let upperBoundRaw, compare(rawValue, upperBoundRaw) >= 0 { return false }
        return true
    }
}

struct RuntimeSortedBounds {
    let lowerBoundRaw: Int?
    let lowerBoundInclusive: Bool
    let upperBoundRaw: Int?
    let upperBoundInclusive: Bool

    init(_ range: RuntimeSortedRange) {
        self.lowerBoundRaw = range.lowerBoundRaw
        self.lowerBoundInclusive = range.lowerBoundRaw != nil
        self.upperBoundRaw = range.upperBoundRaw
        self.upperBoundInclusive = false
    }

    func reversed() -> RuntimeSortedBounds {
        RuntimeSortedBounds(
            lowerBoundRaw: upperBoundRaw,
            lowerBoundInclusive: upperBoundInclusive,
            upperBoundRaw: lowerBoundRaw,
            upperBoundInclusive: lowerBoundInclusive
        )
    }

    func intersecting(
        _ range: RuntimeSortedRange,
        using compare: (Int, Int) -> Int
    ) -> RuntimeSortedBounds {
        let lower: (raw: Int?, inclusive: Bool)
        switch (lowerBoundRaw, range.lowerBoundRaw) {
        case (nil, .some(let requested)):
            lower = (requested, true)
        case (.some(let existing), nil):
            lower = (existing, lowerBoundInclusive)
        case (.some(let existing), .some(let requested)):
            let ordering = compare(existing, requested)
            if ordering < 0 {
                lower = (requested, true)
            } else if ordering > 0 {
                lower = (existing, lowerBoundInclusive)
            } else {
                lower = (existing, lowerBoundInclusive)
            }
        case (nil, nil):
            lower = (nil, false)
        }

        let upper: (raw: Int?, inclusive: Bool)
        switch (upperBoundRaw, range.upperBoundRaw) {
        case (nil, .some(let requested)):
            upper = (requested, false)
        case (.some(let existing), nil):
            upper = (existing, upperBoundInclusive)
        case (.some(let existing), .some(let requested)):
            let ordering = compare(existing, requested)
            if ordering < 0 {
                upper = (existing, upperBoundInclusive)
            } else if ordering > 0 {
                upper = (requested, false)
            } else {
                upper = (existing, false)
            }
        case (nil, nil):
            upper = (nil, false)
        }
        return RuntimeSortedBounds(
            lowerBoundRaw: lower.raw,
            lowerBoundInclusive: lower.inclusive,
            upperBoundRaw: upper.raw,
            upperBoundInclusive: upper.inclusive
        )
    }

    func acceptsRange(_ range: RuntimeSortedRange, using compare: (Int, Int) -> Int) -> Bool {
        if let lower = range.lowerBoundRaw, let upper = range.upperBoundRaw,
           compare(lower, upper) > 0 {
            return false
        }
        if let endpoint = range.lowerBoundRaw {
            if let lowerBoundRaw, compare(endpoint, lowerBoundRaw) < 0 { return false }
            if let upperBoundRaw, compare(endpoint, upperBoundRaw) > 0 { return false }
        }
        if let endpoint = range.upperBoundRaw {
            if let lowerBoundRaw, compare(endpoint, lowerBoundRaw) < 0 { return false }
            if let upperBoundRaw, compare(endpoint, upperBoundRaw) > 0 { return false }
        }
        return true
    }

    private init(
        lowerBoundRaw: Int?,
        lowerBoundInclusive: Bool,
        upperBoundRaw: Int?,
        upperBoundInclusive: Bool
    ) {
        self.lowerBoundRaw = lowerBoundRaw
        self.lowerBoundInclusive = lowerBoundInclusive
        self.upperBoundRaw = upperBoundRaw
        self.upperBoundInclusive = upperBoundInclusive
    }
}

private func runtimeSortedSetBoxCreate(comparatorRaw: Int) -> RuntimeSetBox {
    let box = RuntimeSetBox(elements: [])
    box.enableSorted(comparatorRaw: comparatorRaw)
    return box
}

private func runtimeSortedSetComparatorRaw(_ setRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw), set.sorted else { return 0 }
    return set.comparatorRaw
}

/// Binary-search a navigable bound over `set`'s iteration order. The values
/// array and `sortedCompare` are already reversed on descending views, so a
/// single scan covers plain boxes and views uniformly. `lowerSide` selects
/// the greatest element below `element` (lower/floor); the false arm selects
/// the least element above it (ceiling/higher). `strict` excludes an exact
/// match — lower is `lowerSide:true, strict:true`, floor is
/// `lowerSide:true, strict:false`, ceiling is `lowerSide:false,
/// strict:false`, higher is `lowerSide:false, strict:true`.
private func runtimeSortedSetBound(
    set: RuntimeSetBox,
    element: Int,
    lowerSide: Bool,
    strict: Bool
) -> Int? {
    let elems = set.values
    var low = 0
    var high = elems.count - 1
    var result: Int?
    while low <= high {
        let mid = low + (high - low) / 2
        let comparison = set.sortedCompare(elems[mid].legacyRawValue, element)
        if lowerSide {
            if comparison < 0 || (!strict && comparison == 0) {
                result = elems[mid].legacyRawValue
                low = mid + 1
            } else {
                high = mid - 1
            }
        } else {
            if comparison > 0 || (!strict && comparison == 0) {
                result = elems[mid].legacyRawValue
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
    }
    return result
}


@_cdecl("__kk_tree_set_new")
public func kk_tree_set_new(_ comparatorRaw: Int) -> Int {
    registerRuntimeObject(runtimeSortedSetBoxCreate(comparatorRaw: comparatorRaw), typeID: treeSetRuntimeTypeID)
}

@_cdecl("__kk_tree_set_new_collection")
public func kk_tree_set_new_collection(_ collectionRaw: Int) -> Int {
    let box = runtimeSortedSetBoxCreate(comparatorRaw: 0)
    if let values = runtimeIterableValues(from: collectionRaw) {
        for value in values {
            box.insert(value: value)
        }
    }
    return registerRuntimeObject(box, typeID: treeSetRuntimeTypeID)
}

@_cdecl("__kk_tree_set_new_sorted_set")
public func kk_tree_set_new_sorted_set(_ setRaw: Int) -> Int {
    let box = runtimeSortedSetBoxCreate(comparatorRaw: runtimeSortedSetComparatorRaw(setRaw))
    if let values = runtimeIterableValues(from: setRaw) {
        for value in values {
            box.insert(value: value)
        }
    }
    return registerRuntimeObject(box, typeID: treeSetRuntimeTypeID)
}

@_cdecl("__kk_tree_set_init")
public func kk_tree_set_init(_ setRaw: Int, _ comparatorRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: setRaw),
          let objectBox = tryCast(pointer, to: RuntimeObjectBox.self) else {
        return 0
    }
    objectBox.backingSetBox = runtimeSortedSetBoxCreate(comparatorRaw: comparatorRaw)
    return 0
}


@_cdecl("__kk_sorted_set_comparator")
public func kk_sorted_set_comparator(_ setRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw), set.sorted, set.comparatorRaw != 0 else {
        return runtimeNullSentinelInt
    }
    return set.comparatorRaw
}

@_cdecl("__kk_sorted_set_first")
public func kk_sorted_set_first(_ setRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        guard let set = runtimeSetBox(from: setRaw), let first = set.values.first else {
            throw RuntimeThrownHandle(runtimeAllocateNoSuchElementException(message: nil))
        }
        return first.legacyRawValue
    }
}

@_cdecl("__kk_sorted_set_last")
public func kk_sorted_set_last(_ setRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        guard let set = runtimeSetBox(from: setRaw), let last = set.values.last else {
            throw RuntimeThrownHandle(runtimeAllocateNoSuchElementException(message: nil))
        }
        return last.legacyRawValue
    }
}

private func runtimeSortedSetRangeView(
    setRaw: Int,
    range: RuntimeSortedRange
) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        return registerRuntimeObject(
            runtimeSortedSetBoxCreate(comparatorRaw: 0),
            typeID: navigableSetRuntimeTypeID
        )
    }
    return registerRuntimeObject(
        RuntimeSetBox(rangeViewOf: set, range: range),
        typeID: navigableSetRuntimeTypeID
    )
}

@_cdecl("__kk_sorted_set_head_set")
public func kk_sorted_set_head_set(
    _ setRaw: Int,
    _ toElement: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        let range = RuntimeSortedRange(lowerBoundRaw: nil, upperBoundRaw: toElement)
        if let set = runtimeSetBox(from: setRaw), !set.acceptsRangeView(range) {
            throw RuntimeThrownHandle(runtimeAllocateIllegalArgumentException(message: "Range endpoint outside existing view"))
        }
        return runtimeSortedSetRangeView(
            setRaw: setRaw,
            range: range
        )
    }
}

@_cdecl("__kk_sorted_set_tail_set")
public func kk_sorted_set_tail_set(
    _ setRaw: Int,
    _ fromElement: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        let range = RuntimeSortedRange(lowerBoundRaw: fromElement, upperBoundRaw: nil)
        if let set = runtimeSetBox(from: setRaw), !set.acceptsRangeView(range) {
            throw RuntimeThrownHandle(runtimeAllocateIllegalArgumentException(message: "Range endpoint outside existing view"))
        }
        return runtimeSortedSetRangeView(
            setRaw: setRaw,
            range: range
        )
    }
}

@_cdecl("__kk_sorted_set_sub_set")
public func kk_sorted_set_sub_set(
    _ setRaw: Int,
    _ fromElement: Int,
    _ toElement: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        let range = RuntimeSortedRange(lowerBoundRaw: fromElement, upperBoundRaw: toElement)
        if let set = runtimeSetBox(from: setRaw), !set.acceptsRangeView(range) {
            throw RuntimeThrownHandle(runtimeAllocateIllegalArgumentException(message: "Range endpoints outside existing view"))
        }
        return runtimeSortedSetRangeView(
            setRaw: setRaw,
            range: range
        )
    }
}

@_cdecl("__kk_sorted_set_lower")
public func kk_sorted_set_lower(_ setRaw: Int, _ element: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw),
          let bound = runtimeSortedSetBound(set: set, element: element, lowerSide: true, strict: true) else {
        return runtimeNullSentinelInt
    }
    return bound
}

@_cdecl("__kk_sorted_set_floor")
public func kk_sorted_set_floor(_ setRaw: Int, _ element: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw),
          let bound = runtimeSortedSetBound(set: set, element: element, lowerSide: true, strict: false) else {
        return runtimeNullSentinelInt
    }
    return bound
}

@_cdecl("__kk_sorted_set_ceiling")
public func kk_sorted_set_ceiling(_ setRaw: Int, _ element: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw),
          let bound = runtimeSortedSetBound(set: set, element: element, lowerSide: false, strict: false) else {
        return runtimeNullSentinelInt
    }
    return bound
}

@_cdecl("__kk_sorted_set_higher")
public func kk_sorted_set_higher(_ setRaw: Int, _ element: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw),
          let bound = runtimeSortedSetBound(set: set, element: element, lowerSide: false, strict: true) else {
        return runtimeNullSentinelInt
    }
    return bound
}

@_cdecl("__kk_sorted_set_poll_first")
public func kk_sorted_set_poll_first(_ setRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw), let first = set.values.first else {
        return runtimeNullSentinelInt
    }
    _ = set.remove(rawValue: first.legacyRawValue)
    return first.legacyRawValue
}

@_cdecl("__kk_sorted_set_poll_last")
public func kk_sorted_set_poll_last(_ setRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw), let last = set.values.last else {
        return runtimeNullSentinelInt
    }
    _ = set.remove(rawValue: last.legacyRawValue)
    return last.legacyRawValue
}

@_cdecl("__kk_sorted_set_descending")
public func kk_sorted_set_descending(_ setRaw: Int) -> Int {
    runtimeRegisterViewOrEmpty(
        from: setRaw,
        resolve: runtimeSetBox,
        makeEmpty: { RuntimeSetBox(elements: []) },
        makeView: { RuntimeSetBox(descendingViewOf: $0) },
        typeID: navigableSetRuntimeTypeID
    )
}

@_cdecl("__kk_sorted_set_descending_iterator")
public func kk_sorted_set_descending_iterator(_ setRaw: Int) -> Int {
    let descending = runtimeSetBox(from: setRaw).map { Array($0.elements.reversed()) } ?? []
    let iteratorBox = RuntimeListIteratorBox(elements: descending) { index in
        guard descending.indices.contains(index),
              let set = runtimeSetBox(from: setRaw) else { return }
        _ = set.remove(rawValue: descending[index])
    }
    let reflectedName = "java.util.TreeMap.NavigableSubMap.DescendingSubMapKeyIterator"
    iteratorBox.reflectedClassID = runtimeStableNominalTypeID(fqName: reflectedName)
    iteratorBox.reflectedClassName = reflectedName
    let raw = registerRuntimeObject(iteratorBox)
    registerListIteratorItable(raw: raw)
    return raw
}


private func runtimeSortedMapBoxCreate(comparatorRaw: Int) -> RuntimeMapBox {
    let box = RuntimeMapBox(keys: [], values: [])
    box.enableSorted(comparatorRaw: comparatorRaw)
    return box
}

private func runtimeSortedMapComparatorRaw(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw), map.sorted else { return 0 }
    return map.comparatorRaw
}

private func runtimeSortedMapCopyEntries(from mapRaw: Int, into box: RuntimeMapBox) {
    if let source = runtimeMapBox(from: mapRaw) {
        let keys = source.keys
        let values = source.values
        for (index, key) in keys.enumerated() where index < values.count {
            box.put(key: key, value: values[index])
        }
        return
    }
    guard let keysRaw = runtimeSourceMapKeys(mapRaw),
          let keys = runtimeIterableValues(from: keysRaw) else {
        return
    }
    for key in keys {
        box.put(
            key: key.legacyRawValue,
            value: runtimeSourceMapGet(mapRaw, key: key.legacyRawValue) ?? runtimeNullSentinelInt
        )
    }
}

private func runtimeSortedMapRangeView(
    mapRaw: Int,
    range: RuntimeSortedRange
) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return registerRuntimeObject(
            RuntimeMapBox(keys: [], values: []),
            typeID: navigableMapRuntimeTypeID
        )
    }
    return registerRuntimeObject(
        RuntimeMapBox(rangeViewOf: map, range: range),
        typeID: navigableMapRuntimeTypeID
    )
}

@_cdecl("__kk_sorted_map_sub_map")
public func kk_sorted_map_sub_map(
    _ mapRaw: Int,
    _ fromKey: Int,
    _ toKey: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        let range = RuntimeSortedRange(lowerBoundRaw: fromKey, upperBoundRaw: toKey)
        if let map = runtimeMapBox(from: mapRaw), !map.acceptsRangeView(range) {
            throw RuntimeThrownHandle(runtimeAllocateIllegalArgumentException(message: "Range endpoints outside existing view"))
        }
        return runtimeSortedMapRangeView(
            mapRaw: mapRaw,
            range: range
        )
    }
}

@_cdecl("__kk_sorted_map_head_map")
public func kk_sorted_map_head_map(
    _ mapRaw: Int,
    _ toKey: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        let range = RuntimeSortedRange(lowerBoundRaw: nil, upperBoundRaw: toKey)
        if let map = runtimeMapBox(from: mapRaw), !map.acceptsRangeView(range) {
            throw RuntimeThrownHandle(runtimeAllocateIllegalArgumentException(message: "Range endpoint outside existing view"))
        }
        return runtimeSortedMapRangeView(mapRaw: mapRaw, range: range)
    }
}

@_cdecl("__kk_sorted_map_tail_map")
public func kk_sorted_map_tail_map(
    _ mapRaw: Int,
    _ fromKey: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        let range = RuntimeSortedRange(lowerBoundRaw: fromKey, upperBoundRaw: nil)
        if let map = runtimeMapBox(from: mapRaw), !map.acceptsRangeView(range) {
            throw RuntimeThrownHandle(runtimeAllocateIllegalArgumentException(message: "Range endpoint outside existing view"))
        }
        return runtimeSortedMapRangeView(mapRaw: mapRaw, range: range)
    }
}

private func runtimeSortedMapBound(
    map: RuntimeMapBox,
    key: Int,
    lowerSide: Bool,
    strict: Bool
) -> Int? {
    let keys = map.keyValues
    var low = 0
    var high = keys.count - 1
    var result: Int?
    while low <= high {
        let mid = low + (high - low) / 2
        let comparison = map.sortedCompare(keys[mid].legacyRawValue, key)
        if lowerSide {
            if comparison < 0 || (!strict && comparison == 0) {
                result = keys[mid].legacyRawValue
                low = mid + 1
            } else {
                high = mid - 1
            }
        } else {
            if comparison > 0 || (!strict && comparison == 0) {
                result = keys[mid].legacyRawValue
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
    }
    return result
}


@_cdecl("__kk_tree_map_new")
public func kk_tree_map_new(_ comparatorRaw: Int) -> Int {
    registerRuntimeObject(runtimeSortedMapBoxCreate(comparatorRaw: comparatorRaw), typeID: treeMapRuntimeTypeID)
}

@_cdecl("__kk_tree_map_new_map")
public func kk_tree_map_new_map(_ mapRaw: Int) -> Int {
    let box = runtimeSortedMapBoxCreate(comparatorRaw: 0)
    runtimeSortedMapCopyEntries(from: mapRaw, into: box)
    return registerRuntimeObject(box, typeID: treeMapRuntimeTypeID)
}

@_cdecl("__kk_tree_map_new_sorted_map")
public func kk_tree_map_new_sorted_map(_ mapRaw: Int) -> Int {
    let box = runtimeSortedMapBoxCreate(comparatorRaw: runtimeSortedMapComparatorRaw(mapRaw))
    runtimeSortedMapCopyEntries(from: mapRaw, into: box)
    return registerRuntimeObject(box, typeID: treeMapRuntimeTypeID)
}

@_cdecl("__kk_tree_map_init")
public func kk_tree_map_init(_ mapRaw: Int, _ comparatorRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: mapRaw),
          let objectBox = tryCast(pointer, to: RuntimeObjectBox.self) else {
        return 0
    }
    objectBox.backingMapBox = runtimeSortedMapBoxCreate(comparatorRaw: comparatorRaw)
    return 0
}


@_cdecl("__kk_sorted_map_comparator")
public func kk_sorted_map_comparator(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw), map.sorted, map.comparatorRaw != 0 else {
        return runtimeNullSentinelInt
    }
    return map.comparatorRaw
}

@_cdecl("__kk_sorted_map_first_key")
public func kk_sorted_map_first_key(_ mapRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        guard let map = runtimeMapBox(from: mapRaw), let first = map.keys.first else {
            throw RuntimeThrownHandle(runtimeAllocateNoSuchElementException(message: nil))
        }
        return first
    }
}

@_cdecl("__kk_sorted_map_last_key")
public func kk_sorted_map_last_key(_ mapRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        guard let map = runtimeMapBox(from: mapRaw), let last = map.keys.last else {
            throw RuntimeThrownHandle(runtimeAllocateNoSuchElementException(message: nil))
        }
        return last
    }
}

@_cdecl("__kk_sorted_map_lower_key")
public func kk_sorted_map_lower_key(_ mapRaw: Int, _ key: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw),
          let bound = runtimeSortedMapBound(map: map, key: key, lowerSide: true, strict: true) else {
        return runtimeNullSentinelInt
    }
    return bound
}

@_cdecl("__kk_sorted_map_floor_key")
public func kk_sorted_map_floor_key(_ mapRaw: Int, _ key: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw),
          let bound = runtimeSortedMapBound(map: map, key: key, lowerSide: true, strict: false) else {
        return runtimeNullSentinelInt
    }
    return bound
}

@_cdecl("__kk_sorted_map_ceiling_key")
public func kk_sorted_map_ceiling_key(_ mapRaw: Int, _ key: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw),
          let bound = runtimeSortedMapBound(map: map, key: key, lowerSide: false, strict: false) else {
        return runtimeNullSentinelInt
    }
    return bound
}

@_cdecl("__kk_sorted_map_higher_key")
public func kk_sorted_map_higher_key(_ mapRaw: Int, _ key: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw),
          let bound = runtimeSortedMapBound(map: map, key: key, lowerSide: false, strict: true) else {
        return runtimeNullSentinelInt
    }
    return bound
}

@_cdecl("__kk_sorted_map_first_entry")
public func kk_sorted_map_first_entry(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw),
          let key = map.keys.first,
          let index = map.index(ofRawKey: key),
          let value = map.rawValue(at: index) else {
        return runtimeNullSentinelInt
    }
    return runtimeMapEntryNew(key: key, value: value)
}

@_cdecl("__kk_sorted_map_last_entry")
public func kk_sorted_map_last_entry(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw),
          let key = map.keys.last,
          let index = map.index(ofRawKey: key),
          let value = map.rawValue(at: index) else {
        return runtimeNullSentinelInt
    }
    return runtimeMapEntryNew(key: key, value: value)
}

@_cdecl("__kk_sorted_map_poll_first_entry")
public func kk_sorted_map_poll_first_entry(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw),
          let key = map.keys.first,
          let index = map.index(ofRawKey: key),
          let value = map.rawValue(at: index) else {
        return runtimeNullSentinelInt
    }
    _ = map.remove(key: key)
    return runtimeMapEntryNew(key: key, value: value)
}

@_cdecl("__kk_sorted_map_poll_last_entry")
public func kk_sorted_map_poll_last_entry(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw),
          let key = map.keys.last,
          let index = map.index(ofRawKey: key),
          let value = map.rawValue(at: index) else {
        return runtimeNullSentinelInt
    }
    _ = map.remove(key: key)
    return runtimeMapEntryNew(key: key, value: value)
}

@_cdecl("__kk_sorted_map_descending")
public func kk_sorted_map_descending(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []), typeID: navigableMapRuntimeTypeID)
    }
    return registerRuntimeObject(RuntimeMapBox(descendingViewOf: map), typeID: navigableMapRuntimeTypeID)
}

@_cdecl("__kk_sorted_map_descending_key_set")
public func kk_sorted_map_descending_key_set(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return registerRuntimeObject(RuntimeSetBox(elements: []), typeID: navigableSetRuntimeTypeID)
    }
    let keysView = RuntimeSetBox(mapKeysOf: mapRaw)
    keysView.enableSorted(comparatorRaw: map.comparatorRaw, invertCompare: map.invertCompare)
    return registerRuntimeObject(RuntimeSetBox(descendingViewOf: keysView), typeID: navigableSetRuntimeTypeID)
}
