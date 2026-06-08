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

private let mapIndexedBoxIndexPlusChar: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    _, index, charRaw, _ in
    kk_box_int(index + charRaw)
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

private typealias RuntimeFlatStringHOFEntry = (
    UnsafePointer<UInt8>?,
    Int,
    Int,
    Int,
    Int,
    Int,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>?

private func withFlatStringForHOF<T>(
    _ value: String,
    _ body: (UnsafePointer<UInt8>?, Int, Int, Int) -> T
) -> T {
    var length = 0
    var byteCount = 0
    var hash = 0
    let data = runtimeRegisterFlatString(
        value,
        outLength: &length,
        outByteCount: &byteCount,
        outHash: &hash
    )
    let constData = data.map { UnsafePointer($0) }
    return body(constData, length, byteCount, hash)
}

private func withFlatStringsForHOF<T>(
    _ first: String,
    _ second: String,
    _ body: (
        UnsafePointer<UInt8>?,
        Int,
        Int,
        Int,
        UnsafePointer<UInt8>?,
        Int,
        Int,
        Int
    ) -> T
) -> T {
    withFlatStringForHOF(first) { data, length, byteCount, hash in
        withFlatStringForHOF(second) { otherData, otherLength, otherByteCount, otherHash in
            body(data, length, byteCount, hash, otherData, otherLength, otherByteCount, otherHash)
        }
    }
}

private func flatStringHOFValue(
    _ value: String,
    entry: RuntimeFlatStringHOFEntry,
    fnPtr: Int,
    closureRaw: Int = 0,
    thrown: inout Int
) -> String {
    withFlatStringForHOF(value) { data, length, byteCount, hash in
        var outLength = 0
        var outByteCount = 0
        var outHash = 0
        let outData = entry(
            data,
            length,
            byteCount,
            hash,
            fnPtr,
            closureRaw,
            &outLength,
            &outByteCount,
            &outHash,
            &thrown
        )
        _ = outLength
        _ = outHash
        guard let outData else {
            return ""
        }
        let buffer = UnsafeBufferPointer(start: UnsafePointer(outData), count: outByteCount)
        return String(decoding: buffer, as: UTF8.self)
    }
}

private func runtimeStringValueForHOF(_ raw: Int) -> String {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: raw),
          let box = tryCast(pointer, to: RuntimeStringBox.self) else {
        return ""
    }
    return box.value
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

    func testStringMapFlatReturnsMappedList() {
        withFlatStringForHOF("ab") { data, length, byteCount, hash in
            var thrown = -1
            let result = kk_string_map_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(mapBoxCharValue, to: Int.self),
                0,
                &thrown
            )

            XCTAssertEqual(thrown, 0)
            guard let list = runtimeListBox(from: result) else {
                XCTFail("Expected list from kk_string_map_flat")
                return
            }
            XCTAssertEqual(list.elements.count, 2)
            XCTAssertEqual(kk_unbox_char(list.elements[0]), Int(Unicode.Scalar("a").value))
            XCTAssertEqual(kk_unbox_char(list.elements[1]), Int(Unicode.Scalar("b").value))
        }
    }

    func testStringMapIndexedFlatReturnsMappedList() {
        withFlatStringForHOF("ab") { data, length, byteCount, hash in
            var thrown = -1
            let result = kk_string_mapIndexed_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(mapIndexedBoxIndexPlusChar, to: Int.self),
                0,
                &thrown
            )

            XCTAssertEqual(thrown, 0)
            guard let list = runtimeListBox(from: result) else {
                XCTFail("Expected list from kk_string_mapIndexed_flat")
                return
            }
            XCTAssertEqual(list.elements.count, 2)
            XCTAssertEqual(kk_unbox_int(list.elements[0]), 97)
            XCTAssertEqual(kk_unbox_int(list.elements[1]), 99)
        }
    }

    func testStringMapNotNullFlatFiltersNullResults() {
        withFlatStringForHOF("abc") { data, length, byteCount, hash in
            var thrown = -1
            let result = kk_string_mapNotNull_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(mapNotNullBoxOnlyB, to: Int.self),
                0,
                &thrown
            )

            XCTAssertEqual(thrown, 0)
            guard let list = runtimeListBox(from: result) else {
                XCTFail("Expected list from kk_string_mapNotNull_flat")
                return
            }
            XCTAssertEqual(list.elements.count, 1)
            XCTAssertEqual(kk_unbox_char(list.elements[0]), Int(Unicode.Scalar("b").value))
        }
    }

    func testStringPartitionFlatSplitsIntoPair() {
        withFlatStringForHOF("abc") { data, length, byteCount, hash in
            var thrown = -1
            let result = kk_string_partition_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(partitionMatchesB, to: Int.self),
                0,
                &thrown
            )

            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(runtimeStringValueForHOF(kk_pair_first(result)), "b")
            XCTAssertEqual(runtimeStringValueForHOF(kk_pair_second(result)), "ac")
        }
    }

    func testStringFilterFlatReturnsFlattenedStringFields() {
        var thrown = -1
        let result = flatStringHOFValue(
            "a1b2",
            entry: kk_string_filter_flat,
            fnPtr: unsafeBitCast(isDigitPredicateForIndexOfFirst, to: Int.self),
            thrown: &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, "12")
    }

    func testStringFilterIndexedFlatReturnsFlattenedStringFields() {
        var thrown = -1
        let result = flatStringHOFValue(
            "abcd",
            entry: kk_string_filterIndexed_flat,
            fnPtr: unsafeBitCast(isEvenIndexPredicate, to: Int.self),
            thrown: &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, "ac")
    }

    func testStringFilterNotFlatReturnsFlattenedStringFields() {
        var thrown = -1
        let result = flatStringHOFValue(
            "a1b2",
            entry: kk_string_filterNot_flat,
            fnPtr: unsafeBitCast(isDigitPredicateForIndexOfFirst, to: Int.self),
            thrown: &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, "ab")
    }

    func testStringTakeAndDropWhileFlatReturnFlattenedStringFields() {
        var takeThrown = -1
        let taken = flatStringHOFValue(
            "abc123",
            entry: kk_string_takeWhile_flat,
            fnPtr: unsafeBitCast(isAsciiLowercasePredicate, to: Int.self),
            thrown: &takeThrown
        )
        var dropThrown = -1
        let dropped = flatStringHOFValue(
            "abc123",
            entry: kk_string_dropWhile_flat,
            fnPtr: unsafeBitCast(isAsciiLowercasePredicate, to: Int.self),
            thrown: &dropThrown
        )

        XCTAssertEqual(takeThrown, 0)
        XCTAssertEqual(dropThrown, 0)
        XCTAssertEqual(taken, "abc")
        XCTAssertEqual(dropped, "123")
    }

    // MARK: - kk_string_indexOfFirst_flat (STDLIB-TEXT-FN-022)

    func testIndexOfFirstReturnsIndexOfFirstMatchingChar() {
        withFlatStringForHOF("hello3world") { data, length, byteCount, hash in
            var thrown = 0
            let result = kk_string_indexOfFirst_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(isDigitPredicateForIndexOfFirst, to: Int.self),
                0,
                &thrown
            )

            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(result, 5)
        }
    }

    func testIndexOfFirstReturnsMinusOneWhenNoCharMatches() {
        withFlatStringForHOF("hello") { data, length, byteCount, hash in
            var thrown = 0
            let result = kk_string_indexOfFirst_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(isDigitPredicateForIndexOfFirst, to: Int.self),
                0,
                &thrown
            )

            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(result, -1)
        }
    }

    func testIndexOfFirstOnEmptyStringReturnsMinusOne() {
        withFlatStringForHOF("") { data, length, byteCount, hash in
            var thrown = 0
            let result = kk_string_indexOfFirst_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(isDigitPredicateForIndexOfFirst, to: Int.self),
                0,
                &thrown
            )

            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(result, -1)
        }
    }

    func testIndexOfFirstReturnsZeroWhenFirstCharMatches() {
        withFlatStringForHOF("xabc") { data, length, byteCount, hash in
            var thrown = 0
            let result = kk_string_indexOfFirst_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(isLetterXPredicateForIndexOfFirst, to: Int.self),
                0,
                &thrown
            )

            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(result, 0)
        }
    }

    func testIndexOfFirstStopsAtFirstMatchNotLast() {
        withFlatStringForHOF("axbxc") { data, length, byteCount, hash in
            var thrown = 0
            let result = kk_string_indexOfFirst_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(isLetterXPredicateForIndexOfFirst, to: Int.self),
                0,
                &thrown
            )

            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(result, 1)
        }
    }

    func testFirstNotNullOfReturnsFirstNonNullResult() {
        var thrown = 0

        let result = withFlatStringForHOF("abc") { data, length, byteCount, hash in
            kk_string_firstNotNullOf_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(firstNotNullOfStringForB, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeStringValue(result), "bee")
    }

    func testFirstNotNullOfFlatReturnsFirstNonNullResult() {
        var thrown = 0

        let result = withFlatStringForHOF("abc") { data, length, byteCount, hash in
            kk_string_firstNotNullOf_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(firstNotNullOfStringForB, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeStringValue(result), "bee")
    }

    func testFirstNotNullOfSetsThrownWhenNoResultMatches() {
        var thrown = 0

        let result = withFlatStringForHOF("abc") { data, length, byteCount, hash in
            kk_string_firstNotNullOf_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(firstNotNullOfAlwaysNull, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0)
    }

    func testFirstNotNullOfFlatSetsThrownWhenNoResultMatches() {
        var thrown = 0

        let result = withFlatStringForHOF("abc") { data, length, byteCount, hash in
            kk_string_firstNotNullOf_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(firstNotNullOfAlwaysNull, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0)
    }

    func testFirstNotNullOfTreatsZeroAsNullFromNullableLambda() {
        var thrown = 0

        let result = withFlatStringForHOF("abc") { data, length, byteCount, hash in
            kk_string_firstNotNullOf_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(firstNotNullOfAlwaysZeroNull, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0)
    }

    func testTakeLastWhileUsesUTF16CodeUnits() {
        var thrown = -1
        let result = flatStringHOFValue(
            "a🐻",
            entry: kk_string_takeLastWhile_flat,
            fnPtr: unsafeBitCast(takeLastWhileSurrogateCodeUnit, to: Int.self),
            thrown: &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, "🐻")
    }

    func testFirstNotNullOfOrNullReturnsFirstNonNullResult() {
        var thrown = 0

        let result = withFlatStringForHOF("abc") { data, length, byteCount, hash in
            kk_string_firstNotNullOfOrNull_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(firstNotNullOfStringForB, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeStringValue(result), "bee")
    }

    func testFirstNotNullOfOrNullFlatReturnsFirstNonNullResult() {
        var thrown = 0

        let result = withFlatStringForHOF("abc") { data, length, byteCount, hash in
            kk_string_firstNotNullOfOrNull_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(firstNotNullOfStringForB, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeStringValue(result), "bee")
    }

    func testFirstNotNullOfOrNullReturnsNullSentinelWhenNoResultMatches() {
        var thrown = 0

        let result = withFlatStringForHOF("abc") { data, length, byteCount, hash in
            kk_string_firstNotNullOfOrNull_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(firstNotNullOfAlwaysNull, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testFirstNotNullOfOrNullFlatReturnsNullSentinelWhenNoResultMatches() {
        var thrown = 0

        let result = withFlatStringForHOF("abc") { data, length, byteCount, hash in
            kk_string_firstNotNullOfOrNull_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(firstNotNullOfAlwaysNull, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testFirstNotNullOfOrNullTreatsZeroAsNullFromNullableLambda() {
        var thrown = 0

        let result = withFlatStringForHOF("abc") { data, length, byteCount, hash in
            kk_string_firstNotNullOfOrNull_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(firstNotNullOfAlwaysZeroNull, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testReduceRightIndexedWalksRightToLeftWithIndexes() {
        var thrown = 0

        let result = withFlatStringForHOF("abc") { data, length, byteCount, hash in
            kk_string_reduceRightIndexed_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(reduceRightIndexedPickIndexOne, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Unicode.Scalar("b").value))
    }

    func testReduceRightIndexedFlatWalksRightToLeftWithIndexes() {
        var thrown = 0

        let result = withFlatStringForHOF("abc") { data, length, byteCount, hash in
            kk_string_reduceRightIndexed_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(reduceRightIndexedPickIndexOne, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Unicode.Scalar("b").value))
    }

    func testReduceRightIndexedUsesLastCharacterAsInitialAccumulator() {
        var thrown = 0

        let result = withFlatStringForHOF("abc") { data, length, byteCount, hash in
            kk_string_reduceRightIndexed_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(reduceRightIndexedIndexChecksum, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 295)
    }

    func testReduceRightIndexedSetsThrownForEmptyString() {
        var thrown = 0

        let result = withFlatStringForHOF("") { data, length, byteCount, hash in
            kk_string_reduceRightIndexed_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(reduceRightIndexedPickIndexOne, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
        XCTAssertNotEqual(thrown, 0)
    }

    func testReduceRightIndexedOrNullWalksRightToLeftWithIndexes() {
        var thrown = 0

        let result = withFlatStringForHOF("abc") { data, length, byteCount, hash in
            kk_string_reduceRightIndexedOrNull_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(reduceRightIndexedPickIndexOne, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Unicode.Scalar("b").value))
    }

    func testReduceRightIndexedOrNullReturnsNullSentinelForEmptyString() {
        var thrown = 0

        let result = withFlatStringForHOF("") { data, length, byteCount, hash in
            kk_string_reduceRightIndexedOrNull_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(reduceRightIndexedPickIndexOne, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testReduceRightIndexedOrNullFlatReturnsNullSentinelForEmptyString() {
        var thrown = 0

        let result = withFlatStringForHOF("") { data, length, byteCount, hash in
            kk_string_reduceRightIndexedOrNull_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(reduceRightIndexedPickIndexOne, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testReduceRightIndexedOrNullUsesLastCharacterAsInitialAccumulator() {
        var thrown = 0

        let result = withFlatStringForHOF("abc") { data, length, byteCount, hash in
            kk_string_reduceRightIndexedOrNull_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(reduceRightIndexedIndexChecksum, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 295)
    }

    func testReduceRightOrNullWalksRightToLeft() {
        var thrown = 0

        let result = withFlatStringForHOF("abc") { data, length, byteCount, hash in
            kk_string_reduceRightOrNull_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(reduceRightPickB, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Unicode.Scalar("b").value))
    }

    func testReduceRightOrNullFlatWalksRightToLeft() {
        var thrown = 0

        let result = withFlatStringForHOF("abc") { data, length, byteCount, hash in
            kk_string_reduceRightOrNull_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(reduceRightPickB, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Unicode.Scalar("b").value))
    }

    func testReduceRightOrNullReturnsNullSentinelForEmptyString() {
        var thrown = 0

        let result = withFlatStringForHOF("") { data, length, byteCount, hash in
            kk_string_reduceRightOrNull_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(reduceRightPickB, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testReduceRightOrNullUsesLastCharacterAsInitialAccumulator() {
        var thrown = 0

        let result = withFlatStringForHOF("abc") { data, length, byteCount, hash in
            kk_string_reduceRightOrNull_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(reduceRightChecksum, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 294)
    }

    // MARK: - STDLIB-TEXT-FN-049: kk_string_reduceOrNull_flat

    func testReduceOrNullWalksLeftToRight() {
        var thrown = 0

        let result = withFlatStringForHOF("abc") { data, length, byteCount, hash in
            kk_string_reduceOrNull_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(reduceOrNullPickB, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Unicode.Scalar("b").value))
    }

    func testReduceOrNullReturnsNullSentinelForEmptyString() {
        var thrown = 0

        let result = withFlatStringForHOF("") { data, length, byteCount, hash in
            kk_string_reduceOrNull_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(reduceOrNullPickB, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testReduceOrNullUsesFirstCharacterAsInitialAccumulator() {
        var thrown = 0

        let result = withFlatStringForHOF("abc") { data, length, byteCount, hash in
            kk_string_reduceOrNull_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(reduceOrNullChecksum, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 294)
    }

    func testReduceOrNullFlatUsesFirstCharacterAsInitialAccumulator() {
        var thrown = 0

        let result = withFlatStringForHOF("abc") { data, length, byteCount, hash in
            kk_string_reduceOrNull_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(reduceOrNullChecksum, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 294)
    }

    func testReduceOrNullReturnsSingleCharForOneCharString() {
        var thrown = 0

        let result = withFlatStringForHOF("x") { data, length, byteCount, hash in
            kk_string_reduceOrNull_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(reduceOrNullChecksum, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, Int(Unicode.Scalar("x").value))
    }

    func testReduceOrNullUsesUTF16CodeUnits() {
        var thrown = 0

        let result = withFlatStringForHOF("a🐻") { data, length, byteCount, hash in
            kk_string_reduceOrNull_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(reduceOrNullChecksum, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 97 + 0xD83D + 0xDC3B)
    }

    func testSumByAppliesSelectorToEveryCharacter() {
        var thrown = 0

        let result = withFlatStringForHOF("aba") { data, length, byteCount, hash in
            kk_string_sumBy_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(sumByWeightedA, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 21)
    }

    func testSumByFlatAppliesSelectorToEveryCharacter() {
        var thrown = 0

        let result = withFlatStringForHOF("aba") { data, length, byteCount, hash in
            kk_string_sumBy_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(sumByWeightedA, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 21)
    }

    func testSumByReturnsZeroForEmptyString() {
        var thrown = 0

        let result = withFlatStringForHOF("") { data, length, byteCount, hash in
            kk_string_sumBy_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(sumByWeightedA, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(result, 0)
    }

    func testSumByDoubleAppliesSelectorToEveryCharacter() {
        var thrown = 0

        let result = withFlatStringForHOF("aba") { data, length, byteCount, hash in
            kk_string_sumByDouble_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(sumByDoubleWeightedA, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_bits_to_double(result), 3.25, accuracy: 0.000001)
    }

    func testSumByDoubleFlatAppliesSelectorToEveryCharacter() {
        var thrown = 0

        let result = withFlatStringForHOF("aba") { data, length, byteCount, hash in
            kk_string_sumByDouble_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(sumByDoubleWeightedA, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_bits_to_double(result), 3.25, accuracy: 0.000001)
    }

    func testSumByDoubleReturnsZeroForEmptyString() {
        var thrown = 0

        let result = withFlatStringForHOF("") { data, length, byteCount, hash in
            kk_string_sumByDouble_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(sumByDoubleWeightedA, to: Int.self),
                0,
                &thrown
            )
        }

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_bits_to_double(result), 0.0, accuracy: 0.000001)
    }

    // STDLIB-316: String.zipWithNext()
    func testStringZipWithNextFlatPairsAdjacentScalars() {
        withFlatStringForHOF("ab") { data, length, byteCount, hash in
            let result = kk_string_zipWithNext_flat(data, length, byteCount, hash)
            guard let list = runtimeListBox(from: result) else {
                XCTFail("Expected list from kk_string_zipWithNext_flat")
                return
            }

            XCTAssertEqual(list.elements.count, 1)
            XCTAssertEqual(kk_unbox_char(kk_pair_first(list.elements[0])), Int(Unicode.Scalar("a").value))
            XCTAssertEqual(kk_unbox_char(kk_pair_second(list.elements[0])), Int(Unicode.Scalar("b").value))
        }
    }

    func testStringZipWithNextTransformFlatCombinesAdjacentScalars() {
        withFlatStringForHOF("ab") { data, length, byteCount, hash in
            var thrown = -1
            let result = kk_string_zipWithNextTransform_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(zipTransformSumCodepoints, to: Int.self),
                0,
                &thrown
            )

            XCTAssertEqual(thrown, 0)
            guard let list = runtimeListBox(from: result) else {
                XCTFail("Expected list from kk_string_zipWithNextTransform_flat")
                return
            }
            XCTAssertEqual(list.elements.count, 1)
            XCTAssertEqual(kk_unbox_char(list.elements[0]), 97 + 98)
        }
    }

    // STDLIB-TEXT-FN-116: CharSequence.zip(other)
    func testStringZipPairsCharsAndStopsAtShorterString() {
        withFlatStringsForHOF("abc", "XY") {
            data, length, byteCount, hash, otherData, otherLength, otherByteCount, otherHash in
            let result = kk_string_zip_flat(
                data,
                length,
                byteCount,
                hash,
                otherData,
                otherLength,
                otherByteCount,
                otherHash
            )
            guard let list = runtimeListBox(from: result) else {
                XCTFail("Expected list from kk_string_zip_flat")
                return
            }
            XCTAssertEqual(list.elements.count, 2)
            XCTAssertEqual(kk_unbox_char(kk_pair_first(list.elements[0])), Int(Unicode.Scalar("a").value))
            XCTAssertEqual(kk_unbox_char(kk_pair_second(list.elements[0])), Int(Unicode.Scalar("X").value))
            XCTAssertEqual(kk_unbox_char(kk_pair_first(list.elements[1])), Int(Unicode.Scalar("b").value))
            XCTAssertEqual(kk_unbox_char(kk_pair_second(list.elements[1])), Int(Unicode.Scalar("Y").value))
        }
    }

    func testStringZipReturnsEmptyForEmptySource() {
        withFlatStringsForHOF("", "abc") {
            data, length, byteCount, hash, otherData, otherLength, otherByteCount, otherHash in
            let result = kk_string_zip_flat(
                data,
                length,
                byteCount,
                hash,
                otherData,
                otherLength,
                otherByteCount,
                otherHash
            )
            let list = runtimeListBox(from: result)
            XCTAssertEqual(list?.elements.count, 0)
        }
    }

    func testStringZipFlatUsesUTF16CodeUnits() {
        withFlatStringsForHOF("a🐻", "XYZ") {
            data, length, byteCount, hash, otherData, otherLength, otherByteCount, otherHash in
            let result = kk_string_zip_flat(
                data,
                length,
                byteCount,
                hash,
                otherData,
                otherLength,
                otherByteCount,
                otherHash
            )
            guard let list = runtimeListBox(from: result) else {
                XCTFail("Expected list from kk_string_zip_flat")
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
    }

    // STDLIB-TEXT-FN-116: CharSequence.zip(other, transform)
    func testStringZipTransformCombinesCharsWithLambda() {
        withFlatStringsForHOF("ab", "AB") {
            data, length, byteCount, hash, otherData, otherLength, otherByteCount, otherHash in
            var thrown = 0
            let result = kk_string_zipTransform_flat(
                data,
                length,
                byteCount,
                hash,
                otherData,
                otherLength,
                otherByteCount,
                otherHash,
                unsafeBitCast(zipTransformSumCodepoints, to: Int.self),
                0,
                &thrown
            )
            XCTAssertEqual(thrown, 0)
            guard let list = runtimeListBox(from: result) else {
                XCTFail("Expected list from kk_string_zipTransform_flat")
                return
            }
            XCTAssertEqual(list.elements.count, 2)
            // 'a'(97) + 'A'(65) = 162
            XCTAssertEqual(kk_unbox_char(list.elements[0]), 97 + 65)
            // 'b'(98) + 'B'(66) = 164
            XCTAssertEqual(kk_unbox_char(list.elements[1]), 98 + 66)
        }
    }

    func testStringZipTransformFlatUsesUTF16CodeUnits() {
        withFlatStringsForHOF("🐻", "AZ") {
            data, length, byteCount, hash, otherData, otherLength, otherByteCount, otherHash in
            var thrown = -1
            let result = kk_string_zipTransform_flat(
                data,
                length,
                byteCount,
                hash,
                otherData,
                otherLength,
                otherByteCount,
                otherHash,
                unsafeBitCast(zipTransformSumCodepoints, to: Int.self),
                0,
                &thrown
            )

            XCTAssertEqual(thrown, 0)
            guard let list = runtimeListBox(from: result) else {
                XCTFail("Expected list from kk_string_zipTransform_flat")
                return
            }
            XCTAssertEqual(list.elements.count, 2)
            XCTAssertEqual(kk_unbox_char(list.elements[0]), 0xD83D + Int(Unicode.Scalar("A").value))
            XCTAssertEqual(kk_unbox_char(list.elements[1]), 0xDC3B + Int(Unicode.Scalar("Z").value))
        }
    }

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }
}
