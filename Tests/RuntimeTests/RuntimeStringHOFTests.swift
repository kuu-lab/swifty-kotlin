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

private let mapNotNullBoxOnlyB: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    charRaw == Int(Unicode.Scalar("b").value) ? kk_box_char(charRaw) : runtimeNullSentinelInt
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
    // KSP-410: map/mapIndexed/mapNotNull are bundled Kotlin source
    // (StringHOF.kt); their flat runtime bridges and direct tests were
    // removed. Coverage now lives in Scripts/diff_cases/string_hof.kt /
    // string_indexed_hof.kt via diff_kotlinc.sh.

    // KSP-410: partition and filter are bundled Kotlin source (StringHOF.kt);
    // their flat runtime bridges and direct tests were removed. Coverage now
    // lives in Scripts/diff_cases/string_partition.kt / string_hof.kt via
    // diff_kotlinc.sh.

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

    // KSP-410: filterIndexed is bundled Kotlin source (StringHOF.kt); its
    // flat runtime bridge and direct tests were removed. Coverage now lives
    // in Scripts/diff_cases/string_indexed_hof.kt via diff_kotlinc.sh.

    // KSP-410: filterNot is bundled Kotlin source (StringHOF.kt); its flat
    // runtime bridge and direct tests were removed. Coverage now lives in
    // Scripts/diff_cases/string_hof.kt via diff_kotlinc.sh.

    // KSP-405: takeWhile/dropWhile are bundled Kotlin source (StringTakeDrop.kt);
    // their runtime bridges and direct tests were removed.

    // KSP-408: indexOfFirst/indexOfLast are bundled Kotlin source (StringIndexOf.kt);
    // their runtime bridges and direct tests were removed.

    // KSP-410: firstNotNullOf/firstNotNullOfOrNull are bundled Kotlin source
    // (StringHOF.kt); their flat runtime bridges and direct tests were
    // removed. Coverage now lives in Scripts/diff_cases/string_hof.kt via
    // diff_kotlinc.sh.

    // KSP-410: sumBy/sumByDouble are bundled Kotlin source (StringHOF.kt);
    // their flat runtime bridges and direct tests were removed. Coverage now
    // lives in Scripts/diff_cases/string_sumby.kt via diff_kotlinc.sh.

    // KSP-410: reduce/reduceOrNull/reduceIndexed/reduceIndexedOrNull/
    // reduceRight/reduceRightOrNull/reduceRightIndexed/
    // reduceRightIndexedOrNull are bundled Kotlin source (StringHOF.kt);
    // their flat runtime bridges and direct tests were removed. Coverage now
    // lives in Scripts/diff_cases/string_reduce.kt via diff_kotlinc.sh.

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
