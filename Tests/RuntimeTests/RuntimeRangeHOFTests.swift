@testable import Runtime
import XCTest

private let rangeMapDouble: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value * 2
}

private let rangeFilterNotEven: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 2 == 0 ? 1 : 0
}

private let rangeFoldIndexedSum: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, acc, value, _ in
    acc + index + value
}

private let rangeMapIndexedSum: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
    index + value
}

private let rangeForEachAccumulate: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { closurePtr, value, _ in
    UnsafeMutablePointer<Int>(bitPattern: closurePtr)!.pointee += value
    return 0
}

// Returns the runtime null sentinel for even values so mapNotNull filters them out
private let rangeMapNotNullOddOnly: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 2 == 0 ? runtimeNullSentinelInt : value
}

private let rangeFilterIndexedEvenIndex: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, _, _ in
    index % 2 == 0 ? 1 : 0
}

private let rangeReduceIndexedAccPlusIndexPlusValue: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, acc, value, _ in
    acc + index + value
}

private let rangePredicateEven: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 2 == 0 ? 1 : 0
}

final class RuntimeRangeHOFTests: XCTestCase {
    func testRangeMapProducesMappedList() {
        let range = kk_op_rangeTo(1, 4)
        let mapped = kk_range_map(range, unsafeBitCast(rangeMapDouble, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(mapped), [2, 4, 6, 8])
    }

    func testRangeFilterNotDropsMatchingElements() {
        let range = kk_op_rangeTo(1, 5)
        let filtered = kk_range_filterNot(range, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(filtered), [1, 3, 5])
    }

    func testRangeFoldIndexedAccumulatesWithIndex() {
        let range = kk_op_rangeTo(1, 3)
        let result = kk_range_foldIndexed(range, 10, unsafeBitCast(rangeFoldIndexedSum, to: Int.self), 0, nil)
        XCTAssertEqual(result, 19)
    }

    func testRangeFirstAndLastOrNullWithoutPredicate() {
        let range = kk_op_rangeTo(1, 4)
        XCTAssertEqual(kk_range_firstOrNull(range), 1)
        XCTAssertEqual(kk_range_lastOrNull(range), 4)
    }

    func testUIntRangeMapIndexedUsesUnsignedLowering() {
        let range = kk_uint_rangeTo(1, 4)
        let mapped = kk_uint_range_mapIndexed(range, unsafeBitCast(rangeMapIndexedSum, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(mapped), [1, 3, 5, 7])
    }

    func testULongRangeNoArgOrIndexedHOFs() {
        let range = kk_ulong_rangeTo(1, 4)
        XCTAssertEqual(kk_ulong_range_firstOrNull(range), 1)
        XCTAssertEqual(kk_ulong_range_lastOrNull(range), 4)

        let mapped = kk_ulong_range_mapIndexed(range, unsafeBitCast(rangeMapIndexedSum, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(mapped), [1, 3, 5, 7])
    }

    func testLongRangeFirstAndLastOrNullWithoutPredicate() {
        let range = kk_long_rangeTo(1, 4)
        XCTAssertEqual(kk_long_range_firstOrNull(range), 1)
        XCTAssertEqual(kk_long_range_lastOrNull(range), 4)

        let empty = kk_long_rangeTo(5, 1)
        XCTAssertEqual(kk_long_range_firstOrNull(empty), runtimeNullSentinelInt)
        XCTAssertEqual(kk_long_range_lastOrNull(empty), runtimeNullSentinelInt)
    }

    func testRangeWindowedBuildsNestedLists() {
        let range = kk_op_rangeTo(1, 5)
        let windows = kk_range_windowed(range, 3, 2, 0)
        XCTAssertEqual(kk_list_size(windows), 2)
        XCTAssertEqual(listElements(kk_list_get(windows, 0)), [1, 2, 3])
        XCTAssertEqual(listElements(kk_list_get(windows, 1)), [3, 4, 5])
    }

    func testRangeReduceOnEmptyRangeThrows() {
        let emptyRange = kk_op_rangeTo(5, 1)
        var thrown: Int = 0
        let result = kk_range_reduce(emptyRange, unsafeBitCast(rangeMapDouble, to: Int.self), 0, &thrown)
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0)
    }

    func testRangeReduceOnSingleElement() {
        let singleRange = kk_op_rangeTo(3, 3)
        let result = kk_range_reduce(singleRange, unsafeBitCast(rangeMapDouble, to: Int.self), 0, nil)
        XCTAssertEqual(result, 3)
    }

    func testRangeMapOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let mapped = kk_range_map(emptyRange, unsafeBitCast(rangeMapDouble, to: Int.self), 0, nil)
        XCTAssertEqual(kk_list_size(mapped), 0)
    }

    func testRangeFilterOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let filtered = kk_range_filter(emptyRange, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil)
        XCTAssertEqual(kk_list_size(filtered), 0)
    }

