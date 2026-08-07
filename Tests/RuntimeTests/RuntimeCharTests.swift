#if canImport(Testing)
import Testing
@testable import Runtime

@Suite
struct RuntimeCharTests {
    @Test func charCaseConversionPreservesUnicodeMappings() {
        #expect(runtimeStringValue(kk_char_uppercase(scalarValue(of: "ß"))) == "SS")
        #expect(runtimeStringValue(kk_char_titlecase(scalarValue(of: "ǆ"))) == "ǅ")
        #expect(runtimeStringValue(kk_char_lowercase(scalarValue(of: "İ"))) == "i\u{0307}")
    }

    @Test func lowercaseCharUsesFirstScalarOfLowercaseMapping() {
        #expect(kk_char_lowercaseChar(scalarValue(of: "İ")) == scalarValue(of: "i"))
        #expect(kk_char_lowercaseChar(scalarValue(of: "A")) == scalarValue(of: "a"))
        #expect(kk_char_lowercaseChar(scalarValue(of: "5")) == scalarValue(of: "5"))
    }

    @Test func uppercaseCharUsesOneToOneUppercaseMapping() {
        #expect(kk_char_uppercaseChar(scalarValue(of: "a")) == scalarValue(of: "A"))
        #expect(kk_char_uppercaseChar(scalarValue(of: "ω")) == scalarValue(of: "Ω"))
        #expect(kk_char_uppercaseChar(scalarValue(of: "ß")) == scalarValue(of: "ß"))
        #expect(kk_char_uppercaseChar(scalarValue(of: "1")) == scalarValue(of: "1"))
    }

    @Test func titlecaseCharUsesOneToOneTitlecaseMapping() {
        #expect(kk_char_titlecaseChar(scalarValue(of: "a")) == scalarValue(of: "A"))
        #expect(kk_char_titlecaseChar(scalarValue(of: "ǆ")) == scalarValue(of: "ǅ"))
        #expect(kk_char_titlecaseChar(scalarValue(of: "ß")) == scalarValue(of: "ß"))
        #expect(kk_char_titlecaseChar(scalarValue(of: "+")) == scalarValue(of: "+"))
    }

    // MARK: - STDLIB-003-ABI-001: Char.digitToInt(radix: Int)

    @Test func digitToIntRadix_base10() {
        var thrown = 0
        #expect(kk_char_digitToInt_radix(scalarValue(of: "5"), 10, &thrown) == 5)
        #expect(thrown == 0)
    }

    @Test func digitToIntRadix_base16_lowerHex() {
        var thrown = 0
        #expect(kk_char_digitToInt_radix(scalarValue(of: "a"), 16, &thrown) == 10)
        #expect(thrown == 0)
    }

    @Test func digitToIntRadix_base16_upperHex() {
        var thrown = 0
        #expect(kk_char_digitToInt_radix(scalarValue(of: "F"), 16, &thrown) == 15)
        #expect(thrown == 0)
    }

    @Test func digitToIntRadix_base2() {
        var thrown = 0
        #expect(kk_char_digitToInt_radix(scalarValue(of: "1"), 2, &thrown) == 1)
        #expect(thrown == 0)
        #expect(kk_char_digitToInt_radix(scalarValue(of: "0"), 2, &thrown) == 0)
        #expect(thrown == 0)
    }

    @Test func digitToIntRadix_throwsForInvalidRadix() {
        var thrown = 0
        _ = kk_char_digitToInt_radix(scalarValue(of: "5"), 1, &thrown)
        #expect(thrown != 0, "radix < 2 should throw")

        thrown = 0
        _ = kk_char_digitToInt_radix(scalarValue(of: "5"), 37, &thrown)
        #expect(thrown != 0, "radix > 36 should throw")
    }

    @Test func digitToIntRadix_throwsForCharNotInRadix() {
        var thrown = 0
        _ = kk_char_digitToInt_radix(scalarValue(of: "2"), 2, &thrown)
        #expect(thrown != 0, "'2' is not a valid base-2 digit")
    }

