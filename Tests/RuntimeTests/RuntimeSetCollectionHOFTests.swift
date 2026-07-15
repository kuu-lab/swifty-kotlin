#if canImport(Testing)
import Foundation
import Testing
@testable import Runtime

private final class SetHOFState: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var sum = 0

    func reset() { lock.lock(); calls = 0; sum = 0; lock.unlock() }
    func addCall() { lock.lock(); calls += 1; lock.unlock() }
    func addSum(_ value: Int) { lock.lock(); sum += value; lock.unlock() }
    func callsSnapshot() -> Int { lock.lock(); defer { lock.unlock() }; return calls }
    func sumSnapshot() -> Int { lock.lock(); defer { lock.unlock() }; return sum }
}

private let gSetHOFState = SetHOFState()

private let setFilterGTOne: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, v, _ in
    v > 1 ? 1 : 0
}

private let setFilterEven: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, v, _ in
    v % 2 == 0 ? 1 : 0
}

private let setMapTimesTwo: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, v, _ in
    v * 2
}

private let setFlatMapPair: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, v, _ in
    let arr = kk_array_new(2)
    var thrown = 0
    _ = kk_array_set(arr, 0, v, &thrown)
    _ = kk_array_set(arr, 1, v * 10, &thrown)
    return kk_list_of(arr, 2)
}

private let setForEachAccumulate: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, v, _ in
    gSetHOFState.addCall()
    gSetHOFState.addSum(v)
    return 0
}

private let setThrowingHOF: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "set HOF throw")
    return 0
}

@Suite(.serialized)
struct RuntimeSetCollectionHOFTests {
    init() {
        kk_runtime_force_reset()
        gSetHOFState.reset()
    }

    // MARK: - filter

    @Test
    func testSetFilterEmptySetReturnsEmptyList() {
        let result = kk_set_filter(makeSet([]), unsafeBitCast(setFilterGTOne, to: Int.self), 0, nil)
        #expect(listElements(result) == [])
    }

    @Test
    func testSetFilterAllMatchReturnsAllElements() {
        let result = kk_set_filter(makeSet([2, 3, 4]), unsafeBitCast(setFilterGTOne, to: Int.self), 0, nil)
        #expect(Set(listElements(result)) == Set([2, 3, 4]))
    }

    @Test
    func testSetFilterNoneMatchReturnsEmptyList() {
        let result = kk_set_filter(makeSet([0, 1]), unsafeBitCast(setFilterGTOne, to: Int.self), 0, nil)
        #expect(listElements(result) == [])
    }

    @Test
    func testSetFilterPartialMatchReturnsMatchingElements() {
        let result = kk_set_filter(makeSet([1, 2, 3]), unsafeBitCast(setFilterGTOne, to: Int.self), 0, nil)
        #expect(Set(listElements(result)) == Set([2, 3]))
    }

    @Test
    func testSetFilterPropagatesThrow() {
        var thrown = 0
        _ = kk_set_filter(makeSet([1]), unsafeBitCast(setThrowingHOF, to: Int.self), 0, &thrown)
        #expect(thrown != 0)
    }

    // MARK: - filterNot

    @Test
    func testSetFilterNotEmptySetReturnsEmptyList() {
        let result = kk_set_filterNot(makeSet([]), unsafeBitCast(setFilterGTOne, to: Int.self), 0, nil)
        #expect(listElements(result) == [])
    }

    @Test
    func testSetFilterNotExcludesMatchingElements() {
        let result = kk_set_filterNot(makeSet([1, 2, 3]), unsafeBitCast(setFilterGTOne, to: Int.self), 0, nil)
        #expect(listElements(result) == [1])
    }

    @Test
    func testSetFilterNotAllExcludedReturnsEmptyList() {
        let result = kk_set_filterNot(makeSet([2, 3, 4]), unsafeBitCast(setFilterGTOne, to: Int.self), 0, nil)
        #expect(listElements(result) == [])
    }

    @Test
    func testSetFilterNotPropagatesThrow() {
        var thrown = 0
        _ = kk_set_filterNot(makeSet([1]), unsafeBitCast(setThrowingHOF, to: Int.self), 0, &thrown)
        #expect(thrown != 0)
    }

    // MARK: - map

    @Test
    func testSetMapEmptySetReturnsEmptyList() {
        let result = kk_set_map(makeSet([]), unsafeBitCast(setMapTimesTwo, to: Int.self), 0, nil)
        #expect(listElements(result) == [])
    }

    @Test
    func testSetMapTransformsAllElements() {
        let result = kk_set_map(makeSet([1, 2, 3]), unsafeBitCast(setMapTimesTwo, to: Int.self), 0, nil)
        #expect(Set(listElements(result)) == Set([2, 4, 6]))
    }

    @Test
    func testSetMapPropagatesThrow() {
        var thrown = 0
        _ = kk_set_map(makeSet([1]), unsafeBitCast(setThrowingHOF, to: Int.self), 0, &thrown)
        #expect(thrown != 0)
    }