    func testRangeFoldOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let result = kk_range_fold(emptyRange, 10, unsafeBitCast(rangeMapDouble, to: Int.self), 0, nil)
        XCTAssertEqual(result, 10)
    }

    func testRangeWithNegativeStep() {
        let range = kk_op_downTo(5, 1)
        let mapped = kk_range_map(range, unsafeBitCast(rangeMapDouble, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(mapped), [10, 8, 6, 4, 2])
    }

    func testRangeFindOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let found = kk_range_find(emptyRange, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil)
        XCTAssertEqual(found, runtimeNullSentinelInt)
    }

    func testRangeAnyAllNoneOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        XCTAssertEqual(kk_range_any(emptyRange, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil), 0)
        XCTAssertEqual(kk_range_all(emptyRange, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil), 1)
        XCTAssertEqual(kk_range_none(emptyRange, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil), 1)
    }

    func testRangeChunkedOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let chunks = kk_range_chunked(emptyRange, 2)
        XCTAssertEqual(kk_list_size(chunks), 0)
    }

    func testRangeWindowedOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let windows = kk_range_windowed(emptyRange, 3, 1, 0)
        XCTAssertEqual(kk_list_size(windows), 0)
    }

    func testRangeForEachIteratesAllElements() {
        let range = kk_op_rangeTo(1, 4)
        var sum = 0
        withUnsafeMutablePointer(to: &sum) { ptr in
            _ = kk_range_forEach(range, unsafeBitCast(rangeForEachAccumulate, to: Int.self), Int(bitPattern: ptr), nil)
        }
        XCTAssertEqual(sum, 10)
    }

    func testRangeForEachOnDescendingProgression() {
        let range = kk_op_downTo(5, 3)
        var sum = 0
        withUnsafeMutablePointer(to: &sum) { ptr in
            _ = kk_range_forEach(range, unsafeBitCast(rangeForEachAccumulate, to: Int.self), Int(bitPattern: ptr), nil)
        }
        XCTAssertEqual(sum, 12)
    }

    func testRangeForEachOnEmptyRangeIsNoOp() {
        let emptyRange = kk_op_rangeTo(5, 1)
        var sum = 0
        withUnsafeMutablePointer(to: &sum) { ptr in
            _ = kk_range_forEach(emptyRange, unsafeBitCast(rangeForEachAccumulate, to: Int.self), Int(bitPattern: ptr), nil)
        }
        XCTAssertEqual(sum, 0)
    }

    func testRangeDropReducesFromFront() {
        let range = kk_op_rangeTo(1, 5)
        let dropped = kk_range_drop(range, 2)
        XCTAssertEqual(listElements(dropped), [3, 4, 5])
    }

    func testRangeDropOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let dropped = kk_range_drop(emptyRange, 2)
        XCTAssertEqual(kk_list_size(dropped), 0)
    }

    func testRangeTakeLimitsFromFront() {
        let range = kk_op_rangeTo(1, 5)
        let taken = kk_range_take(range, 3)
        XCTAssertEqual(listElements(taken), [1, 2, 3])
    }

    func testRangeTakeOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let taken = kk_range_take(emptyRange, 3)
        XCTAssertEqual(kk_list_size(taken), 0)
    }

    func testRangeSortedOnDescendingProgressionProducesAscendingList() {
        let range = kk_op_downTo(5, 1)
        let sorted = kk_range_sorted(range)
        XCTAssertEqual(listElements(sorted), [1, 2, 3, 4, 5])
    }

    func testRangeAverageReturnsDoubleAsBitPattern() {
        let range = kk_op_rangeTo(1, 4)
        let avg = unsafeBitCast(kk_range_average(range), to: Double.self)
        XCTAssertEqual(avg, 2.5)
    }

    func testRangeAverageOnSingleElement() {
        let range = kk_op_rangeTo(7, 7)
        let avg = unsafeBitCast(kk_range_average(range), to: Double.self)
        XCTAssertEqual(avg, 7.0)
    }

    func testRangeAverageOnEmptyRangeProducesNaN() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let avg = unsafeBitCast(kk_range_average(emptyRange), to: Double.self)
        XCTAssertTrue(avg.isNaN)
    }

    func testRangeMapIndexedCombinesIndexAndValue() {
        let range = kk_op_rangeTo(1, 4)
        let mapped = kk_range_mapIndexed(range, unsafeBitCast(rangeMapIndexedSum, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(mapped), [1, 3, 5, 7])
    }

    func testRangeMapIndexedOnDescendingProgression() {
        let range = kk_op_downTo(5, 3)
        let mapped = kk_range_mapIndexed(range, unsafeBitCast(rangeMapIndexedSum, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(mapped), [5, 5, 5])
    }

    func testRangeMapNotNullFiltersNullResults() {
        let range = kk_op_rangeTo(1, 5)
        let mapped = kk_range_mapNotNull(range, unsafeBitCast(rangeMapNotNullOddOnly, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(mapped), [1, 3, 5])
    }

    func testRangeMapNotNullOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let mapped = kk_range_mapNotNull(emptyRange, unsafeBitCast(rangeMapNotNullOddOnly, to: Int.self), 0, nil)
        XCTAssertEqual(kk_list_size(mapped), 0)
    }

    func testRangeFilterIndexedKeepsEvenIndexedElements() {
        let range = kk_op_rangeTo(1, 4)
        let filtered = kk_range_filterIndexed(range, unsafeBitCast(rangeFilterIndexedEvenIndex, to: Int.self), 0, nil)
        XCTAssertEqual(listElements(filtered), [1, 3])
    }

    func testRangeFilterIndexedOnEmptyRange() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let filtered = kk_range_filterIndexed(emptyRange, unsafeBitCast(rangeFilterIndexedEvenIndex, to: Int.self), 0, nil)
        XCTAssertEqual(kk_list_size(filtered), 0)
    }

    func testRangeFindLastReturnsLastMatchingElement() {
        let range = kk_op_rangeTo(1, 6)
        let found = kk_range_findLast(range, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil)
        XCTAssertEqual(found, 6)
    }

    func testRangeFindLastOnEmptyRangeReturnsNullSentinel() {
        let emptyRange = kk_op_rangeTo(5, 1)
        let found = kk_range_findLast(emptyRange, unsafeBitCast(rangeFilterNotEven, to: Int.self), 0, nil)
        XCTAssertEqual(found, runtimeNullSentinelInt)
    }

    func testRangeReduceIndexedAccumulatesWithIndex() {
        // acc=1(first), then index=1,acc=1,val=2→4; index=2,acc=4,val=3→9; index=3,acc=9,val=4→16
        let range = kk_op_rangeTo(1, 4)
        let result = kk_range_reduceIndexed(range, unsafeBitCast(rangeReduceIndexedAccPlusIndexPlusValue, to: Int.self), 0, nil)
        XCTAssertEqual(result, 16)
    }

    func testRangeReduceIndexedOnSingleElement() {
        let range = kk_op_rangeTo(5, 5)
        let result = kk_range_reduceIndexed(range, unsafeBitCast(rangeReduceIndexedAccPlusIndexPlusValue, to: Int.self), 0, nil)
        XCTAssertEqual(result, 5)
    }

    func testRangeReduceIndexedOnEmptyRangeThrows() {
        let emptyRange = kk_op_rangeTo(5, 1)
        var thrown = 0
        _ = kk_range_reduceIndexed(emptyRange, unsafeBitCast(rangeReduceIndexedAccPlusIndexPlusValue, to: Int.self), 0, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    func testRangeFirstPredicateOnEmptyRangeThrows() {
        let emptyRange = kk_op_rangeTo(5, 1)
        var thrown = 0
        let result = kk_range_first_predicate(emptyRange, unsafeBitCast(rangePredicateEven, to: Int.self), 0, &thrown)
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0)
    }

    func testRangeFirstAndLastPredicatesOnSingleElementRange() {
        let singleRange = kk_op_rangeTo(2, 2)
        let predicate = unsafeBitCast(rangePredicateEven, to: Int.self)

        XCTAssertEqual(kk_range_first_predicate(singleRange, predicate, 0, nil), 2)
        XCTAssertEqual(kk_range_last_predicate(singleRange, predicate, 0, nil), 2)
    }

    func testRangeLastPredicateFindsLastMatchInDescendingProgression() {
        let range = kk_op_downTo(5, 1)
        let result = kk_range_last_predicate(range, unsafeBitCast(rangePredicateEven, to: Int.self), 0, nil)
        XCTAssertEqual(result, 2)
    }

    func testLongRangeForEachIteratesAllElements() {
        let range = kk_long_rangeTo(1, 4)
        var sum = 0
        withUnsafeMutablePointer(to: &sum) { ptr in
            _ = kk_long_range_forEach(range, unsafeBitCast(rangeForEachAccumulate, to: Int.self), Int(bitPattern: ptr), nil)
        }
        XCTAssertEqual(sum, 10)
    }

    func testLongRangeDropReducesFromFront() {
        let range = kk_long_rangeTo(1, 5)
        let dropped = kk_long_range_drop(range, 2)
        XCTAssertEqual(listElements(dropped), [3, 4, 5])
    }

    func testLongRangeTakeLimitsFromFront() {
        let range = kk_long_rangeTo(1, 5)
        let taken = kk_long_range_take(range, 3)
        XCTAssertEqual(listElements(taken), [1, 2, 3])
    }

    func testLongRangeSortedProducesAscendingList() {
        let range = kk_op_downTo(4, 1)
        let sorted = kk_long_range_sorted(range)
        XCTAssertEqual(listElements(sorted), [1, 2, 3, 4])
    }

    func testLongRangeAverageReturnsDoubleAsBitPattern() {
        let range = kk_long_rangeTo(1, 4)
        let avg = unsafeBitCast(kk_long_range_average(range), to: Double.self)
        XCTAssertEqual(avg, 2.5)
    }

    func testLongRangeForEachOnEmptyRangeIsNoOp() {
        let emptyRange = kk_long_rangeTo(5, 1)
        var sum = 0
        withUnsafeMutablePointer(to: &sum) { ptr in
            _ = kk_long_range_forEach(emptyRange, unsafeBitCast(rangeForEachAccumulate, to: Int.self), Int(bitPattern: ptr), nil)
        }
        XCTAssertEqual(sum, 0)
    }

    func testLongRangeDropOnEmptyRange() {
        let emptyRange = kk_long_rangeTo(5, 1)
        let dropped = kk_long_range_drop(emptyRange, 2)
        XCTAssertEqual(kk_list_size(dropped), 0)
    }

    func testLongRangeTakeOnSingleElementRange() {
        let singleRange = kk_long_rangeTo(7, 7)
        let taken = kk_long_range_take(singleRange, 3)
        XCTAssertEqual(listElements(taken), [7])
    }

    func testLongRangeAverageOnEmptyRangeProducesNaN() {
        let emptyRange = kk_long_rangeTo(5, 1)
        let avg = unsafeBitCast(kk_long_range_average(emptyRange), to: Double.self)
        XCTAssertTrue(avg.isNaN)
    }

    private func listElements(_ listRaw: Int) -> [Int] {
        let size = kk_list_size(listRaw)
        if size <= 0 {
            return []
        }
        return (0 ..< size).map { kk_list_get(listRaw, $0) }
    }
}
