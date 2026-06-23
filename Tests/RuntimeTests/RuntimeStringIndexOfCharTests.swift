@testable import Runtime
import XCTest

/// STDLIB-TEXT-FN-020: Verifies the dedicated Char-overload runtime entry
/// `kk_string_indexOf_char` behaves consistently with Kotlin's
/// `CharSequence.indexOf(char: Char, startIndex: Int = 0, ignoreCase: Boolean = false)`.
final class RuntimeStringIndexOfCharTests: XCTestCase {
    private func runtimeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: max(1, text.utf8.count)) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    private func charRaw(_ char: Character) -> Int {
        kk_box_char(Int(char.unicodeScalars.first!.value))
    }

    private func indexOfChar(
        _ value: String,
        _ char: Character,
        startIndex: Int,
        ignoreCase: Int
    ) -> Int {
        kk_string_indexOf_char(runtimeString(value), charRaw(char), startIndex, ignoreCase)
    }

    func testIndexOfCharBasicMatchAtStart() {
        XCTAssertEqual(indexOfChar("hello", "h", startIndex: 0, ignoreCase: 0), 0)
    }

    func testIndexOfCharMidStringMatch() {
        XCTAssertEqual(indexOfChar("hello", "l", startIndex: 0, ignoreCase: 0), 2)
    }

    func testIndexOfCharNoMatchReturnsMinusOne() {
        XCTAssertEqual(indexOfChar("hello", "z", startIndex: 0, ignoreCase: 0), -1)
    }

    func testIndexOfCharRespectsStartIndex() {
        XCTAssertEqual(indexOfChar("hello", "l", startIndex: 3, ignoreCase: 0), 3)
    }

    func testIndexOfCharIgnoreCaseMatch() {
        XCTAssertEqual(indexOfChar("Hello", "h", startIndex: 0, ignoreCase: 1), 0)
    }

    func testIndexOfCharEmptyStringReturnsMinusOne() {
        XCTAssertEqual(indexOfChar("", "a", startIndex: 0, ignoreCase: 0), -1)
    }
}
