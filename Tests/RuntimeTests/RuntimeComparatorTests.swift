import Foundation
@testable import Runtime
import Testing

// MARK: - Trampoline wrappers
// Local @convention(c) closures that delegate to the @_cdecl runtime functions.
// We must NOT pass @_cdecl functions directly to comparatorPtr() because Swift
// would re-export the C symbol in this module, causing duplicate symbol linker errors.

// MARK: - Test lambdas

private let selectIdentity: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value
}

private let selectModTen: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
    value % 10
}

private let throwingSelector: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = 1
    return 0
}

private let comparatorNatural: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, a, b, _ in
    if a < b { return -1 }
    if a > b { return 1 }
    return 0
}

private let comparatorByModTen: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, a, b, _ in
    let ka = a % 10
    let kb = b % 10
    if ka < kb { return -1 }
    if ka > kb { return 1 }
    return 0
}

private let comparatorReversed: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, a, b, _ in
    if a < b { return 1 }
    if a > b { return -1 }
    return 0
}

private let throwingComparator: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _, outThrown in
    outThrown?.pointee = 1
    return 0
}

private let comparatorObjectCompare: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { receiver, a, b, _ in
    guard let receiverPtr = UnsafeMutableRawPointer(bitPattern: receiver) else {
        return 0
    }
    guard let box = tryCast(receiverPtr, to: RuntimeObjectBox.self) else {
        return 0
    }
    let mode = box.elements.first ?? 0
    if mode == 0 {
        if a < b { return -1 }
        if a > b { return 1 }
        return 0
    }
    if a < b { return 1 }
    if a > b { return -1 }
    return 0
}

// MARK: - Helpers

private func selectorPtr(_ fn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    unsafeBitCast(fn, to: Int.self)
}

private func comparatorPtr(_ fn: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    unsafeBitCast(fn, to: Int.self)
}

private func primitiveComparatorPtr(_ fn: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    unsafeBitCast(fn, to: Int.self)
}

private func makeList(_ elements: [Int]) -> Int {
    let box = RuntimeListBox(elements: elements)
    return registerRuntimeObject(box)
}

private func makeArray(_ elements: [Int]) -> Int {
    let array = kk_array_new(elements.count)
    var thrown = 0
    for (index, element) in elements.enumerated() {
        _ = kk_array_set(array, index, element, &thrown)
    }
    return array
}

private func makeRuntimeString(_ value: String) -> Int {
    registerRuntimeObject(RuntimeStringBox(value))
}

private func runtimeStringValue(_ raw: Int) -> String {
    extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
}

private func listElements(_ listRaw: Int) -> [Int] {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: listRaw) else { return [] }
    guard let box = tryCast(ptr, to: RuntimeListBox.self) else { return [] }
    return box.elements
}

private func originalIndexes(for elements: [Int], indexedByHandle: [Int: Int]) -> [Int] {
    elements.compactMap { indexedByHandle[$0] }
}

private func withComparatorObject(mode: Int, body: (Int) -> Void) {
    let object = kk_object_new(1, 0)
    let payload = UnsafeMutableRawPointer(bitPattern: object)!
    guard let box = tryCast(payload, to: RuntimeObjectBox.self) else {
        return
    }
    box.elements[0] = mode
    _ = kk_object_register_itable_method(object, 0, 0, unsafeBitCast(comparatorObjectCompare, to: Int.self))
    body(object)
}

// MARK: - Tests

@Suite(.runtimeIsolation(.all))
struct RuntimeComparatorTests {
    // MARK: - compareBy ascending

    // MARK: - compareByDescending

    // MARK: - compareValues

    // KSP-461: `compareValues` is bundled Kotlin source; the residual runtime
    // entry point is the generic comparison core reached through `compareTo` on a
    // `Comparable<*>` receiver.
    @Test
    func testComparableCompareToOrdersBoxedValues() {
        #expect(__kk_comparable_compareTo(kk_box_int(3), kk_box_int(7)) < 0)
        #expect(__kk_comparable_compareTo(kk_box_int(5), kk_box_int(5)) == 0)
        #expect(__kk_comparable_compareTo(kk_box_int(9), kk_box_int(2)) > 0)
    }

