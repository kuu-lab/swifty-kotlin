@testable import Runtime
import XCTest

/// STDLIB-TEXT-FN-035: Verifies `kk_string_lastIndexOfAny_chars` and
/// `kk_string_lastIndexOfAny_strings` behave consistently with Kotlin's
/// `CharSequence.lastIndexOfAny(chars/strings, startIndex, ignoreCase)`.
final class RuntimeStringLastIndexOfAnyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    private func makeStringRaw(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
                Int(bitPattern: kk_string_from_utf8(pointer, Int32(value.utf8.count)))
            }
        }
    }

    private func makeCharArrayRaw(_ chars: [Character]) -> Int {
        let array = kk_array_new(chars.count)
        var thrown = 0
        for (index, char) in chars.enumerated() {
            let boxed = kk_box_char(Int(char.unicodeScalars.first!.value))
            _ = kk_array_set(array, index, boxed, &thrown)
        }
        return array
    }

    private func makeStringListRaw(_ strings: [String]) -> Int {
        let elements = strings.map { makeStringRaw($0) }
        return registerRuntimeObject(RuntimeListBox(elements: elements))
    }

    // MARK: - lastIndexOfAny(chars)

    func testLastIndexOfAnyCharsFindsLastMatch() {
        let strRaw = makeStringRaw("abca")
        let charsRaw = makeCharArrayRaw(["a"])
        XCTAssertEqual(kk_string_lastIndexOfAny_chars(strRaw, charsRaw, 3, 0), 3)
    }

    func testLastIndexOfAnyCharsRespectsStartIndex() {
        let strRaw = makeStringRaw("abca")
        let charsRaw = makeCharArrayRaw(["a"])
        XCTAssertEqual(kk_string_lastIndexOfAny_chars(strRaw, charsRaw, 2, 0), 0)
    }

    func testLastIndexOfAnyCharsNoMatchReturnsNegativeOne() {
        let strRaw = makeStringRaw("abc")
        let charsRaw = makeCharArrayRaw(["x"])
        XCTAssertEqual(kk_string_lastIndexOfAny_chars(strRaw, charsRaw, 2, 0), -1)
    }

    func testLastIndexOfAnyCharsIgnoreCaseFindsUppercase() {
        let strRaw = makeStringRaw("abc")
        let charsRaw = makeCharArrayRaw(["C"])
        XCTAssertEqual(kk_string_lastIndexOfAny_chars(strRaw, charsRaw, 2, 1), 2)
    }

    func testLastIndexOfAnyCharsCaseSensitiveDoesNotFindUppercase() {
        let strRaw = makeStringRaw("abc")
        let charsRaw = makeCharArrayRaw(["C"])
        XCTAssertEqual(kk_string_lastIndexOfAny_chars(strRaw, charsRaw, 2, 0), -1)
    }

    func testLastIndexOfAnyCharsNegativeStartIndexReturnsNegativeOne() {
        let strRaw = makeStringRaw("abc")
        let charsRaw = makeCharArrayRaw(["a"])
        XCTAssertEqual(kk_string_lastIndexOfAny_chars(strRaw, charsRaw, -1, 0), -1)
    }

    func testLastIndexOfAnyCharsMultipleCandidates() {
        let strRaw = makeStringRaw("Kotlin")
        let charsRaw = makeCharArrayRaw(["t", "o"])
        XCTAssertEqual(kk_string_lastIndexOfAny_chars(strRaw, charsRaw, 5, 0), 2)
    }

    func testLastIndexOfAnyCharsIgnoreCaseMultipleCandidates() {
        let strRaw = makeStringRaw("Kotlin")
        let charsRaw = makeCharArrayRaw(["k"])
        XCTAssertEqual(kk_string_lastIndexOfAny_chars(strRaw, charsRaw, 5, 1), 0)
    }

    func testLastIndexOfAnyCharsEmptyStringReturnsNegativeOne() {
        let strRaw = makeStringRaw("")
        let charsRaw = makeCharArrayRaw(["a"])
        XCTAssertEqual(kk_string_lastIndexOfAny_chars(strRaw, charsRaw, 0, 0), -1)
    }

    func testLastIndexOfAnyCharsStartIndexClampedToLastChar() {
        let strRaw = makeStringRaw("abc")
        let charsRaw = makeCharArrayRaw(["c"])
        XCTAssertEqual(kk_string_lastIndexOfAny_chars(strRaw, charsRaw, 100, 0), 2)
    }

    // MARK: - lastIndexOfAny(strings)

    func testLastIndexOfAnyStringsFindsLastMatch() {
        let strRaw = makeStringRaw("abc")
        let stringsRaw = makeStringListRaw(["x", "bc"])
        XCTAssertEqual(kk_string_lastIndexOfAny_strings(strRaw, stringsRaw, 2, 0), 1)
    }

    func testLastIndexOfAnyStringsEmptyNeedleReturnsClampedStart() {
        let strRaw = makeStringRaw("abc")
        let stringsRaw = makeStringListRaw([""])
        XCTAssertEqual(kk_string_lastIndexOfAny_strings(strRaw, stringsRaw, 5, 0), 3)
    }

    func testLastIndexOfAnyStringsEmptyNeedleWithinBoundsReturnsStart() {
        let strRaw = makeStringRaw("abc")
        let stringsRaw = makeStringListRaw([""])
        XCTAssertEqual(kk_string_lastIndexOfAny_strings(strRaw, stringsRaw, 2, 0), 2)
    }

    func testLastIndexOfAnyStringsNegativeStartIndexReturnsNegativeOne() {
        let strRaw = makeStringRaw("abc")
        let stringsRaw = makeStringListRaw(["a"])
        XCTAssertEqual(kk_string_lastIndexOfAny_strings(strRaw, stringsRaw, -1, 0), -1)
    }

    func testLastIndexOfAnyStringsIgnoreCaseFindsUppercase() {
        let strRaw = makeStringRaw("abc")
        let stringsRaw = makeStringListRaw(["C"])
        XCTAssertEqual(kk_string_lastIndexOfAny_strings(strRaw, stringsRaw, 2, 1), 2)
    }

    func testLastIndexOfAnyStringsCaseSensitiveDoesNotFindUppercase() {
        let strRaw = makeStringRaw("abc")
        let stringsRaw = makeStringListRaw(["C"])
        XCTAssertEqual(kk_string_lastIndexOfAny_strings(strRaw, stringsRaw, 2, 0), -1)
    }

    func testLastIndexOfAnyStringsMultipleCandidates() {
        let strRaw = makeStringRaw("Kotlin")
        let stringsRaw = makeStringListRaw(["ot", "li"])
        XCTAssertEqual(kk_string_lastIndexOfAny_strings(strRaw, stringsRaw, 5, 0), 3)
    }

    func testLastIndexOfAnyStringsIgnoreCaseMultipleCandidates() {
        let strRaw = makeStringRaw("Kotlin")
        let stringsRaw = makeStringListRaw(["KO"])
        XCTAssertEqual(kk_string_lastIndexOfAny_strings(strRaw, stringsRaw, 5, 1), 0)
    }

    func testLastIndexOfAnyStringsNoMatchReturnsNegativeOne() {
        let strRaw = makeStringRaw("abc")
        let stringsRaw = makeStringListRaw(["x"])
        XCTAssertEqual(kk_string_lastIndexOfAny_strings(strRaw, stringsRaw, 2, 0), -1)
    }

    func testLastIndexOfAnyStringsEmptySourceReturnsNegativeOne() {
        let strRaw = makeStringRaw("")
        let stringsRaw = makeStringListRaw(["a"])
        XCTAssertEqual(kk_string_lastIndexOfAny_strings(strRaw, stringsRaw, 0, 0), -1)
    }
}
