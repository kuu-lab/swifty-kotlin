// STDLIB-TEXT-PROP-009: Char.isJavaIdentifierPart runtime tests
// Tests that kk_char_isJavaIdentifierPart matches java.lang.Character.isJavaIdentifierPart semantics.

#if canImport(Testing)
import Testing
@testable import Runtime

@Suite
struct RuntimeCharIsJavaIdentifierPartTests {

    private func boolValue(_ raw: Int) -> Bool {
        kk_unbox_bool(raw) != 0
    }

    private func scalar(_ ch: Character) -> Int {
        Int(ch.unicodeScalars.first?.value ?? 0)
    }

    // MARK: - Letters (always valid identifier parts)

    @Test
    func testLetterIsIdentifierPart() {
        #expect(boolValue(kk_char_isJavaIdentifierPart(scalar("A"))))
        #expect(boolValue(kk_char_isJavaIdentifierPart(scalar("z"))))
    }

    @Test
    func testUnicodeLetterIsIdentifierPart() {
        // U+00E9 'é' - lowercase letter
        #expect(boolValue(kk_char_isJavaIdentifierPart(0x00E9)))
        // U+4E2D '中' - CJK ideograph (other letter)
        #expect(boolValue(kk_char_isJavaIdentifierPart(0x4E2D)))
    }

    // MARK: - Digits (valid identifier parts)

    @Test
    func testDecimalDigitIsIdentifierPart() {
        #expect(boolValue(kk_char_isJavaIdentifierPart(scalar("0"))))
        #expect(boolValue(kk_char_isJavaIdentifierPart(scalar("9"))))
    }

    // MARK: - Connector punctuation (underscore etc.)

    @Test
    func testUnderscoreIsIdentifierPart() {
        // '_' is connector punctuation (Pc)
        #expect(boolValue(kk_char_isJavaIdentifierPart(scalar("_"))))
    }

    // MARK: - Currency symbols

    @Test
    func testDollarSignIsIdentifierPart() {
        // '$' is currency symbol (Sc)
        #expect(boolValue(kk_char_isJavaIdentifierPart(scalar("$"))))
    }

    // MARK: - Characters that are NOT identifier parts

    @Test
    func testSpaceIsNotIdentifierPart() {
        #expect(!boolValue(kk_char_isJavaIdentifierPart(scalar(" "))))
    }

    @Test
    func testPlusIsNotIdentifierPart() {
        #expect(!boolValue(kk_char_isJavaIdentifierPart(scalar("+"))))
    }

    @Test
    func testAtSignIsNotIdentifierPart() {
        #expect(!boolValue(kk_char_isJavaIdentifierPart(scalar("@"))))
    }

    @Test
    func testPeriodIsNotIdentifierPart() {
        #expect(!boolValue(kk_char_isJavaIdentifierPart(scalar("."))))
    }

    // MARK: - Identifier-ignorable code points

    @Test
    func testIgnorableControlIsIdentifierPart() {
        #expect(boolValue(kk_char_isJavaIdentifierPart(0x0001)))
    }

    @Test
    func testIgnorableFormatIsIdentifierPart() {
        #expect(boolValue(kk_char_isJavaIdentifierPart(0xFEFF)))
    }

    // MARK: - Other_ID_* characters

    @Test
    func testOtherIdCharactersAreNotIdentifierPart() {
        #expect(!boolValue(kk_char_isJavaIdentifierPart(0x2118)))
        #expect(!boolValue(kk_char_isJavaIdentifierPart(0x309B)))
        #expect(!boolValue(kk_char_isJavaIdentifierPart(0x00B7)))
        #expect(!boolValue(kk_char_isJavaIdentifierPart(0x0387)))
    }

    // MARK: - Surrogate code units

    @Test
    func testSurrogateIsNotIdentifierPart() {
        // Surrogate code units are not valid Java identifier parts.
        #expect(!boolValue(kk_char_isJavaIdentifierPart(0xD800)))
        #expect(!boolValue(kk_char_isJavaIdentifierPart(0xDFFF)))
    }

    // MARK: - Letter number (Nl category)

    @Test
    func testLetterNumberIsIdentifierPart() {
        // U+2160 'Ⅰ' - Roman numeral one (letter number Nl)
        #expect(boolValue(kk_char_isJavaIdentifierPart(0x2160)))
    }

    // MARK: - Non-spacing combining marks (Mn category)

    @Test
    func testCombiningMarkIsIdentifierPart() {
        // U+0300 COMBINING GRAVE ACCENT (non-spacing mark Mn)
        #expect(boolValue(kk_char_isJavaIdentifierPart(0x0300)))
    }
}
#endif
