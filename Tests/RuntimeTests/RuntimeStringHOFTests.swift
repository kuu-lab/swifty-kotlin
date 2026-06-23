@testable import Runtime
import XCTest

// Predicate: matches ASCII digit characters (0x30 .. 0x39 = '0' .. '9')
private let isDigitPredicateForIndexOfFirst: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    (charRaw >= 0x30 && charRaw <= 0x39) ? 1 : 0
}

// Predicate: matches the letter 'x'
private let isLetterXPredicateForIndexOfFirst: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    charRaw == Int(Unicode.Scalar("x").value) ? 1 : 0
}

private let firstNotNullOfStringForB: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    if charRaw == Int(Unicode.Scalar("b").value) {
        return registerRuntimeObject(RuntimeStringBox("bee"))
    }
    return runtimeNullSentinelInt
}

private let firstNotNullOfAlwaysNull: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _ in
    runtimeNullSentinelInt
}

private let firstNotNullOfAlwaysZeroNull: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _ in
    0
}

private let reduceRightIndexedPickIndexOne: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, charRaw, acc, _ in
    index == 1 ? charRaw : acc
}

private let reduceRightIndexedIndexChecksum: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, charRaw, acc, _ in
    acc + charRaw + index
}

private let reduceRightPickB: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, acc, _ in
    charRaw == Int(Unicode.Scalar("b").value) ? charRaw : acc
}

private let reduceRightChecksum: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, acc, _ in
    acc + charRaw
}

// MARK: - STDLIB-TEXT-FN-049: reduceOrNull helpers (acc first, char second)

private let reduceOrNullPickB: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, acc, charRaw, _ in
    charRaw == Int(Unicode.Scalar("b").value) ? charRaw : acc
}

private let reduceOrNullChecksum: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, acc, charRaw, _ in
    acc + charRaw
}

private let sumByWeightedA: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    charRaw == Int(Unicode.Scalar("a").value) ? 10 : 1
}

// STDLIB-TEXT-FN-116: zip transform — combines two chars into their sum codepoint
private let zipTransformSumCodepoints: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, aRaw, bRaw, _ in
    kk_box_char(kk_unbox_char(aRaw) + kk_unbox_char(bRaw))
}

private let zipTransformStringPairName: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, aRaw, bRaw, _ in
    let a = UnicodeScalar(kk_unbox_char(aRaw)).map { String(Character($0)) } ?? "?"
    let b = UnicodeScalar(kk_unbox_char(bRaw)).map { String(Character($0)) } ?? "?"
    return registerRuntimeObject(RuntimeStringBox("\(a):\(b)"))
}

private let zipTransformRejectBoxedCharArgs: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, aRaw, bRaw, _ in
    if aRaw > 0x10_FFFF || bRaw > 0x10_FFFF {
        return kk_box_char(0)
    }
    return kk_box_char(aRaw + bRaw)
}

private let sumByDoubleWeightedA: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    kk_double_to_bits(charRaw == Int(Unicode.Scalar("a").value) ? 1.5 : 0.25)
}

private let isAsciiLowercasePredicate: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    (0x61 ... 0x7A).contains(charRaw) ? 1 : 0
}

private let isEvenIndexPredicate: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, index, _, _ in
    index.isMultiple(of: 2) ? 1 : 0
}

private let mapBoxCharValue: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    kk_box_char(charRaw)
}

private let mapStringNameForChar: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    let value = charRaw == Int(Unicode.Scalar("a").value) ? "alpha" : "beta"
    return registerRuntimeObject(RuntimeStringBox(value))
}

private let mapIndexedBoxIndexPlusChar: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, index, charRaw, _ in
    kk_box_int(index + charRaw)
}

private let mapIndexedStringName: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, index, charRaw, _ in
    let scalarText = UnicodeScalar(charRaw).map { String(Character($0)) } ?? "?"
    return registerRuntimeObject(RuntimeStringBox("\(index):\(scalarText)"))
}

private let mapNotNullBoxOnlyB: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    charRaw == Int(Unicode.Scalar("b").value) ? kk_box_char(charRaw) : runtimeNullSentinelInt
}

private let partitionMatchesB: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    charRaw == Int(Unicode.Scalar("b").value) ? 1 : 0
}

private let takeLastWhileSurrogateCodeUnit: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, charRaw, _ in
    (0xD800 ... 0xDFFF).contains(charRaw) ? 1 : 0
}

