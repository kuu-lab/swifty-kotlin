// java.util sorted-collection runtime (KUU-1361).
//
// `TreeSet`/`TreeMap` are ordinary `RuntimeSetBox`/`RuntimeMapBox` instances
// carrying comparator state (`sorted`/`comparatorRaw`), so every existing
// `__kk` collection bridge already operates on them. This file adds the
// entry points that construct those boxes and serve the
// SortedSet/NavigableSet/SortedMap/NavigableMap member surface declared in
// `Sources/CompilerCore/Stdlib/java/util/`.

// MARK: - Sorted set helpers

private func runtimeSortedSetBoxCreate(comparatorRaw: Int) -> RuntimeSetBox {
    let box = RuntimeSetBox(elements: [])
    box.enableSorted(comparatorRaw: comparatorRaw)
    return box
}

/// The comparator object stored on a sorted set box, or 0 for natural order.
/// Non-sorted and non-box receivers both answer 0.
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

// MARK: - TreeSet construction (__kk_tree_set_*)

/// `java.util.TreeSet(comparator)` / `java.util.TreeSet()` — a null-sentinel
/// or 0 comparator selects natural order.
@_cdecl("__kk_tree_set_new")
public func kk_tree_set_new(_ comparatorRaw: Int) -> Int {
    registerRuntimeObject(runtimeSortedSetBoxCreate(comparatorRaw: comparatorRaw), typeID: treeSetRuntimeTypeID)
}

/// `java.util.TreeSet(Collection)` — natural order; duplicates collapse under
/// natural comparison, matching `java.util.TreeSet.addAll` semantics.
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

/// `java.util.TreeSet(SortedSet)` — inherits the source comparator.
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

/// Attach a sorted backing box to a source-allocated TreeSet instance
/// (superclass-init path — `__kk_linked_hash_set_init` precedent). The
/// comparator argument arrives from the primary constructor parameter.
@_cdecl("__kk_tree_set_init")
public func kk_tree_set_init(_ setRaw: Int, _ comparatorRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: setRaw),
          let objectBox = tryCast(pointer, to: RuntimeObjectBox.self) else {
        return 0
    }
    objectBox.backingSetBox = runtimeSortedSetBoxCreate(comparatorRaw: comparatorRaw)
    return 0
}

// MARK: - SortedSet members (__kk_sorted_set_*)

/// `SortedSet.comparator()` — the stored comparator object, or null for
/// natural ordering.
@_cdecl("__kk_sorted_set_comparator")
public func kk_sorted_set_comparator(_ setRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw), set.sorted, set.comparatorRaw != 0 else {
        return runtimeNullSentinelInt
    }
    return set.comparatorRaw
}

/// `SortedSet.first()` — least element; throws NoSuchElementException on
/// empty. On descending views `values` is already reversed, so `first` is the
/// original set's greatest element, matching `descendingSet().first()`.
@_cdecl("__kk_sorted_set_first")
public func kk_sorted_set_first(_ setRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if let outThrown { outThrown.pointee = 0 }
    guard let set = runtimeSetBox(from: setRaw), let first = set.values.first else {
        runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: nil))
        return runtimeNullSentinelInt
    }
    return first.legacyRawValue
}

/// `SortedSet.last()` — greatest element; throws NoSuchElementException on
/// empty.
@_cdecl("__kk_sorted_set_last")
public func kk_sorted_set_last(_ setRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if let outThrown { outThrown.pointee = 0 }
    guard let set = runtimeSetBox(from: setRaw), let last = set.values.last else {
        runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: nil))
        return runtimeNullSentinelInt
    }
    return last.legacyRawValue
}

/// `NavigableSet.lower(e)` — greatest element strictly below `e`.
@_cdecl("__kk_sorted_set_lower")
public func kk_sorted_set_lower(_ setRaw: Int, _ element: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw),
          let bound = runtimeSortedSetBound(set: set, element: element, lowerSide: true, strict: true) else {
        return runtimeNullSentinelInt
    }
    return bound
}

/// `NavigableSet.floor(e)` — greatest element at or below `e`.
@_cdecl("__kk_sorted_set_floor")
public func kk_sorted_set_floor(_ setRaw: Int, _ element: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw),
          let bound = runtimeSortedSetBound(set: set, element: element, lowerSide: true, strict: false) else {
        return runtimeNullSentinelInt
    }
    return bound
}

/// `NavigableSet.ceiling(e)` — least element at or above `e`.
@_cdecl("__kk_sorted_set_ceiling")
public func kk_sorted_set_ceiling(_ setRaw: Int, _ element: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw),
          let bound = runtimeSortedSetBound(set: set, element: element, lowerSide: false, strict: false) else {
        return runtimeNullSentinelInt
    }
    return bound
}

