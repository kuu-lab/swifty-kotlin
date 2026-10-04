// STDLIB-TEXT-PROP-017: Char.isUnicodeIdentifierPart runtime tests
// Tests that kk_char_isUnicodeIdentifierPart matches Unicode identifier-part semantics.
// Unicode identifier part includes: letters (Lu/Ll/Lt/Lm/Lo), letter numbers (Nl),
// non-spacing marks (Mn), spacing marks (Mc), enclosing marks (Me),
// decimal digits (Nd), connector punctuation (Pc), format characters (Cf),
// identifier-ignorable control characters, and Unicode Other_ID_* characters.
// Unlike isJavaIdentifierPart, currency symbols (Sc) and surrogates are NOT included.

#if canImport(Testing)
import Testing
@testable import Runtime

@Suite
struct RuntimeCharIsUnicodeIdentifierPartTests {

    private func boolValue(_ raw: Int) -> Bool {
        kk_unbox_bool(raw) != 0
    }

    private func scalar(_ ch: Character) -> Int {
        Int(ch.unicodeScalars.first?.value ?? 0)
    }

    // MARK: - Letters (Lu, Ll, Lt, Lm, Lo)

    @Test
    func testAsciiLetterIsIdentifierPart() {
        #expect(boolValue(kk_char_isUnicodeIdentifierPart(scalar("A"))))
        #expect(boolValue(kk_char_isUnicodeIdentifierPart(scalar("z"))))
    }

    @Test
    func testUnicodeLetterIsIdentifierPart() {
        // U+00E9 'é' - lowercase letter (Ll)
        #expect(boolValue(kk_char_isUnicodeIdentifierPart(0x00E9)))
        // U+4E2D '中' - CJK ideograph (Lo)
        #expect(boolValue(kk_char_isUnicodeIdentifierPart(0x4E2D)))
    }

    // MARK: - Decimal digits (Nd)

    @Test
    func testDecimalDigitIsIdentifierPart() {
        #expect(boolValue(kk_char_isUnicodeIdentifierPart(scalar("0"))))
        #expect(boolValue(kk_char_isUnicodeIdentifierPart(scalar("9"))))
    }

    // MARK: - Letter numbers (Nl)

    @Test
    func testLetterNumberIsIdentifierPart() {
        // U+2160 'Ⅰ' - Roman numeral one (Nl)
        #expect(boolValue(kk_char_isUnicodeIdentifierPart(0x2160)))
    }

    // MARK: - Non-spacing combining marks (Mn)

    @Test
    func testNonspacingMarkIsIdentifierPart() {
        // U+0300 COMBINING GRAVE ACCENT (Mn)
        #expect(boolValue(kk_char_isUnicodeIdentifierPart(0x0300)))
    }

    // MARK: - Connector punctuation (Pc)

    @Test
    func testUnderscoreIsIdentifierPart() {
        // '_' U+005F is connector punctuation (Pc)
        #expect(boolValue(kk_char_isUnicodeIdentifierPart(scalar("_"))))
    }

    // MARK: - Format characters (Cf) - identifier-ignorable but valid part

    @Test
    func testFormatCharIsIdentifierPart() {
        // U+200C ZERO WIDTH NON-JOINER (Cf) - identifier-ignorable
        #expect(boolValue(kk_char_isUnicodeIdentifierPart(0x200C)))
    }

    // MARK: - Other_ID_Start / Other_ID_Continue characters

    @Test
    func testOtherIdStartCharactersAreIdentifierPart() {
        // U+2118 SCRIPT CAPITAL P (Other_ID_Start)
        #expect(boolValue(kk_char_isUnicodeIdentifierPart(0x2118)))
        // U+309B KATAKANA-HIRAGANA VOICED SOUND MARK (Other_ID_Start)
        #expect(boolValue(kk_char_isUnicodeIdentifierPart(0x309B)))
    }

    @Test
    func testOtherIdContinueCharactersAreIdentifierPart() {
        // U+00B7 MIDDLE DOT (Other_ID_Continue)
        #expect(boolValue(kk_char_isUnicodeIdentifierPart(0x00B7)))
        // U+0387 GREEK ANO TELEIA (Other_ID_Continue)
        #expect(boolValue(kk_char_isUnicodeIdentifierPart(0x0387)))
    }

    // MARK: - Ignorable control characters

    @Test
    func testIgnorableControlIsIdentifierPart() {
        #expect(boolValue(kk_char_isUnicodeIdentifierPart(0x0001)))
    }

    // MARK: - Characters NOT in isUnicodeIdentifierPart (differ from isJavaIdentifierPart)

    @Test
    func testDollarSignIsNotIdentifierPart() {
        // '$' U+0024 is currency symbol (Sc) - valid for Java but NOT Unicode
        #expect(!boolValue(kk_char_isUnicodeIdentifierPart(scalar("$"))))
    }

    @Test
    func testSurrogateIsNotIdentifierPart() {
        // Java treats surrogates as identifier parts, but Unicode standard does not
        #expect(!boolValue(kk_char_isUnicodeIdentifierPart(0xD800)))
        #expect(!boolValue(kk_char_isUnicodeIdentifierPart(0xDFFF)))
    }

    // MARK: - Characters that are NOT identifier parts at all

    @Test
    func testSpaceIsNotIdentifierPart() {
        #expect(!boolValue(kk_char_isUnicodeIdentifierPart(scalar(" "))))
    }

    @Test
    func testPlusIsNotIdentifierPart() {
        #expect(!boolValue(kk_char_isUnicodeIdentifierPart(scalar("+"))))
    }

    @Test
    func testAtSignIsNotIdentifierPart() {
        #expect(!boolValue(kk_char_isUnicodeIdentifierPart(scalar("@"))))
    }

    @Test
    func testPeriodIsNotIdentifierPart() {
        #expect(!boolValue(kk_char_isUnicodeIdentifierPart(scalar("."))))
    }
}
#endif
