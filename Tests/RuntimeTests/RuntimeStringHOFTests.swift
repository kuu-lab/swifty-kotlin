#if canImport(Testing)
import Testing
@testable import Runtime

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

private func assertAggregateStringList(
    _ list: RuntimeListBox?,
    equals expected: [String]
) {
    guard let list else {
        Issue.record("Expected a RuntimeListBox")
        return
    }
    #expect(list.values.map(\.tag) == Array(repeating: RuntimeValue.stringTag, count: expected.count))
    #expect(list.values.map { runtimeRenderAnyForPrint($0) } == expected)
    #expect(list.elements.map(runtimeStringValueForHOF) == expected)
}

@Suite(.serialized)
struct RuntimeStringHOFTests {
    @Test
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

            #expect(thrown == 0)
            guard let list = runtimeListBox(from: result) else {
                Issue.record("Expected list from kk_string_map_flat")
                return
            }
            #expect(list.elements.count == 2)
            #expect(kk_unbox_char(list.elements[0]) == Int(Unicode.Scalar("a").value))
            #expect(kk_unbox_char(list.elements[1]) == Int(Unicode.Scalar("b").value))
            #expect(list.values.map(\.tag) == [RuntimeValue.charTag, RuntimeValue.charTag])
            #expect(list.values.map(\.payload0) == [Int(Unicode.Scalar("a").value), Int(Unicode.Scalar("b").value)])
        }
    }

    @Test
    func testStringMapFlatStoresAggregateStringResults() {
        withFlatStringForHOF("ab") { data, length, byteCount, hash in
            var thrown = -1
            let result = kk_string_map_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(mapStringNameForChar, to: Int.self),
                0,
                &thrown
            )

            #expect(thrown == 0)
            assertAggregateStringList(runtimeListBox(from: result), equals: ["alpha", "beta"])
        }
    }

    @Test
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

            #expect(thrown == 0)
            guard let list = runtimeListBox(from: result) else {
                Issue.record("Expected list from kk_string_mapIndexed_flat")
                return
            }
            #expect(list.elements.count == 2)
            #expect(kk_unbox_int(list.elements[0]) == 97)
            #expect(kk_unbox_int(list.elements[1]) == 99)
        }
    }

    @Test
    func testStringMapIndexedFlatStoresAggregateStringResults() {
        withFlatStringForHOF("ab") { data, length, byteCount, hash in
            var thrown = -1
            let result = kk_string_mapIndexed_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(mapIndexedStringName, to: Int.self),
                0,
                &thrown
            )

            #expect(thrown == 0)
            assertAggregateStringList(runtimeListBox(from: result), equals: ["0:a", "1:b"])
        }
    }

    @Test
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

            #expect(thrown == 0)
            guard let list = runtimeListBox(from: result) else {
                Issue.record("Expected list from kk_string_mapNotNull_flat")
                return
            }
            #expect(list.elements.count == 1)
            #expect(kk_unbox_char(list.elements[0]) == Int(Unicode.Scalar("b").value))
            #expect(list.values.map(\.tag) == [RuntimeValue.charTag])
            #expect(list.values.map(\.payload0) == [Int(Unicode.Scalar("b").value)])
        }
    }

    @Test
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

            #expect(thrown == 0)
            guard let pairPtr = UnsafeMutableRawPointer(bitPattern: result),
                  let pairBox = tryCast(pairPtr, to: RuntimePairBox.self)
            else {
                Issue.record("Expected Pair from kk_string_partition_flat")
                return
            }
            #expect(pairBox.firstValue.tag == RuntimeValue.stringTag)
            #expect(pairBox.secondValue.tag == RuntimeValue.stringTag)
            #expect(runtimeRenderAnyForPrint(pairBox.firstValue) == "b")
            #expect(runtimeRenderAnyForPrint(pairBox.secondValue) == "ac")
            #expect(runtimeElementToString(result) == "(b, ac)")
            #expect(runtimeStringValueForHOF(kk_pair_first(result)) == "b")
            #expect(runtimeStringValueForHOF(kk_pair_second(result)) == "ac")
        }
    }

    @Test
    func testStringFilterFlatReturnsFlattenedStringFields() {
        var thrown = -1
        let result = flatStringHOFValue(
            "a1b2",
            entry: kk_string_filter_flat,
            fnPtr: unsafeBitCast(isDigitPredicateForIndexOfFirst, to: Int.self),
            thrown: &thrown
        )

        #expect(thrown == 0)
        #expect(result == "12")
    }

    @Test
    func testStringTrimPredicateFlatReturnsFlattenedStringFields() {
        let fnPtr = unsafeBitCast(isLetterXPredicateForIndexOfFirst, to: Int.self)

        var trimThrown = -1
        #expect(flatStringHOFValue("xxabxx", entry: kk_string_trim_predicate_flat, fnPtr: fnPtr, thrown: &trimThrown) == "ab")
        #expect(trimThrown == 0)

        var trimStartThrown = -1
        #expect(flatStringHOFValue(
                "xxabxx",
                entry: kk_string_trimStart_predicate_flat,
                fnPtr: fnPtr,
                thrown: &trimStartThrown
            ) == "abxx")
        #expect(trimStartThrown == 0)

        var trimEndThrown = -1
        #expect(flatStringHOFValue(
                "xxabxx",
                entry: kk_string_trimEnd_predicate_flat,
                fnPtr: fnPtr,
                thrown: &trimEndThrown
            ) == "xxab")
        #expect(trimEndThrown == 0)
    }

    @Test
    func testStringFilterIndexedFlatReturnsFlattenedStringFields() {
        var thrown = -1
        let result = flatStringHOFValue(
            "abcd",
            entry: kk_string_filterIndexed_flat,
            fnPtr: unsafeBitCast(isEvenIndexPredicate, to: Int.self),
            thrown: &thrown
        )

        #expect(thrown == 0)
        #expect(result == "ac")
    }

    @Test
    func testStringFilterNotFlatReturnsFlattenedStringFields() {
        var thrown = -1
        let result = flatStringHOFValue(
            "a1b2",
            entry: kk_string_filterNot_flat,
            fnPtr: unsafeBitCast(isDigitPredicateForIndexOfFirst, to: Int.self),
            thrown: &thrown
        )

        #expect(thrown == 0)
        #expect(result == "ab")
    }

    @Test
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

        #expect(takeThrown == 0)
        #expect(dropThrown == 0)
        #expect(taken == "abc")
        #expect(dropped == "123")
    }

    // MARK: - kk_string_indexOfFirst_flat (STDLIB-TEXT-FN-022)

    @Test
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

            #expect(thrown == 0)
            #expect(result == 5)
        }
    }

    @Test
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

            #expect(thrown == 0)
            #expect(result == -1)
        }
    }

    @Test
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

            #expect(thrown == 0)
            #expect(result == -1)
        }
    }

    @Test
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

            #expect(thrown == 0)
            #expect(result == 0)
        }
    }

    @Test
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

            #expect(thrown == 0)
            #expect(result == 1)
        }
    }

    @Test
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

        #expect(thrown == 0)
        #expect(runtimeStringValue(result) == "bee")
    }

    @Test
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

        #expect(thrown == 0)
        #expect(runtimeStringValue(result) == "bee")
    }

    @Test
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

        #expect(result == 0)
        #expect(thrown != 0)
    }

    @Test
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

        #expect(result == 0)
        #expect(thrown != 0)
    }

    @Test
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

        #expect(result == 0)
        #expect(thrown != 0)
    }

    @Test
    func testTakeLastWhileUsesUTF16CodeUnits() {
        var thrown = -1
        let result = flatStringHOFValue(
            "a🐻",
            entry: kk_string_takeLastWhile_flat,
            fnPtr: unsafeBitCast(takeLastWhileSurrogateCodeUnit, to: Int.self),
            thrown: &thrown
        )

        #expect(thrown == 0)
        #expect(result == "🐻")
    }

    @Test
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

        #expect(thrown == 0)
        #expect(runtimeStringValue(result) == "bee")
    }

    @Test
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

        #expect(thrown == 0)
        #expect(runtimeStringValue(result) == "bee")
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == runtimeNullSentinelInt)
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == runtimeNullSentinelInt)
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == runtimeNullSentinelInt)
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == Int(Unicode.Scalar("b").value))
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == Int(Unicode.Scalar("b").value))
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == 295)
    }

    @Test
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

        #expect(result == runtimeExceptionCaughtSentinel)
        #expect(thrown != 0)
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == Int(Unicode.Scalar("b").value))
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == runtimeNullSentinelInt)
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == runtimeNullSentinelInt)
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == 295)
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == Int(Unicode.Scalar("b").value))
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == Int(Unicode.Scalar("b").value))
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == runtimeNullSentinelInt)
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == 294)
    }

    // MARK: - STDLIB-TEXT-FN-049: kk_string_reduceOrNull_flat

    @Test
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

        #expect(thrown == 0)
        #expect(result == Int(Unicode.Scalar("b").value))
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == runtimeNullSentinelInt)
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == 294)
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == 294)
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == Int(Unicode.Scalar("x").value))
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == 97 + 0xD83D + 0xDC3B)
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == 21)
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == 21)
    }

    @Test
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

        #expect(thrown == 0)
        #expect(result == 0)
    }

    @Test
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

        #expect(thrown == 0)
        #expect(abs((kk_bits_to_double(result)) - (3.25)) <= 0.000001)
    }

    @Test
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

        #expect(thrown == 0)
        #expect(abs((kk_bits_to_double(result)) - (3.25)) <= 0.000001)
    }

    @Test
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

        #expect(thrown == 0)
        #expect(abs((kk_bits_to_double(result)) - (0.0)) <= 0.000001)
    }

    // STDLIB-316: String.zipWithNext()
    @Test
    func testStringZipWithNextFlatPairsAdjacentScalars() {
        withFlatStringForHOF("ab") { data, length, byteCount, hash in
            let result = kk_string_zipWithNext_flat(data, length, byteCount, hash)
            guard let list = runtimeListBox(from: result) else {
                Issue.record("Expected list from kk_string_zipWithNext_flat")
                return
            }

            #expect(list.elements.count == 1)
            assertCharPairValue(
                list.values[0].legacyRawValue,
                first: Int(Unicode.Scalar("a").value),
                second: Int(Unicode.Scalar("b").value)
            )
            #expect(kk_unbox_char(kk_pair_first(list.elements[0])) == Int(Unicode.Scalar("a").value))
            #expect(kk_unbox_char(kk_pair_second(list.elements[0])) == Int(Unicode.Scalar("b").value))
        }
    }

    @Test
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

            #expect(thrown == 0)
            guard let list = runtimeListBox(from: result) else {
                Issue.record("Expected list from kk_string_zipWithNextTransform_flat")
                return
            }
            #expect(list.elements.count == 1)
            #expect(kk_unbox_char(list.elements[0]) == 97 + 98)
            #expect(list.values.map(\.tag) == [RuntimeValue.charTag])
            #expect(list.values.map(\.payload0) == [97 + 98])
        }
    }

    @Test
    func testStringZipWithNextTransformPassesRawCharArgs() {
        withFlatStringForHOF("ab") { data, length, byteCount, hash in
            var thrown = -1
            let result = kk_string_zipWithNextTransform_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(zipTransformRejectBoxedCharArgs, to: Int.self),
                0,
                &thrown
            )

            #expect(thrown == 0)
            guard let list = runtimeListBox(from: result) else {
                Issue.record("Expected list from kk_string_zipWithNextTransform_flat")
                return
            }
            #expect(list.values.map(\.tag) == [RuntimeValue.charTag])
            #expect(list.values.map(\.payload0) == [97 + 98])
        }
    }

    @Test
    func testStringZipWithNextTransformFlatStoresAggregateStringResults() {
        withFlatStringForHOF("abc") { data, length, byteCount, hash in
            var thrown = -1
            let result = kk_string_zipWithNextTransform_flat(
                data,
                length,
                byteCount,
                hash,
                unsafeBitCast(zipTransformStringPairName, to: Int.self),
                0,
                &thrown
            )

            #expect(thrown == 0)
            assertAggregateStringList(runtimeListBox(from: result), equals: ["a:b", "b:c"])
        }
    }

    // STDLIB-TEXT-FN-116: CharSequence.zip(other)
    @Test
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
                Issue.record("Expected list from kk_string_zip_flat")
                return
            }
            #expect(list.elements.count == 2)
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
            #expect(kk_unbox_char(kk_pair_first(list.elements[0])) == Int(Unicode.Scalar("a").value))
            #expect(kk_unbox_char(kk_pair_second(list.elements[0])) == Int(Unicode.Scalar("X").value))
            #expect(kk_unbox_char(kk_pair_first(list.elements[1])) == Int(Unicode.Scalar("b").value))
            #expect(kk_unbox_char(kk_pair_second(list.elements[1])) == Int(Unicode.Scalar("Y").value))
        }
    }

    @Test
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
            #expect(list?.elements.count == 0)
        }
    }

    @Test
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
                Issue.record("Expected list from kk_string_zip_flat")
                return
            }

            #expect(list.elements.count == 3)
            #expect(kk_unbox_char(kk_pair_first(list.elements[0])) == 97)
            #expect(kk_unbox_char(kk_pair_second(list.elements[0])) == Int(Unicode.Scalar("X").value))
            #expect(kk_unbox_char(kk_pair_first(list.elements[1])) == 0xD83D)
            #expect(kk_unbox_char(kk_pair_second(list.elements[1])) == Int(Unicode.Scalar("Y").value))
            #expect(kk_unbox_char(kk_pair_first(list.elements[2])) == 0xDC3B)
            #expect(kk_unbox_char(kk_pair_second(list.elements[2])) == Int(Unicode.Scalar("Z").value))
        }
    }

    // STDLIB-TEXT-FN-116: CharSequence.zip(other, transform)
    @Test
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
            #expect(thrown == 0)
            guard let list = runtimeListBox(from: result) else {
                Issue.record("Expected list from kk_string_zipTransform_flat")
                return
            }
            #expect(list.elements.count == 2)
            // 'a'(97) + 'A'(65) = 162
            #expect(kk_unbox_char(list.elements[0]) == 97 + 65)
            // 'b'(98) + 'B'(66) = 164
            #expect(kk_unbox_char(list.elements[1]) == 98 + 66)
            #expect(list.values.map(\.tag) == [RuntimeValue.charTag, RuntimeValue.charTag])
            #expect(list.values.map(\.payload0) == [97 + 65, 98 + 66])
        }
    }

    @Test
    func testStringZipTransformPassesRawCharArgs() {
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
                unsafeBitCast(zipTransformRejectBoxedCharArgs, to: Int.self),
                0,
                &thrown
            )

            #expect(thrown == 0)
            guard let list = runtimeListBox(from: result) else {
                Issue.record("Expected list from kk_string_zipTransform_flat")
                return
            }
            #expect(list.values.map(\.tag) == [RuntimeValue.charTag, RuntimeValue.charTag])
            #expect(list.values.map(\.payload0) == [97 + 65, 98 + 66])
        }
    }

    @Test
    func testStringZipTransformStoresAggregateStringResults() {
        withFlatStringsForHOF("ab", "XY") {
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
                unsafeBitCast(zipTransformStringPairName, to: Int.self),
                0,
                &thrown
            )

            #expect(thrown == 0)
            assertAggregateStringList(runtimeListBox(from: result), equals: ["a:X", "b:Y"])
        }
    }

    @Test
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

            #expect(thrown == 0)
            guard let list = runtimeListBox(from: result) else {
                Issue.record("Expected list from kk_string_zipTransform_flat")
                return
            }
            #expect(list.elements.count == 2)
            #expect(kk_unbox_char(list.elements[0]) == 0xD83D + Int(Unicode.Scalar("A").value))
            #expect(kk_unbox_char(list.elements[1]) == 0xDC3B + Int(Unicode.Scalar("Z").value))
        }
    }

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    private func assertCharPairValue(
        _ raw: Int,
        first: Int,
        second: Int
    ) {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let pairBox = tryCast(ptr, to: RuntimePairBox.self)
        else {
            Issue.record("Expected RuntimePairBox")
            return
        }

        #expect(pairBox.firstValue.tag == RuntimeValue.charTag)
        #expect(pairBox.firstValue.payload0 == first)
        #expect(pairBox.secondValue.tag == RuntimeValue.charTag)
        #expect(pairBox.secondValue.payload0 == second)
    }
}
#endif