/// `NavigableSet.higher(e)` — least element strictly above `e`.
@_cdecl("__kk_sorted_set_higher")
public func kk_sorted_set_higher(_ setRaw: Int, _ element: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw),
          let bound = runtimeSortedSetBound(set: set, element: element, lowerSide: false, strict: true) else {
        return runtimeNullSentinelInt
    }
    return bound
}

/// `NavigableSet.pollFirst()` — removes and returns the least element, or
/// null on empty.
@_cdecl("__kk_sorted_set_poll_first")
public func kk_sorted_set_poll_first(_ setRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw), let first = set.values.first else {
        return runtimeNullSentinelInt
    }
    _ = set.remove(rawValue: first.legacyRawValue)
    return first.legacyRawValue
}

/// `NavigableSet.pollLast()` — removes and returns the greatest element, or
/// null on empty.
@_cdecl("__kk_sorted_set_poll_last")
public func kk_sorted_set_poll_last(_ setRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw), let last = set.values.last else {
        return runtimeNullSentinelInt
    }
    _ = set.remove(rawValue: last.legacyRawValue)
    return last.legacyRawValue
}

/// `NavigableSet.descendingSet()` — a live reversed view sharing the parent's
/// storage, tagged as NavigableSet (matching `java.util.TreeSet`'s
/// descendingSet, which is not itself a TreeSet).
@_cdecl("__kk_sorted_set_descending")
public func kk_sorted_set_descending(_ setRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: setRaw) else {
        return registerRuntimeObject(RuntimeSetBox(elements: []), typeID: navigableSetRuntimeTypeID)
    }
    return registerRuntimeObject(RuntimeSetBox(descendingViewOf: set), typeID: navigableSetRuntimeTypeID)
}

/// `NavigableSet.descendingIterator()` — a MutableIterator over the reversed
/// view whose `remove()` writes through to the set (same RuntimeListIteratorBox
/// removeAction mechanism `kk_list_iterator` uses for set receivers).
@_cdecl("__kk_sorted_set_descending_iterator")
public func kk_sorted_set_descending_iterator(_ setRaw: Int) -> Int {
    let descending = runtimeSetBox(from: setRaw).map { Array($0.elements.reversed()) } ?? []
    let iteratorBox = RuntimeListIteratorBox(elements: descending) { index in
        guard descending.indices.contains(index),
              let set = runtimeSetBox(from: setRaw) else { return }
        _ = set.remove(rawValue: descending[index])
    }
    let raw = registerRuntimeObject(iteratorBox)
    registerListIteratorItable(raw: raw)
    return raw
}

// MARK: - Sorted map helpers

private func runtimeSortedMapBoxCreate(comparatorRaw: Int) -> RuntimeMapBox {
    let box = RuntimeMapBox(keys: [], values: [])
    box.enableSorted(comparatorRaw: comparatorRaw)
    return box
}

private func runtimeSortedMapComparatorRaw(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw), map.sorted else { return 0 }
    return map.comparatorRaw
}

/// Copy every entry of `mapRaw` into `box` through `put`, preserving the
/// destination's comparator order. Handles both box-backed maps and
/// source-implemented `Map` receivers (which expose keys/get through their
/// itable).
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

/// Binary-search a navigable key bound over the map's key order — same
/// lower/floor vs ceiling/higher parameterization as `runtimeSortedSetBound`.
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

// MARK: - TreeMap construction (__kk_tree_map_*)

/// `java.util.TreeMap(comparator)` / `java.util.TreeMap()`.
@_cdecl("__kk_tree_map_new")
public func kk_tree_map_new(_ comparatorRaw: Int) -> Int {
    registerRuntimeObject(runtimeSortedMapBoxCreate(comparatorRaw: comparatorRaw), typeID: treeMapRuntimeTypeID)
}

/// `java.util.TreeMap(Map)` — natural key order.
@_cdecl("__kk_tree_map_new_map")
public func kk_tree_map_new_map(_ mapRaw: Int) -> Int {
    let box = runtimeSortedMapBoxCreate(comparatorRaw: 0)
    runtimeSortedMapCopyEntries(from: mapRaw, into: box)
    return registerRuntimeObject(box, typeID: treeMapRuntimeTypeID)
}

/// `java.util.TreeMap(SortedMap)` — inherits the source comparator.
@_cdecl("__kk_tree_map_new_sorted_map")
public func kk_tree_map_new_sorted_map(_ mapRaw: Int) -> Int {
    let box = runtimeSortedMapBoxCreate(comparatorRaw: runtimeSortedMapComparatorRaw(mapRaw))
    runtimeSortedMapCopyEntries(from: mapRaw, into: box)
    return registerRuntimeObject(box, typeID: treeMapRuntimeTypeID)
}

/// Attach a sorted backing box to a source-allocated TreeMap instance.
@_cdecl("__kk_tree_map_init")
public func kk_tree_map_init(_ mapRaw: Int, _ comparatorRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: mapRaw),
          let objectBox = tryCast(pointer, to: RuntimeObjectBox.self) else {
        return 0
    }
    objectBox.backingMapBox = runtimeSortedMapBoxCreate(comparatorRaw: comparatorRaw)
    return 0
}