    @Test func digitToIntRadix_base36() {
        var thrown = 0
        #expect(kk_char_digitToInt_radix(scalarValue(of: "z"), 36, &thrown) == 35)
        #expect(thrown == 0)
    }

    /// Official doc samples for Char.digitToInt(radix).
    @Test func digitToIntRadix_matchesOfficialDocSamples() {
        var thrown = 0
        #expect(kk_char_digitToInt_radix(scalarValue(of: "3"), 8, &thrown) == 3)
        #expect(thrown == 0)
        #expect(kk_char_digitToInt_radix(scalarValue(of: "A"), 16, &thrown) == 10)
        #expect(thrown == 0)
        #expect(kk_char_digitToInt_radix(scalarValue(of: "k"), 36, &thrown) == 20)
        #expect(thrown == 0)
    }

    /// Kotlin accepts Unicode decimal digits (category Nd) when their value < radix.
    /// e.g. Arabic-Indic '٥' (U+0665) and fullwidth '５' (U+FF15) both equal 5.
    @Test func digitToIntRadix_acceptsUnicodeDecimalDigits() {
        var thrown = 0
        #expect(kk_char_digitToInt_radix(0x0665, 10, &thrown) == 5) // Arabic-Indic five
        #expect(thrown == 0)
        #expect(kk_char_digitToInt_radix(0x0669, 10, &thrown) == 9) // Arabic-Indic nine
        #expect(thrown == 0)
        #expect(kk_char_digitToInt_radix(0xFF15, 10, &thrown) == 5) // fullwidth digit five
        #expect(thrown == 0)
        // Devanagari digit three '३' (U+0969) equals 3, valid in radix 8.
        #expect(kk_char_digitToInt_radix(0x0969, 8, &thrown) == 3)
        #expect(thrown == 0)
        // Devanagari digit one '१' (U+0967) equals 1.
        #expect(kk_char_digitToInt_radix(0x0967, 10, &thrown) == 1)
        #expect(thrown == 0)
    }

    /// Kotlin accepts fullwidth Latin letters as digits >= 10.
    /// e.g. fullwidth 'Ａ' (U+FF21) and 'ａ' (U+FF41) equal 10 in radix 16.
    @Test func digitToIntRadix_acceptsFullwidthLatinLetters() {
        var thrown = 0
        #expect(kk_char_digitToInt_radix(0xFF21, 16, &thrown) == 10) // fullwidth 'A'
        #expect(thrown == 0)
        #expect(kk_char_digitToInt_radix(0xFF41, 16, &thrown) == 10) // fullwidth 'a'
        #expect(thrown == 0)
        #expect(kk_char_digitToInt_radix(0xFF3A, 36, &thrown) == 35) // fullwidth 'Z'
        #expect(thrown == 0)
    }

    // MARK: - STDLIB-003-ABI-001: Char.digitToIntOrNull(radix: Int)

    @Test func digitToIntOrNullRadix_base16() {
        var thrown = 0
        #expect(kk_char_digitToIntOrNull_radix(scalarValue(of: "a"), 16, &thrown) == 10)
        #expect(thrown == 0)
    }

