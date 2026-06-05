@testable import Runtime
import XCTest

final class RuntimeRegexTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    private func makeRuntimeString(_ value: String) -> Int {
        let utf8 = Array(value.utf8)
        return utf8.withUnsafeBufferPointer { buffer in
            Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
        }
    }

    private func withFlatString<T>(
        _ value: String,
        _ body: (UnsafePointer<UInt8>?, Int, Int, Int) -> T
    ) -> T {
        Array(value.utf8).withUnsafeBufferPointer { buffer in
            body(buffer.baseAddress, value.unicodeScalars.count, value.utf8.count, 0)
        }
    }

    private func runtimeString(_ raw: Int) -> String {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeStringBox.self) else {
            return ""
        }
        return box.value
    }

    private func runtimeListStrings(_ raw: Int) -> [String] {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeListBox.self) else {
            return []
        }
        return box.elements.map(runtimeString)
    }

    func testMatchResultValueAndGroupValues() {
        let regexRaw = kk_regex_create(makeRuntimeString("(ab)(cd)"))
        let matchRaw = kk_regex_find(regexRaw, makeRuntimeString("zzabcdyy"))

        XCTAssertNotEqual(matchRaw, runtimeNullSentinelInt)
        XCTAssertEqual(runtimeString(kk_match_result_value(matchRaw)), "abcd")
        XCTAssertEqual(runtimeListStrings(kk_match_result_groupValues(matchRaw)), ["abcd", "ab", "cd"])
    }

    // MARK: - STDLIB-TEXT-FN-105: String.toRegex / toRegex(option) / toRegex(options)

    func testStringToRegexCreatesEquivalentRegex() {
        let patternRaw = makeRuntimeString("[a-z]+")
        let regexRaw = kk_string_toRegex(patternRaw)
        XCTAssertNotEqual(regexRaw, runtimeNullSentinelInt)
        let patternBack = runtimeString(kk_regex_pattern(regexRaw))
        XCTAssertEqual(patternBack, "[a-z]+")
    }

    func testStringToRegexMatchesSameAsRegexCreate() {
        let patternRaw = makeRuntimeString("ab+c")
        let direct = kk_regex_create(patternRaw)
        let viaToRegex = kk_string_toRegex(patternRaw)
        let input = makeRuntimeString("abbbc")
        XCTAssertEqual(
            kk_regex_find(direct, input) == runtimeNullSentinelInt,
            kk_regex_find(viaToRegex, input) == runtimeNullSentinelInt
        )
    }

    func testStringToRegexWithOptionIgnoreCase() {
        // ordinal 0 = IGNORE_CASE
        let patternRaw = makeRuntimeString("hello")
        let optionRaw = kk_box_int(0)
        let regexRaw = kk_string_toRegex_with_option(patternRaw, optionRaw)
        XCTAssertNotEqual(regexRaw, runtimeNullSentinelInt)
        let matchRaw = kk_regex_find(regexRaw, makeRuntimeString("say HELLO world"))
        XCTAssertNotEqual(matchRaw, runtimeNullSentinelInt)
        XCTAssertEqual(runtimeString(kk_match_result_value(matchRaw)), "HELLO")
    }

    func testStringToRegexWithOptionPreservesPattern() {
        // ordinal 1 = MULTILINE
        let patternRaw = makeRuntimeString("^foo")
        let optionRaw = kk_box_int(1)
        let regexRaw = kk_string_toRegex_with_option(patternRaw, optionRaw)
        XCTAssertNotEqual(regexRaw, runtimeNullSentinelInt)
        XCTAssertEqual(runtimeString(kk_regex_pattern(regexRaw)), "^foo")
    }

    func testStringToRegexWithOptionsSetIgnoreCase() {
        // Set<RegexOption> with ordinal 0 = IGNORE_CASE
        let patternRaw = makeRuntimeString("world")
        let setRaw = registerRuntimeObject(RuntimeSetBox(elements: [kk_box_int(0)]))
        let regexRaw = kk_string_toRegex_with_options(patternRaw, setRaw)
        XCTAssertNotEqual(regexRaw, runtimeNullSentinelInt)
        let matchRaw = kk_regex_find(regexRaw, makeRuntimeString("Hello WORLD!"))
        XCTAssertNotEqual(matchRaw, runtimeNullSentinelInt)
        XCTAssertEqual(runtimeString(kk_match_result_value(matchRaw)), "WORLD")
    }

    func testStringToRegexWithEmptyOptionsSet() {
        let patternRaw = makeRuntimeString("[0-9]+")
        let setRaw = registerRuntimeObject(RuntimeSetBox(elements: []))
        let regexRaw = kk_string_toRegex_with_options(patternRaw, setRaw)
        XCTAssertNotEqual(regexRaw, runtimeNullSentinelInt)
        let matchRaw = kk_regex_find(regexRaw, makeRuntimeString("abc123def"))
        XCTAssertNotEqual(matchRaw, runtimeNullSentinelInt)
        XCTAssertEqual(runtimeString(kk_match_result_value(matchRaw)), "123")
    }

    func testMatchGroupCollectionGetAndRange() {
        let regexRaw = kk_regex_create(makeRuntimeString("(?<lhs>ab)(?<rhs>cd)"))
        let matchRaw = kk_regex_find(regexRaw, makeRuntimeString("zzabcdyy"))
        let groupsRaw = kk_match_result_groups(matchRaw)
        let lhsGroupRaw = kk_match_group_collection_get(groupsRaw, makeRuntimeString("lhs"))
        let rhsGroupRaw = kk_match_group_collection_get(groupsRaw, makeRuntimeString("rhs"))

        XCTAssertNotEqual(lhsGroupRaw, runtimeNullSentinelInt)
        XCTAssertNotEqual(rhsGroupRaw, runtimeNullSentinelInt)
        XCTAssertEqual(runtimeString(kk_match_group_value(lhsGroupRaw)), "ab")
        XCTAssertEqual(runtimeString(kk_match_group_value(rhsGroupRaw)), "cd")

        let lhsRangeRaw = kk_match_group_range(lhsGroupRaw)
        let rhsRangeRaw = kk_match_group_range(rhsGroupRaw)

        guard let lhsPtr = UnsafeMutableRawPointer(bitPattern: lhsRangeRaw),
              let rhsPtr = UnsafeMutableRawPointer(bitPattern: rhsRangeRaw),
              let lhsRange = tryCast(lhsPtr, to: RuntimeRangeBox.self),
              let rhsRange = tryCast(rhsPtr, to: RuntimeRangeBox.self) else {
            return XCTFail("Expected range boxes for named groups")
        }

        XCTAssertEqual(lhsRange.first, 2)
        XCTAssertEqual(lhsRange.last, 3)
        XCTAssertEqual(rhsRange.first, 4)
        XCTAssertEqual(rhsRange.last, 5)
    }

    func testFlatStringRegexRuntimeAPIsUseFlattenedStringFields() {
        let regexRaw = withFlatString("[a-z]+") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash)
        }

        withFlatString("abc") { data, length, byteCount, hash in
            XCTAssertEqual(kk_unbox_bool(kk_string_matches_regex_flat(data, length, byteCount, hash, regexRaw)), 1)
        }
        withFlatString("abc123") { data, length, byteCount, hash in
            XCTAssertEqual(kk_unbox_bool(kk_string_matches_regex_flat(data, length, byteCount, hash, regexRaw)), 0)
        }
        withFlatString("123abc") { data, length, byteCount, hash in
            XCTAssertEqual(kk_unbox_bool(kk_string_contains_regex_flat(data, length, byteCount, hash, regexRaw)), 1)
        }

        let fromToRegex = withFlatString("\\d+") { data, length, byteCount, hash in
            kk_string_toRegex_flat(data, length, byteCount, hash)
        }
        XCTAssertEqual(runtimeString(kk_regex_pattern(fromToRegex)), "\\d+")

        let literalRegex = withFlatString("a.b") { data, length, byteCount, hash in
            kk_regex_create_with_option_flat(data, length, byteCount, hash, kk_box_int(3))
        }
        withFlatString("a.b") { data, length, byteCount, hash in
            XCTAssertEqual(kk_unbox_bool(kk_string_matches_regex_flat(data, length, byteCount, hash, literalRegex)), 1)
        }
        withFlatString("axb") { data, length, byteCount, hash in
            XCTAssertEqual(kk_unbox_bool(kk_string_matches_regex_flat(data, length, byteCount, hash, literalRegex)), 0)
        }

        let ignoreCaseOptions = registerRuntimeObject(RuntimeSetBox(elements: [kk_box_int(0)]))
        let ignoreCaseRegex = withFlatString("[a-z]+") { data, length, byteCount, hash in
            kk_regex_create_with_options_flat(data, length, byteCount, hash, ignoreCaseOptions)
        }
        withFlatString("HELLO") { data, length, byteCount, hash in
            XCTAssertEqual(kk_unbox_bool(kk_string_matches_regex_flat(data, length, byteCount, hash, ignoreCaseRegex)), 1)
        }
    }
}
