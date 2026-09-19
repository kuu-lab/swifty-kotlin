#if canImport(Testing)
@testable import Runtime
import Testing

// KUU-634: CharArray.concatToString() must treat elements as UTF-16 code
// units — surrogate pairs recombine into supplementary scalars and isolated
// surrogates survive via the marker representation. The old scalar loop
// silently dropped every surrogate unit.
@Suite(.serialized)
struct RuntimeCharArrayConcatToStringTests {
    @Test
    func testSurrogatePairCombinesIntoSupplementaryScalar() {
        let value = concat([0xD800, 0xDC00])

        #expect(value.unicodeScalars.count == 1)
        #expect(value.unicodeScalars.first?.value == 0x10000)
        #expect(runtimeKotlinStringUTF16CodeUnits(value) == [0xD800, 0xDC00])
    }

    @Test
    func testIsolatedSurrogateSurvivesRoundTrip() {
        let value = concat([0x0041, 0xDC00, 0x0042])

        #expect(runtimeKotlinStringUTF16CodeUnits(value) == [0x0041, 0xDC00, 0x0042])
    }

    @Test
    func testBmpContentConcatenatesVerbatim() {
        #expect(concat([0x0048, 0x0065, 0x006C, 0x006C, 0x006F]) == "Hello")
        #expect(concat([]).isEmpty)
    }

    private func concat(_ units: [Int]) -> String {
        let array = kk_array_new(units.count)
        var thrown = 0
        for (index, unit) in units.enumerated() {
            _ = kk_array_set(array, index, kk_box_char(unit), &thrown)
            #expect(thrown == 0)
        }
        let raw = kk_chararray_concatToString(array)
        return extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? "<invalid>"
    }
}
#endif
