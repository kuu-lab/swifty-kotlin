import Foundation
@testable import Runtime
import XCTest

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

final class RuntimeSetCollectionHOFTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
        gSetHOFState.reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // MARK: - filter

    func testSetFilterEmptySetReturnsEmptyList() {
        let result = kk_set_filter(makeSet([]), unsafeBitCast(setFilterGTOne, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(result), [])
    }

    func testSetFilterAllMatchReturnsAllElements() {
        let result = kk_set_filter(makeSet([2, 3, 4]), unsafeBitCast(setFilterGTOne, to: Int.self), 0, nil)
        XCTAssertEqual(Set(listElements(result)), Set([2, 3, 4]))
    }

    func testSetFilterNoneMatchReturnsEmptyList() {
        let result = kk_set_filter(makeSet([0, 1]), unsafeBitCast(setFilterGTOne, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(result), [])
    }

    func testSetFilterPartialMatchReturnsMatchingElements() {
        let result = kk_set_filter(makeSet([1, 2, 3]), unsafeBitCast(setFilterGTOne, to: Int.self), 0, nil)
        XCTAssertEqual(Set(listElements(result)), Set([2, 3]))
    }

    func testSetFilterPropagatesThrow() {
        var thrown = 0
        _ = kk_set_filter(makeSet([1]), unsafeBitCast(setThrowingHOF, to: Int.self), 0, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    // MARK: - filterNot

    func testSetFilterNotEmptySetReturnsEmptyList() {
        let result = kk_set_filterNot(makeSet([]), unsafeBitCast(setFilterGTOne, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(result), [])
    }

    func testSetFilterNotExcludesMatchingElements() {
        let result = kk_set_filterNot(makeSet([1, 2, 3]), unsafeBitCast(setFilterGTOne, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(result), [1])
    }

    func testSetFilterNotAllExcludedReturnsEmptyList() {
        let result = kk_set_filterNot(makeSet([2, 3, 4]), unsafeBitCast(setFilterGTOne, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(result), [])
    }

    func testSetFilterNotPropagatesThrow() {
        var thrown = 0
        _ = kk_set_filterNot(makeSet([1]), unsafeBitCast(setThrowingHOF, to: Int.self), 0, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    // MARK: - map

    func testSetMapEmptySetReturnsEmptyList() {
        let result = kk_set_map(makeSet([]), unsafeBitCast(setMapTimesTwo, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(result), [])
    }

    func testSetMapTransformsAllElements() {
        let result = kk_set_map(makeSet([1, 2, 3]), unsafeBitCast(setMapTimesTwo, to: Int.self), 0, nil)
        XCTAssertEqual(Set(listElements(result)), Set([2, 4, 6]))
    }

    func testSetMapPropagatesThrow() {
        var thrown = 0
        _ = kk_set_map(makeSet([1]), unsafeBitCast(setThrowingHOF, to: Int.self), 0, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    // MARK: - flatMap

    func testSetFlatMapEmptySetReturnsEmptyList() {
        let result = kk_set_flatMap(makeSet([]), unsafeBitCast(setFlatMapPair, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(result), [])
    }

    func testSetFlatMapFlattensSubListsFromEachElement() {
        let result = kk_set_flatMap(makeSet([1, 2]), unsafeBitCast(setFlatMapPair, to: Int.self), 0, nil)
        XCTAssertEqual(Set(listElements(result)), Set([1, 10, 2, 20]))
    }

    func testSetFlatMapPropagatesThrow() {
        var thrown = 0
        _ = kk_set_flatMap(makeSet([1]), unsafeBitCast(setThrowingHOF, to: Int.self), 0, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    // MARK: - all

    func testSetAllEmptySetReturnsTrue() {
        XCTAssertEqual(kk_set_all(makeSet([]), unsafeBitCast(setFilterGTOne, to: Int.self), 0, nil), 1)
    }

    func testSetAllAllMatchReturnsTrue() {
        XCTAssertEqual(kk_set_all(makeSet([2, 3, 4]), unsafeBitCast(setFilterGTOne, to: Int.self), 0, nil), 1)
    }

    func testSetAllSomeDontMatchReturnsFalse() {
        XCTAssertEqual(kk_set_all(makeSet([1, 2, 3]), unsafeBitCast(setFilterGTOne, to: Int.self), 0, nil), 0)
    }

    func testSetAllPropagatesThrow() {
        var thrown = 0
        _ = kk_set_all(makeSet([1]), unsafeBitCast(setThrowingHOF, to: Int.self), 0, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    // MARK: - any

    func testSetAnyEmptySetNoPredicateReturnsFalse() {
        XCTAssertEqual(kk_set_any(makeSet([]), 0, 0, nil), 0)
    }

    func testSetAnyNonEmptySetNoPredicateReturnsTrue() {
        XCTAssertEqual(kk_set_any(makeSet([1, 2]), 0, 0, nil), 1)
    }

    func testSetAnyWithPredicateOneMatchReturnsTrue() {
        XCTAssertEqual(kk_set_any(makeSet([1, 2, 3]), unsafeBitCast(setFilterEven, to: Int.self), 0, nil), 1)
    }

    func testSetAnyWithPredicateNoMatchReturnsFalse() {
        XCTAssertEqual(kk_set_any(makeSet([1, 3, 5]), unsafeBitCast(setFilterEven, to: Int.self), 0, nil), 0)
    }

    func testSetAnyPropagatesThrow() {
        var thrown = 0
        _ = kk_set_any(makeSet([1]), unsafeBitCast(setThrowingHOF, to: Int.self), 0, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    // MARK: - forEach

    func testSetForEachEmptySetMakesNoCalls() {
        _ = kk_set_forEach(makeSet([]), unsafeBitCast(setForEachAccumulate, to: Int.self), 0, nil)
        XCTAssertEqual(gSetHOFState.callsSnapshot(), 0)
    }

    func testSetForEachVisitsEachElementExactlyOnce() {
        _ = kk_set_forEach(makeSet([1, 2, 3]), unsafeBitCast(setForEachAccumulate, to: Int.self), 0, nil)
        XCTAssertEqual(gSetHOFState.callsSnapshot(), 3)
        XCTAssertEqual(gSetHOFState.sumSnapshot(), 6)
    }

    func testSetForEachPropagatesThrow() {
        var thrown = 0
        _ = kk_set_forEach(makeSet([1]), unsafeBitCast(setThrowingHOF, to: Int.self), 0, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    // MARK: - maxOrNull / minOrNull

    func testSetMaxOrNullEmptySetReturnsNullSentinel() {
        XCTAssertEqual(kk_set_maxOrNull(makeSet([])), runtimeNullSentinelInt)
    }

    func testSetMaxOrNullSingleElementReturnsThatElement() {
        XCTAssertEqual(kk_set_maxOrNull(makeSet([7])), 7)
    }

    func testSetMaxOrNullReturnsLargestElement() {
        XCTAssertEqual(kk_set_maxOrNull(makeSet([3, 1, 4, 2])), 4)
    }

    func testSetMinOrNullEmptySetReturnsNullSentinel() {
        XCTAssertEqual(kk_set_minOrNull(makeSet([])), runtimeNullSentinelInt)
    }

    func testSetMinOrNullSingleElementReturnsThatElement() {
        XCTAssertEqual(kk_set_minOrNull(makeSet([7])), 7)
    }

    func testSetMinOrNullReturnsSmallestElement() {
        XCTAssertEqual(kk_set_minOrNull(makeSet([3, 1, 4, 2])), 1)
    }

    // MARK: - sorted / sortedDescending

    func testSetSortedEmptySetReturnsEmptyList() {
        XCTAssertEqual(listElements(kk_set_sorted(makeSet([]))), [])
    }

    func testSetSortedSingleElementReturnsSingletonList() {
        XCTAssertEqual(listElements(kk_set_sorted(makeSet([5]))), [5])
    }

    func testSetSortedReturnsElementsInAscendingOrder() {
        XCTAssertEqual(listElements(kk_set_sorted(makeSet([3, 1, 4, 2]))), [1, 2, 3, 4])
    }

    func testSetSortedDescendingEmptySetReturnsEmptyList() {
        XCTAssertEqual(listElements(kk_set_sortedDescending(makeSet([]))), [])
    }

    func testSetSortedDescendingSingleElementReturnsSingletonList() {
        XCTAssertEqual(listElements(kk_set_sortedDescending(makeSet([5]))), [5])
    }

    func testSetSortedDescendingReturnsElementsInDescendingOrder() {
        XCTAssertEqual(listElements(kk_set_sortedDescending(makeSet([3, 1, 4, 2]))), [4, 3, 2, 1])
    }

    // MARK: - count (predicate)

    func testSetCountPredicateNullFnPtrOnEmptySetReturnsZero() {
        XCTAssertEqual(kk_set_count_predicate(makeSet([]), 0, 0, nil), 0)
    }

    func testSetCountPredicateNullFnPtrReturnsElementCount() {
        XCTAssertEqual(kk_set_count_predicate(makeSet([1, 2, 3]), 0, 0, nil), 3)
    }

    func testSetCountPredicateCountsMatchingElements() {
        let count = kk_set_count_predicate(makeSet([1, 2, 3, 4]), unsafeBitCast(setFilterEven, to: Int.self), 0, nil)
        XCTAssertEqual(count, 2)
    }

    func testSetCountPredicatePropagatesThrow() {
        var thrown = 0
        _ = kk_set_count_predicate(makeSet([1]), unsafeBitCast(setThrowingHOF, to: Int.self), 0, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    // MARK: - first / last

    func testSetFirstNonEmptyReturnsFirstInsertionOrderElement() {
        var thrown = 0
        let result = kk_set_first(makeSet([42, 7, 3]), &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 42)
    }

    func testSetFirstEmptySetThrows() {
        var thrown = 0
        _ = kk_set_first(makeSet([]), &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    func testSetLastNonEmptyReturnsLastInsertionOrderElement() {
        var thrown = 0
        let result = kk_set_last(makeSet([42, 7, 3]), &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 3)
    }

    func testSetLastEmptySetThrows() {
        var thrown = 0
        _ = kk_set_last(makeSet([]), &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    // MARK: - lastOrNull

    func testSetLastOrNullEmptySetReturnsNullSentinel() {
        XCTAssertEqual(kk_set_lastOrNull(makeSet([])), runtimeNullSentinelInt)
    }

    func testSetLastOrNullNonEmptyReturnsLastElement() {
        XCTAssertEqual(kk_set_lastOrNull(makeSet([10, 20, 30])), 30)
    }

    // MARK: - singleOrNull

    func testSetSingleOrNullEmptySetReturnsNullSentinel() {
        XCTAssertEqual(kk_set_singleOrNull(makeSet([])), runtimeNullSentinelInt)
    }

    func testSetSingleOrNullSingleElementReturnsThatElement() {
        XCTAssertEqual(kk_set_singleOrNull(makeSet([99])), 99)
    }

    func testSetSingleOrNullMultipleElementsReturnsNullSentinel() {
        XCTAssertEqual(kk_set_singleOrNull(makeSet([1, 2])), runtimeNullSentinelInt)
    }

    // MARK: - Helpers

    private func makeArray(_ elements: [Int]) -> Int {
        let arr = kk_array_new(elements.count)
        var thrown = 0
        for (i, e) in elements.enumerated() {
            _ = kk_array_set(arr, i, e, &thrown)
            XCTAssertEqual(thrown, 0)
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