    // MARK: - flatMap

    @Test
    func testSetFlatMapEmptySetReturnsEmptyList() {
        let result = kk_set_flatMap(makeSet([]), unsafeBitCast(setFlatMapPair, to: Int.self), 0, nil)
        #expect(listElements(result) == [])
    }

    @Test
    func testSetFlatMapFlattensSubListsFromEachElement() {
        let result = kk_set_flatMap(makeSet([1, 2]), unsafeBitCast(setFlatMapPair, to: Int.self), 0, nil)
        #expect(Set(listElements(result)) == Set([1, 10, 2, 20]))
    }

    @Test
    func testSetFlatMapPropagatesThrow() {
        var thrown = 0
        _ = kk_set_flatMap(makeSet([1]), unsafeBitCast(setThrowingHOF, to: Int.self), 0, &thrown)
        #expect(thrown != 0)
    }

    // MARK: - all

    @Test
    func testSetAllEmptySetReturnsTrue() {
        #expect(kk_set_all(makeSet([]), unsafeBitCast(setFilterGTOne, to: Int.self), 0, nil) == 1)
    }

    @Test
    func testSetAllAllMatchReturnsTrue() {
        #expect(kk_set_all(makeSet([2, 3, 4]), unsafeBitCast(setFilterGTOne, to: Int.self), 0, nil) == 1)
    }

    @Test
    func testSetAllSomeDontMatchReturnsFalse() {
        #expect(kk_set_all(makeSet([1, 2, 3]), unsafeBitCast(setFilterGTOne, to: Int.self), 0, nil) == 0)
    }

    @Test
    func testSetAllPropagatesThrow() {
        var thrown = 0
        _ = kk_set_all(makeSet([1]), unsafeBitCast(setThrowingHOF, to: Int.self), 0, &thrown)
        #expect(thrown != 0)
    }

    // MARK: - any

    @Test
    func testSetAnyEmptySetNoPredicateReturnsFalse() {
        #expect(kk_set_any(makeSet([]), 0, 0, nil) == 0)
    }

    @Test
    func testSetAnyNonEmptySetNoPredicateReturnsTrue() {
        #expect(kk_set_any(makeSet([1, 2]), 0, 0, nil) == 1)
    }

    @Test
    func testSetAnyWithPredicateOneMatchReturnsTrue() {
        #expect(kk_set_any(makeSet([1, 2, 3]), unsafeBitCast(setFilterEven, to: Int.self), 0, nil) == 1)
    }

    @Test
    func testSetAnyWithPredicateNoMatchReturnsFalse() {
        #expect(kk_set_any(makeSet([1, 3, 5]), unsafeBitCast(setFilterEven, to: Int.self), 0, nil) == 0)
    }

    @Test
    func testSetAnyPropagatesThrow() {
        var thrown = 0
        _ = kk_set_any(makeSet([1]), unsafeBitCast(setThrowingHOF, to: Int.self), 0, &thrown)
        #expect(thrown != 0)
    }

    // MARK: - forEach

    @Test
    func testSetForEachEmptySetMakesNoCalls() {
        _ = kk_set_forEach(makeSet([]), unsafeBitCast(setForEachAccumulate, to: Int.self), 0, nil)
        #expect(gSetHOFState.callsSnapshot() == 0)
    }

    @Test
    func testSetForEachVisitsEachElementExactlyOnce() {
        _ = kk_set_forEach(makeSet([1, 2, 3]), unsafeBitCast(setForEachAccumulate, to: Int.self), 0, nil)
        #expect(gSetHOFState.callsSnapshot() == 3)
        #expect(gSetHOFState.sumSnapshot() == 6)
    }

    @Test
    func testSetForEachPropagatesThrow() {
        var thrown = 0
        _ = kk_set_forEach(makeSet([1]), unsafeBitCast(setThrowingHOF, to: Int.self), 0, &thrown)
        #expect(thrown != 0)
    }

    // MARK: - maxOrNull / minOrNull

    @Test
    func testSetMaxOrNullEmptySetReturnsNullSentinel() {
        #expect(kk_set_maxOrNull(makeSet([])) == runtimeNullSentinelInt)
    }

    @Test
    func testSetMaxOrNullSingleElementReturnsThatElement() {
        #expect(kk_set_maxOrNull(makeSet([7])) == 7)
    }

    @Test
    func testSetMaxOrNullReturnsLargestElement() {
        #expect(kk_set_maxOrNull(makeSet([3, 1, 4, 2])) == 4)
    }

    @Test
    func testSetMinOrNullEmptySetReturnsNullSentinel() {
        #expect(kk_set_minOrNull(makeSet([])) == runtimeNullSentinelInt)
    }

    @Test
    func testSetMinOrNullSingleElementReturnsThatElement() {
        #expect(kk_set_minOrNull(makeSet([7])) == 7)
    }

