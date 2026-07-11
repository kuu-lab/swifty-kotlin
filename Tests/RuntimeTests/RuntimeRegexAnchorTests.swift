#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeRegexAnchorTests {
    init() {
        kk_runtime_force_reset()
    }

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
            kk_regex_create_flat(data, length, byteCount, hash)
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

    private func runtimeString(_ raw: Int) -> String {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeStringBox.self) else {
            return ""
        }
        return box.value
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
    func testWordBoundaryPatternFindsWholeWordOnly() {
        let regexRaw = makeRegex("\\bcat\\b")
        let match = find(regexRaw: regexRaw, input: "a cat naps")
        let noMatch = find(regexRaw: regexRaw, input: "concatenate")

        #expect(match != runtimeNullSentinelInt)
        #expect(runtimeString(kk_match_result_value(match)) == "cat")
        #expect(noMatch == runtimeNullSentinelInt)
    }

    @Test
    func testLookaheadPatternMatchesExpectedPrefix() {
        let regexRaw = makeRegex("foo(?=bar)")
        let match = find(regexRaw: regexRaw, input: "foobar")
        let noMatch = find(regexRaw: regexRaw, input: "foobaz")

        #expect(match != runtimeNullSentinelInt)
        #expect(runtimeString(kk_match_result_value(match)) == "foo")
        #expect(noMatch == runtimeNullSentinelInt)
    }
}
#endif
