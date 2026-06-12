// STDLIB-TEXT-PROP-017: Char.isUnicodeIdentifierPart runtime tests
// Tests that kk_char_isUnicodeIdentifierPart matches Unicode identifier-part semantics.
// Unicode identifier part includes: letters (Lu/Ll/Lt/Lm/Lo), letter numbers (Nl),
// non-spacing marks (Mn), spacing marks (Mc), enclosing marks (Me),
// decimal digits (Nd), connector punctuation (Pc), and format characters (Cf).
// Unlike isJavaIdentifierPart, currency symbols (Sc) and surrogates are NOT included.

@testable import Runtime
import XCTest

final class RuntimeCharIsUnicodeIdentifierPartTests: XCTestCase {

    private func boolValue(_ raw: Int) -> Bool {
        kk_unbox_bool(raw) != 0
    }

    private func scalar(_ ch: Character) -> Int {
        Int(ch.unicodeScalars.first?.value ?? 0)
    }

    // MARK: - Letters (Lu, Ll, Lt, Lm, Lo)

    func testAsciiLetterIsIdentifierPart() {
        XCTAssertTrue(boolValue(kk_char_isUnicodeIdentifierPart(scalar("A"))))
        XCTAssertTrue(boolValue(kk_char_isUnicodeIdentifierPart(scalar("z"))))
    }

    func testUnicodeLetterIsIdentifierPart() {
        // U+00E9 'é' - lowercase letter (Ll)
        XCTAssertTrue(boolValue(kk_char_isUnicodeIdentifierPart(0x00E9)))
        // U+4E2D '中' - CJK ideograph (Lo)
        XCTAssertTrue(boolValue(kk_char_isUnicodeIdentifierPart(0x4E2D)))
    }

    // MARK: - Decimal digits (Nd)

    func testDecimalDigitIsIdentifierPart() {
        XCTAssertTrue(boolValue(kk_char_isUnicodeIdentifierPart(scalar("0"))))
        XCTAssertTrue(boolValue(kk_char_isUnicodeIdentifierPart(scalar("9"))))
    }

    // MARK: - Letter numbers (Nl)

    func testLetterNumberIsIdentifierPart() {
        // U+2160 'Ⅰ' - Roman numeral one (Nl)
        XCTAssertTrue(boolValue(kk_char_isUnicodeIdentifierPart(0x2160)))
    }

    // MARK: - Non-spacing combining marks (Mn)

    func testNonspacingMarkIsIdentifierPart() {
        // U+0300 COMBINING GRAVE ACCENT (Mn)
        XCTAssertTrue(boolValue(kk_char_isUnicodeIdentifierPart(0x0300)))
    }

    // MARK: - Connector punctuation (Pc)

    func testUnderscoreIsIdentifierPart() {
        // '_' U+005F is connector punctuation (Pc)
        XCTAssertTrue(boolValue(kk_char_isUnicodeIdentifierPart(scalar("_"))))
    }

    // MARK: - Format characters (Cf) - identifier-ignorable but valid part

    func testFormatCharIsIdentifierPart() {
        // U+200C ZERO WIDTH NON-JOINER (Cf) - identifier-ignorable
        XCTAssertTrue(boolValue(kk_char_isUnicodeIdentifierPart(0x200C)))
    }

    // MARK: - Characters NOT in isUnicodeIdentifierPart (differ from isJavaIdentifierPart)

    func testDollarSignIsNotIdentifierPart() {
        // '$' U+0024 is currency symbol (Sc) - valid for Java but NOT Unicode
        XCTAssertFalse(boolValue(kk_char_isUnicodeIdentifierPart(scalar("$"))))
    }

    func testSurrogateIsNotIdentifierPart() {
        // Java treats surrogates as identifier parts, but Unicode standard does not
        XCTAssertFalse(boolValue(kk_char_isUnicodeIdentifierPart(0xD800)))
        XCTAssertFalse(boolValue(kk_char_isUnicodeIdentifierPart(0xDFFF)))
    }

    // MARK: - Characters that are NOT identifier parts at all

    func testSpaceIsNotIdentifierPart() {
        XCTAssertFalse(boolValue(kk_char_isUnicodeIdentifierPart(scalar(" "))))
    }

    func testPlusIsNotIdentifierPart() {
        XCTAssertFalse(boolValue(kk_char_isUnicodeIdentifierPart(scalar("+"))))
    }

    func testAtSignIsNotIdentifierPart() {
        XCTAssertFalse(boolValue(kk_char_isUnicodeIdentifierPart(scalar("@"))))
    }

    func testPeriodIsNotIdentifierPart() {
        XCTAssertFalse(boolValue(kk_char_isUnicodeIdentifierPart(scalar("."))))
    }
}
