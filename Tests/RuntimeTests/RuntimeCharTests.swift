#if canImport(Testing)
import Testing
@testable import Runtime

@Suite
struct RuntimeCharTests {
    // KSP-662: 変換ロジックは kotlin.text.CharConversions が持ち、ランタイムには
    // Unicode ケースマッピング表と digitOf テーブル参照だけが残る。

    @Test func charCaseConversionPreservesUnicodeMappings() {
        #expect(runtimeStringValue(__kk_char_uppercase_string(scalarValue(of: "ß"))) == "SS")
        #expect(runtimeStringValue(__kk_char_titlecase_string(scalarValue(of: "ǆ"))) == "ǅ")
        #expect(runtimeStringValue(__kk_char_lowercase_string(scalarValue(of: "İ"))) == "i\u{0307}")
    }

    @Test func lowercaseCodeUsesFirstScalarOfLowercaseMapping() {
        #expect(__kk_char_lowercase_code(scalarValue(of: "İ")) == scalarValue(of: "i"))
        #expect(__kk_char_lowercase_code(scalarValue(of: "A")) == scalarValue(of: "a"))
        #expect(__kk_char_lowercase_code(scalarValue(of: "5")) == scalarValue(of: "5"))
    }

    @Test func uppercaseCodeUsesOneToOneUppercaseMapping() {
        #expect(__kk_char_uppercase_code(scalarValue(of: "a")) == scalarValue(of: "A"))
        #expect(__kk_char_uppercase_code(scalarValue(of: "ω")) == scalarValue(of: "Ω"))
        // 'ß' maps to the multi-scalar "SS"; the caller keeps the original Char.
        #expect(__kk_char_uppercase_code(scalarValue(of: "ß")) == -1)
        #expect(__kk_char_uppercase_code(scalarValue(of: "1")) == scalarValue(of: "1"))
    }

    @Test func titlecaseCodeUsesOneToOneTitlecaseMapping() {
        #expect(__kk_char_titlecase_code(scalarValue(of: "a")) == scalarValue(of: "A"))
        #expect(__kk_char_titlecase_code(scalarValue(of: "ǆ")) == scalarValue(of: "ǅ"))
        #expect(__kk_char_titlecase_code(scalarValue(of: "+")) == scalarValue(of: "+"))
    }

    @Test func caseMappingBridgesRejectUnpairedSurrogates() {
        #expect(__kk_char_uppercase_code(0xD800) == -1)
        #expect(__kk_char_lowercase_code(0xD800) == -1)
        #expect(__kk_char_titlecase_code(0xD800) == -1)
    }

    // MARK: - KSP-662: __kk_char_digit_value (kotlin.text.digitOf 相当)

    @Test func digitValue_asciiDigitsAndLatinLetters() {
        #expect(__kk_char_digit_value(scalarValue(of: "5")) == 5)
        #expect(__kk_char_digit_value(scalarValue(of: "0")) == 0)
        #expect(__kk_char_digit_value(scalarValue(of: "a")) == 10)
        #expect(__kk_char_digit_value(scalarValue(of: "F")) == 15)
        #expect(__kk_char_digit_value(scalarValue(of: "z")) == 35)
    }

    @Test func digitValue_rejectsNonDigitAscii() {
        #expect(__kk_char_digit_value(scalarValue(of: "+")) == -1)
        #expect(__kk_char_digit_value(scalarValue(of: " ")) == -1)
    }

    /// Kotlin accepts Unicode decimal digits (category Nd).
    /// e.g. Arabic-Indic '٥' (U+0665) and fullwidth '５' (U+FF15) both equal 5.
    @Test func digitValue_acceptsUnicodeDecimalDigits() {
        #expect(__kk_char_digit_value(0x0665) == 5) // Arabic-Indic five
        #expect(__kk_char_digit_value(0x0669) == 9) // Arabic-Indic nine
        #expect(__kk_char_digit_value(0xFF15) == 5) // fullwidth digit five
        #expect(__kk_char_digit_value(0x0969) == 3) // Devanagari digit three
        #expect(__kk_char_digit_value(0x0967) == 1) // Devanagari digit one
    }

    /// Kotlin accepts fullwidth Latin letters as digits >= 10.
    @Test func digitValue_acceptsFullwidthLatinLetters() {
        #expect(__kk_char_digit_value(0xFF21) == 10) // fullwidth 'A'
        #expect(__kk_char_digit_value(0xFF41) == 10) // fullwidth 'a'
        #expect(__kk_char_digit_value(0xFF3A) == 35) // fullwidth 'Z'
    }

    /// Non-Latin letters are never valid digits > 9 (doc note: only Latin letters).
    @Test func digitValue_rejectsNonLatinLetter() {
        #expect(__kk_char_digit_value(0x03B2) == -1) // Greek small beta 'β'
    }

    // MARK: - STDLIB-003-ABI-003: Char(code: Int)

    @Test func charFromCode_validCode() {
        var thrown = 0
        #expect(kk_char_fromCode(65, &thrown) == 65) // 'A'
        #expect(thrown == 0)
    }

    @Test func charFromCode_zero() {
        var thrown = 0
        #expect(kk_char_fromCode(0, &thrown) == 0)
        #expect(thrown == 0)
    }

    @Test func charFromCode_maxValidCode() {
        var thrown = 0
        #expect(kk_char_fromCode(0xFFFF, &thrown) == 0xFFFF)
        #expect(thrown == 0)
    }

    @Test func charFromCode_throwsForNegativeCode() {
        var thrown = 0
        _ = kk_char_fromCode(-1, &thrown)
        #expect(thrown != 0, "negative code should throw")
    }

    @Test func charFromCode_throwsForCodeAbove0xFFFF() {
        var thrown = 0
        _ = kk_char_fromCode(0x10000, &thrown)
        #expect(thrown != 0, "code > 0xFFFF should throw")
    }

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    private func scalarValue(of character: Character) -> Int {
        Int(character.unicodeScalars.first?.value ?? 0)
    }
}
#endif
