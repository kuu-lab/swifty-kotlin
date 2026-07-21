#if canImport(Testing)
import Testing
@testable import Runtime

/// STDLIB-TEXT-FN-035: Verifies `kk_string_lastIndexOfAny_chars` and
/// `kk_string_lastIndexOfAny_strings` behave consistently with Kotlin's
/// `CharSequence.lastIndexOfAny(chars/strings, startIndex, ignoreCase)`.
///
/// NOTE: Swift Testing suites share one process with all other suites, so this
/// suite must not call `kk_runtime_force_reset()` — it would deallocate live
/// handles owned by concurrently running suites.
@Suite
struct RuntimeStringLastIndexOfAnyTests {
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

    @Test
    func testLastIndexOfAnyCharsFindsLastMatch() {
        let strRaw = makeStringRaw("abca")
        let charsRaw = makeCharArrayRaw(["a"])
        #expect(kk_string_lastIndexOfAny_chars(strRaw, charsRaw, 3, 0) == 3)
    }

    @Test
    func testLastIndexOfAnyCharsRespectsStartIndex() {
        let strRaw = makeStringRaw("abca")
        let charsRaw = makeCharArrayRaw(["a"])
        #expect(kk_string_lastIndexOfAny_chars(strRaw, charsRaw, 2, 0) == 0)
    }

    @Test
    func testLastIndexOfAnyCharsNoMatchReturnsNegativeOne() {
        let strRaw = makeStringRaw("abc")
        let charsRaw = makeCharArrayRaw(["x"])
        #expect(kk_string_lastIndexOfAny_chars(strRaw, charsRaw, 2, 0) == -1)
    }

    @Test
    func testLastIndexOfAnyCharsIgnoreCaseFindsUppercase() {
        let strRaw = makeStringRaw("abc")
        let charsRaw = makeCharArrayRaw(["C"])
        #expect(kk_string_lastIndexOfAny_chars(strRaw, charsRaw, 2, 1) == 2)
    }

    @Test
    func testLastIndexOfAnyCharsCaseSensitiveDoesNotFindUppercase() {
        let strRaw = makeStringRaw("abc")
        let charsRaw = makeCharArrayRaw(["C"])
        #expect(kk_string_lastIndexOfAny_chars(strRaw, charsRaw, 2, 0) == -1)
    }

    @Test
    func testLastIndexOfAnyCharsNegativeStartIndexReturnsNegativeOne() {
        let strRaw = makeStringRaw("abc")
        let charsRaw = makeCharArrayRaw(["a"])
        #expect(kk_string_lastIndexOfAny_chars(strRaw, charsRaw, -1, 0) == -1)
    }

    @Test
    func testLastIndexOfAnyCharsMultipleCandidates() {
        let strRaw = makeStringRaw("Kotlin")
        let charsRaw = makeCharArrayRaw(["t", "o"])
        #expect(kk_string_lastIndexOfAny_chars(strRaw, charsRaw, 5, 0) == 2)
    }

    @Test
    func testLastIndexOfAnyCharsIgnoreCaseMultipleCandidates() {
        let strRaw = makeStringRaw("Kotlin")
        let charsRaw = makeCharArrayRaw(["k"])
        #expect(kk_string_lastIndexOfAny_chars(strRaw, charsRaw, 5, 1) == 0)
    }

    @Test
    func testLastIndexOfAnyCharsEmptyStringReturnsNegativeOne() {
        let strRaw = makeStringRaw("")
        let charsRaw = makeCharArrayRaw(["a"])
        #expect(kk_string_lastIndexOfAny_chars(strRaw, charsRaw, 0, 0) == -1)
    }

    @Test
    func testLastIndexOfAnyCharsStartIndexClampedToLastChar() {
        let strRaw = makeStringRaw("abc")
        let charsRaw = makeCharArrayRaw(["c"])
        #expect(kk_string_lastIndexOfAny_chars(strRaw, charsRaw, 100, 0) == 2)
    }

    // MARK: - lastIndexOfAny(strings)

    @Test
    func testLastIndexOfAnyStringsFindsLastMatch() {
        let strRaw = makeStringRaw("abc")
        let stringsRaw = makeStringListRaw(["x", "bc"])
        #expect(kk_string_lastIndexOfAny_strings(strRaw, stringsRaw, 2, 0) == 1)
    }

    @Test
    func testLastIndexOfAnyStringsEmptyNeedleReturnsClampedStart() {
        let strRaw = makeStringRaw("abc")
        let stringsRaw = makeStringListRaw([""])
        #expect(kk_string_lastIndexOfAny_strings(strRaw, stringsRaw, 5, 0) == 3)
    }

    @Test
    func testLastIndexOfAnyStringsEmptyNeedleWithinBoundsReturnsStart() {
        let strRaw = makeStringRaw("abc")
        let stringsRaw = makeStringListRaw([""])
        #expect(kk_string_lastIndexOfAny_strings(strRaw, stringsRaw, 2, 0) == 2)
    }

    @Test
    func testLastIndexOfAnyStringsNegativeStartIndexReturnsNegativeOne() {
        let strRaw = makeStringRaw("abc")
        let stringsRaw = makeStringListRaw(["a"])
        #expect(kk_string_lastIndexOfAny_strings(strRaw, stringsRaw, -1, 0) == -1)
    }

    @Test
    func testLastIndexOfAnyStringsIgnoreCaseFindsUppercase() {
        let strRaw = makeStringRaw("abc")
        let stringsRaw = makeStringListRaw(["C"])
        #expect(kk_string_lastIndexOfAny_strings(strRaw, stringsRaw, 2, 1) == 2)
    }

    @Test
    func testLastIndexOfAnyStringsCaseSensitiveDoesNotFindUppercase() {
        let strRaw = makeStringRaw("abc")
        let stringsRaw = makeStringListRaw(["C"])
        #expect(kk_string_lastIndexOfAny_strings(strRaw, stringsRaw, 2, 0) == -1)
    }

    @Test
    func testLastIndexOfAnyStringsMultipleCandidates() {
        let strRaw = makeStringRaw("Kotlin")
        let stringsRaw = makeStringListRaw(["ot", "li"])
        #expect(kk_string_lastIndexOfAny_strings(strRaw, stringsRaw, 5, 0) == 3)
    }

    @Test
    func testLastIndexOfAnyStringsIgnoreCaseMultipleCandidates() {
        let strRaw = makeStringRaw("Kotlin")
        let stringsRaw = makeStringListRaw(["KO"])
        #expect(kk_string_lastIndexOfAny_strings(strRaw, stringsRaw, 5, 1) == 0)
    }

    @Test
    func testLastIndexOfAnyStringsNoMatchReturnsNegativeOne() {
        let strRaw = makeStringRaw("abc")
        let stringsRaw = makeStringListRaw(["x"])
        #expect(kk_string_lastIndexOfAny_strings(strRaw, stringsRaw, 2, 0) == -1)
    }

    @Test
    func testLastIndexOfAnyStringsEmptySourceReturnsNegativeOne() {
        let strRaw = makeStringRaw("")
        let stringsRaw = makeStringListRaw(["a"])
        #expect(kk_string_lastIndexOfAny_strings(strRaw, stringsRaw, 0, 0) == -1)
    }
}
#endif
