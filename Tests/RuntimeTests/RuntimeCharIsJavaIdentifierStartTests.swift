// STDLIB-TEXT-PROP-010: Char.isJavaIdentifierStart runtime tests
// Tests that kk_char_isJavaIdentifierStart matches java.lang.Character.isJavaIdentifierStart semantics.

#if canImport(Testing)
import Testing
@testable import Runtime

@Suite
struct RuntimeCharIsJavaIdentifierStartTests {

    private func boolValue(_ raw: Int) -> Bool {
        kk_unbox_bool(raw) != 0
    }

    private func scalar(_ ch: Character) -> Int {
        Int(ch.unicodeScalars.first?.value ?? 0)
    }

    // MARK: - Letters (Lu / Ll / Lt / Lm / Lo)

    @Test
    func testUppercaseLetterIsIdentifierStart() {
        #expect(boolValue(kk_char_isJavaIdentifierStart(scalar("A"))))
        #expect(boolValue(kk_char_isJavaIdentifierStart(scalar("Z"))))
    }

    @Test
    func testLowercaseLetterIsIdentifierStart() {
        #expect(boolValue(kk_char_isJavaIdentifierStart(scalar("a"))))
        #expect(boolValue(kk_char_isJavaIdentifierStart(scalar("z"))))
    }

    @Test
    func testUnicodeLetterIsIdentifierStart() {
        // U+00E9 'é' - lowercase letter (Ll)
        #expect(boolValue(kk_char_isJavaIdentifierStart(0x00E9)))
        // U+4E2D '中' - CJK ideograph (other letter Lo)
        #expect(boolValue(kk_char_isJavaIdentifierStart(0x4E2D)))
    }

    // MARK: - Letter number (Nl category)

    @Test
    func testLetterNumberIsIdentifierStart() {
        // U+2160 'Ⅰ' - Roman numeral one (letter number Nl)
        #expect(boolValue(kk_char_isJavaIdentifierStart(0x2160)))
    }

    // MARK: - Currency symbol (Sc category)

    @Test
    func testDollarSignIsIdentifierStart() {
        // '$' is a currency symbol (Sc)
        #expect(boolValue(kk_char_isJavaIdentifierStart(scalar("$"))))
    }

    // MARK: - Connector punctuation (Pc category)

    @Test
    func testUnderscoreIsIdentifierStart() {
        // '_' is connector punctuation (Pc)
        #expect(boolValue(kk_char_isJavaIdentifierStart(scalar("_"))))
    }

    // MARK: - Characters that are NOT identifier starts

    @Test
    func testDecimalDigitIsNotIdentifierStart() {
        // digits (Nd) are valid identifier parts, but NOT starts
        #expect(!boolValue(kk_char_isJavaIdentifierStart(scalar("0"))))
        #expect(!boolValue(kk_char_isJavaIdentifierStart(scalar("9"))))
    }

    @Test
    func testSpaceIsNotIdentifierStart() {
        #expect(!boolValue(kk_char_isJavaIdentifierStart(scalar(" "))))
    }

    @Test
    func testPlusIsNotIdentifierStart() {
        #expect(!boolValue(kk_char_isJavaIdentifierStart(scalar("+"))))
    }

    @Test
    func testAtSignIsNotIdentifierStart() {
        #expect(!boolValue(kk_char_isJavaIdentifierStart(scalar("@"))))
    }

    @Test
    func testPeriodIsNotIdentifierStart() {
        #expect(!boolValue(kk_char_isJavaIdentifierStart(scalar("."))))
    }

    @Test
    func testExclamationIsNotIdentifierStart() {
        #expect(!boolValue(kk_char_isJavaIdentifierStart(scalar("!"))))
    }

    // MARK: - Combining marks (Mn/Mc/Me) — valid identifier parts, but NOT starts

    @Test
    func testCombiningMarkIsNotIdentifierStart() {
        // U+0300 COMBINING GRAVE ACCENT (non-spacing mark Mn) — NOT a start char
        #expect(!boolValue(kk_char_isJavaIdentifierStart(0x0300)))
    }

    // MARK: - Other_ID_Start characters are not Java identifier starts

    @Test
    func testOtherIdStartCharactersAreNotIdentifierStart() {
        #expect(!boolValue(kk_char_isJavaIdentifierStart(0x2118)))
        #expect(!boolValue(kk_char_isJavaIdentifierStart(0x309B)))
    }

    // MARK: - Surrogate code units — NOT identifier starts (unlike isJavaIdentifierPart)

    @Test
    func testSurrogateIsNotIdentifierStart() {
        // Surrogates are valid identifier parts in Java, but not starts
        #expect(!boolValue(kk_char_isJavaIdentifierStart(0xD800)))
        #expect(!boolValue(kk_char_isJavaIdentifierStart(0xDFFF)))
    }
}
#endif
