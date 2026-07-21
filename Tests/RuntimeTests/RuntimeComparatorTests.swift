import Foundation
@testable import Runtime
import XCTest

// MARK: - Trampoline wrappers
// Local @convention(c) closures that delegate to the @_cdecl runtime functions.
// We must NOT pass @_cdecl functions directly to comparatorPtr() because Swift
// would re-export the C symbol in this module, causing duplicate symbol linker errors.

private let nullsFirstTrampoline: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { closureRaw, a, b, outThrown in
    kk_comparator_nulls_first_trampoline(closureRaw, a, b, outThrown)
}

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

final class RuntimeComparatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // MARK: - compareBy ascending

    // MARK: - compareByDescending

    func testComparatorFromMultiSelectorsVararg() {
        let selectors = makeArray([
            selectorPtr(selectModTen), 0,
            selectorPtr(selectIdentity), 0,
            selectorPtr(selectIdentity), 0,
            selectorPtr(selectIdentity), 0,
        ])
        let closureRaw = kk_comparator_from_multi_selectors_vararg(selectors)

        XCTAssertLessThan(kk_comparator_from_multi_selectors_trampoline(closureRaw, 13, 25, nil), 0)
        XCTAssertLessThan(kk_comparator_from_multi_selectors_trampoline(closureRaw, 13, 23, nil), 0)
        XCTAssertEqual(kk_comparator_from_multi_selectors_trampoline(closureRaw, 17, 17, nil), 0)
    }

    // MARK: - compareValues

    func testCompareValuesLessThan() {
        var thrown = 0
        let result = kk_compareValues(kk_box_int(3), kk_box_int(7), &thrown)
        XCTAssertLessThan(kk_unbox_int(result), 0)
        XCTAssertEqual(thrown, 0)
    }

    func testCompareValuesEqual() {
        var thrown = 0
        let result = kk_compareValues(kk_box_int(5), kk_box_int(5), &thrown)
        XCTAssertEqual(kk_unbox_int(result), 0)
        XCTAssertEqual(thrown, 0)
    }

    func testCompareValuesGreaterThan() {
        var thrown = 0
        let result = kk_compareValues(kk_box_int(9), kk_box_int(2), &thrown)
        XCTAssertGreaterThan(kk_unbox_int(result), 0)
        XCTAssertEqual(thrown, 0)
    }

    func testCompareValuesNullLessThanNonNull() {
        var thrown = 0
        let result = kk_compareValues(runtimeNullSentinelInt, kk_box_int(1), &thrown)
        XCTAssertLessThan(kk_unbox_int(result), 0)
        XCTAssertEqual(thrown, 0)
    }

    func testCompareValuesNonNullGreaterThanNull() {
        var thrown = 0
        let result = kk_compareValues(kk_box_int(1), runtimeNullSentinelInt, &thrown)
        XCTAssertGreaterThan(kk_unbox_int(result), 0)
        XCTAssertEqual(thrown, 0)
    }

    func testCompareValuesBothNull() {
        var thrown = 0
        let result = kk_compareValues(runtimeNullSentinelInt, runtimeNullSentinelInt, &thrown)
        XCTAssertEqual(kk_unbox_int(result), 0)
        XCTAssertEqual(thrown, 0)
    }

    func testCompareValuesByVarargSelectors() {
        let selectors = makeArray([
            selectorPtr(selectModTen), 0,
            selectorPtr(selectIdentity), 0,
            selectorPtr(selectIdentity), 0,
            selectorPtr(selectIdentity), 0,
        ])
        var thrown = 0
        let result = kk_compareValuesByVararg(13, 25, selectors, &thrown)
        XCTAssertEqual(kk_unbox_int(result), -1)
        XCTAssertEqual(thrown, 0)

        let tiedFirstKey = kk_compareValuesByVararg(13, 23, selectors, &thrown)
        XCTAssertEqual(kk_unbox_int(tiedFirstKey), -1)
        XCTAssertEqual(thrown, 0)
    }

    func testCompareValuesByComparatorSelector() {
        withComparatorObject(mode: 0) { comparatorRaw in
            var thrown = 0
            let result = kk_compareValuesByComparator(
                13,
                25,
                comparatorRaw,
                selectorPtr(selectModTen),
                0,
                &thrown
            )
            XCTAssertEqual(kk_unbox_int(result), -1)
            XCTAssertEqual(thrown, 0)
        }
    }

    // MARK: - thenBy

    // MARK: - thenDescending

    // MARK: - thenComparator

    // MARK: - reversed

    // MARK: - naturalOrder / reverseOrder

    func testCaseInsensitiveOrderComparatorObjectDispatchesThroughITable() {
        let comparatorRaw = kk_string_case_insensitive_order()
        let compareFnPtr = kk_itable_lookup(comparatorRaw, 0, 0)
        XCTAssertNotEqual(compareFnPtr, 0)

        let compareFn = unsafeBitCast(compareFnPtr, to: RuntimeCollectionLambda2.self)
        XCTAssertEqual(
            compareFn(comparatorRaw, makeRuntimeString("alpha"), makeRuntimeString("ALPHA"), nil),
            0
        )
        XCTAssertLessThan(
            compareFn(comparatorRaw, makeRuntimeString("apple"), makeRuntimeString("banana"), nil),
            0
        )
        XCTAssertGreaterThan(
            compareFn(comparatorRaw, makeRuntimeString("Zoo"), makeRuntimeString("apple"), nil),
            0
        )
    }

    func testSortedWithCaseInsensitiveOrderComparatorObject() {
        let source = makeList([
            makeRuntimeString("b"),
            makeRuntimeString("A"),
            makeRuntimeString("c"),
            makeRuntimeString("a"),
        ])
        let comparatorRaw = kk_string_case_insensitive_order()

        let sorted = kk_list_sortedWith(source, comparatorRaw, 0, nil)
        XCTAssertEqual(listElements(sorted).map(runtimeStringValue), ["A", "a", "b", "c"])
    }

    // MARK: - sortedWith E2E

    func testSortedWithComparator() {
        let source = makeList([5, 3, 8, 1, 4])
        let sorted = kk_list_sortedWith(
            source,
            comparatorPtr(comparatorNatural),
            0,
            nil
        )
        XCTAssertEqual(listElements(sorted), [1, 3, 4, 5, 8])
    }

    func testPrimitiveListSortedAscending() {
        let source = makeList([5, 3, 8, 1, 4])
        let sorted = kk_list_sorted_primitive(source, 0)
        XCTAssertEqual(listElements(sorted), [1, 3, 4, 5, 8])
    }

    func testPrimitiveListSortedDescending() {
        let source = makeList([5, 3, 8, 1, 4])
        let sorted = kk_list_sortedDescending_primitive(source, 0)
        XCTAssertEqual(listElements(sorted), [8, 5, 4, 3, 1])
    }

    func testListSortedDescendingComparableObjectsReturnsNewSortedList() {
        let source = makeList([
            makeRuntimeString("b"),
            makeRuntimeString("a"),
            makeRuntimeString("c"),
        ])
        let sorted = kk_list_sortedDescending(source)

        XCTAssertEqual(listElements(sorted).map(runtimeStringValue), ["c", "b", "a"])
        XCTAssertEqual(listElements(source).map(runtimeStringValue), ["b", "a", "c"])
    }

    func testPrimitiveListSortedByAscending() {
        let source = makeList([22, 12, 21, 11])
        let sorted = kk_list_sortedBy_primitive(source, selectorPtr(selectModTen), 0, 0, nil)
        XCTAssertEqual(listElements(sorted), [21, 11, 22, 12])
    }

    func testPrimitiveListSortedByDescending() {
        let source = makeList([22, 12, 21, 11])
        let sorted = kk_list_sortedByDescending_primitive(source, selectorPtr(selectModTen), 0, 0, nil)
        XCTAssertEqual(listElements(sorted), [22, 12, 21, 11])
    }

    func testPrimitiveListSortedStability() {
        let source = makeList([2, 1, 2, 1, 2])
        let sorted = kk_list_sorted_primitive(source, 0)
        XCTAssertEqual(listElements(sorted), [1, 1, 2, 2, 2])
    }

    func testListSortedComparableObjectsReturnsNewSortedList() {
        let source = makeList([
            makeRuntimeString("b"),
            makeRuntimeString("a"),
            makeRuntimeString("c"),
        ])
        let sorted = kk_list_sorted(source)
        XCTAssertEqual(listElements(sorted).map(runtimeStringValue), ["a", "b", "c"])
        XCTAssertEqual(listElements(source).map(runtimeStringValue), ["b", "a", "c"])
    }

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

        XCTAssertEqual(
            listElements(floatSorted).map { kk_unbox_float($0) },
            [Float(1.5).bitPattern, Float(2.0).bitPattern, Float(3.0).bitPattern].map { Int(truncatingIfNeeded: $0) }
        )
        XCTAssertEqual(
            listElements(doubleSorted).map { kk_unbox_double($0) },
            [Double(1.5).bitPattern, Double(2.0).bitPattern, Double(3.0).bitPattern].map { Int(truncatingIfNeeded: $0) }
        )
    }

    func testSortedWithReversedComparator() {
        let source = makeList([5, 3, 8, 1, 4])
        let sorted = kk_list_sortedWith(
            source,
            comparatorPtr(comparatorReversed),
            0,
            nil
        )
        XCTAssertEqual(listElements(sorted), [8, 5, 4, 3, 1])
    }

    func testSortedWithComparatorObjectDispatchesThroughVtable() {
        let source = makeList([5, 3, 8, 1, 4])

        withComparatorObject(mode: 0) { comparatorRaw in
            let sorted = kk_list_sortedWith(source, comparatorRaw, 0, nil)
            XCTAssertEqual(listElements(sorted), [1, 3, 4, 5, 8])
        }

        withComparatorObject(mode: 1) { comparatorRaw in
            let sorted = kk_list_sortedWith(source, comparatorRaw, 0, nil)
            XCTAssertEqual(listElements(sorted), [8, 5, 4, 3, 1])
        }
    }

    func testArrayBinarySearchCompareWithComparatorObjectAndRange() {
        let source = makeArray([1, 3, 5, 7, 9])

        withComparatorObject(mode: 0) { comparatorRaw in
            var thrown = 0

            let found = kk_array_binarySearch_compare(source, 5, comparatorRaw, 0, 0, 5, &thrown)
            XCTAssertEqual(found, 2)
            XCTAssertEqual(thrown, 0)

            let missing = kk_array_binarySearch_compare(source, 4, comparatorRaw, 0, 0, 5, &thrown)
            XCTAssertEqual(missing, -3)
            XCTAssertEqual(thrown, 0)

            let ranged = kk_array_binarySearch_compare(source, 7, comparatorRaw, 0, 2, 5, &thrown)
            XCTAssertEqual(ranged, 3)
            XCTAssertEqual(thrown, 0)
        }
    }

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
        XCTAssertEqual(found, 2)
        XCTAssertEqual(thrown, 0)

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
        XCTAssertEqual(missing, -4)
        XCTAssertEqual(thrown, 0)
    }

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
            XCTAssertEqual(found, 3)
            XCTAssertEqual(thrown, 0)
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
            XCTAssertEqual(found, 2)
            XCTAssertEqual(thrown, 0)
        }
    }

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
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0)
    }

    func testArrayBinarySearchCompareObjectDispatchesThroughVtable() {
        let source = makeArray([1, 3, 4, 9])

        withComparatorObject(mode: 0) { comparatorRaw in
            let hit = kk_array_binarySearch_compare(source, 4, comparatorRaw, 0, 0, 4, nil)
            XCTAssertEqual(hit, 2)

            let miss = kk_array_binarySearch_compare(source, 5, comparatorRaw, 0, 1, 3, nil)
            XCTAssertEqual(miss, -4)
        }
    }

    func testMutableListPrimitiveSortAscending() {
        let source = makeList([5, 3, 8, 1, 4])
        XCTAssertEqual(kk_mutable_list_sort_primitive(source, 0), 0)
        XCTAssertEqual(listElements(source), [1, 3, 4, 5, 8])
    }

    func testMutableListSortComparableObjectsMutatesInPlace() {
        let source = makeList([
            makeRuntimeString("b"),
            makeRuntimeString("a"),
            makeRuntimeString("c"),
        ])
        XCTAssertEqual(kk_mutable_list_sort(source), 0)
        XCTAssertEqual(listElements(source).map(runtimeStringValue), ["a", "b", "c"])
    }

    func testMutableListPrimitiveSortDescending() {
        let source = makeList([5, 3, 8, 1, 4])
        XCTAssertEqual(kk_mutable_list_sortDescending_primitive(source, 0), 0)
        XCTAssertEqual(listElements(source), [8, 5, 4, 3, 1])
    }

    func testMutableListSortWithComparatorMutatesInPlace() {
        let source = makeList([14, 3, 23, 5, 13, 24])
        XCTAssertEqual(kk_mutable_list_sortWith(source, comparatorPtr(comparatorByModTen), 0, nil), 0)
        XCTAssertEqual(listElements(source), [3, 23, 13, 14, 24, 5])
    }

    func testMutableListPrimitiveSortByAscending() {
        let source = makeList([22, 12, 21, 11])
        XCTAssertEqual(kk_mutable_list_sortBy_primitive(source, selectorPtr(selectModTen), 0, 0, nil), 0)
        XCTAssertEqual(listElements(source), [21, 11, 22, 12])
    }

    func testMutableListPrimitiveSortByDescending() {
        let source = makeList([22, 12, 21, 11])
        XCTAssertEqual(kk_mutable_list_sortByDescending_primitive(source, selectorPtr(selectModTen), 0, 0, nil), 0)
        XCTAssertEqual(listElements(source), [22, 12, 21, 11])
    }

    func testSortedWithNullsFirstComparator() {
        let source = makeList([5, runtimeNullSentinelInt, 3, runtimeNullSentinelInt, 4, 1])
        let chain = kk_comparator_nulls_first(comparatorPtr(comparatorNatural), 0)
        let sorted = kk_list_sortedWith(
            source,
            comparatorPtr(nullsFirstTrampoline),
            chain,
            nil
        )
        XCTAssertEqual(listElements(sorted), [runtimeNullSentinelInt, runtimeNullSentinelInt, 1, 3, 4, 5])
    }

    // MARK: - Exception propagation

    // MARK: - Edge cases

    func testComparatorNullsFirstTrampoline() {
        let chain = kk_comparator_nulls_first(comparatorPtr(comparatorNatural), 0)
        XCTAssertLessThan(kk_comparator_nulls_first_trampoline(chain, runtimeNullSentinelInt, 5, nil), 0)
        XCTAssertGreaterThan(kk_comparator_nulls_first_trampoline(chain, 5, runtimeNullSentinelInt, nil), 0)
        XCTAssertLessThan(kk_comparator_nulls_first_trampoline(chain, 3, 5, nil), 0)
        XCTAssertEqual(kk_comparator_nulls_first_trampoline(chain, runtimeNullSentinelInt, runtimeNullSentinelInt, nil), 0)
    }

    func testComparatorNullsLastTrampoline() {
        let chain = kk_comparator_nulls_last(comparatorPtr(comparatorNatural), 0)
        XCTAssertGreaterThan(kk_comparator_nulls_last_trampoline(chain, runtimeNullSentinelInt, 5, nil), 0)
        XCTAssertLessThan(kk_comparator_nulls_last_trampoline(chain, 5, runtimeNullSentinelInt, nil), 0)
        XCTAssertGreaterThan(kk_comparator_nulls_last_trampoline(chain, 5, 3, nil), 0)
        XCTAssertEqual(kk_comparator_nulls_last_trampoline(chain, runtimeNullSentinelInt, runtimeNullSentinelInt, nil), 0)
    }

    // MARK: - naturalOrder / reverseOrder: runtimeNullSentinelInt 挙動 (TEST-COMP-011)

    // MARK: - compareBy: 全キー等値で 0 を返すこと (TEST-COMP-011)

    func testCompareByAllSelectorsEqualReturnsZero() {
        // All four slots use selectModTen.  13%10 == 23%10 == 3 for every selector,
        // so the loop exhausts without finding a non-zero result and returns 0.
        let selectors = makeArray([
            selectorPtr(selectModTen), 0,
            selectorPtr(selectModTen), 0,
            selectorPtr(selectModTen), 0,
            selectorPtr(selectModTen), 0,
        ])
        let closureRaw = kk_comparator_from_multi_selectors_vararg(selectors)
        // inputs differ (13 ≠ 23) but all key projections are identical
        XCTAssertEqual(kk_comparator_from_multi_selectors_trampoline(closureRaw, 13, 23, nil), 0)
        XCTAssertEqual(kk_comparator_from_multi_selectors_trampoline(closureRaw, 23, 13, nil), 0)
        // sanity: equal inputs still produce 0
        XCTAssertEqual(kk_comparator_from_multi_selectors_trampoline(closureRaw, 7, 7, nil), 0)
    }

    // MARK: - 参照型オブジェクトの安定ソート（原順序保持：インデックスベース検証）(TEST-COMP-011)

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
        XCTAssertEqual(originalIndexes(for: listElements(sorted), indexedByHandle: originalIndexesByHandle), [0, 1, 2])
    }

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
        XCTAssertEqual(
            originalIndexes(for: listElements(sorted), indexedByHandle: originalIndexesByHandle),
            [2, 1, 3, 4, 0]
        )
    }
}
