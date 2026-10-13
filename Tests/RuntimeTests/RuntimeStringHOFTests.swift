#if canImport(Testing)
import Testing
@testable import Runtime

// Predicate: matches ASCII digit characters (0x30 .. 0x39 = '0' .. '9')

// Predicate: matches the letter 'x'
private let isLetterXPredicateForIndexOfFirst: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, charRaw, _ in
    charRaw == Int(Unicode.Scalar("x").value) ? 1 : 0
}




// STDLIB-TEXT-FN-116: zip transform — combines two chars into their sum codepoint








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
}
#endif