// MARK: - SortedMap members (__kk_sorted_map_*)

/// `SortedMap.comparator()` — the stored comparator object, or null.
@_cdecl("__kk_sorted_map_comparator")
public func kk_sorted_map_comparator(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw), map.sorted, map.comparatorRaw != 0 else {
        return runtimeNullSentinelInt
    }
    return map.comparatorRaw
}

/// `SortedMap.firstKey()` — least key; throws NoSuchElementException on
/// empty. On descending views `keys` is already reversed, so `firstKey` is
/// the original map's greatest key, matching `descendingMap().firstKey()`.
@_cdecl("__kk_sorted_map_first_key")
public func kk_sorted_map_first_key(_ mapRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if let outThrown { outThrown.pointee = 0 }
    guard let map = runtimeMapBox(from: mapRaw), let first = map.keys.first else {
        runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: nil))
        return runtimeNullSentinelInt
    }
    return first
}

/// `SortedMap.lastKey()` — greatest key; throws NoSuchElementException on
/// empty.
@_cdecl("__kk_sorted_map_last_key")
public func kk_sorted_map_last_key(_ mapRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if let outThrown { outThrown.pointee = 0 }
    guard let map = runtimeMapBox(from: mapRaw), let last = map.keys.last else {
        runtimeSetThrown(outThrown, runtimeAllocateNoSuchElementException(message: nil))
        return runtimeNullSentinelInt
    }
    return last
}

/// `NavigableMap.lowerKey(k)` — greatest key strictly below `k`.
@_cdecl("__kk_sorted_map_lower_key")
public func kk_sorted_map_lower_key(_ mapRaw: Int, _ key: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw),
          let bound = runtimeSortedMapBound(map: map, key: key, lowerSide: true, strict: true) else {
        return runtimeNullSentinelInt
    }
    return bound
}

/// `NavigableMap.floorKey(k)` — greatest key at or below `k`.
@_cdecl("__kk_sorted_map_floor_key")
public func kk_sorted_map_floor_key(_ mapRaw: Int, _ key: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw),
          let bound = runtimeSortedMapBound(map: map, key: key, lowerSide: true, strict: false) else {
        return runtimeNullSentinelInt
    }
    return bound
}

/// `NavigableMap.ceilingKey(k)` — least key at or above `k`.
@_cdecl("__kk_sorted_map_ceiling_key")
public func kk_sorted_map_ceiling_key(_ mapRaw: Int, _ key: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw),
          let bound = runtimeSortedMapBound(map: map, key: key, lowerSide: false, strict: false) else {
        return runtimeNullSentinelInt
    }
    return bound
}

/// `NavigableMap.higherKey(k)` — least key strictly above `k`.
@_cdecl("__kk_sorted_map_higher_key")
public func kk_sorted_map_higher_key(_ mapRaw: Int, _ key: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw),
          let bound = runtimeSortedMapBound(map: map, key: key, lowerSide: false, strict: true) else {
        return runtimeNullSentinelInt
    }
    return bound
}

/// `NavigableMap.firstEntry()` — detached snapshot entry (JVM returns an
/// immutable entry; a plain pair box is its closest analogue).
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

/// `NavigableMap.lastEntry()` — detached snapshot entry.
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

/// `NavigableMap.pollFirstEntry()` — removes the least entry and returns a
/// detached snapshot (JVM's returned entry is not live).
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

/// `NavigableMap.pollLastEntry()` — removes the greatest entry and returns a
/// detached snapshot.
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

/// `NavigableMap.descendingMap()` — a live reversed view sharing the parent's
/// storage, tagged as NavigableMap.
@_cdecl("__kk_sorted_map_descending")
public func kk_sorted_map_descending(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return registerRuntimeObject(RuntimeMapBox(keys: [], values: []), typeID: navigableMapRuntimeTypeID)
    }
    return registerRuntimeObject(RuntimeMapBox(descendingViewOf: map), typeID: navigableMapRuntimeTypeID)
}

/// `NavigableMap.descendingKeySet()` — a live reversed view over the map's
/// keys: a `descendingViewOf` wrapper around a `mapKeysOf` view, so removes
/// write through to the map and the iteration is the reversed key order.
@_cdecl("__kk_sorted_map_descending_key_set")
public func kk_sorted_map_descending_key_set(_ mapRaw: Int) -> Int {
    guard let map = runtimeMapBox(from: mapRaw) else {
        return registerRuntimeObject(RuntimeSetBox(elements: []), typeID: navigableSetRuntimeTypeID)
    }
    let keysView = RuntimeSetBox(mapKeysOf: mapRaw)
    keysView.enableSorted(comparatorRaw: map.comparatorRaw, invertCompare: map.invertCompare)
    return registerRuntimeObject(RuntimeSetBox(descendingViewOf: keysView), typeID: navigableSetRuntimeTypeID)
}