    @Test func digitToIntOrNullRadix_returnsNullForInvalidDigit() {
        var thrown = 0
        #expect(
            kk_char_digitToIntOrNull_radix(scalarValue(of: "g"), 16, &thrown)
                == runtimeNullSentinelInt
        )
        #expect(thrown == 0)
    }

    @Test func digitToIntOrNullRadix_throwsForInvalidRadix() {
        var thrown = 0
        _ = kk_char_digitToIntOrNull_radix(scalarValue(of: "5"), 1, &thrown)
        #expect(thrown != 0)
    }

    /// A Unicode decimal digit whose value is not below the radix must be rejected.
    @Test func digitToIntRadix_rejectsUnicodeDigitOutOfRadix() {
        var thrown = 0
        _ = kk_char_digitToInt_radix(0x0669, 8, &thrown) // Arabic-Indic nine, radix 8
        #expect(thrown != 0, "'٩' (9) is not a valid base-8 digit")
    }

    /// Non-Latin letters are never valid digits > 9 (doc note: only Latin letters).
    @Test func digitToIntRadix_rejectsNonLatinLetter() {
        var thrown = 0
        _ = kk_char_digitToInt_radix(0x03B2, 36, &thrown) // Greek small beta 'β'
        #expect(thrown != 0, "'β'.digitToInt(36) should fail per the docs")
    }

    // MARK: - STDLIB-003-ABI-002: Char.Companion.digitToChar(digit: Int, radix: Int)

    @Test func digitToCharRadix_singleDigit() {
        var thrown = 0
        let code = kk_char_digitToChar_radix(5, 10, &thrown)
        #expect(thrown == 0)
        #expect(code == Int(("5" as UnicodeScalar).value))
    }

    @Test func digitToCharRadix_hexLetter() {
        // Kotlin: 10.digitToChar(16) == 'A' (UPPERCASE per the official docs sample).
        var thrown = 0
        let code = kk_char_digitToChar_radix(10, 16, &thrown)
        #expect(thrown == 0)
        #expect(code == Int(("A" as UnicodeScalar).value))
    }

    @Test func digitToCharRadix_throwsForInvalidRadix() {
        var thrown = 0
        _ = kk_char_digitToChar_radix(0, 1, &thrown)
        #expect(thrown != 0, "radix < 2 should throw")

        thrown = 0
        _ = kk_char_digitToChar_radix(0, 37, &thrown)
        #expect(thrown != 0, "radix > 36 should throw")
    }

    @Test func digitToCharRadix_throwsForDigitOutOfRange() {
        var thrown = 0
        _ = kk_char_digitToChar_radix(-1, 10, &thrown)
        #expect(thrown != 0, "negative digit should throw")

        thrown = 0
        _ = kk_char_digitToChar_radix(10, 10, &thrown)
        #expect(thrown != 0, "digit >= radix should throw")
    }

    @Test func digitToCharRadix_base36() {
        // Kotlin: 35.digitToChar(36) == 'Z' (UPPERCASE per the official docs sample).
        var thrown = 0
        let code = kk_char_digitToChar_radix(35, 36, &thrown)
        #expect(thrown == 0)
        #expect(code == Int(("Z" as UnicodeScalar).value))
    }

    /// Documented samples from kotlin.text.digitToChar: digits >= 10 map to the
    /// UPPERCASE Latin letters, not lowercase.
    @Test func digitToCharRadix_matchesOfficialDocSamples() {
        var thrown = 0
        #expect(kk_char_digitToChar_radix(5, 10, &thrown) == Int(("5" as UnicodeScalar).value))
        #expect(thrown == 0)
        #expect(kk_char_digitToChar_radix(3, 8, &thrown) == Int(("3" as UnicodeScalar).value))
        #expect(thrown == 0)
        #expect(kk_char_digitToChar_radix(10, 16, &thrown) == Int(("A" as UnicodeScalar).value))
        #expect(thrown == 0)
        #expect(kk_char_digitToChar_radix(20, 36, &thrown) == Int(("K" as UnicodeScalar).value))
        #expect(thrown == 0)
    }

    /// Every digit value 10..35 must map to 'A'..'Z' (round-trips with digitToInt).
    @Test func digitToCharRadix_allLetterDigitsAreUppercase() {
        for digit in 10 ... 35 {
            var thrown = 0
            let code = kk_char_digitToChar_radix(digit, 36, &thrown)
            #expect(thrown == 0)
            let expected = Int(("A" as UnicodeScalar).value) + digit - 10
            #expect(code == expected, "digit \(digit) should map to '\(Character(UnicodeScalar(expected)!))'")
            #expect(code >= Int(("A" as UnicodeScalar).value) && code <= Int(("Z" as UnicodeScalar).value))
        }
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
