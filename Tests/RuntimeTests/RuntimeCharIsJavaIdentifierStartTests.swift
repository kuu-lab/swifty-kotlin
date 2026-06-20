// STDLIB-TEXT-PROP-010: Char.isJavaIdentifierStart runtime tests
// Tests that kk_char_isJavaIdentifierStart matches java.lang.Character.isJavaIdentifierStart semantics.

@testable import Runtime
import XCTest

final class RuntimeCharIsJavaIdentifierStartTests: XCTestCase {

    private func boolValue(_ raw: Int) -> Bool {
        kk_unbox_bool(raw) != 0
    }

    private func scalar(_ ch: Character) -> Int {
        Int(ch.unicodeScalars.first?.value ?? 0)
    }

    // MARK: - Letters (Lu / Ll / Lt / Lm / Lo)

    func testUppercaseLetterIsIdentifierStart() {
        XCTAssertTrue(boolValue(kk_char_isJavaIdentifierStart(scalar("A"))))
        XCTAssertTrue(boolValue(kk_char_isJavaIdentifierStart(scalar("Z"))))
    }

    func testLowercaseLetterIsIdentifierStart() {
        XCTAssertTrue(boolValue(kk_char_isJavaIdentifierStart(scalar("a"))))
        XCTAssertTrue(boolValue(kk_char_isJavaIdentifierStart(scalar("z"))))
    }

    func testUnicodeLetterIsIdentifierStart() {
        // U+00E9 'é' - lowercase letter (Ll)
        XCTAssertTrue(boolValue(kk_char_isJavaIdentifierStart(0x00E9)))
        // U+4E2D '中' - CJK ideograph (other letter Lo)
        XCTAssertTrue(boolValue(kk_char_isJavaIdentifierStart(0x4E2D)))
    }

    // MARK: - Letter number (Nl category)

    func testLetterNumberIsIdentifierStart() {
        // U+2160 'Ⅰ' - Roman numeral one (letter number Nl)
        XCTAssertTrue(boolValue(kk_char_isJavaIdentifierStart(0x2160)))
    }

    // MARK: - Currency symbol (Sc category)

    func testDollarSignIsIdentifierStart() {
        // '$' is a currency symbol (Sc)
        XCTAssertTrue(boolValue(kk_char_isJavaIdentifierStart(scalar("$"))))
    }

    // MARK: - Connector punctuation (Pc category)

    func testUnderscoreIsIdentifierStart() {
        // '_' is connector punctuation (Pc)
        XCTAssertTrue(boolValue(kk_char_isJavaIdentifierStart(scalar("_"))))
    }

    // MARK: - Characters that are NOT identifier starts

    func testDecimalDigitIsNotIdentifierStart() {
        // digits (Nd) are valid identifier parts, but NOT starts
        XCTAssertFalse(boolValue(kk_char_isJavaIdentifierStart(scalar("0"))))
        XCTAssertFalse(boolValue(kk_char_isJavaIdentifierStart(scalar("9"))))
    }

    func testSpaceIsNotIdentifierStart() {
        XCTAssertFalse(boolValue(kk_char_isJavaIdentifierStart(scalar(" "))))
    }

    func testPlusIsNotIdentifierStart() {
        XCTAssertFalse(boolValue(kk_char_isJavaIdentifierStart(scalar("+"))))
    }

    func testAtSignIsNotIdentifierStart() {
        XCTAssertFalse(boolValue(kk_char_isJavaIdentifierStart(scalar("@"))))
    }

    func testPeriodIsNotIdentifierStart() {
        XCTAssertFalse(boolValue(kk_char_isJavaIdentifierStart(scalar("."))))
    }

    func testExclamationIsNotIdentifierStart() {
        XCTAssertFalse(boolValue(kk_char_isJavaIdentifierStart(scalar("!"))))
    }

    // MARK: - Combining marks (Mn/Mc/Me) — valid identifier parts, but NOT starts

    func testCombiningMarkIsNotIdentifierStart() {
        // U+0300 COMBINING GRAVE ACCENT (non-spacing mark Mn) — NOT a start char
        XCTAssertFalse(boolValue(kk_char_isJavaIdentifierStart(0x0300)))
    }

    // MARK: - Other_ID_Start characters are not Java identifier starts

    func testOtherIdStartCharactersAreNotIdentifierStart() {
        XCTAssertFalse(boolValue(kk_char_isJavaIdentifierStart(0x2118)))
        XCTAssertFalse(boolValue(kk_char_isJavaIdentifierStart(0x309B)))
    }

    // MARK: - Surrogate code units — NOT identifier starts (unlike isJavaIdentifierPart)

    func testSurrogateIsNotIdentifierStart() {
        // Surrogates are valid identifier parts in Java, but not starts
        XCTAssertFalse(boolValue(kk_char_isJavaIdentifierStart(0xD800)))
        XCTAssertFalse(boolValue(kk_char_isJavaIdentifierStart(0xDFFF)))
    }
}
