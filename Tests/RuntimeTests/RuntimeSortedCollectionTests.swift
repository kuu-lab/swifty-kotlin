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

private func makeTreeMap(_ pairs: [(String, Int)]) -> Int {
    let raw = kk_tree_map_new(0)
    var thrown = 0
    for (key, value) in pairs {
        _ = kk_mutable_map_put(raw, runtimeString(key), value, &thrown)
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

private func mapStringKeys(_ raw: Int) -> [String] {
    mapKeys(raw).map { runtimeString($0) }
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
    func sortedSetRangeViewsStayLiveAndRejectOutOfRangeAdds() {
        let set = makeTreeSet([1, 2, 4, 6])
        var thrown = 0
        let subset = kk_sorted_set_sub_set(set, 2, 5, &thrown)
        #expect(thrown == 0)
        #expect(setElements(subset) == [2, 4])

        _ = kk_mutable_set_add(set, 3, &thrown)
        #expect(thrown == 0)
        #expect(setElements(subset) == [2, 3, 4])

        _ = kk_mutable_set_remove(subset, 3, &thrown)
        #expect(thrown == 0)
        #expect(setElements(set) == [1, 2, 4, 6])

        _ = kk_mutable_set_add(subset, 5, &thrown)
        #expect(thrown != 0)
        #expect(setElements(set) == [1, 2, 4, 6])

        thrown = 0
        _ = kk_sorted_set_sub_set(set, 5, 2, &thrown)
        #expect(thrown != 0)
    }

    @Test
    func sortedSetNestedRangeViewsValidateParentEndpoints() {
        let set = makeTreeSet([1, 2, 4, 6])
        var thrown = 0
        let subset = kk_sorted_set_sub_set(set, 2, 5, &thrown)
        #expect(thrown == 0)
        #expect(setElements(kk_sorted_set_head_set(subset, 5, &thrown)) == [2, 4])
        #expect(thrown == 0)
        #expect(setElements(kk_sorted_set_tail_set(subset, 2, &thrown)) == [2, 4])
        #expect(thrown == 0)

        _ = kk_sorted_set_head_set(subset, 1, &thrown)
        #expect(thrown != 0)
        _ = kk_sorted_set_tail_set(subset, 6, &thrown)
        #expect(thrown != 0)
        _ = kk_sorted_set_sub_set(subset, 1, 3, &thrown)
        #expect(thrown != 0)
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
    func sortedMapRangeViewsStayLiveAndRejectOutOfRangePuts() {
        let map = makeTreeMap([(1, 10), (2, 20), (4, 40), (6, 60)])
        var thrown = 0
        let subMap = kk_sorted_map_sub_map(map, 2, 5, &thrown)
        #expect(thrown == 0)
        #expect(mapKeys(subMap) == [2, 4])
        #expect(runtimeValuesEqual(subMap, makeTreeMap([(2, 20), (4, 40)])))

        _ = kk_mutable_map_put(map, 3, 30, &thrown)
        #expect(thrown == 0)
        #expect(mapKeys(subMap) == [2, 3, 4])

        _ = kk_mutable_map_remove(subMap, 3, &thrown)
        #expect(thrown == 0)
        #expect(mapKeys(map) == [1, 2, 4, 6])

        _ = kk_mutable_map_put(subMap, 5, 50, &thrown)
        #expect(thrown != 0)
        #expect(mapKeys(map) == [1, 2, 4, 6])

        thrown = 0
        _ = kk_sorted_map_sub_map(map, 5, 2, &thrown)
        #expect(thrown != 0)
    }

    @Test
    func sortedMapHeadAndTailRangeViewsStayLive() {
        let map = makeTreeMap([(1, 10), (2, 20), (4, 40), (6, 60)])
        var thrown = 0

        let headMap = kk_sorted_map_head_map(map, 4, &thrown)
        #expect(thrown == 0)
        #expect(mapKeys(headMap) == [1, 2])

        let tailMap = kk_sorted_map_tail_map(map, 4, &thrown)
        #expect(thrown == 0)
        #expect(mapKeys(tailMap) == [4, 6])

        _ = kk_mutable_map_put(map, 3, 30, &thrown)
        #expect(thrown == 0)
        #expect(mapKeys(headMap) == [1, 2, 3])
        #expect(mapKeys(tailMap) == [4, 6])

        _ = kk_mutable_map_put(headMap, 4, 40, &thrown)
        #expect(thrown != 0)
        thrown = 0
        _ = kk_mutable_map_put(tailMap, 3, 30, &thrown)
        #expect(thrown != 0)

        thrown = 0
        let subMap = kk_sorted_map_sub_map(map, 2, 6, &thrown)
        #expect(thrown == 0)
        let nestedHeadMap = kk_sorted_map_head_map(subMap, 6, &thrown)
        #expect(thrown == 0)
        #expect(mapKeys(nestedHeadMap) == [2, 3, 4])
        let nestedTailMap = kk_sorted_map_tail_map(subMap, 2, &thrown)
        #expect(thrown == 0)
        #expect(mapKeys(nestedTailMap) == [2, 3, 4])

        _ = kk_sorted_map_head_map(subMap, 7, &thrown)
        #expect(thrown != 0)
        thrown = 0
        _ = kk_sorted_map_tail_map(subMap, 1, &thrown)
        #expect(thrown != 0)
    }

    @Test
    func sortedMapNestedRangeViewsValidateParentEndpoints() {
        let map = makeTreeMap([(1, 10), (2, 20), (4, 40), (6, 60)])
        var thrown = 0
        let subMap = kk_sorted_map_sub_map(map, 2, 5, &thrown)
        #expect(thrown == 0)
        #expect(mapKeys(kk_sorted_map_sub_map(subMap, 2, 5, &thrown)) == [2, 4])
        #expect(thrown == 0)

        _ = kk_sorted_map_sub_map(subMap, 1, 3, &thrown)
        #expect(thrown != 0)
        _ = kk_sorted_map_sub_map(subMap, 2, 6, &thrown)
        #expect(thrown != 0)
    }

    @Test
    func sortedMapRangeViewsCountIsEmptyAndValuesUseWindow() {
        let map = makeTreeMap([(1, 10), (2, 20), (4, 40), (6, 60), (8, 80), (10, 100)])
        var thrown = 0
        let subMap = kk_sorted_map_sub_map(map, 2, 8, &thrown)
        #expect(thrown == 0)
        #expect(kk_map_size(subMap) == 3)
        #expect(kk_map_is_empty(subMap) == 0)
        #expect(mapKeys(subMap) == [2, 4, 6])
        #expect(runtimeMapBox(from: subMap)?.values == [20, 40, 60])
        #expect(runtimeMapBox(from: subMap)?.entryValues.map(\.legacyRawValue) == [20, 40, 60])

        let empty = kk_sorted_map_sub_map(map, 3, 4, &thrown)
        #expect(thrown == 0)
        #expect(kk_map_size(empty) == 0)
        #expect(kk_map_is_empty(empty) == 1)
        #expect(mapKeys(empty) == [])

        let headMap = kk_sorted_map_head_map(map, 6, &thrown)
        let tailMap = kk_sorted_map_tail_map(map, 6, &thrown)
        #expect(thrown == 0)
        #expect(kk_map_size(headMap) == 3)
        #expect(mapKeys(headMap) == [1, 2, 4])
        #expect(kk_map_size(tailMap) == 3)
        #expect(mapKeys(tailMap) == [6, 8, 10])

        let nested = kk_sorted_map_sub_map(subMap, 4, 8, &thrown)
        #expect(thrown == 0)
        #expect(kk_map_size(nested) == 2)
        #expect(mapKeys(nested) == [4, 6])

        _ = kk_mutable_map_put(map, 5, 50, &thrown)
        #expect(thrown == 0)
        #expect(kk_map_size(subMap) == 4)
        #expect(kk_map_size(nested) == 3)
        _ = kk_mutable_map_remove(map, 4, &thrown)
        #expect(thrown == 0)
        #expect(kk_map_size(nested) == 2)
        #expect(mapKeys(nested) == [5, 6])
    }

    @Test
    func sortedMapDescendingRangeViewKeepsWindowOrder() {
        let map = makeTreeMap([(1, 10), (2, 20), (4, 40), (6, 60), (8, 80), (10, 100)])
        var thrown = 0
        let descending = kk_sorted_map_descending(map)
        #expect(mapKeys(descending) == [10, 8, 6, 4, 2, 1])
        #expect(kk_map_size(descending) == 6)
        #expect(kk_map_is_empty(descending) == 0)

        let ranged = kk_sorted_map_sub_map(descending, 8, 2, &thrown)
        #expect(thrown == 0)
        #expect(mapKeys(ranged) == [8, 6, 4])
        #expect(runtimeMapBox(from: ranged)?.values == [80, 60, 40])
        #expect(kk_map_size(ranged) == 3)
        #expect(kk_map_is_empty(ranged) == 0)

        _ = kk_mutable_map_put(map, 5, 50, &thrown)
        #expect(thrown == 0)
        #expect(mapKeys(ranged) == [8, 6, 5, 4])
        #expect(kk_map_size(ranged) == 4)
    }

    @Test
    func sortedMapStringKeyRangeViewUsesOrderedWindow() {
        let map = makeTreeMap([("a", 1), ("c", 3), ("e", 5), ("g", 7), ("i", 9)])
        var thrown = 0
        let subMap = kk_sorted_map_sub_map(map, runtimeString("b"), runtimeString("h"), &thrown)
        #expect(thrown == 0)
        #expect(kk_map_size(subMap) == 3)
        #expect(kk_map_is_empty(subMap) == 0)
        #expect(mapStringKeys(subMap) == ["c", "e", "g"])
        #expect(runtimeMapBox(from: subMap)?.values == [3, 5, 7])

        let empty = kk_sorted_map_sub_map(map, runtimeString("b"), runtimeString("c"), &thrown)
        #expect(thrown == 0)
        #expect(kk_map_size(empty) == 0)
        #expect(kk_map_is_empty(empty) == 1)
        #expect(mapStringKeys(empty) == [])
    }

    @Test
    func mutableMapIteratorOverRangeViewRemovesThroughView() {
        let map = makeTreeMap([(1, 10), (2, 20), (4, 40), (6, 60), (8, 80), (10, 100)])
        var thrown = 0
        let subMap = kk_sorted_map_sub_map(map, 2, 8, &thrown)
        #expect(thrown == 0)
        let iterator = kk_mutable_map_iterator(subMap)

        #expect(kk_mutable_map_iterator_hasNext(iterator) == 1)
        var entry = kk_mutable_map_iterator_next(iterator, &thrown)
        #expect(thrown == 0)
        #expect(kk_pair_first(entry) == 2)
        #expect(kk_pair_second(entry) == 20)
        _ = kk_mutable_map_iterator_remove(iterator, &thrown)
        #expect(thrown == 0)
        #expect(mapKeys(subMap) == [4, 6])

        entry = kk_mutable_map_iterator_next(iterator, &thrown)
        #expect(thrown == 0)
        #expect(kk_pair_first(entry) == 4)
        #expect(kk_pair_second(entry) == 40)
        _ = kk_mutable_map_iterator_remove(iterator, &thrown)
        #expect(thrown == 0)
        #expect(mapKeys(map) == [1, 6, 8, 10])
        #expect(mapKeys(subMap) == [6])

        #expect(kk_mutable_map_iterator_hasNext(iterator) == 1)
        entry = kk_mutable_map_iterator_next(iterator, &thrown)
        #expect(thrown == 0)
        #expect(kk_pair_first(entry) == 6)
        #expect(kk_pair_second(entry) == 60)
        #expect(kk_mutable_map_iterator_hasNext(iterator) == 0)
        _ = kk_mutable_map_iterator_next(iterator, &thrown)
        #expect(thrown != 0)
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
