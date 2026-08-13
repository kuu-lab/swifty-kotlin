import Foundation
@testable import Runtime
import Testing

/// STDLIB-563: Global counter used by laziness verification tests.
/// Tracks how many times to yield side-effects in builder thunk execute.
/// Must be global (not a class property) because `@convention(c)` closures
/// cannot capture context.
/// Access is safe because tests run sequentially and counter is only
/// mutated from one thread at a time (the producer thread).
private let lazyTestYieldCounterLock = NSLock()
nonisolated(unsafe) private var __lazyTestYieldCounter = 0

var _lazyTestYieldCounter: Int {
    get {
        lazyTestYieldCounterLock.lock()
        defer { lazyTestYieldCounterLock.unlock() }
        return __lazyTestYieldCounter
    }
    set {
        lazyTestYieldCounterLock.lock()
        defer { lazyTestYieldCounterLock.unlock() }
        __lazyTestYieldCounter = newValue
    }
}

private let lazySequenceOnEachIndexedTraceLock = NSLock()
nonisolated(unsafe) private var __lazySequenceOnEachIndexedTrace: [Int] = []

var _lazySequenceOnEachIndexedTrace: [Int] {
    get {
        lazySequenceOnEachIndexedTraceLock.lock()
        defer { lazySequenceOnEachIndexedTraceLock.unlock() }
        return __lazySequenceOnEachIndexedTrace
    }
    set {
        lazySequenceOnEachIndexedTraceLock.lock()
        defer { lazySequenceOnEachIndexedTraceLock.unlock() }
        __lazySequenceOnEachIndexedTrace = newValue
    }
}

private func appendLazySequenceOnEachIndexedTrace(_ value: Int) {
    lazySequenceOnEachIndexedTraceLock.lock()
    defer { lazySequenceOnEachIndexedTraceLock.unlock() }
    __lazySequenceOnEachIndexedTrace.append(value)
}

private let lazyYieldAllInnerThunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
    _lazyTestYieldCounter += 1
    _ = __kk_sequence_builder_yield(builderRaw, 10)
    _lazyTestYieldCounter += 1
    _ = __kk_sequence_builder_yield(builderRaw, 20)
    _lazyTestYieldCounter += 1
    _ = __kk_sequence_builder_yield(builderRaw, 30)
    _lazyTestYieldCounter += 1
    _ = __kk_sequence_builder_yield(builderRaw, 40)
    _lazyTestYieldCounter += 1
    _ = __kk_sequence_builder_yield(builderRaw, 50)
    return 0
}

private let lazyYieldAllInnerSequenceRaw: Int = {
    let innerFnPtr = unsafeBitCast(lazyYieldAllInnerThunk, to: Int.self)
    return __kk_sequence_builder_build(innerFnPtr)
}()

let lazyYieldAllOuterThunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, builderRaw, _ in
    _ = __kk_sequence_builder_yieldAll(builderRaw, lazyYieldAllInnerSequenceRaw)
    _ = __kk_sequence_builder_yield(builderRaw, 99)
    return 0
}

private let stringKeySelector: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    switch value {
    case 1:
        return runtimeTestStringHandle("banana")
    case 2:
        return runtimeTestStringHandle("apple")
    default:
        return runtimeTestStringHandle("carrot")
    }
}

private let throwingSelector: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "sortedBy selector failed")
    return 0
}

private let ascendingComparator: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, lhs, rhs, _ in
    lhs - rhs
}

private let throwingComparator: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "sortedWith comparator failed")
    return 0
}

private let accumulatingSum: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, acc, value, _ in
    acc + value
}

private let indexedAccumulatingSum: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, acc, value, _ in
    acc + index * value
}

private let reduceRightChecksum: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, acc, _ in
    value * 10 + acc
}
private let reduceRightIndexedChecksum: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, acc, _ in
    index * 100 + value * 10 + acc
}

private let throwingAccumulator: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "sequence accumulator failed")
    return 0
}

private let throwingIndexedAccumulator: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "sequence indexed accumulator failed")
    return 0
}

private let throwingSequenceGenerator: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "sequence generator failed")
    return 0
}

private let sequenceAssociatePair: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    kk_pair_new(value * 2, value * 10)
}

// Maps value → (value % 2, value * 10), producing duplicate keys for odd/even groups.
private let sequenceAssociatePairDuplicateKeys: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    kk_pair_new(value % 2, value * 10)
}

private let sequenceParitySelector: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 2
}

private let sequenceLessThanThree: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value < 3 ? 1 : 0
}

private let sequenceModuloThreeSelector: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 3
}

private let sequenceIndexTimesTen: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, _ in
    index * 10
}

private let sequenceValueTimesTen: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value * 10
}

private let sequenceLessThanFour: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value < 4 ? 1 : 0
}

private let sequenceReverseIntComparator: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, lhs, rhs, _ in
    if lhs > rhs {
        return -1
    }
    if lhs < rhs {
        return 1
    }
    return 0
}

let sequenceFirstNullableEvenTimesTen: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value.isMultiple(of: 2) ? value * 10 : runtimeNullSentinelInt
}

let sequenceAlwaysNullTransform: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _ in
    runtimeNullSentinelInt
}

private let sequenceAdjacentDifference: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, left, right, _ in
    right - left
}

private let throwingSequenceAdjacentTransform: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "sequence zipWithNext transform failed")
    return 0
}

let throwingSequenceDestinationLambda: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "sequence destination transform failed")
    return 0
}

let recordingOnEachIndexedAction: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
    appendLazySequenceOnEachIndexedTrace(index * 100 + value)
    return 0
}

private let keepEvenIndexOrLargeValue: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, value, _ in
    index.isMultiple(of: 2) || value > 30 ? 1 : 0
}

let summingWindowTransform: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, windowRaw, _ in
    let size = kk_list_size(windowRaw)
    guard size > 0 else { return 0 }
    var sum = 0
    for index in 0 ..< size {
        sum += kk_list_get(windowRaw, index)
    }
    return sum
}

let throwingWindowTransform: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "window transform failed")
    return 0
}

private let sequenceFirstNotNullOfStringForTwo: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value == 2 ? runtimeTestStringHandle("two") : runtimeNullSentinelInt
}

private let sequenceFirstNotNullOfAlwaysNull: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _ in
    runtimeNullSentinelInt
}

private let sequenceSumByWeightedTwo: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value == 2 ? 10 : value
}

private let sequenceSumByDoubleWeightedTwo: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    kk_double_to_bits(value == 2 ? 1.5 : 0.25)
}

private let sequenceGreaterThanTwo: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value > 2 ? 1 : 0
}

private let sequenceNegatedSelector: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    -value
}

private let sequenceMaxWithNaturalComparator: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, lhs, rhs, _ in
    lhs - rhs
}

private let sequenceMaxWithOrNullNaturalComparator: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, lhs, rhs, _ in
    lhs - rhs
}

private func runtimeTestStringHandle(_ value: String) -> Int {
    let bytes = Array(value.utf8)
    return bytes.withUnsafeBufferPointer { buffer in
        let baseAddress = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0x1)!
        let raw = kk_string_from_utf8(baseAddress, Int32(bytes.count))
        return Int(bitPattern: raw)
    }
}

private func runtimeTestStringBuilder(_ value: String) -> Int {
    let bytes = Array(value.utf8)
    return bytes.withUnsafeBufferPointer { buffer in
        __kk_string_builder_new_from_string_flat(
            buffer.baseAddress,
            value.unicodeScalars.count,
            value.utf8.count,
            0
        )
    }
}

private func resetRuntimeSequenceTestState() {
    _lazyTestYieldCounter = 0
    _lazySequenceOnEachIndexedTrace = []
}