    @Test
    func testComparableCompareToOrdersNullsFirst() {
        #expect(__kk_comparable_compareTo(runtimeNullSentinelInt, kk_box_int(1)) < 0)
        #expect(__kk_comparable_compareTo(kk_box_int(1), runtimeNullSentinelInt) > 0)
        #expect(__kk_comparable_compareTo(runtimeNullSentinelInt, runtimeNullSentinelInt) == 0)
    }

    // Regression (KSP-659): a boxed zero can reach the comparison core as the raw
    // value 0 (e.g. the generic element argument of `Array<Int>.binarySearch(0)`).
    // It must compare as the integer zero and must not be mistaken for `null`.
    @Test
    func testComparableCompareToBoxedZeroIsNotNull() {
        #expect(__kk_comparable_compareTo(kk_box_int(0), 0) == 0)
        #expect(__kk_comparable_compareTo(0, kk_box_int(0)) == 0)
        #expect(__kk_comparable_compareTo(0, 0) == 0)
        #expect(__kk_comparable_compareTo(0, kk_box_int(5)) < 0)
        #expect(__kk_comparable_compareTo(kk_box_int(5), 0) > 0)
    }

    // Regression (KSP-461): `String.compareTo` returns the difference of the first
    // differing characters in Kotlin, and the generic comparison core has to report
    // the same magnitude (it used to normalise the result to -1/0/1).
    @Test
    func testComparableCompareToReportsKotlinStringDifference() {
        #expect(
            __kk_comparable_compareTo(makeRuntimeString("a"), makeRuntimeString("c")) == -2
        )
        #expect(
            __kk_comparable_compareTo(makeRuntimeString("c"), makeRuntimeString("a")) == 2
        )
        #expect(
            __kk_comparable_compareTo(makeRuntimeString("ab"), makeRuntimeString("abcd")) == -2
        )
        #expect(
            __kk_comparable_compareTo(makeRuntimeString("abc"), makeRuntimeString("abc")) == 0
        )
    }

    // Regression (KSP-659): only the null sentinel counts as `null`, so a real
    // null orders strictly below a boxed zero (previously they compared equal).
    @Test
    func testComparableCompareToNullOrdersBelowBoxedZero() {
        #expect(__kk_comparable_compareTo(runtimeNullSentinelInt, 0) < 0)
        #expect(__kk_comparable_compareTo(0, runtimeNullSentinelInt) > 0)
    }

    // KSP-461: explicit comparator arguments (e.g. `maxWith`) route through the
    // demoted invocation bridge, which dispatches the comparator object's compare.
    @Test
    func testCompareWithComparatorDispatchesComparatorObject() {
        withComparatorObject(mode: 0) { comparatorRaw in
            #expect(__kk_compare_with_comparator(comparatorRaw, 3, 7, nil) < 0)
            #expect(__kk_compare_with_comparator(comparatorRaw, 7, 3, nil) > 0)
            #expect(__kk_compare_with_comparator(comparatorRaw, 7, 7, nil) == 0)
        }
        withComparatorObject(mode: 1) { comparatorRaw in
            #expect(__kk_compare_with_comparator(comparatorRaw, 3, 7, nil) > 0)
        }
    }

    // MARK: - thenBy

    // MARK: - thenDescending

    // MARK: - thenComparator

    // MARK: - reversed

    // MARK: - naturalOrder / reverseOrder

    @Test
    func testCaseInsensitiveOrderComparatorObjectDispatchesThroughITable() {
        let comparatorRaw = kk_string_case_insensitive_order()
        let compareFnPtr = kk_itable_lookup(comparatorRaw, 0, 0)
        #expect(compareFnPtr != 0)

        let compareFn = unsafeBitCast(compareFnPtr, to: RuntimeCollectionLambda2.self)
        #expect(
            compareFn(comparatorRaw, makeRuntimeString("alpha"), makeRuntimeString("ALPHA"), nil) == 0
        )
        #expect(
            compareFn(comparatorRaw, makeRuntimeString("apple"), makeRuntimeString("banana"), nil) < 0
        )
        #expect(
            compareFn(comparatorRaw, makeRuntimeString("Zoo"), makeRuntimeString("apple"), nil) > 0
        )
    }

    @Test
    func testSortedWithCaseInsensitiveOrderComparatorObject() {
        let source = makeList([
            makeRuntimeString("b"),
            makeRuntimeString("A"),
            makeRuntimeString("c"),
            makeRuntimeString("a"),
        ])
        let comparatorRaw = kk_string_case_insensitive_order()

        let sorted = kk_list_sortedWith(source, comparatorRaw, 0, nil)
        #expect(listElements(sorted).map(runtimeStringValue) == ["A", "a", "b", "c"])
    }

    // MARK: - sortedWith E2E

    @Test
    func testSortedWithComparator() {
        let source = makeList([5, 3, 8, 1, 4])
        let sorted = kk_list_sortedWith(
            source,
            comparatorPtr(comparatorNatural),
            0,
            nil
        )
        #expect(listElements(sorted) == [1, 3, 4, 5, 8])
    }

    @Test
    func testPrimitiveListSortedAscending() {
        let source = makeList([5, 3, 8, 1, 4])
        let sorted = kk_list_sorted_primitive(source, 0)
        #expect(listElements(sorted) == [1, 3, 4, 5, 8])
    }

    @Test
    func testPrimitiveListSortedDescending() {
        let source = makeList([5, 3, 8, 1, 4])
        let sorted = kk_list_sortedDescending_primitive(source, 0)
        #expect(listElements(sorted) == [8, 5, 4, 3, 1])
    }

    @Test
    func testListSortedDescendingComparableObjectsReturnsNewSortedList() {
        let source = makeList([
            makeRuntimeString("b"),
            makeRuntimeString("a"),
            makeRuntimeString("c"),
        ])
        let sorted = kk_list_sortedDescending(source)

        #expect(listElements(sorted).map(runtimeStringValue) == ["c", "b", "a"])
        #expect(listElements(source).map(runtimeStringValue) == ["b", "a", "c"])
    }

    @Test
    func testPrimitiveListSortedByAscending() {
        let source = makeList([22, 12, 21, 11])
        let sorted = kk_list_sortedBy_primitive(source, selectorPtr(selectModTen), 0, 0, nil)
        #expect(listElements(sorted) == [21, 11, 22, 12])
    }

    @Test
    func testPrimitiveListSortedByDescending() {
        let source = makeList([22, 12, 21, 11])
        let sorted = kk_list_sortedByDescending_primitive(source, selectorPtr(selectModTen), 0, 0, nil)
        #expect(listElements(sorted) == [22, 12, 21, 11])
    }

    @Test
    func testPrimitiveListSortedStability() {
        let source = makeList([2, 1, 2, 1, 2])
        let sorted = kk_list_sorted_primitive(source, 0)
        #expect(listElements(sorted) == [1, 1, 2, 2, 2])
    }

    @Test
    func testListSortedComparableObjectsReturnsNewSortedList() {
        let source = makeList([
            makeRuntimeString("b"),
            makeRuntimeString("a"),
            makeRuntimeString("c"),
        ])
        let sorted = kk_list_sorted(source)
        #expect(listElements(sorted).map(runtimeStringValue) == ["a", "b", "c"])
        #expect(listElements(source).map(runtimeStringValue) == ["b", "a", "c"])
    }

    @Test
    func testPrimitiveListSortedFloatAndDouble() {
        let floatValues = [
            kk_box_float(Int(truncatingIfNeeded: Float(3.0).bitPattern)),
            kk_box_float(Int(truncatingIfNeeded: Float(1.5).bitPattern)),
            kk_box_float(Int(truncatingIfNeeded: Float(2.0).bitPattern)),
        ]
        let doubleValues = [
            kk_box_double(Int(truncatingIfNeeded: Double(3.0).bitPattern)),
            kk_box_double(Int(truncatingIfNeeded: Double(1.5).bitPattern)),
            kk_box_double(Int(truncatingIfNeeded: Double(2.0).bitPattern)),
        ]

        let floatSorted = kk_list_sorted_primitive(makeList(floatValues), 6)
        let doubleSorted = kk_list_sorted_primitive(makeList(doubleValues), 7)

        let expectedFloats = [Float(1.5).bitPattern, Float(2.0).bitPattern, Float(3.0).bitPattern]
            .map { Int(truncatingIfNeeded: $0) }
        let expectedDoubles = [Double(1.5).bitPattern, Double(2.0).bitPattern, Double(3.0).bitPattern]
            .map { Int(truncatingIfNeeded: $0) }
        #expect(listElements(floatSorted).map { kk_unbox_float($0) } == expectedFloats)
        #expect(listElements(doubleSorted).map { kk_unbox_double($0) } == expectedDoubles)
    }

    @Test
    func testSortedWithReversedComparator() {
        let source = makeList([5, 3, 8, 1, 4])
        let sorted = kk_list_sortedWith(
            source,
            comparatorPtr(comparatorReversed),
            0,
            nil
        )
        #expect(listElements(sorted) == [8, 5, 4, 3, 1])
    }

    @Test
    func testSortedWithComparatorObjectDispatchesThroughVtable() {
        let source = makeList([5, 3, 8, 1, 4])

        withComparatorObject(mode: 0) { comparatorRaw in
            let sorted = kk_list_sortedWith(source, comparatorRaw, 0, nil)
            #expect(listElements(sorted) == [1, 3, 4, 5, 8])
        }

        withComparatorObject(mode: 1) { comparatorRaw in
            let sorted = kk_list_sortedWith(source, comparatorRaw, 0, nil)
            #expect(listElements(sorted) == [8, 5, 4, 3, 1])
        }
    }

    @Test
    func testBinarySearchComparatorWithExplicitRange() {
        let source = makeList([1, 3, 5, 7, 9])
        var thrown = 0

        let found = kk_list_binarySearch_comparator(
            source,
            5,
            comparatorPtr(comparatorNatural),
            0,
            1,
            4,
            &thrown
        )
        #expect(found == 2)
        #expect(thrown == 0)

        thrown = 0
        let missing = kk_list_binarySearch_comparator(
            source,
            6,
            comparatorPtr(comparatorNatural),
            0,
            1,
            4,
            &thrown
        )
        #expect(missing == -4)
        #expect(thrown == 0)
    }

    @Test
    func testBinarySearchComparatorObjectDispatchesThroughVtable() {
        let ascending = makeList([1, 3, 5, 7, 9])
        withComparatorObject(mode: 0) { comparatorRaw in
            var thrown = 0
            let found = kk_list_binarySearch_comparator(
                ascending,
                7,
                comparatorRaw,
                0,
                0,
                5,
                &thrown
            )
            #expect(found == 3)
            #expect(thrown == 0)
        }

        let descending = makeList([9, 7, 5, 3, 1])
        withComparatorObject(mode: 1) { comparatorRaw in
            var thrown = 0
            let found = kk_list_binarySearch_comparator(
                descending,
                5,
                comparatorRaw,
                0,
                0,
                5,
                &thrown
            )
            #expect(found == 2)
            #expect(thrown == 0)
        }
    }

    @Test
    func testBinarySearchComparatorRangeValidationThrows() {
        let source = makeList([1, 3, 5, 7, 9])
        var thrown = 0
        let result = kk_list_binarySearch_comparator(
            source,
            5,
            comparatorPtr(comparatorNatural),
            0,
            4,
            2,
            &thrown
        )
        #expect(result == 0)
        #expect(thrown != 0)
    }

    @Test
    func testMutableListPrimitiveSortAscending() {
        let source = makeList([5, 3, 8, 1, 4])
        #expect(kk_mutable_list_sort_primitive(source, 0) == 0)
        #expect(listElements(source) == [1, 3, 4, 5, 8])
    }

    @Test
    func testMutableListSortComparableObjectsMutatesInPlace() {
        let source = makeList([
            makeRuntimeString("b"),
            makeRuntimeString("a"),
            makeRuntimeString("c"),
        ])
        #expect(kk_mutable_list_sort(source) == 0)
        #expect(listElements(source).map(runtimeStringValue) == ["a", "b", "c"])
    }

    @Test
    func testMutableListPrimitiveSortDescending() {
        let source = makeList([5, 3, 8, 1, 4])
        #expect(kk_mutable_list_sortDescending_primitive(source, 0) == 0)
        #expect(listElements(source) == [8, 5, 4, 3, 1])
    }

    @Test
    func testMutableListSortWithComparatorMutatesInPlace() {
        let source = makeList([14, 3, 23, 5, 13, 24])
        #expect(kk_mutable_list_sortWith(source, comparatorPtr(comparatorByModTen), 0, nil) == 0)
        #expect(listElements(source) == [3, 23, 13, 14, 24, 5])
    }

    @Test
    func testMutableListPrimitiveSortByAscending() {
        let source = makeList([22, 12, 21, 11])
        #expect(kk_mutable_list_sortBy_primitive(source, selectorPtr(selectModTen), 0, 0, nil) == 0)
        #expect(listElements(source) == [21, 11, 22, 12])
    }

    @Test
    func testMutableListPrimitiveSortByDescending() {
        let source = makeList([22, 12, 21, 11])
        #expect(kk_mutable_list_sortByDescending_primitive(source, selectorPtr(selectModTen), 0, 0, nil) == 0)
        #expect(listElements(source) == [22, 12, 21, 11])
    }

    // MARK: - Exception propagation

    // MARK: - Edge cases

    // MARK: - naturalOrder / reverseOrder: runtimeNullSentinelInt 挙動 (TEST-COMP-011)

    // MARK: - 参照型オブジェクトの安定ソート（原順序保持：インデックスベース検証）(TEST-COMP-011)

    @Test
    func testStableSortPreservesOriginalOrderOfEqualReferenceObjects() {
        // Create three distinct RuntimeStringBox objects that all hold "b".
        // Use original positions as the assertion target so the stability check is
        // explicit and independent from the raw pointer order.
        let b0 = makeRuntimeString("b")
        let b1 = makeRuntimeString("b")
        let b2 = makeRuntimeString("b")

        let source = makeList([b0, b1, b2])
        let sorted = kk_list_sorted(source)

        let originalIndexesByHandle = [b0: 0, b1: 1, b2: 2]
        #expect(originalIndexes(for: listElements(sorted), indexedByHandle: originalIndexesByHandle) == [0, 1, 2])
    }

    @Test
    func testStableSortWithMixedElementsPreservesEqualGroupOrder() {
        // Input: [c, b_first, a, b_second, b_third]
        // Natural string order groups: a < b < c.
        // Within the "b" group the three objects are equal by value but distinct by identity.
        // A stable sort must emit them in the same relative order they appeared in the input,
        // which we verify through their original indexes.
        let bFirst  = makeRuntimeString("b")
        let bSecond = makeRuntimeString("b")
        let bThird  = makeRuntimeString("b")
        let aStr = makeRuntimeString("a")
        let cStr = makeRuntimeString("c")

        let source = makeList([cStr, bFirst, aStr, bSecond, bThird])
        let sorted = kk_list_sorted(source)

        let originalIndexesByHandle = [
            cStr: 0,
            bFirst: 1,
            aStr: 2,
            bSecond: 3,
            bThird: 4,
        ]
        #expect(
            originalIndexes(for: listElements(sorted), indexedByHandle: originalIndexesByHandle) == [2, 1, 3, 4, 0]
        )
    }
}
