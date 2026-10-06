import Foundation
@testable import Runtime
import Testing

// KUU-1361: sorted collection boxes — ordering, navigation, descending
// views, and comparator dispatch.

private let comparatorInterfaceTypeID = runtimeStableNominalTypeID(fqName: "kotlin.Comparator")

private let reverseIntCompare: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, lhs, rhs, outThrown in
    outThrown?.pointee = 0
    if lhs == rhs { return kk_box_int(0) }
    return kk_box_int(lhs < rhs ? 1 : -1)
}

private func makeReverseComparator() -> Int {
    let object = kk_object_new(0, 0)
    runtimeRegisterObjectType(rawValue: object, classID: comparatorInterfaceTypeID)
    _ = kk_object_register_itable_iface(object, Int(comparatorInterfaceTypeID), 0)
    _ = kk_object_register_itable_method(
        object,
        0,
        0,
        unsafeBitCast(reverseIntCompare, to: Int.self)
    )
    return object
}

private func makeTreeSet(_ elements: [Int], comparatorRaw: Int = 0) -> Int {
    let raw = kk_tree_set_new(comparatorRaw)
    for element in elements {
        _ = kk_mutable_collection_add(raw, element)
    }
    return raw
}

private func setElements(_ raw: Int) -> [Int] {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let box = tryCast(ptr, to: RuntimeSetBox.self)
    else {
        return []
    }
    return box.elements
}

private func makeTreeMap(_ pairs: [(Int, Int)], comparatorRaw: Int = 0) -> Int {
    let raw = kk_tree_map_new(comparatorRaw)
    var thrown = 0
    for (key, value) in pairs {
        _ = kk_mutable_map_put(raw, key, value, &thrown)
    }
    return raw
}

private func mapKeys(_ raw: Int) -> [Int] {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let box = tryCast(ptr, to: RuntimeMapBox.self)
    else {
        return []
    }
    return box.keys
}

@Suite(.runtimeIsolation(.all))
struct RuntimeSortedCollectionTests {
    @Test
    func treeSetSortsAndDedupesOnInsert() {
        let set = makeTreeSet([3, 1, 2, 1, 3])
        #expect(setElements(set) == [1, 2, 3])
    }

    @Test
    func treeSetNavigationBoundsAndNulls() {
        let set = makeTreeSet([1, 3, 5, 7])
        #expect(kk_sorted_set_lower(set, 5) == 3)
        #expect(kk_sorted_set_floor(set, 5) == 5)
        #expect(kk_sorted_set_floor(set, 4) == 3)
        #expect(kk_sorted_set_ceiling(set, 4) == 5)
        #expect(kk_sorted_set_higher(set, 5) == 7)
        #expect(kk_sorted_set_lower(set, 1) == runtimeNullSentinelInt)
        #expect(kk_sorted_set_higher(set, 7) == runtimeNullSentinelInt)
    }

    @Test
    func treeSetFirstLastAndEmptyThrow() {
        var thrown = 0
        let set = makeTreeSet([4, 2, 6])
        #expect(kk_sorted_set_first(set, &thrown) == 2)
        #expect(thrown == 0)
        #expect(kk_sorted_set_last(set, &thrown) == 6)
        #expect(thrown == 0)
        let empty = kk_tree_set_new(0)
        _ = kk_sorted_set_first(empty, &thrown)
        #expect(thrown != 0)
        thrown = 0
        _ = kk_sorted_set_last(empty, &thrown)
        #expect(thrown != 0)
    }

    @Test
    func treeSetPollRemovesExtremes() {
        let set = makeTreeSet([1, 3, 5])
        #expect(kk_sorted_set_poll_first(set) == 1)
        #expect(kk_sorted_set_poll_last(set) == 5)
        #expect(setElements(set) == [3])
        #expect(kk_sorted_set_poll_first(makeTreeSet([])) == runtimeNullSentinelInt)
    }

    @Test
    func descendingSetIsLiveReversedView() {
        let set = makeTreeSet([1, 2, 3, 4])
        let descending = kk_sorted_set_descending(set)
        #expect(setElements(descending) == [4, 3, 2, 1])
        _ = kk_mutable_collection_add(descending, 5)
        #expect(setElements(set) == [1, 2, 3, 4, 5])
        #expect(setElements(descending) == [5, 4, 3, 2, 1])
    }

    @Test
    func descendingIteratorWalksBackwards() {
        let set = makeTreeSet([1, 2, 3])
        let iterator = kk_sorted_set_descending_iterator(set)
        var thrown = 0
        var visited: [Int] = []
        while kk_iterator_hasNext(iterator, &thrown) != 0 {
            visited.append(kk_iterator_next(iterator, &thrown))
        }
        #expect(visited == [3, 2, 1])
        #expect(thrown == 0)
    }

    @Test
    func treeSetHonoursComparator() {
        let set = makeTreeSet([1, 2, 3], comparatorRaw: makeReverseComparator())
        #expect(setElements(set) == [3, 2, 1])
        #expect(kk_sorted_set_comparator(set) != runtimeNullSentinelInt)
        #expect(kk_sorted_set_comparator(makeTreeSet([1])) == runtimeNullSentinelInt)
    }

