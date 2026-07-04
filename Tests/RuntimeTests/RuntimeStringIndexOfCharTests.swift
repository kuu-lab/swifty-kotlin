@testable import Runtime
import XCTest

/// STDLIB-TEXT-FN-020: Verifies the dedicated Char-overload runtime entry
/// `kk_string_indexOf_char_flat` behaves consistently with Kotlin's
/// `CharSequence.indexOf(char: Char, startIndex: Int = 0, ignoreCase: Boolean = false)`.
final class RuntimeStringIndexOfCharTests: XCTestCase {
    private func withFlatString<T>(
        _ value: String,
        _ body: (UnsafePointer<UInt8>?, Int, Int, Int) -> T
    ) -> T {
        var length = 0
        var byteCount = 0
        var hash = 0
        let data = runtimeRegisterFlatString(
            value,
            outLength: &length,
            outByteCount: &byteCount,
            outHash: &hash
        )
        return body(data.map { UnsafePointer($0) }, length, byteCount, hash)
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
        withFlatString(value) { data, length, byteCount, hash in
            kk_string_indexOf_char_flat(
                data,
                length,
                byteCount,
                hash,
                charRaw(char),
                startIndex,
                ignoreCase
            )
        }
    }

    func testIndexOfCharBasicMatchAtStart() {
        XCTAssertEqual(indexOfChar("hello", "h", startIndex: 0, ignoreCase: 0), 0)
    }

    func testIndexOfCharBasicMatchInMiddle() {
        XCTAssertEqual(indexOfChar("hello", "l", startIndex: 0, ignoreCase: 0), 2)
    }

    func testIndexOfCharNotFoundReturnsNegativeOne() {
        XCTAssertEqual(indexOfChar("hello", "z", startIndex: 0, ignoreCase: 0), -1)
    }

    func testIndexOfCharRespectsStartIndex() {
        XCTAssertEqual(indexOfChar("hello", "l", startIndex: 3, ignoreCase: 0), 3)
    }

    func testIndexOfCharStartIndexBeyondLengthReturnsNegativeOne() {
        XCTAssertEqual(indexOfChar("hello", "l", startIndex: 10, ignoreCase: 0), -1)
    }

    func testIndexOfCharIgnoreCaseFindsUppercase() {
        XCTAssertEqual(indexOfChar("hello", "L", startIndex: 0, ignoreCase: 1), 2)
    }

    func testIndexOfCharCaseSensitiveDoesNotFindUppercase() {
        XCTAssertEqual(indexOfChar("hello", "L", startIndex: 0, ignoreCase: 0), -1)
    }

    func testIndexOfCharNegativeStartIndexIsClamped() {
        XCTAssertEqual(indexOfChar("hello", "h", startIndex: -5, ignoreCase: 0), 0)
    }

    func testIndexOfCharOnEmptyStringReturnsNegativeOne() {
        XCTAssertEqual(indexOfChar("", "a", startIndex: 0, ignoreCase: 0), -1)
    }
}