@Suite(.runtimeIsolation(.gcOnly, resetAdditionalState: resetRuntimeSequenceTestState))
struct RuntimeSequenceTests {
    @Test func firstNotNullOfReturnsFirstTransformedValue() {
        var thrown = 0
        let result = kk_sequence_firstNotNullOf(
            makeSequence([1, 2, 3]),
            unsafeBitCast(sequenceFirstNotNullOfStringForTwo, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(extractString(from: UnsafeMutableRawPointer(bitPattern: result)) == "two")
    }

    @Test func firstNotNullOfThrowsWhenNoElementTransformsToValue() {
        var thrown = 0
        let result = kk_sequence_firstNotNullOf(
            makeSequence([1, 2, 3]),
            unsafeBitCast(sequenceFirstNotNullOfAlwaysNull, to: Int.self),
            0,
            &thrown
        )

        #expect(result == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }





    @Test func firstNotNullOfOrNullReturnsFirstTransformedValue() {
        var thrown = 0
        let result = kk_sequence_firstNotNullOfOrNull(
            makeSequence([1, 2, 3]),
            unsafeBitCast(sequenceFirstNotNullOfStringForTwo, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(extractString(from: UnsafeMutableRawPointer(bitPattern: result)) == "two")
    }

    @Test func firstNotNullOfOrNullReturnsNullSentinelWhenNoElementTransformsToValue() {
        var thrown = 0
        let result = kk_sequence_firstNotNullOfOrNull(
            makeSequence([1, 2, 3]),
            unsafeBitCast(sequenceFirstNotNullOfAlwaysNull, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(result == runtimeNullSentinelInt)
    }

    @Test func takeLimitsSequenceElements() {
        #expect(sequenceElements(kk_sequence_take(makeSequence([1, 2, 3, 4]), 2)) == [1, 2])
        #expect(sequenceElements(kk_sequence_take(makeSequence([1, 2]), 5)) == [1, 2])
        #expect(sequenceElements(kk_sequence_take(makeSequence([1, 2]), 0)) == [])
    }

    @Test func takeLastReturnsTrailingElementsAsList() {
        #expect(listElements(kk_sequence_takeLast(makeSequence([1, 2, 3, 4]), 2, nil)) == [3, 4])
        #expect(listElements(kk_sequence_takeLast(makeSequence([1, 2]), 5, nil)) == [1, 2])
        #expect(listElements(kk_sequence_takeLast(makeSequence([1, 2]), 0, nil)) == [])
    }

    @Test func takeLastNegativeCountSetsThrowable() {
        var thrown = 0
        let result = kk_sequence_takeLast(makeSequence([1, 2]), -1, &thrown)
        #expect(listElements(result) == [])
        #expect(thrown != 0)
    }

    @Test func takeLastWhileReturnsMatchingSuffixAsList() {
        var thrown = 0
        let result = kk_sequence_takeLastWhile(
            makeSequence([1, 3, 4, 2, 5, 6]),
            unsafeBitCast(sequenceGreaterThanTwo, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(listElements(result) == [5, 6])
    }

    @Test func takeLastWhilePropagatesPredicateThrowable() {
        var thrown = 0
        _ = kk_sequence_takeLastWhile(
            makeSequence([1, 2]),
            unsafeBitCast(throwingSequenceDestinationLambda, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown != 0)
    }

    @Test func sumAccumulatesIntElements() {
        #expect(kk_sequence_sum(makeSequence([1, 2, 3, 4])) == 10)
        #expect(kk_sequence_sum(makeSequence([])) == 0)
    }





    @Test func minOrNullReturnsSmallestElementAndNullOnEmpty() {
        #expect(kk_sequence_minOrNull(makeSequence([5, 2, 3])) == 2)
        #expect(kk_sequence_minOrNull(makeSequence([])) == runtimeNullSentinelInt)
    }

    @Test func maxOrNullReturnsLargestElementAndNullOnEmpty() {
        #expect(kk_sequence_maxOrNull(makeSequence([3, 1, 4, 2])) == 4)
        #expect(kk_sequence_maxOrNull(makeSequence([])) == runtimeNullSentinelInt)
    }



    @Test func sortedByUsesRuntimeValueComparisonForSelectorKeys() {
        let source = makeSequence([1, 2, 3])
        let sorted = kk_sequence_sortedBy(
            source,
            unsafeBitCast(stringKeySelector, to: Int.self),
            0,
            nil
        )

        #expect(listElements(kk_sequence_to_list(sorted, nil)) == [2, 1, 3])
    }

    @Test func sortedByPropagatesSelectorThrowables() {
        let source = makeSequence([1, 2, 3])
        var thrown = 0
        let sorted = kk_sequence_sortedBy(
            source,
            unsafeBitCast(throwingSelector, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown != 0)
        #expect(listElements(kk_sequence_to_list(sorted, nil)) == [])
    }

    @Test func sortedByDescendingUsesRuntimeValueComparisonForSelectorKeys() {
        let source = makeSequence([1, 2, 3])
        let sorted = kk_sequence_sortedByDescending(
            source,
            unsafeBitCast(stringKeySelector, to: Int.self),
            0,
            nil
        )

        #expect(listElements(kk_sequence_to_list(sorted, nil)) == [3, 1, 2])
    }

    @Test func sortedByDescendingPropagatesSelectorThrowables() {
        let source = makeSequence([1, 2, 3])
        var thrown = 0
        let sorted = kk_sequence_sortedByDescending(
            source,
            unsafeBitCast(throwingSelector, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown != 0)
        #expect(listElements(kk_sequence_to_list(sorted, nil)) == [])
    }

    @Test func sortedWithUsesComparatorResults() {
        let source = makeSequence([3, 1, 2, 1])
        let sorted = kk_sequence_sortedWith(
            source,
            unsafeBitCast(ascendingComparator, to: Int.self),
            0,
            nil
        )

        #expect(sequenceElements(sorted) == [1, 1, 2, 3])
    }

    @Test func sortedWithPropagatesComparatorThrowables() {
        let source = makeSequence([3, 1, 2])
        var thrown = 0
        let sorted = kk_sequence_sortedWith(
            source,
            unsafeBitCast(throwingComparator, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown != 0)
        #expect(sequenceElements(sorted) == [])
    }
    @Test func takeWhileKeepsMatchingPrefixLazily() {
        let source = makeSequence([1, 2, 3, 4, 2])
        let taken = kk_sequence_takeWhile(
            source,
            unsafeBitCast(sequenceLessThanFour, to: Int.self),
            0
        )

        #expect(listElements(kk_sequence_to_list(taken, nil)) == [1, 2, 3])
    }

    @Test func takeWhilePropagatesPredicateThrowableOnMaterialization() {
        let source = makeSequence([1, 2, 3])
        let taken = kk_sequence_takeWhile(
            source,
            unsafeBitCast(throwingSequenceDestinationLambda, to: Int.self),
            0
        )
        var thrown = 0
        let result = kk_sequence_to_list(taken, &thrown)

        #expect(thrown != 0)
        #expect(result == runtimeNullSentinelInt)
    }

    @Test func sortedOrdersSequenceElementsWithRuntimeComparison() {
        let source = makeSequence([3, 1, 2, 1])
        let sorted = kk_sequence_sorted(source)

        #expect(sequenceElements(sorted) == [1, 1, 2, 3])
    }

    @Test func sortedDescendingOrdersSequenceElementsWithRuntimeComparison() {
        let source = makeSequence([3, 1, 2, 1])
        let sorted = kk_sequence_sortedDescending(source)

        #expect(sequenceElements(sorted) == [3, 2, 1, 1])
    }


    @Test func lastIndexOfReturnsFinalMatchingIndexOrMinusOne() {
        let seq = makeSequence([1, 2, 3, 2])

        #expect(kk_sequence_lastIndexOf(seq, 2) == 3)
        #expect(kk_sequence_lastIndexOf(seq, 4) == -1)
    }


    @Test func lastReturnsFinalElement() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_last(seq, &thrown)

        #expect(thrown == 0)
        #expect(result == 3)
    }

    @Test func lastOrNullReturnsLastElementOrNullSentinel() {
        var thrown = 0
        let result = kk_sequence_lastOrNull(makeSequence([1, 2, 3]), &thrown)

        #expect(thrown == 0)
        #expect(result == 3)
        #expect(kk_sequence_lastOrNull(makeSequence([]), &thrown) == runtimeNullSentinelInt)
        #expect(thrown == 0)
    }








    @Test func indexOfLastReturnsLastMatchingPredicateIndexOrMinusOne() {
        let seq = makeSequence([1, 4, 5, 6])
        let evenPredicate: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value.isMultiple(of: 2) ? 1 : 0
        }
        let greaterThanTenPredicate: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value > 10 ? 1 : 0
        }

        #expect(kk_sequence_indexOfLast(seq, unsafeBitCast(evenPredicate, to: Int.self), 0, nil) == 3)
        #expect(kk_sequence_indexOfLast(seq, unsafeBitCast(greaterThanTenPredicate, to: Int.self), 0, nil) == -1)
    }

    @Test func intersectReturnsDeduplicatedSetInReceiverOrder() {
        let seq = makeSequence([1, 2, 2, 3, 4])
        let other = registerRuntimeObject(RuntimeListBox(elements: [2, 4, 5]))

        let result = kk_sequence_intersect(seq, other)

        #expect(setElements(result) == [2, 4])
    }
    @Test func groupByGroupsElementsIntoNewMap() {
        let seq = makeSequence([1, 2, 3, 4, 5])

        let result = kk_sequence_groupBy(
            seq,
            unsafeBitCast(sequenceParitySelector, to: Int.self),
            0,
            nil
        )

        #expect(mapKeys(result) == [1, 0])
        #expect(listElements(kk_map_get(result, 1)) == [1, 3, 5])
        #expect(listElements(kk_map_get(result, 0)) == [2, 4])
    }

    @Test func indexOfReturnsFirstMatchingIndexOrMinusOne() {
        let seq = makeSequence([10, 20, 10, 30])

        #expect(kk_sequence_indexOf(seq, 10) == 0)
        #expect(kk_sequence_indexOf(seq, 20) == 1)
        #expect(kk_sequence_indexOf(seq, 99) == -1)
    }

    @Test func indexOfFirstReturnsFirstMatchingPredicateIndexOrMinusOne() {
        let seq = makeSequence([1, 3, 4, 6])
        let evenPredicate: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value.isMultiple(of: 2) ? 1 : 0
        }
        let greaterThanTenPredicate: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value > 10 ? 1 : 0
        }

        #expect(kk_sequence_indexOfFirst(seq, unsafeBitCast(evenPredicate, to: Int.self), 0, nil) == 2)
        #expect(kk_sequence_indexOfFirst(seq, unsafeBitCast(greaterThanTenPredicate, to: Int.self), 0, nil) == -1)
    }





    // MARK: - Iterator Builder Tests (STDLIB-331/564)

    @Test func iteratorBuilderBuildYieldsElementsInOrder() {
        // Closure thunk: yields 10, 20, 30 to the builder
        let thunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { builderRaw, _ in
            _ = __kk_sequence_builder_yield(builderRaw, 10)
            _ = __kk_sequence_builder_yield(builderRaw, 20)
            _ = __kk_sequence_builder_yield(builderRaw, 30)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let iterHandle = __kk_iterator_builder_build(fnPtr)

        #expect(__kk_iterator_builder_hasNext(iterHandle) == 1)
        #expect(__kk_iterator_builder_next(iterHandle) == 10)
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 1)
        #expect(__kk_iterator_builder_next(iterHandle) == 20)
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 1)
        #expect(__kk_iterator_builder_next(iterHandle) == 30)
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 0)
    }

    @Test func iteratorBuilderEmptyHasNextReturnsFalse() {
        let thunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let iterHandle = __kk_iterator_builder_build(fnPtr)

        #expect(__kk_iterator_builder_hasNext(iterHandle) == 0)
    }

    @Test func iteratorBuilderYieldDirectlyAppendsToBuilder() {
        // Test __kk_iterator_builder_yield works directly with RuntimeIteratorBuilderBox
        let thunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { builderRaw, _ in
            _ = __kk_iterator_builder_yield(builderRaw, 100)
            _ = __kk_iterator_builder_yield(builderRaw, 200)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let iterHandle = __kk_iterator_builder_build(fnPtr)

        #expect(__kk_iterator_builder_next(iterHandle) == 100)
        #expect(__kk_iterator_builder_next(iterHandle) == 200)
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 0)
    }

    @Test func iteratorBuilderSingleElement() {
        let thunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { builderRaw, _ in
            _ = __kk_sequence_builder_yield(builderRaw, 42)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let iterHandle = __kk_iterator_builder_build(fnPtr)

        #expect(__kk_iterator_builder_hasNext(iterHandle) == 1)
        #expect(__kk_iterator_builder_next(iterHandle) == 42)
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 0)
    }

    // MARK: - Lazy / Continuation-based Iterator Tests (STDLIB-564)

    /// Verifies that the producer is truly lazy: values are produced on-demand,
    /// not eagerly collected into a buffer.  We use a shared counter that the
    /// producer increments on each yield; the consumer asserts the counter
    /// hasn't advanced beyond what was requested.
    @Test func iteratorBuilderIsLazyNotEager() {
        // We use a class wrapper so the thunk can capture and mutate it.
        // The thunk yields yieldCount values: 1, 2, 3, 4, 5.
        // Between each next() call on the consumer side, we verify the
        // producer hasn't run ahead.
        let thunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { builderRaw, _ in
            // Yield 5 values.  Each yield suspends the producer until the
            // consumer calls next(), so the producer can never run ahead.
            _ = __kk_iterator_builder_yield(builderRaw, 1)
            _ = __kk_iterator_builder_yield(builderRaw, 2)
            _ = __kk_iterator_builder_yield(builderRaw, 3)
            _ = __kk_iterator_builder_yield(builderRaw, 4)
            _ = __kk_iterator_builder_yield(builderRaw, 5)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let iterHandle = __kk_iterator_builder_build(fnPtr)

        // Consume only the first 3 elements; the producer should not have
        // produced elements 4 and 5 yet (lazy).
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 1)
        #expect(__kk_iterator_builder_next(iterHandle) == 1)
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 1)
        #expect(__kk_iterator_builder_next(iterHandle) == 2)
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 1)
        #expect(__kk_iterator_builder_next(iterHandle) == 3)

        // Now consume the rest.
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 1)
        #expect(__kk_iterator_builder_next(iterHandle) == 4)
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 1)
        #expect(__kk_iterator_builder_next(iterHandle) == 5)
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 0)
    }

    /// Verifies that calling next() without hasNext() works correctly
    /// (the continuation advances the producer automatically).
    @Test func iteratorBuilderNextWithoutHasNext() {
        let thunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { builderRaw, _ in
            _ = __kk_iterator_builder_yield(builderRaw, 10)
            _ = __kk_iterator_builder_yield(builderRaw, 20)
            _ = __kk_iterator_builder_yield(builderRaw, 30)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let iterHandle = __kk_iterator_builder_build(fnPtr)

        // Call next() directly without hasNext().
        #expect(__kk_iterator_builder_next(iterHandle) == 10)
        #expect(__kk_iterator_builder_next(iterHandle) == 20)
        #expect(__kk_iterator_builder_next(iterHandle) == 30)
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 0)
    }

    /// Verifies that calling hasNext() multiple times without next() is
    /// idempotent (returns the same result without advancing the iterator).
    @Test func iteratorBuilderHasNextIsIdempotent() {
        let thunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { builderRaw, _ in
            _ = __kk_iterator_builder_yield(builderRaw, 42)
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let iterHandle = __kk_iterator_builder_build(fnPtr)

        // Multiple hasNext() calls should all return 1.
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 1)
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 1)
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 1)
        #expect(__kk_iterator_builder_next(iterHandle) == 42)
        // After consuming, multiple hasNext() calls should all return 0.
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 0)
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 0)
    }

    /// Verifies that the iterator builder works with a computed sequence
    /// (loop-based yield), matching the pattern in the diff case.
    @Test func iteratorBuilderWithComputedSequence() {
        let thunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { builderRaw, _ in
            // Yield squares: 1, 4, 9, 16, 25
            for i in 1 ... 5 {
                _ = __kk_iterator_builder_yield(builderRaw, i * i)
            }
            return 0
        }
        let fnPtr = unsafeBitCast(thunk, to: Int.self)
        let iterHandle = __kk_iterator_builder_build(fnPtr)

        var results: [Int] = []
        while __kk_iterator_builder_hasNext(iterHandle) == 1 {
            results.append(__kk_iterator_builder_next(iterHandle))
        }
        #expect(results == [1, 4, 9, 16, 25])
    }

    // Backwards-compatibility: older lowering paths may pass a RuntimeListIteratorBox
    // to __kk_iterator_builder_hasNext / __kk_iterator_builder_next.
    @Test func iteratorBuilderBackwardsCompatWithListIterator() {
        let listHandle = makeList([10, 20, 30])
        let iterHandle = kk_list_iterator(listHandle)

        #expect(__kk_iterator_builder_hasNext(iterHandle) == 1)
        #expect(__kk_iterator_builder_next(iterHandle) == 10)
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 1)
        #expect(__kk_iterator_builder_next(iterHandle) == 20)
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 1)
        #expect(__kk_iterator_builder_next(iterHandle) == 30)
        #expect(__kk_iterator_builder_hasNext(iterHandle) == 0)

        // STDLIB-538: Test backward iteration with hasPrevious()/previous()
        #expect(kk_list_iterator_hasPrevious(iterHandle) == 1)
        #expect(kk_list_iterator_previous(iterHandle) == 30)
        #expect(kk_list_iterator_hasPrevious(iterHandle) == 1)
        #expect(kk_list_iterator_previous(iterHandle) == 20)
        #expect(kk_list_iterator_hasPrevious(iterHandle) == 1)
        #expect(kk_list_iterator_previous(iterHandle) == 10)

        // After going back to beginning, no more previous
        #expect(kk_list_iterator_hasPrevious(iterHandle) == 0)
        #expect(kk_list_iterator_previous(iterHandle) == 0)
    }

    // MARK: - Sequence scan / runningFold / runningReduce Tests (STDLIB-558, 559, 560)

    @Test func scanIncludesInitialAccumulator() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_scan(
            seq,
            10,
            unsafeBitCast(accumulatingSum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(sequenceElements(result) == [10, 11, 13, 16])
    }

    @Test func runningFoldIncludesInitialAccumulator() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_runningFold(
            seq,
            5,
            unsafeBitCast(accumulatingSum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(sequenceElements(result) == [5, 6, 8, 11])
    }

    @Test func runningFoldIndexedIncludesInitialAccumulatorAndIndex() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_runningFoldIndexed(
            seq,
            10,
            unsafeBitCast(indexedAccumulatingSum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(sequenceElements(result) == [10, 10, 12, 18])
    }

    @Test func scanIndexedIncludesInitialAccumulatorAndIndex() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_scanIndexed(
            seq,
            10,
            unsafeBitCast(indexedAccumulatingSum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(sequenceElements(result) == [10, 10, 12, 18])
    }

    @Test func runningReduceEmptySequenceReturnsEmptyList() {
        let seq = makeSequence([])
        var thrown = 0

        let result = kk_sequence_runningReduce(
            seq,
            unsafeBitCast(accumulatingSum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(listElements(result) == [])
    }

    @Test func runningReduceNonEmptySequenceAccumulatesCorrectly() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_runningReduce(
            seq,
            unsafeBitCast(accumulatingSum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        // Kotlin: [1, 2, 3].runningReduce { acc, x -> acc + x } == [1, 3, 6]
        #expect(listElements(result) == [1, 3, 6])
    }

    @Test func runningReduceSingleElementReturnsThatElement() {
        let seq = makeSequence([42])
        var thrown = 0

        let result = kk_sequence_runningReduce(
            seq,
            unsafeBitCast(accumulatingSum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(listElements(result) == [42])
    }

    // MARK: - Sequence runningReduceIndexed tests (STDLIB-SEQ-017)

    @Test func runningReduceIndexedAccumulatesWithIndex() {
        let seq = makeSequence([1, 2, 3, 4])
        var thrown = 0

        let result = kk_sequence_runningReduceIndexed(
            seq,
            unsafeBitCast(indexedAccumulatingSum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(sequenceElements(result) == [1, 3, 9, 21])
    }

    @Test func runningReduceIndexedReturnsEmptyListForEmptySequence() {
        let seq = makeSequence([])
        var thrown = 0

        let result = kk_sequence_runningReduceIndexed(
            seq,
            unsafeBitCast(indexedAccumulatingSum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(sequenceElements(result) == [])
    }

    @Test func runningReduceIndexedReturnsZeroWhenLambdaThrows() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_runningReduceIndexed(
            seq,
            unsafeBitCast(throwingIndexedAccumulator, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown != 0)
        #expect(result == 0)
    }

    @Test func scanReturnsZeroWhenLambdaThrows() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_scan(
            seq,
            0,
            unsafeBitCast(throwingAccumulator, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown != 0)
        #expect(result == 0)
    }

    @Test func runningFoldIndexedReturnsZeroWhenLambdaThrows() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_runningFoldIndexed(
            seq,
            0,
            unsafeBitCast(throwingIndexedAccumulator, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown != 0)
        #expect(result == 0)
    }

    @Test func runningReduceReturnsZeroWhenLambdaThrows() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_runningReduce(
            seq,
            unsafeBitCast(throwingAccumulator, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown != 0)
        #expect(result == 0)
    }

    @Test func scanReturnsZeroWhenSequenceTraversalThrows() {
        let seq = kk_sequence_generate(
            1,
            unsafeBitCast(throwingSequenceGenerator, to: Int.self),
            0
        )
        var thrown = 0

        let result = kk_sequence_scan(
            seq,
            0,
            unsafeBitCast(accumulatingSum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown != 0)
        #expect(result == 0)
    }

    // MARK: - Sequence reduction tests (STDLIB-SEQ-FN-093, STDLIB-SEQ-FN-094, STDLIB-556, STDLIB-SEQ-015)

    @Test func reduceOrNullEmptySequenceReturnsNullSentinel() {
        let seq = makeSequence([])
        var thrown = 0

        let result = kk_sequence_reduceOrNull(
            seq,
            unsafeBitCast(accumulatingSum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(result == runtimeNullSentinelInt)
    }

    @Test func reduceOrNullNonEmptySequenceAccumulates() {
        let seq = makeSequence([1, 2, 3, 4])
        var thrown = 0

        let result = kk_sequence_reduceOrNull(
            seq,
            unsafeBitCast(accumulatingSum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(result == 10)
    }

    @Test func reduceOrNullReturnsZeroWhenLambdaThrows() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_reduceOrNull(
            seq,
            unsafeBitCast(throwingAccumulator, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown != 0)
        #expect(result == 0)
    }

    @Test func reduceRightEmptySequenceThrows() {
        let seq = makeSequence([])
        var thrown = 0

        let result = kk_sequence_reduceRight(
            seq,
            unsafeBitCast(reduceRightChecksum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown != 0)
        #expect(result == 0)
    }

    @Test func reduceRightNonEmptySequenceAccumulatesFromRight() {
        let seq = makeSequence([1, 2, 3, 4])
        var thrown = 0

        let result = kk_sequence_reduceRight(
            seq,
            unsafeBitCast(reduceRightChecksum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(result == 64)
    }

    @Test func reduceRightReturnsZeroWhenLambdaThrows() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_reduceRight(
            seq,
            unsafeBitCast(throwingAccumulator, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown != 0)
        #expect(result == 0)
    }

    @Test func reduceIndexedEmptySequenceThrows() {
        let seq = makeSequence([])
        var thrown = 0

        let result = kk_sequence_reduceIndexed(
            seq,
            unsafeBitCast(indexedAccumulatingSum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown != 0)
        #expect(result == 0)
    }

    @Test func reduceIndexedNonEmptySequenceAccumulatesWithIndex() {
        let seq = makeSequence([1, 2, 3, 4])
        var thrown = 0

        let result = kk_sequence_reduceIndexed(
            seq,
            unsafeBitCast(indexedAccumulatingSum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(result == 21)
    }

    @Test func reduceIndexedReturnsZeroWhenLambdaThrows() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_reduceIndexed(
            seq,
            unsafeBitCast(throwingIndexedAccumulator, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown != 0)
        #expect(result == 0)
    }

    @Test func reduceIndexedOrNullEmptySequenceReturnsNullSentinel() {
        let seq = makeSequence([])
        var thrown = 0

        let result = kk_sequence_reduceIndexedOrNull(
            seq,
            unsafeBitCast(indexedAccumulatingSum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(result == runtimeNullSentinelInt)
    }

    @Test func reduceIndexedOrNullNonEmptySequenceAccumulatesWithIndex() {
        let seq = makeSequence([1, 2, 3, 4])
        var thrown = 0

        let result = kk_sequence_reduceIndexedOrNull(
            seq,
            unsafeBitCast(indexedAccumulatingSum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(result == 21)
    }

    @Test func reduceIndexedOrNullReturnsZeroWhenLambdaThrows() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_reduceIndexedOrNull(
            seq,
            unsafeBitCast(throwingIndexedAccumulator, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown != 0)
        #expect(result == 0)
    }

    @Test func reduceIndexedSingleElementReturnsElementWithoutCallingAccumulator() {
        let seq = makeSequence([42])
        var thrown = 0
        let result = kk_sequence_reduceIndexed(
            seq,
            unsafeBitCast(throwingIndexedAccumulator, to: Int.self),
            0,
            &thrown
        )
        #expect(thrown == 0, "accumulator must not be called for single-element sequence")
        #expect(result == 42)
    }

    // MARK: - Sequence right-indexed reduction tests (STDLIB-SEQ-FN-095)

    @Test func reduceRightIndexedEmptySequenceThrows() {
        let seq = makeSequence([])
        var thrown = 0

        let result = kk_sequence_reduceRightIndexed(
            seq,
            unsafeBitCast(reduceRightIndexedChecksum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown != 0)
        #expect(result == 0)
    }

    @Test func reduceRightIndexedNonEmptySequenceAccumulatesFromRight() {
        let seq = makeSequence([1, 2, 3, 4])
        var thrown = 0

        let result = kk_sequence_reduceRightIndexed(
            seq,
            unsafeBitCast(reduceRightIndexedChecksum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(result == 364)
    }

    @Test func reduceRightIndexedReturnsZeroWhenLambdaThrows() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_reduceRightIndexed(
            seq,
            unsafeBitCast(throwingIndexedAccumulator, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown != 0)
        #expect(result == 0)
    }

    @Test func reduceRightIndexedSingleElementReturnsElementWithoutCallingAccumulator() {
        let seq = makeSequence([99])
        var thrown = 0
        let result = kk_sequence_reduceRightIndexed(
            seq,
            unsafeBitCast(throwingIndexedAccumulator, to: Int.self),
            0,
            &thrown
        )
        #expect(thrown == 0, "accumulator must not be called for single-element sequence")
        #expect(result == 99)
    }

    // MARK: - Sequence nullable right-indexed reduction tests (STDLIB-SEQ-FN-096)

    @Test func reduceRightIndexedOrNullEmptySequenceReturnsNullSentinel() {
        let seq = makeSequence([])
        var thrown = 0

        let result = kk_sequence_reduceRightIndexedOrNull(
            seq,
            unsafeBitCast(reduceRightIndexedChecksum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(result == runtimeNullSentinelInt)
    }

    @Test func reduceRightIndexedOrNullNonEmptySequenceAccumulatesFromRight() {
        let seq = makeSequence([1, 2, 3, 4])
        var thrown = 0

        let result = kk_sequence_reduceRightIndexedOrNull(
            seq,
            unsafeBitCast(reduceRightIndexedChecksum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(result == 364)
    }

    @Test func reduceRightIndexedOrNullSingleElementReturnsElement() {
        let seq = makeSequence([42])
        var thrown = 0

        let result = kk_sequence_reduceRightIndexedOrNull(
            seq,
            unsafeBitCast(reduceRightIndexedChecksum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(result == 42)
    }

    @Test func reduceRightIndexedOrNullReturnsZeroWhenLambdaThrows() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_reduceRightIndexedOrNull(
            seq,
            unsafeBitCast(throwingIndexedAccumulator, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown != 0)
        #expect(result == 0)
    }

    // MARK: - Sequence nullable right reduction tests (STDLIB-SEQ-FN-097)

    @Test func reduceRightOrNullEmptySequenceReturnsNullSentinel() {
        let seq = makeSequence([])
        var thrown = 0

        let result = kk_sequence_reduceRightOrNull(
            seq,
            unsafeBitCast(reduceRightChecksum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(result == runtimeNullSentinelInt)
    }

    @Test func reduceRightOrNullNonEmptySequenceAccumulatesFromRight() {
        let seq = makeSequence([1, 2, 3, 4])
        var thrown = 0

        let result = kk_sequence_reduceRightOrNull(
            seq,
            unsafeBitCast(reduceRightChecksum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(result == 64)
    }

    @Test func reduceRightOrNullSingleElementReturnsElement() {
        let seq = makeSequence([42])
        var thrown = 0

        let result = kk_sequence_reduceRightOrNull(
            seq,
            unsafeBitCast(reduceRightChecksum, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(result == 42)
    }

    @Test func reduceRightOrNullReturnsZeroWhenLambdaThrows() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_reduceRightOrNull(
            seq,
            unsafeBitCast(throwingAccumulator, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown != 0)
        #expect(result == 0)
    }

    // MARK: - Sequence zipWithNext transform tests (STDLIB-SEQ-018)

    @Test func zipWithNextTransformAppliesLambdaToAdjacentElements() {
        let seq = makeSequence([1, 2, 4, 8])
        var thrown = 0

        let result = kk_sequence_zipWithNextTransform(
            seq,
            unsafeBitCast(sequenceAdjacentDifference, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(listElements(result) == [1, 2, 4])
    }

    @Test func zipWithNextTransformReturnsEmptyListForShortSequences() {
        let empty = makeSequence([])
        let single = makeSequence([42])
        var emptyThrown = 0
        var singleThrown = 0

        let emptyResult = kk_sequence_zipWithNextTransform(
            empty,
            unsafeBitCast(sequenceAdjacentDifference, to: Int.self),
            0,
            &emptyThrown
        )
        let singleResult = kk_sequence_zipWithNextTransform(
            single,
            unsafeBitCast(sequenceAdjacentDifference, to: Int.self),
            0,
            &singleThrown
        )

        #expect(emptyThrown == 0)
        #expect(singleThrown == 0)
        #expect(listElements(emptyResult) == [])
        #expect(listElements(singleResult) == [])
    }

    @Test func zipWithNextTransformReturnsZeroWhenLambdaThrows() {
        let seq = makeSequence([1, 2, 3])
        var thrown = 0

        let result = kk_sequence_zipWithNextTransform(
            seq,
            unsafeBitCast(throwingSequenceAdjacentTransform, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown != 0)
        #expect(result == 0)
    }

    @Test func minReturnsSmallestElementAndThrowsOnEmpty() {
        var thrown = 0
        #expect(kk_sequence_min(makeSequence([3, 1, 4, 2]), &thrown) == 1)
        #expect(thrown == 0)

        let emptyResult = kk_sequence_min(makeSequence([]), &thrown)
        #expect(emptyResult == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test func sequenceSingleReturnsOnlyElement() {
        let seq = makeSequence([42])
        var thrown = 0

        let result = kk_sequence_single(seq, &thrown)

        #expect(thrown == 0)
        #expect(result == 42)
    }

    @Test func sequenceSingleThrowsForEmptyAndMultipleElements() {
        var emptyThrown = 0
        let emptyResult = kk_sequence_single(makeSequence([]), &emptyThrown)
        #expect(emptyThrown != 0)
        #expect(emptyResult == 0)

        var multipleThrown = 0
        let multipleResult = kk_sequence_single(makeSequence([1, 2]), &multipleThrown)
        #expect(multipleThrown != 0)
        #expect(multipleResult == 0)
    }

    @Test func sequenceSingleOrNullReturnsOnlyElement() {
        let seq = makeSequence([42])
        var thrown = 0

        let result = kk_sequence_singleOrNull(seq, &thrown)

        #expect(thrown == 0)
        #expect(result == 42)
    }

    @Test func sequenceSingleOrNullReturnsNullForEmptyAndMultipleElements() {
        var emptyThrown = 0
        let emptyResult = kk_sequence_singleOrNull(makeSequence([]), &emptyThrown)
        #expect(emptyThrown == 0)
        #expect(emptyResult == runtimeNullSentinelInt)

        var multipleThrown = 0
        let multipleResult = kk_sequence_singleOrNull(makeSequence([1, 2]), &multipleThrown)
        #expect(multipleThrown == 0)
        #expect(multipleResult == runtimeNullSentinelInt)
    }

    private func makeArray(_ elements: [Int]) -> Int {
        let arrayRaw = kk_array_new(elements.count)
        var thrown = 0
        for (index, element) in elements.enumerated() {
            _ = kk_array_set(arrayRaw, index, element, &thrown)
            #expect(thrown == 0)
        }
        return arrayRaw
    }

    private func makeList(_ elements: [Int]) -> Int {
        let arrayRaw = makeArray(elements)
        return kk_list_of(arrayRaw, elements.count)
    }

    func makeSequence(_ elements: [Int]) -> Int {
        kk_sequence_from_list(makeList(elements))
    }

    @Test func filterIsInstanceToAppendsMatchingRuntimeTypesToDestination() {
        let seq = makeSequence([1, runtimeTestStringHandle("two"), 3])
        let destination = makeList([0])

        let result = kk_sequence_filterIsInstanceTo(seq, destination, 3)

        #expect(result == destination)
        #expect(listElements(destination) == [0, 1, 3])
    }

    // MARK: - Sequence.constrainOnce (STDLIB-SEQ-006)

    @Test func constrainOnceReportsIllegalStateOnSecondToList() {
        let seq = kk_sequence_constrainOnce(makeSequence([1, 2, 3]))
        var firstThrown = 0
        let firstList = kk_sequence_to_list(seq, &firstThrown)
        #expect(firstThrown == 0)
        #expect(listElements(firstList) == [1, 2, 3])

        var secondThrown = 0
        let secondList = kk_sequence_to_list(seq, &secondThrown)
        #expect(secondThrown != 0)
        #expect(secondList == runtimeNullSentinelInt)
    }

    @Test func containsFindsMatchingElement() {
        let seq = makeSequence([1, 2, 3])

        #expect(kk_unbox_bool(kk_sequence_contains(seq, 2)) == 1)
        #expect(kk_unbox_bool(kk_sequence_contains(seq, 9)) == 0)
    }

    @Test func distinctPreservesFirstOccurrenceOrder() {
        let result = kk_sequence_distinct(makeSequence([3, 1, 2, 1, 3, 4]))

        #expect(listElements(kk_sequence_to_list(result, nil)) == [3, 1, 2, 4])
    }

    @Test func dropSkipsRequestedPrefix() {
        let result = kk_sequence_drop(makeSequence([1, 2, 3, 4, 5]), 2)

        #expect(listElements(kk_sequence_to_list(result, nil)) == [3, 4, 5])
    }

    @Test func dropWhileSkipsLeadingMatchesOnly() {
        let result = kk_sequence_dropWhile(
            makeSequence([1, 2, 3, 1, 4]),
            unsafeBitCast(sequenceLessThanThree, to: Int.self),
            0
        )

        #expect(listElements(kk_sequence_to_list(result, nil)) == [3, 1, 4])
    }

    @Test func countReturnsElementCount() {
        var thrown = 0
        let count = kk_sequence_count(makeSequence([1, 2, 3]), &thrown)

        #expect(thrown == 0)
        #expect(count == 3)
    }

    @Test func countReturnsZeroForEmptySequence() {
        var thrown = 0
        let count = kk_sequence_count(makeSequence([]), &thrown)

        #expect(thrown == 0)
        #expect(count == 0)
    }

    @Test func countCountsElementsMatchingPredicateViaFilter() {
        let seq = makeSequence([1, 2, 3, 4])
        let filtered = kk_sequence_filter(
            seq,
            unsafeBitCast(sequenceLessThanThree, to: Int.self),
            0
        )

        var thrown = 0
        let count = kk_sequence_count(filtered, &thrown)

        #expect(thrown == 0)
        #expect(count == 2)
    }

    @Test func elementAtOrNullReturnsIndexedValueOrNullSentinel() {
        #expect(kk_sequence_elementAtOrNull(makeSequence([10, 20, 30]), 1) == 20)
        #expect(kk_sequence_elementAtOrNull(makeSequence([10]), 3) == runtimeNullSentinelInt)
    }
    @Test func distinctByPreservesFirstKeyOccurrenceOrder() {
        var thrown = 0
        let result = kk_sequence_distinctBy(
            makeSequence([3, 1, 2, 5, 4, 7]),
            unsafeBitCast(sequenceParitySelector, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(listElements(kk_sequence_to_list(result, nil)) == [3, 2])
    }

    @Test func distinctByEmptySequenceReturnsEmpty() {
        var thrown = 0
        let result = kk_sequence_distinctBy(
            makeSequence([]),
            unsafeBitCast(sequenceParitySelector, to: Int.self),
            0,
            &thrown
        )
        #expect(thrown == 0)
        #expect(listElements(kk_sequence_to_list(result, nil)) == [])
    }

    @Test func distinctByAllSameKeyPreservesFirstElement() {
        var thrown = 0
        let result = kk_sequence_distinctBy(
            makeSequence([2, 4, 6]),
            unsafeBitCast(sequenceParitySelector, to: Int.self),
            0,
            &thrown
        )
        #expect(thrown == 0)
        #expect(listElements(kk_sequence_to_list(result, nil)) == [2])
    }

    @Test func distinctByKeySelectorExceptionPropagatesOnMaterialization() {
        let result = kk_sequence_distinctBy(
            makeSequence([1, 2, 3]),
            unsafeBitCast(throwingSelector, to: Int.self),
            0,
            nil
        )
        var thrown = 0
        _ = kk_sequence_to_list(result, &thrown)
        #expect(thrown != 0)
    }

    @Test func elementAtReturnsIndexedValue() {
        var thrown = 0
        let result = kk_sequence_elementAt(makeSequence([10, 20, 30]), 1, &thrown)

        #expect(thrown == 0)
        #expect(result == 20)
    }

    @Test func elementAtReportsOutOfBounds() {
        var thrown = 0
        let result = kk_sequence_elementAt(makeSequence([10]), 3, &thrown)

        #expect(thrown != 0)
        #expect(result == runtimeNullSentinelInt)
    }

    @Test func filterIndexedToAppendsMatchingElementsToDestination() {
        let destination = makeList([1])
        let fn = unsafeBitCast(keepEvenIndexOrLargeValue, to: Int.self)
        let result = kk_sequence_filterIndexedTo(makeSequence([10, 20, 30, 40]), destination, fn, 0, nil)

        #expect(result == destination)
        #expect(listElements(destination) == [1, 10, 30, 40])
    }

    @Test func filterIsInstanceKeepsMatchingRuntimeTypes() {
        let seq = makeSequence([1, runtimeTestStringHandle("two"), 3])
        let filtered = kk_sequence_filterIsInstance(seq, 3)
        #expect(sequenceElements(filtered) == [1, 3])
    }

    @Test func filterIsInstanceEmptySequenceReturnsEmpty() {
        let filtered = kk_sequence_filterIsInstance(makeSequence([]), 3)
        #expect(sequenceElements(filtered) == [])
    }

    @Test func filterIsInstanceAllMatchReturnsAllElements() {
        let filtered = kk_sequence_filterIsInstance(makeSequence([1, 2, 3]), 3)
        #expect(sequenceElements(filtered) == [1, 2, 3])
    }

    @Test func filterIsInstanceNoneMatchReturnsEmpty() {
        let seq = makeSequence([
            runtimeTestStringHandle("a"),
            runtimeTestStringHandle("b"),
        ])
        let filtered = kk_sequence_filterIsInstance(seq, 3)
        #expect(sequenceElements(filtered) == [])
    }

    @Test func filterIndexedKeepsElementsMatchingIndexedPredicate() {
        let fn = unsafeBitCast(keepEvenIndexOrLargeValue, to: Int.self)
        let filtered = kk_sequence_filterIndexed(makeSequence([10, 20, 30, 40]), fn, 0, nil)
        #expect(sequenceElements(filtered) == [10, 30, 40])
    }

    @Test func elementAtOrElseReturnsIndexedValueWhenPresent() {
        var thrown = 0
        let result = kk_sequence_elementAtOrElse(
            makeSequence([10, 20, 30]),
            1,
            unsafeBitCast(sequenceIndexTimesTen, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(result == 20)
    }

    @Test func elementAtOrElseUsesDefaultForOutOfBoundsIndex() {
        var thrown = 0
        let result = kk_sequence_elementAtOrElse(
            makeSequence([10]),
            3,
            unsafeBitCast(sequenceIndexTimesTen, to: Int.self),
            0,
            &thrown
        )

        #expect(thrown == 0)
        #expect(result == 30)
    }

    // MARK: - Sequence shuffled tests (STDLIB-SEQ-019)

    @Test func sequenceShuffledPreservesElements() {
        let seq = makeSequence([1, 2, 3, 4])
        let shuffled = kk_sequence_shuffled(seq)
        #expect(sequenceElements(shuffled).sorted() == [1, 2, 3, 4])
    }

    @Test func sequenceShuffledRandomPreservesElementsAndHandlesSmallSequences() {
        let seq = makeSequence([1, 2, 3, 4])
        let shuffled = kk_sequence_shuffled_random(seq, 0)
        #expect(sequenceElements(shuffled).sorted() == [1, 2, 3, 4])

        #expect(sequenceElements(kk_sequence_shuffled_random(makeSequence([]), 0)) == [])
        #expect(sequenceElements(kk_sequence_shuffled_random(makeSequence([42]), 0)) == [42])
    }

    @Test func sequenceMaxReturnsLargestElementAndThrowsOnEmpty() throws {
        var thrown = 0
        let result = kk_sequence_max(makeSequence([3, 1, 4, 2]), &thrown)
        #expect(thrown == 0)
        #expect(result == 4)

        let emptyResult = kk_sequence_max(makeSequence([]), &thrown)
        #expect(emptyResult == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
        let box = try #require(throwableBox(from: thrown))
        #expect(box.message == kEmptySequenceNoSuchElement)
    }

    // MARK: - STDLIB-SEQ-014: Sequence.requireNoNulls()

    @Test func sequenceRequireNoNullsPreservesNonNullElements() {
        let seq = makeSequence([1, 2, 3])
        let checked = kk_sequence_requireNoNulls(seq)
        var thrown = 0
        let list = kk_sequence_to_list(checked, &thrown)

        #expect(thrown == 0)
        #expect(listElements(list) == [1, 2, 3])
    }

    @Test func sequenceRequireNoNullsThrowsOnNullDuringTraversal() throws {
        let seq = makeSequence([1, runtimeNullSentinelInt, 3])
        let checked = kk_sequence_requireNoNulls(seq)
        var thrown = 0
        let list = kk_sequence_to_list(checked, &thrown)

        #expect(thrown != 0)
        #expect(listElements(list) == [])
        let box = try #require(throwableBox(from: thrown))
        #expect(box.exceptionFQName == "kotlin.IllegalArgumentException")
    }

    @Test func sequenceRequireNoNullsIsLazyUntilNullIsReached() {
        let seq = makeSequence([1, runtimeNullSentinelInt, 3])
        let checked = kk_sequence_requireNoNulls(seq)
        let firstOnly = kk_sequence_take(checked, 1)
        var thrown = 0
        let list = kk_sequence_to_list(firstOnly, &thrown)

        #expect(thrown == 0)
        #expect(listElements(list) == [1])
    }

    @Test func sequenceRequireNoNullsPropagatesThroughEagerConsumers() throws {
        let seq = makeSequence([1, runtimeNullSentinelInt, 3])
        let checked = kk_sequence_requireNoNulls(seq)
        var thrown = 0

        let result = kk_sequence_zipWithNextTransform(
            checked,
            unsafeBitCast(sequenceAdjacentDifference, to: Int.self),
            0,
            &thrown
        )

        #expect(result == 0)
        #expect(thrown != 0)
        let box = try #require(throwableBox(from: thrown))
        #expect(box.exceptionFQName == "kotlin.IllegalArgumentException")
    }

    // MARK: - STDLIB-SEQ-FN-099: Sequence.reversed()

    @Test func sequenceReversedMaterializesInReverseOrder() {
        let seq = makeSequence([1, 2, 3, 4])
        let reversed = kk_sequence_reversed(seq)
        var thrown = 0
        let list = kk_sequence_to_list(reversed, &thrown)

        #expect(thrown == 0)
        #expect(listElements(list) == [4, 3, 2, 1])
    }

    @Test func sequenceReversedEmptySequenceReturnsEmptySequence() {
        let reversed = kk_sequence_reversed(makeSequence([]))
        var thrown = 0
        let list = kk_sequence_to_list(reversed, &thrown)

        #expect(thrown == 0)
        #expect(listElements(list) == [])
    }

    // MARK: - Sequence mutable conversions (STDLIB-SEQ-025)

    @Test func toMutableListReturnsIndependentCopy() {
        let seq = makeSequence([3, 1, 2, 1, 3])
        let copied = kk_sequence_toMutableList(seq)

        #expect(listElements(copied) == [3, 1, 2, 1, 3])
        #expect(sequenceElements(seq) == [3, 1, 2, 1, 3])
    }

    @Test func toMutableSetDeduplicatesPreservingOrder() {
        let seq = makeSequence([3, 1, 2, 1, 3])
        let copied = kk_sequence_toMutableSet(seq)

        #expect(setElements(copied) == [3, 1, 2])
    }

    @Test func toSortedSetSortsAndDeduplicates() {
        let seq = makeSequence([3, 1, 2, 1, 3])
        let copied = kk_sequence_toSortedSet(seq)

        #expect(setElements(copied) == [1, 2, 3])
    }

    @Test func toSetDeduplicatesPreservingOrder() {
        let seq = makeSequence([3, 1, 2, 1, 3])
        let copied = kk_sequence_toSet(seq)

        #expect(setElements(copied) == [3, 1, 2])
    }

    @Test func toCollectionAppendsIntoMutableListDestination() {
        let seq = makeSequence([1, 2, 3])
        let destination = makeList([0])
        let result = kk_sequence_toCollection(seq, destination)

        #expect(result == destination)
        #expect(listElements(destination) == [0, 1, 2, 3])
    }

    @Test func toCollectionAppendsIntoMutableSetDestination() {
        let seq = makeSequence([1, 2, 2, 3])
        let destination = registerRuntimeObject(RuntimeSetBox(elements: [10, 2]))
        let result = kk_sequence_toCollection(seq, destination)

        #expect(result == destination)
        #expect(setElements(destination) == [10, 2, 1, 3])
    }

    @Test func toHashSetDeduplicatesPreservingOrder() {
        let seq = makeSequence([3, 1, 2, 1, 3])
        let copied = kk_sequence_toHashSet(seq)

        #expect(setElements(copied) == [3, 1, 2])
    }

    // MARK: - Sequence.plus (STDLIB-561)

    @Test func plusConcatenatesTwoSequences() {
        let seq1 = makeSequence([1, 2, 3])
        let seq2 = makeSequence([4, 5])
        let combined = kk_sequence_plus(seq1, seq2)
        #expect(sequenceElements(combined) == [1, 2, 3, 4, 5])
    }

    @Test func plusWithEmptySequence() {
        let seq1 = makeSequence([1, 2])
        let seq2 = makeSequence([])
        #expect(sequenceElements(kk_sequence_plus(seq1, seq2)) == [1, 2])
        #expect(sequenceElements(kk_sequence_plus(seq2, seq1)) == [1, 2])
    }

    @Test func plusWithListAsOther() {
        let seq = makeSequence([1, 2])
        let list = makeList([3, 4])
        let combined = kk_sequence_plus(seq, list)
        #expect(sequenceElements(combined) == [1, 2, 3, 4])
    }

    @Test func unionCombinesSequenceAndIterableIntoSet() {
        let seq = makeSequence([1, 2, 3, 2])
        let other = makeList([3, 4, 1])
        let unioned = kk_sequence_union(seq, other)

        #expect(setElements(unioned) == [1, 2, 3, 4])
    }

    // MARK: - Sequence.minus (STDLIB-562)

    @Test func minusRemovesFirstOccurrenceOfElement() {
        let seq = makeSequence([1, 2, 3, 2, 4])
        let result = kk_sequence_minus(seq, 2)
        #expect(sequenceElements(result) == [1, 3, 2, 4])
    }

    @Test func minusElementNotPresent() {
        let seq = makeSequence([1, 2, 3])
        let result = kk_sequence_minus(seq, 99)
        #expect(sequenceElements(result) == [1, 2, 3])
    }

    @Test func minusOnEmptySequence() {
        let seq = makeSequence([])
        let result = kk_sequence_minus(seq, 1)
        #expect(sequenceElements(result) == [])
    }

    @Test func plusResultIsSequence() {
        // Verify the result of plus can be chained with other sequence operations
        let seq1 = makeSequence([1, 2])
        let seq2 = makeSequence([3, 4])
        let combined = kk_sequence_plus(seq1, seq2)
        let asList = kk_sequence_to_list(combined, nil)
        #expect(listElements(asList) == [1, 2, 3, 4])
    }

    @Test func minusResultIsSequence() {
        // Verify the result of minus can be chained with other sequence operations
        let seq = makeSequence([1, 2, 3])
        let reduced = kk_sequence_minus(seq, 2)
        let asList = kk_sequence_to_list(reduced, nil)
        #expect(listElements(asList) == [1, 3])
    }

    // MARK: - Sequence.subtract (STDLIB-SEQ-FN-115)

    @Test func subtractReturnsSetRemovingIterableElements() {
        let seq = makeSequence([1, 2, 2, 3, 4])
        let other = makeList([2, 4, 2])
        let result = kk_sequence_subtract(seq, other)
        #expect(setElements(result) == [1, 3])
    }

    // MARK: - Eager Materialization (Intentional Simplification)

    @Test func plusEagerlyMaterializesResult() {
        // NOTE: Kotlin's Sequence.plus returns a lazy sequence, but our
        // runtime intentionally materializes eagerly via evaluateSequence.
        // This test documents the current eager behavior; it should be
        // updated if/when lazy concat steps are added to the pipeline.
        let seq1 = makeSequence([10, 20])
        let seq2 = makeSequence([30, 40])
        let combined = kk_sequence_plus(seq1, seq2)
        // The result is immediately available (eagerly materialized).
        #expect(sequenceElements(combined) == [10, 20, 30, 40])
    }

    @Test func minusEagerlyMaterializesResult() {
        // Same as above: documents intentional eager materialization.
        let seq = makeSequence([5, 10, 15, 10])
        let result = kk_sequence_minus(seq, 10)
        #expect(sequenceElements(result) == [5, 15, 10])
    }

    // MARK: - Plus with array as RHS

    @Test func plusWithArrayAsOther() {
        let seq = makeSequence([1, 2])
        let array = makeArray([3, 4])
        let combined = kk_sequence_plus(seq, array)
        #expect(sequenceElements(combined) == [1, 2, 3, 4])
    }

    // MARK: - Plus with kk_sequence_of_single as RHS

    @Test func plusWithSingleElementWrappedViaOfSingle() {
        // Verifies the ABI pattern the compiler emits for `seq + element`:
        // the element is wrapped via kk_sequence_of_single before being
        // passed to kk_sequence_plus.
        let seq = makeSequence([1, 2, 3])
        let wrappedElement = kk_sequence_of_single(42)
        let combined = kk_sequence_plus(seq, wrappedElement)
        #expect(sequenceElements(combined) == [1, 2, 3, 42])
    }

    @Test func plusWithSingleElementWrappedViaOfSingleEmptyLHS() {
        let seq = makeSequence([])
        let wrappedElement = kk_sequence_of_single(99)
        let combined = kk_sequence_plus(seq, wrappedElement)
        #expect(sequenceElements(combined) == [99])
    }

    @Test func plusElementAppendsSingleElement() {
        let seq = makeSequence([1, 2, 3])
        let combined = kk_sequence_plus_element(seq, 42)
        #expect(sequenceElements(combined) == [1, 2, 3, 42])
    }

    @Test func randomReturnsOnlyElementAndThrowsOnEmpty() {
        var thrown = 0
        #expect(kk_sequence_random(makeSequence([42]), &thrown) == 42)
        #expect(thrown == 0)
        thrown = 0
        #expect(kk_sequence_random(makeSequence([]), &thrown) == 0)
        #expect(thrown != 0)
    }


    @Test func randomOrNullReturnsOnlyElementAndNullOnEmpty() {
        var thrown = 0
        let only = kk_sequence_randomOrNull(makeSequence([42]), &thrown)
        #expect(thrown == 0)
        #expect(only == 42)

        thrown = 0
        let emptyResult = kk_sequence_randomOrNull(makeSequence([]), &thrown)
        #expect(thrown == 0)
        #expect(emptyResult == runtimeNullSentinelInt)
    }



    // MARK: - Lazy Sequence Builder Tests (STDLIB-563)

    private func listElements(_ listRaw: Int) -> [Int] {
        let size = kk_list_size(listRaw)
        if size <= 0 {
            return []
        }
        return (0 ..< size).map { index in
            kk_list_get(listRaw, index)
        }
    }

    private func sequenceElements(_ seqRaw: Int) -> [Int] {
        listElements(kk_sequence_to_list(seqRaw, nil))
    }

    private func setElements(_ setRaw: Int) -> [Int] {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: setRaw) else {
            return []
        }
        guard let box = tryCast(ptr, to: RuntimeSetBox.self) else {
            return []
        }
        return box.elements
    }

    private func throwableBox(from handle: Int) -> RuntimeThrowableBox? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
            return nil
        }
        return tryCast(ptr, to: RuntimeThrowableBox.self)
    }

    private func mapKeys(_ mapRaw: Int) -> [Int] {
        let iterator = kk_map_iterator(mapRaw)
        var keys: [Int] = []
        while kk_map_iterator_hasNext(iterator) != 0 {
            keys.append(kk_map_iterator_next(iterator))
        }
        return keys
    }

}
