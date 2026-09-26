#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeRegexAnchorTests {
    private func withFlatString<T>(
        _ value: String,
        _ body: (UnsafePointer<UInt8>?, Int, Int, Int) -> T
    ) -> T {
        Array(value.utf8).withUnsafeBufferPointer { buffer in
            body(buffer.baseAddress, value.unicodeScalars.count, value.utf8.count, 0)
        }
    }

    private func makeRegex(_ pattern: String) -> Int {
        withFlatString(pattern) { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
    }

    private func find(regexRaw: Int, input: String) -> Int {
        withFlatString(input) { data, length, byteCount, hash in
            kk_regex_find_flat(regexRaw, data, length, byteCount, hash)
        }
    }

    private func matchEntire(regexRaw: Int, input: String) -> Int {
        withFlatString(input) { data, length, byteCount, hash in
            kk_regex_matchEntire_flat(regexRaw, data, length, byteCount, hash)
        }
    }

    private func stringMatches(regexRaw: Int, input: String) -> Bool {
        withFlatString(input) { data, length, byteCount, hash in
            kk_unbox_bool(kk_string_matches_regex_flat(data, length, byteCount, hash, regexRaw)) == 1
        }
    }

    private func runtimeString(_ raw: Int) -> String {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeStringBox.self) else {
            return ""
        }
        return box.value
    }

    private func group0(_ matchRaw: Int) -> String {
        runtimeString(__kk_match_result_group_value(matchRaw, 0))
    }

    @Test
    func testAnchoredMatchEntireRequiresWholeString() {
        let regexRaw = makeRegex("^abc$")
        let full = matchEntire(regexRaw: regexRaw, input: "abc")
        let partial = matchEntire(regexRaw: regexRaw, input: "zabc")

        #expect(full != runtimeNullSentinelInt)
        #expect(partial == runtimeNullSentinelInt)
    }

    @Test
    func testEntireStringAlternativesBacktrackToWholeInput() {
        let firstShortRegex = makeRegex("a|ab")
        let secondShortRegex = makeRegex("ab|abc")

        let firstMatch = matchEntire(regexRaw: firstShortRegex, input: "ab")
        let secondMatch = matchEntire(regexRaw: secondShortRegex, input: "abc")

        #expect(firstMatch != runtimeNullSentinelInt)
        #expect(group0(firstMatch) == "ab")
        #expect(secondMatch != runtimeNullSentinelInt)
        #expect(group0(secondMatch) == "abc")
        #expect(stringMatches(regexRaw: firstShortRegex, input: "ab"))
        #expect(stringMatches(regexRaw: secondShortRegex, input: "abc"))
    }

    @Test
    func testWordBoundaryPatternFindsWholeWordOnly() {
        let regexRaw = makeRegex("\\bcat\\b")
        let match = find(regexRaw: regexRaw, input: "a cat naps")
        let noMatch = find(regexRaw: regexRaw, input: "concatenate")

        #expect(match != runtimeNullSentinelInt)
        #expect(group0(match) == "cat")
        #expect(noMatch == runtimeNullSentinelInt)
    }

    @Test
    func testLookaheadPatternMatchesExpectedPrefix() {
        let regexRaw = makeRegex("foo(?=bar)")
        let match = find(regexRaw: regexRaw, input: "foobar")
        let noMatch = find(regexRaw: regexRaw, input: "foobaz")

        #expect(match != runtimeNullSentinelInt)
        #expect(group0(match) == "foo")
        #expect(noMatch == runtimeNullSentinelInt)
    }

    @Test
    func testNextDoesNotTreatCaretAsStartOfRemainder() {
        let regexRaw = makeRegex("^.")
        let match = find(regexRaw: regexRaw, input: "ab")
        #expect(match != runtimeNullSentinelInt)
        #expect(group0(match) == "a")
        #expect(__kk_match_result_next(match) == runtimeNullSentinelInt)
    }

    @Test
    func testNextPreservesWordBoundaryAgainstOriginalInput() {
        let regexRaw = makeRegex("\\b\\w")
        let match = find(regexRaw: regexRaw, input: "ab")
        #expect(match != runtimeNullSentinelInt)
        #expect(group0(match) == "a")
        #expect(__kk_match_result_next(match) == runtimeNullSentinelInt)
    }

    @Test
    func testNextPreservesLookbehindAgainstOriginalInput() {
        let caretLookbehind = makeRegex("(?<=^).")
        let caretMatch = find(regexRaw: caretLookbehind, input: "ab")
        #expect(caretMatch != runtimeNullSentinelInt)
        #expect(group0(caretMatch) == "a")
        #expect(__kk_match_result_next(caretMatch) == runtimeNullSentinelInt)

        let crossingLookbehind = makeRegex("a|(?<=a)b")
        let first = find(regexRaw: crossingLookbehind, input: "ab")
        #expect(group0(first) == "a")
        let next = __kk_match_result_next(first)
        #expect(next != runtimeNullSentinelInt)
        #expect(group0(next) == "b")
        #expect(__kk_match_result_group_start(next, 0) == 1)
    }

    @Test
    func testNextFindsSubsequentUnanchoredMatchWithOriginalOffsets() {
        let regexRaw = makeRegex("\\d+")
        let first = find(regexRaw: regexRaw, input: "a1b22")
        #expect(group0(first) == "1")
        #expect(__kk_match_result_group_start(first, 0) == 1)

        let second = __kk_match_result_next(first)
        #expect(second != runtimeNullSentinelInt)
        #expect(group0(second) == "22")
        #expect(__kk_match_result_group_start(second, 0) == 3)
        #expect(__kk_match_result_group_end(second, 0) == 4)
        #expect(__kk_match_result_next(second) == runtimeNullSentinelInt)
    }

    @Test
    func testNextCanMatchDollarAtEndOfInput() {
        let regexRaw = makeRegex("b|$")
        let first = find(regexRaw: regexRaw, input: "ab")
        #expect(group0(first) == "b")

        let next = __kk_match_result_next(first)
        #expect(next != runtimeNullSentinelInt)
        #expect(group0(next) == "")
        #expect(__kk_match_result_group_start(next, 0) == 2)
        #expect(__kk_match_result_next(next) == runtimeNullSentinelInt)
    }

    @Test
    func testNextHonorsMultilineCaretOnOriginalInput() {
        let regexRaw = withFlatString("^.") { data, length, byteCount, hash in
            kk_regex_create_with_option_flat(data, length, byteCount, hash, kk_box_int(1), nil)
        }
        let first = find(regexRaw: regexRaw, input: "ab\ncd")
        #expect(group0(first) == "a")

        let next = __kk_match_result_next(first)
        #expect(next != runtimeNullSentinelInt)
        #expect(group0(next) == "c")
        #expect(__kk_match_result_group_start(next, 0) == 3)
        #expect(__kk_match_result_next(next) == runtimeNullSentinelInt)
    }
}
#endif