private func runtimeStringValueForHOF(_ raw: Int) -> String {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw),
          let box = tryCast(pointer, to: RuntimeStringBox.self) else {
        return ""
    }
    return box.value
}

private func assertAggregateStringList(
    _ list: RuntimeListBox?,
    equals expected: [String],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let list else {
        XCTFail("Expected a RuntimeListBox", file: file, line: line)
        return
    }
    XCTAssertEqual(
        list.values.map(\.tag),
        Array(repeating: RuntimeValue.stringTag, count: expected.count),
        file: file,
        line: line
    )
    XCTAssertEqual(list.values.map { runtimeRenderAnyForPrint($0) }, expected, file: file, line: line)
    XCTAssertEqual(list.elements.map(runtimeStringValueForHOF), expected, file: file, line: line)
}

final class RuntimeStringHOFTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    private func runtimeString(_ text: String) -> Int {
        runtimeMakeStringRaw(text)
    }

    private func stringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    func testStringMapReturnsMappedList() {
        let strRaw = runtimeString("ab")
        var thrown = -1
        let result = kk_string_map(
            strRaw,
            unsafeBitCast(mapBoxCharValue, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        guard let list = runtimeListBox(from: result) else {
            XCTFail("Expected list from kk_string_map")
            return
        }
        XCTAssertEqual(list.elements.count, 2)
        XCTAssertEqual(kk_unbox_char(list.elements[0]), Int(Unicode.Scalar("a").value))
        XCTAssertEqual(kk_unbox_char(list.elements[1]), Int(Unicode.Scalar("b").value))
        XCTAssertEqual(list.values.map(\.tag), [RuntimeValue.charTag, RuntimeValue.charTag])
        XCTAssertEqual(
            list.values.map(\.payload0),
            [Int(Unicode.Scalar("a").value), Int(Unicode.Scalar("b").value)]
        )
    }

    func testStringMapStoresAggregateStringResults() {
        let strRaw = runtimeString("ab")
        var thrown = -1
        let result = kk_string_map(
            strRaw,
            unsafeBitCast(mapStringNameForChar, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        assertAggregateStringList(runtimeListBox(from: result), equals: ["alpha", "beta"])
    }

    func testStringMapIndexedReturnsMappedList() {
        let strRaw = runtimeString("ab")
        var thrown = -1
        let result = kk_string_mapIndexed(
            strRaw,
            unsafeBitCast(mapIndexedBoxIndexPlusChar, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        guard let list = runtimeListBox(from: result) else {
            XCTFail("Expected list from kk_string_mapIndexed")
            return
        }
        XCTAssertEqual(list.elements.count, 2)
        XCTAssertEqual(kk_unbox_int(list.elements[0]), 97)
        XCTAssertEqual(kk_unbox_int(list.elements[1]), 99)
    }

    func testStringMapIndexedStoresAggregateStringResults() {
        let strRaw = runtimeString("ab")
        var thrown = -1
        let result = kk_string_mapIndexed(
            strRaw,
            unsafeBitCast(mapIndexedStringName, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        assertAggregateStringList(runtimeListBox(from: result), equals: ["0:a", "1:b"])
    }

    func testStringMapNotNullFiltersNullResults() {
        let strRaw = runtimeString("abc")
        var thrown = -1
        let result = kk_string_mapNotNull(
            strRaw,
            unsafeBitCast(mapNotNullBoxOnlyB, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        guard let list = runtimeListBox(from: result) else {
            XCTFail("Expected list from kk_string_mapNotNull")
            return
        }
        XCTAssertEqual(list.elements.count, 1)
        XCTAssertEqual(kk_unbox_char(list.elements[0]), Int(Unicode.Scalar("b").value))
        XCTAssertEqual(list.values.map(\.tag), [RuntimeValue.charTag])
        XCTAssertEqual(list.values.map(\.payload0), [Int(Unicode.Scalar("b").value)])
    }

    func testStringPartitionSplitsIntoPair() {
        let strRaw = runtimeString("abc")
        var thrown = -1
        let result = kk_string_partition(
            strRaw,
            unsafeBitCast(partitionMatchesB, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        guard let pairPtr = UnsafeMutableRawPointer(bitPattern: result),
              let pairBox = tryCast(pairPtr, to: RuntimePairBox.self)
        else {
            XCTFail("Expected Pair from kk_string_partition")
            return
        }
        XCTAssertEqual(pairBox.firstValue.tag, RuntimeValue.stringTag)
        XCTAssertEqual(pairBox.secondValue.tag, RuntimeValue.stringTag)
        XCTAssertEqual(runtimeRenderAnyForPrint(pairBox.firstValue), "b")
        XCTAssertEqual(runtimeRenderAnyForPrint(pairBox.secondValue), "ac")
        XCTAssertEqual(runtimeElementToString(result), "(b, ac)")
        XCTAssertEqual(runtimeStringValueForHOF(kk_pair_first(result)), "b")
        XCTAssertEqual(runtimeStringValueForHOF(kk_pair_second(result)), "ac")
    }

    func testStringFilterReturnsFiltedString() {
        let strRaw = runtimeString("a1b2")
        var thrown = -1
        let result = kk_string_filter(
            strRaw,
            unsafeBitCast(isDigitPredicateForIndexOfFirst, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(stringValue(result), "12")
    }

    func testStringTrimPredicateReturnsFilteredString() {
        let fnPtr = unsafeBitCast(isLetterXPredicateForIndexOfFirst, to: Int.self)

        var trimThrown = -1
        let trimResult = kk_string_trim_predicate(
            runtimeString("xxabxx"),
            fnPtr,
            0,
            &trimThrown
        )
        XCTAssertEqual(trimThrown, 0)
        XCTAssertEqual(stringValue(trimResult), "ab")

        var trimStartThrown = -1
        let trimStartResult = kk_string_trimStart_predicate(
            runtimeString("xxabxx"),
            fnPtr,
            0,
            &trimStartThrown
        )
        XCTAssertEqual(trimStartThrown, 0)
        XCTAssertEqual(stringValue(trimStartResult), "abxx")

        var trimEndThrown = -1
        let trimEndResult = kk_string_trimEnd_predicate(
            runtimeString("xxabxx"),
            fnPtr,
            0,
            &trimEndThrown
        )
        XCTAssertEqual(trimEndThrown, 0)
        XCTAssertEqual(stringValue(trimEndResult), "xxab")
    }

    func testStringFilterIndexedReturnsFilteredString() {
        let strRaw = runtimeString("abcd")
        var thrown = -1
        let result = kk_string_filterIndexed(
            strRaw,
            unsafeBitCast(isEvenIndexPredicate, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(stringValue(result), "ac")
    }

    func testStringFilterNotReturnsFilteredString() {
        let strRaw = runtimeString("a1b2")
        var thrown = -1
        let result = kk_string_filterNot(
            strRaw,
            unsafeBitCast(isDigitPredicateForIndexOfFirst, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(stringValue(result), "ab")
    }

    func testStringTakeAndDropWhileReturnFilteredStrings() {
        var takeThrown = -1
        let taken = kk_string_takeWhile(
            runtimeString("abc123"),
            unsafeBitCast(isAsciiLowercasePredicate, to: Int.self),
            0,
            &takeThrown
        )
        var dropThrown = -1
        let dropped = kk_string_dropWhile(
            runtimeString("abc123"),
            unsafeBitCast(isAsciiLowercasePredicate, to: Int.self),
            0,
            &dropThrown
        )

        XCTAssertEqual(takeThrown, 0)
        XCTAssertEqual(dropThrown, 0)
        XCTAssertEqual(stringValue(taken), "abc")
        XCTAssertEqual(stringValue(dropped), "123")
    }

    // MARK: - kk_string_indexOfFirst (STDLIB-TEXT-FN-022)

    func testIndexOfFirstReturnsIndexOfFirstMatchingChar() {
        let strRaw = runtimeString("hello3world")
        var thrown = 0
        let result = kk_string_indexOfFirst(
            strRaw,
            unsafeBitCast(isDigitPredicateForIndexOfFirst, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 5)
    }

    func testIndexOfFirstReturnsMinusOneWhenNoCharMatches() {
        let strRaw = runtimeString("hello")
        var thrown = 0
        let result = kk_string_indexOfFirst(
            strRaw,
            unsafeBitCast(isDigitPredicateForIndexOfFirst, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, -1)
    }

    func testIndexOfFirstOnEmptyStringReturnsMinusOne() {
        let strRaw = runtimeString("")
        var thrown = 0
        let result = kk_string_indexOfFirst(
            strRaw,
            unsafeBitCast(isDigitPredicateForIndexOfFirst, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, -1)
    }

    func testIndexOfFirstReturnsZeroWhenFirstCharMatches() {
        let strRaw = runtimeString("xabc")
        var thrown = 0
        let result = kk_string_indexOfFirst(
            strRaw,
            unsafeBitCast(isLetterXPredicateForIndexOfFirst, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 0)
    }

    func testIndexOfFirstStopsAtFirstMatchNotLast() {
        let strRaw = runtimeString("axbxc")
        var thrown = 0
        let result = kk_string_indexOfFirst(
            strRaw,
            unsafeBitCast(isLetterXPredicateForIndexOfFirst, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 1)
    }

    func testFirstNotNullOfReturnsFirstNonNullResult() {
        let strRaw = runtimeString("abc")
        var thrown = 0
        let result = kk_string_firstNotNullOf(
            strRaw,
            unsafeBitCast(firstNotNullOfStringForB, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(stringValue(result), "bee")
    }

    func testFirstNotNullOfSetsThrownWhenNoResultMatches() {
        let strRaw = runtimeString("abc")
        var thrown = 0
        let result = kk_string_firstNotNullOf(
            strRaw,
            unsafeBitCast(firstNotNullOfAlwaysNull, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0)
    }

    func testFirstNotNullOfTreatsZeroAsNullFromNullableLambda() {
        let strRaw = runtimeString("abc")
        var thrown = 0
        let result = kk_string_firstNotNullOf(
            strRaw,
            unsafeBitCast(firstNotNullOfAlwaysZeroNull, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0)
    }

    func testTakeLastWhileUsesUTF16CodeUnits() {
        let strRaw = runtimeString("a🐻")
        var thrown = -1
        let result = kk_string_takeLastWhile(
            strRaw,
            unsafeBitCast(takeLastWhileSurrogateCodeUnit, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(stringValue(result), "🐻")
    }

    func testFirstNotNullOfOrNullReturnsFirstNonNullResult() {
        let strRaw = runtimeString("abc")
        var thrown = 0
        let result = kk_string_firstNotNullOfOrNull(
            strRaw,
            unsafeBitCast(firstNotNullOfStringForB, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(stringValue(result), "bee")
    }

    func testFirstNotNullOfOrNullReturnsNullSentinelWhenNoResultMatches() {
        let strRaw = runtimeString("abc")
        var thrown = 0
        let result = kk_string_firstNotNullOfOrNull(
            strRaw,
            unsafeBitCast(firstNotNullOfAlwaysNull, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testFirstNotNullOfOrNullTreatsZeroAsNullFromNullableLambda() {
        let strRaw = runtimeString("abc")
        var thrown = 0
        let result = kk_string_firstNotNullOfOrNull(
            strRaw,
            unsafeBitCast(firstNotNullOfAlwaysZeroNull, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testReduceRightIndexedWalksRightToLeftWithIndexes() {
        let strRaw = runtimeString("abc")
        var thrown = 0
        let result = kk_string_reduceRightIndexed(
            strRaw,
            unsafeBitCast(reduceRightIndexedPickIndexOne, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Unicode.Scalar("b").value))
    }

    func testReduceRightIndexedUsesLastCharacterAsInitialAccumulator() {
        let strRaw = runtimeString("abc")
        var thrown = 0
        let result = kk_string_reduceRightIndexed(
            strRaw,
            unsafeBitCast(reduceRightIndexedIndexChecksum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 295)
    }

    func testReduceRightIndexedSetsThrownForEmptyString() {
        let strRaw = runtimeString("")
        var thrown = 0
        let result = kk_string_reduceRightIndexed(
            strRaw,
            unsafeBitCast(reduceRightIndexedPickIndexOne, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
        XCTAssertNotEqual(thrown, 0)
    }

    func testReduceRightIndexedOrNullWalksRightToLeftWithIndexes() {
        let strRaw = runtimeString("abc")
        var thrown = 0
        let result = kk_string_reduceRightIndexedOrNull(
            strRaw,
            unsafeBitCast(reduceRightIndexedPickIndexOne, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Unicode.Scalar("b").value))
    }

    func testReduceRightIndexedOrNullReturnsNullSentinelForEmptyString() {
        let strRaw = runtimeString("")
        var thrown = 0
        let result = kk_string_reduceRightIndexedOrNull(
            strRaw,
            unsafeBitCast(reduceRightIndexedPickIndexOne, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testReduceRightIndexedOrNullUsesLastCharacterAsInitialAccumulator() {
        let strRaw = runtimeString("abc")
        var thrown = 0
        let result = kk_string_reduceRightIndexedOrNull(
            strRaw,
            unsafeBitCast(reduceRightIndexedIndexChecksum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 295)
    }

    func testReduceRightOrNullWalksRightToLeft() {
        let strRaw = runtimeString("abc")
        var thrown = 0
        let result = kk_string_reduceRightOrNull(
            strRaw,
            unsafeBitCast(reduceRightPickB, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Unicode.Scalar("b").value))
    }

    func testReduceRightOrNullReturnsNullSentinelForEmptyString() {
        let strRaw = runtimeString("")
        var thrown = 0
        let result = kk_string_reduceRightOrNull(
            strRaw,
            unsafeBitCast(reduceRightPickB, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testReduceRightOrNullUsesLastCharacterAsInitialAccumulator() {
        let strRaw = runtimeString("abc")
        var thrown = 0
        let result = kk_string_reduceRightOrNull(
            strRaw,
            unsafeBitCast(reduceRightChecksum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 294)
    }

    // MARK: - STDLIB-TEXT-FN-049: kk_string_reduceOrNull

    func testReduceOrNullWalksLeftToRight() {
        let strRaw = runtimeString("abc")
        var thrown = 0
        let result = kk_string_reduceOrNull(
            strRaw,
            unsafeBitCast(reduceOrNullPickB, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Unicode.Scalar("b").value))
    }

    func testReduceOrNullReturnsNullSentinelForEmptyString() {
        let strRaw = runtimeString("")
        var thrown = 0
        let result = kk_string_reduceOrNull(
            strRaw,
            unsafeBitCast(reduceOrNullPickB, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testReduceOrNullUsesFirstCharacterAsInitialAccumulator() {
        let strRaw = runtimeString("abc")
        var thrown = 0
        let result = kk_string_reduceOrNull(
            strRaw,
            unsafeBitCast(reduceOrNullChecksum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 294)
    }

    func testReduceOrNullReturnsSingleCharForOneCharString() {
        let strRaw = runtimeString("x")
        var thrown = 0
        let result = kk_string_reduceOrNull(
            strRaw,
            unsafeBitCast(reduceOrNullChecksum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Unicode.Scalar("x").value))
    }

    func testReduceOrNullUsesUTF16CodeUnits() {
        let strRaw = runtimeString("a🐻")
        var thrown = 0
        let result = kk_string_reduceOrNull(
            strRaw,
            unsafeBitCast(reduceOrNullChecksum, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 97 + 0xD83D + 0xDC3B)
    }

    func testSumByAppliesSelectorToEveryCharacter() {
        let strRaw = runtimeString("aba")
        var thrown = 0
        let result = kk_string_sumBy(
            strRaw,
            unsafeBitCast(sumByWeightedA, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 21)
    }

    func testSumByReturnsZeroForEmptyString() {
        let strRaw = runtimeString("")
        var thrown = 0
        let result = kk_string_sumBy(
            strRaw,
            unsafeBitCast(sumByWeightedA, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 0)
    }

    func testSumByDoubleAppliesSelectorToEveryCharacter() {
        let strRaw = runtimeString("aba")
        var thrown = 0
        let result = kk_string_sumByDouble(
            strRaw,
            unsafeBitCast(sumByDoubleWeightedA, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_bits_to_double(result), 3.25, accuracy: 0.000001)
    }

    func testSumByDoubleReturnsZeroForEmptyString() {
        let strRaw = runtimeString("")
        var thrown = 0
        let result = kk_string_sumByDouble(
            strRaw,
            unsafeBitCast(sumByDoubleWeightedA, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_bits_to_double(result), 0.0, accuracy: 0.000001)
    }

    // STDLIB-316: String.zipWithNext()
    func testStringZipWithNextPairsAdjacentScalars() {
        let strRaw = runtimeString("ab")
        let result = kk_string_zipWithNext(strRaw)
        guard let list = runtimeListBox(from: result) else {
            XCTFail("Expected list from kk_string_zipWithNext")
            return
        }

        XCTAssertEqual(list.elements.count, 1)
        assertCharPairValue(
            list.values[0].legacyRawValue,
            first: Int(Unicode.Scalar("a").value),
            second: Int(Unicode.Scalar("b").value)
        )
        XCTAssertEqual(kk_unbox_char(kk_pair_first(list.elements[0])), Int(Unicode.Scalar("a").value))
        XCTAssertEqual(kk_unbox_char(kk_pair_second(list.elements[0])), Int(Unicode.Scalar("b").value))
    }

    func testStringZipWithNextTransformCombinesAdjacentScalars() {
        let strRaw = runtimeString("ab")
        var thrown = -1
        let result = kk_string_zipWithNextTransform(
            strRaw,
            unsafeBitCast(zipTransformSumCodepoints, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        guard let list = runtimeListBox(from: result) else {
            XCTFail("Expected list from kk_string_zipWithNextTransform")
            return
        }
        XCTAssertEqual(list.elements.count, 1)
        XCTAssertEqual(kk_unbox_char(list.elements[0]), 97 + 98)
        XCTAssertEqual(list.values.map(\.tag), [RuntimeValue.charTag])
        XCTAssertEqual(list.values.map(\.payload0), [97 + 98])
    }

    func testStringZipWithNextTransformPassesRawCharArgs() {
        let strRaw = runtimeString("ab")
        var thrown = -1
        let result = kk_string_zipWithNextTransform(
            strRaw,
            unsafeBitCast(zipTransformRejectBoxedCharArgs, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        guard let list = runtimeListBox(from: result) else {
            XCTFail("Expected list from kk_string_zipWithNextTransform")
            return
        }
        XCTAssertEqual(list.values.map(\.tag), [RuntimeValue.charTag])
        XCTAssertEqual(list.values.map(\.payload0), [97 + 98])
    }

    func testStringZipWithNextTransformStoresAggregateStringResults() {
        let strRaw = runtimeString("abc")
        var thrown = -1
        let result = kk_string_zipWithNextTransform(
            strRaw,
            unsafeBitCast(zipTransformStringPairName, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        assertAggregateStringList(runtimeListBox(from: result), equals: ["a:b", "b:c"])
    }

    // STDLIB-TEXT-FN-116: CharSequence.zip(other)
    func testStringZipPairsCharsAndStopsAtShorterString() {
        let strRaw = runtimeString("abc")
        let otherRaw = runtimeString("XY")
        let result = kk_string_zip(strRaw, otherRaw)
        guard let list = runtimeListBox(from: result) else {
            XCTFail("Expected list from kk_string_zip")
            return
        }
        XCTAssertEqual(list.elements.count, 2)
        assertCharPairValue(
            list.values[0].legacyRawValue,
            first: Int(Unicode.Scalar("a").value),
            second: Int(Unicode.Scalar("X").value)
        )
        assertCharPairValue(
            list.values[1].legacyRawValue,
            first: Int(Unicode.Scalar("b").value),
            second: Int(Unicode.Scalar("Y").value)
        )
        XCTAssertEqual(kk_unbox_char(kk_pair_first(list.elements[0])), Int(Unicode.Scalar("a").value))
        XCTAssertEqual(kk_unbox_char(kk_pair_second(list.elements[0])), Int(Unicode.Scalar("X").value))
        XCTAssertEqual(kk_unbox_char(kk_pair_first(list.elements[1])), Int(Unicode.Scalar("b").value))
        XCTAssertEqual(kk_unbox_char(kk_pair_second(list.elements[1])), Int(Unicode.Scalar("Y").value))
    }

    func testStringZipReturnsEmptyForEmptySource() {
        let strRaw = runtimeString("")
        let otherRaw = runtimeString("abc")
        let result = kk_string_zip(strRaw, otherRaw)
        let list = runtimeListBox(from: result)
        XCTAssertEqual(list?.elements.count, 0)
    }

    func testStringZipUsesUTF16CodeUnits() {
        let strRaw = runtimeString("a🐻")
        let otherRaw = runtimeString("XYZ")
        let result = kk_string_zip(strRaw, otherRaw)
        guard let list = runtimeListBox(from: result) else {
            XCTFail("Expected list from kk_string_zip")
            return
        }

        XCTAssertEqual(list.elements.count, 3)
        XCTAssertEqual(kk_unbox_char(kk_pair_first(list.elements[0])), 97)
        XCTAssertEqual(kk_unbox_char(kk_pair_second(list.elements[0])), Int(Unicode.Scalar("X").value))
        XCTAssertEqual(kk_unbox_char(kk_pair_first(list.elements[1])), 0xD83D)
        XCTAssertEqual(kk_unbox_char(kk_pair_second(list.elements[1])), Int(Unicode.Scalar("Y").value))
        XCTAssertEqual(kk_unbox_char(kk_pair_first(list.elements[2])), 0xDC3B)
        XCTAssertEqual(kk_unbox_char(kk_pair_second(list.elements[2])), Int(Unicode.Scalar("Z").value))
    }

    // STDLIB-TEXT-FN-116: CharSequence.zip(other, transform)
    func testStringZipTransformCombinesCharsWithLambda() {
        let strRaw = runtimeString("ab")
        let otherRaw = runtimeString("AB")
        var thrown = 0
        let result = kk_string_zipTransform(
            strRaw,
            otherRaw,
            unsafeBitCast(zipTransformSumCodepoints, to: Int.self),
            0,
            &thrown
        )
        XCTAssertEqual(thrown, 0)
        guard let list = runtimeListBox(from: result) else {
            XCTFail("Expected list from kk_string_zipTransform")
            return
        }
        XCTAssertEqual(list.elements.count, 2)
        // 'a'(97) + 'A'(65) = 162
        XCTAssertEqual(kk_unbox_char(list.elements[0]), 97 + 65)
        // 'b'(98) + 'B'(66) = 164
        XCTAssertEqual(kk_unbox_char(list.elements[1]), 98 + 66)
        XCTAssertEqual(list.values.map(\.tag), [RuntimeValue.charTag, RuntimeValue.charTag])
        XCTAssertEqual(list.values.map(\.payload0), [97 + 65, 98 + 66])
    }

    func testStringZipTransformPassesRawCharArgs() {
        let strRaw = runtimeString("ab")
        let otherRaw = runtimeString("AB")
        var thrown = 0
        let result = kk_string_zipTransform(
            strRaw,
            otherRaw,
            unsafeBitCast(zipTransformRejectBoxedCharArgs, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        guard let list = runtimeListBox(from: result) else {
            XCTFail("Expected list from kk_string_zipTransform")
            return
        }
        XCTAssertEqual(list.values.map(\.tag), [RuntimeValue.charTag, RuntimeValue.charTag])
        XCTAssertEqual(list.values.map(\.payload0), [97 + 65, 98 + 66])
    }

    func testStringZipTransformStoresAggregateStringResults() {
        let strRaw = runtimeString("ab")
        let otherRaw = runtimeString("XY")
        var thrown = 0
        let result = kk_string_zipTransform(
            strRaw,
            otherRaw,
            unsafeBitCast(zipTransformStringPairName, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        assertAggregateStringList(runtimeListBox(from: result), equals: ["a:X", "b:Y"])
    }

    func testStringZipTransformUsesUTF16CodeUnits() {
        let strRaw = runtimeString("🐻")
        let otherRaw = runtimeString("AZ")
        var thrown = -1
        let result = kk_string_zipTransform(
            strRaw,
            otherRaw,
            unsafeBitCast(zipTransformSumCodepoints, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        guard let list = runtimeListBox(from: result) else {
            XCTFail("Expected list from kk_string_zipTransform")
            return
        }
        XCTAssertEqual(list.elements.count, 2)
        XCTAssertEqual(kk_unbox_char(list.elements[0]), 0xD83D + Int(Unicode.Scalar("A").value))
        XCTAssertEqual(kk_unbox_char(list.elements[1]), 0xDC3B + Int(Unicode.Scalar("Z").value))
    }

    private func assertCharPairValue(
        _ raw: Int,
        first: Int,
        second: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let pairBox = tryCast(ptr, to: RuntimePairBox.self)
        else {
            XCTFail("Expected RuntimePairBox", file: file, line: line)
            return
        }

        XCTAssertEqual(pairBox.firstValue.tag, RuntimeValue.charTag, file: file, line: line)
        XCTAssertEqual(pairBox.firstValue.payload0, first, file: file, line: line)
        XCTAssertEqual(pairBox.secondValue.tag, RuntimeValue.charTag, file: file, line: line)
        XCTAssertEqual(pairBox.secondValue.payload0, second, file: file, line: line)
    }
}