    @Test
    func testSetMinOrNullReturnsSmallestElement() {
        #expect(kk_set_minOrNull(makeSet([3, 1, 4, 2])) == 1)
    }

    // MARK: - sorted / sortedDescending

    @Test
    func testSetSortedEmptySetReturnsEmptyList() {
        #expect(listElements(kk_set_sorted(makeSet([]))) == [])
    }

    @Test
    func testSetSortedSingleElementReturnsSingletonList() {
        #expect(listElements(kk_set_sorted(makeSet([5]))) == [5])
    }

    @Test
    func testSetSortedReturnsElementsInAscendingOrder() {
        #expect(listElements(kk_set_sorted(makeSet([3, 1, 4, 2]))) == [1, 2, 3, 4])
    }

    @Test
    func testSetSortedDescendingEmptySetReturnsEmptyList() {
        #expect(listElements(kk_set_sortedDescending(makeSet([]))) == [])
    }

    @Test
    func testSetSortedDescendingSingleElementReturnsSingletonList() {
        #expect(listElements(kk_set_sortedDescending(makeSet([5]))) == [5])
    }

    @Test
    func testSetSortedDescendingReturnsElementsInDescendingOrder() {
        #expect(listElements(kk_set_sortedDescending(makeSet([3, 1, 4, 2]))) == [4, 3, 2, 1])
    }

    // MARK: - count (predicate)

    @Test
    func testSetCountPredicateNullFnPtrOnEmptySetReturnsZero() {
        #expect(kk_set_count_predicate(makeSet([]), 0, 0, nil) == 0)
    }

    @Test
    func testSetCountPredicateNullFnPtrReturnsElementCount() {
        #expect(kk_set_count_predicate(makeSet([1, 2, 3]), 0, 0, nil) == 3)
    }

    @Test
    func testSetCountPredicateCountsMatchingElements() {
        let count = kk_set_count_predicate(makeSet([1, 2, 3, 4]), unsafeBitCast(setFilterEven, to: Int.self), 0, nil)
        #expect(count == 2)
    }

    @Test
    func testSetCountPredicatePropagatesThrow() {
        var thrown = 0
        _ = kk_set_count_predicate(makeSet([1]), unsafeBitCast(setThrowingHOF, to: Int.self), 0, &thrown)
        #expect(thrown != 0)
    }

    // MARK: - first / last

    @Test
    func testSetFirstNonEmptyReturnsFirstInsertionOrderElement() {
        var thrown = 0
        let result = kk_set_first(makeSet([42, 7, 3]), &thrown)
        #expect(thrown == 0)
        #expect(result == 42)
    }

    @Test
    func testSetFirstEmptySetThrows() {
        var thrown = 0
        _ = kk_set_first(makeSet([]), &thrown)
        #expect(thrown != 0)
    }

    @Test
    func testSetLastNonEmptyReturnsLastInsertionOrderElement() {
        var thrown = 0
        let result = kk_set_last(makeSet([42, 7, 3]), &thrown)
        #expect(thrown == 0)
        #expect(result == 3)
    }

    @Test
    func testSetLastEmptySetThrows() {
        var thrown = 0
        _ = kk_set_last(makeSet([]), &thrown)
        #expect(thrown != 0)
    }

    // MARK: - lastOrNull

    @Test
    func testSetLastOrNullEmptySetReturnsNullSentinel() {
        #expect(kk_set_lastOrNull(makeSet([])) == runtimeNullSentinelInt)
    }

    @Test
    func testSetLastOrNullNonEmptyReturnsLastElement() {
        #expect(kk_set_lastOrNull(makeSet([10, 20, 30])) == 30)
    }

    // MARK: - singleOrNull

    @Test
    func testSetSingleOrNullEmptySetReturnsNullSentinel() {
        #expect(kk_set_singleOrNull(makeSet([])) == runtimeNullSentinelInt)
    }

    @Test
    func testSetSingleOrNullSingleElementReturnsThatElement() {
        #expect(kk_set_singleOrNull(makeSet([99])) == 99)
    }

    @Test
    func testSetSingleOrNullMultipleElementsReturnsNullSentinel() {
        #expect(kk_set_singleOrNull(makeSet([1, 2])) == runtimeNullSentinelInt)
    }

    // MARK: - Helpers

    private func makeArray(_ elements: [Int]) -> Int {
        let arr = kk_array_new(elements.count)
        var thrown = 0
        for (i, e) in elements.enumerated() {
            _ = kk_array_set(arr, i, e, &thrown)
            #expect(thrown == 0)
        }
        return arr
    }

    private func makeSet(_ elements: [Int]) -> Int {
        kk_set_of(makeArray(elements), elements.count)
    }

    private func listElements(_ listRaw: Int) -> [Int] {
        let size = kk_list_size(listRaw)
        guard size > 0 else { return [] }
        return (0 ..< size).map { kk_list_get(listRaw, $0) }
    }
}
#endif
