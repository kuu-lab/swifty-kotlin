@testable import Runtime
import XCTest

final class RuntimeRegexAnchorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
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

    func testAnchoredMatchEntireRequiresWholeString() {
        let regexRaw = makeRegex("^abc$")
        let full = matchEntire(regexRaw: regexRaw, input: "abc")
        let partial = matchEntire(regexRaw: regexRaw, input: "zabc")

        XCTAssertNotEqual(full, runtimeNullSentinelInt)
        XCTAssertEqual(partial, runtimeNullSentinelInt)
    }

    func testWordBoundaryPatternFindsWholeWordOnly() {
        let regexRaw = makeRegex("\\bcat\\b")
        let match = find(regexRaw: regexRaw, input: "a cat naps")
        let noMatch = find(regexRaw: regexRaw, input: "concatenate")

        XCTAssertNotEqual(match, runtimeNullSentinelInt)
        XCTAssertEqual(runtimeString(kk_match_result_value(match)), "cat")
        XCTAssertEqual(noMatch, runtimeNullSentinelInt)
    }

    func testLookaheadPatternMatchesExpectedPrefix() {
        let regexRaw = makeRegex("foo(?=bar)")
        let match = find(regexRaw: regexRaw, input: "foobar")
        let noMatch = find(regexRaw: regexRaw, input: "foobaz")

        XCTAssertNotEqual(match, runtimeNullSentinelInt)
        XCTAssertEqual(runtimeString(kk_match_result_value(match)), "foo")
        XCTAssertEqual(noMatch, runtimeNullSentinelInt)
    }
}