    @Test
    func treeSetCopyConstructors() {
        let list = registerRuntimeObject(RuntimeListBox(elements: [3, 1, 2]))
        let copied = kk_tree_set_new_collection(list)
        #expect(setElements(copied) == [1, 2, 3])
        let source = makeTreeSet([1, 2, 3], comparatorRaw: makeReverseComparator())
        let reordered = kk_tree_set_new_sorted_set(source)
        #expect(setElements(reordered) == [3, 2, 1])
    }

    @Test
    func treeMapSortsKeysAndReadsValues() {
        let map = makeTreeMap([(3, 30), (1, 10), (2, 20)])
        #expect(mapKeys(map) == [1, 2, 3])
        #expect(kk_map_get(map, 2) == 20)
    }

    @Test
    func treeMapNavigation() {
        let map = makeTreeMap([(1, 10), (3, 30), (5, 50)])
        #expect(kk_sorted_map_lower_key(map, 3) == 1)
        #expect(kk_sorted_map_floor_key(map, 4) == 3)
        #expect(kk_sorted_map_ceiling_key(map, 4) == 5)
        #expect(kk_sorted_map_higher_key(map, 3) == 5)
        #expect(kk_sorted_map_lower_key(map, 1) == runtimeNullSentinelInt)
        #expect(kk_sorted_map_higher_key(map, 5) == runtimeNullSentinelInt)
        var thrown = 0
        #expect(kk_sorted_map_first_key(map, &thrown) == 1)
        #expect(kk_sorted_map_last_key(map, &thrown) == 5)
        let empty = kk_tree_map_new(0)
        thrown = 0
        _ = kk_sorted_map_first_key(empty, &thrown)
        #expect(thrown != 0)
    }

    @Test
    func treeMapEntryAndPollEntrySnapshots() {
        let map = makeTreeMap([(1, 10), (2, 20), (3, 30)])
        let first = kk_sorted_map_first_entry(map)
        #expect(kk_pair_first(first) == 1)
        #expect(kk_pair_second(first) == 10)
        let last = kk_sorted_map_last_entry(map)
        #expect(kk_pair_first(last) == 3)
        #expect(kk_pair_second(last) == 30)
        let polledFirst = kk_sorted_map_poll_first_entry(map)
        #expect(kk_pair_first(polledFirst) == 1)
        let polledLast = kk_sorted_map_poll_last_entry(map)
        #expect(kk_pair_first(polledLast) == 3)
        #expect(mapKeys(map) == [2])
        #expect(kk_sorted_map_first_entry(kk_tree_map_new(0)) == runtimeNullSentinelInt)
    }

    @Test
    func descendingMapAndKeySetAreLiveViews() {
        let map = makeTreeMap([(1, 10), (2, 20), (3, 30)])
        let descending = kk_sorted_map_descending(map)
        #expect(mapKeys(descending) == [3, 2, 1])
        let keys = kk_sorted_map_descending_key_set(map)
        #expect(setElements(keys) == [3, 2, 1])
        var thrown = 0
        _ = kk_mutable_map_put(descending, 4, 40, &thrown)
        #expect(mapKeys(map) == [1, 2, 3, 4])
        #expect(mapKeys(descending) == [4, 3, 2, 1])
        #expect(kk_map_get(map, 4) == 40)
    }

    @Test
    func treeMapHonoursComparatorAndCopyConstructors() {
        let map = makeTreeMap([(1, 10), (2, 20), (3, 30)], comparatorRaw: makeReverseComparator())
        #expect(mapKeys(map) == [3, 2, 1])
        #expect(kk_sorted_map_comparator(map) != runtimeNullSentinelInt)
        let plain = registerRuntimeObject(RuntimeMapBox(keys: [2, 1], values: [20, 10]))
        let copied = kk_tree_map_new_map(plain)
        #expect(mapKeys(copied) == [1, 2])
        let reordered = kk_tree_map_new_sorted_map(map)
        #expect(mapKeys(reordered) == [3, 2, 1])
    }

    @Test
    func sortedTypeIDsFormTheExpectedHierarchy() {
        registerSortedCollectionTypeEdgesOnce()
        #expect(runtimeIsAssignable(sourceTypeID: treeSetRuntimeTypeID, targetTypeID: navigableSetRuntimeTypeID))
        #expect(runtimeIsAssignable(sourceTypeID: navigableSetRuntimeTypeID, targetTypeID: sortedSetRuntimeTypeID))
        #expect(runtimeIsAssignable(sourceTypeID: treeSetRuntimeTypeID, targetTypeID: sortedSetRuntimeTypeID))
        #expect(runtimeIsAssignable(sourceTypeID: treeMapRuntimeTypeID, targetTypeID: navigableMapRuntimeTypeID))
        #expect(runtimeIsAssignable(sourceTypeID: navigableMapRuntimeTypeID, targetTypeID: sortedMapRuntimeTypeID))
        #expect(runtimeIsAssignable(sourceTypeID: treeMapRuntimeTypeID, targetTypeID: sortedMapRuntimeTypeID))
        #expect(runtimeIsAssignable(sourceTypeID: treeSetRuntimeTypeID, targetTypeID: setRuntimeTypeID))
        #expect(runtimeIsAssignable(sourceTypeID: treeMapRuntimeTypeID, targetTypeID: mutableMapRuntimeTypeID))
    }
}
