#if canImport(Testing)
import Foundation
import Testing
@testable import Runtime

/// Regression tests for Kotlin/JVM edge cases in string parsing, splitting and
/// case conversion (Scripts/diff_cases/string_numeric_parse_jvm_edges.kt and
/// string_unicode_case_split_edges.kt are the end-to-end counterparts).
@Suite
struct RuntimeStringJVMEdgeCaseTests {
    private func makeString(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: max(1, value.utf8.count)) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
            }
        }
    }

    // MARK: integer parsing

    @Test func unsignedParsersRejectNegativeZero() {
        #expect(runtimeParseKotlinInteger("-0", radix: 10, as: UInt32.self) == nil)
        #expect(runtimeParseKotlinInteger("-00", radix: 10, as: UInt8.self) == nil)
        #expect(runtimeParseKotlinInteger("-0", radix: 16, as: UInt16.self) == nil)
        #expect(runtimeParseKotlinInteger("-0", radix: 10, as: UInt64.self) == nil)
        #expect(runtimeParseKotlinInteger("+7", radix: 10, as: UInt32.self) == 7)
        #expect(runtimeParseKotlinInteger("-0", radix: 10, as: Int32.self) == 0)
        #expect(runtimeParseKotlinInteger("+", radix: 10, as: Int32.self) == nil)
        #expect(runtimeParseKotlinInteger("", radix: 10, as: Int64.self) == nil)
    }

    @Test func integerParsersAcceptNonAsciiDecimalDigits() {
        #expect(runtimeParseKotlinInteger("\u{661}\u{662}\u{663}", radix: 10, as: Int32.self) == 123)
        #expect(runtimeParseKotlinInteger("\u{FF14}\u{FF12}", radix: 10, as: Int64.self) == 42)
        #expect(runtimeParseKotlinInteger("-\u{967}\u{966}", radix: 10, as: Int32.self) == -10)
        #expect(runtimeParseKotlinInteger("\u{FF21}\u{FF22}", radix: 16, as: Int32.self) == 0xAB)
        // Supplementary digits are not a Kotlin `Char`, so they are rejected.
        #expect(runtimeParseKotlinInteger("\u{1D7D9}", radix: 10, as: Int32.self) == nil)
        #expect(runtimeParseKotlinInteger("\u{E000}", radix: 10, as: Int32.self) == nil)
    }

    @Test func integerParsersDetectOverflowAtBounds() {
        #expect(runtimeParseKotlinInteger("-8000000000000000", radix: 16, as: Int64.self) == Int64.min)
        #expect(runtimeParseKotlinInteger("8000000000000000", radix: 16, as: Int64.self) == nil)
        #expect(runtimeParseKotlinInteger("7fffffffffffffff", radix: 16, as: Int64.self) == Int64.max)
        #expect(runtimeParseKotlinInteger("ffffffffffffffff", radix: 16, as: UInt64.self) == UInt64.max)
        #expect(runtimeParseKotlinInteger("10000000000000000", radix: 16, as: UInt64.self) == nil)
        #expect(runtimeParseKotlinInteger("-128", radix: 10, as: Int8.self) == -128)
        #expect(runtimeParseKotlinInteger("128", radix: 10, as: Int8.self) == nil)
    }

    @Test func toLongRadixBridges() {
        var thrown = 0
        #expect(__kk_string_toLong_radix(makeString("zz"), 36, &thrown) == 1295)
        #expect(thrown == 0)
        #expect(__kk_string_toLong_radix(makeString("-101"), 2, &thrown) == -5)
        #expect(kk_unbox_long(__kk_string_toLongOrNull_radix(makeString("ff"), 16, &thrown)) == 255)
        #expect(__kk_string_toLongOrNull_radix(makeString("12"), 2, &thrown) == runtimeNullSentinelInt)
        thrown = 0
        _ = __kk_string_toLong_radix(makeString("12"), 2, &thrown)
        #expect(thrown != 0)
        thrown = 0
        _ = __kk_string_toLong_radix(makeString("1"), 99, &thrown)
        #expect(thrown != 0)
    }

    // MARK: floating parsing

    private func doubleOrNull(_ text: String) -> Double? {
        let raw = __kk_string_toDoubleOrNull(makeString(text))
        return raw == runtimeNullSentinelInt ? nil : Double(bitPattern: UInt64(UInt(bitPattern: kk_unbox_double(raw))))
    }

    @Test func floatingParsersAcceptSignedNaNAndTrimOnlyControlAndSpace() {
        #expect(doubleOrNull("-NaN")?.isNaN == true)
        #expect(doubleOrNull("+NaN")?.isNaN == true)
        #expect(doubleOrNull(" 1.5") == 1.5)
        #expect(doubleOrNull("1.5\u{1}") == 1.5)
        #expect(doubleOrNull("\u{A0}1.5") == nil)
        #expect(doubleOrNull("1.5\u{2003}") == nil)
    }

    // MARK: split / lowercase

    @Test func splitComparesUTF16CodeUnitsNotCanonicalEquivalents() {
        #expect(runtimeSplitString("caf\u{E9}", delimiter: "\u{E9}").count == 2)
        #expect(runtimeSplitString("cafe\u{301}", delimiter: "\u{E9}") == ["cafe\u{301}"])
        #expect(runtimeSplitString("cafe\u{301}", delimiter: "e\u{301}") == ["caf", ""])
        #expect(runtimeSplitStringLimit("stra\u{DF}e", delimiter: "SS", ignoreCase: true, limit: 0).count == 1)
        #expect(runtimeSplitStringLimit("aXbxc", delimiter: "x", ignoreCase: true, limit: 0) == ["a", "b", "c"])
        #expect(runtimeSplitString("a,b,,c", delimiter: ",", limit: 2) == ["a", "b,,c"])
    }

    @Test func lowercaseAppliesFinalSigmaRule() {
        #expect(runtimeKotlinLowercased("\u{39F}\u{394}\u{39F}\u{3A3}") == "\u{3BF}\u{3B4}\u{3BF}\u{3C2}")
        #expect(runtimeKotlinLowercased("\u{3A3}") == "\u{3C3}")
        #expect(runtimeKotlinLowercased("\u{3A3}\u{39F}") == "\u{3C3}\u{3BF}")
        #expect(runtimeKotlinLowercased("\u{39F}\u{3A3} \u{39F}") == "\u{3BF}\u{3C2} \u{3BF}")
        #expect(runtimeKotlinLowercased("ABC") == "abc")
    }

    @Test func charsEqualIgnoringCaseUsesSimpleMappings() {
        #expect(runtimeCharsEqualIgnoringCase(0x130, 0x69))
        #expect(runtimeCharsEqualIgnoringCase(0x3C2, 0x3C3))
        #expect(runtimeCharsEqualIgnoringCase(0x131, 0x49))
        #expect(runtimeCharsEqualIgnoringCase(0x131, 0x69))
        #expect(!runtimeCharsEqualIgnoringCase(0x131, 0x6A))
        #expect(!runtimeCharsEqualIgnoringCase(0xD83D, 0xD83E))
    }
}
#endif
