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
        runtimeListElements(raw).map(runtimeString)
    }

    private func runtimeListElements(_ raw: Int) -> [Int] {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeListBox.self) else {
            return []
        }
        return box.elements
    }

    private func regexFind(_ regexRaw: Int, input: String) -> Int {
        withFlatString(input) { data, length, byteCount, hash in
            kk_regex_find_flat(regexRaw, data, length, byteCount, hash)
        }
    }

    func testMatchResultValueAndGroupValues() {
        let regexRaw = withFlatString("(ab)(cd)") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let matchRaw = withFlatString("zzabcdyy") { data, length, byteCount, hash in
            kk_regex_find_flat(regexRaw, data, length, byteCount, hash)
        }

        XCTAssertNotEqual(matchRaw, runtimeNullSentinelInt)
        XCTAssertEqual(runtimeString(kk_match_result_value(matchRaw)), "abcd")
        XCTAssertEqual(runtimeListStrings(kk_match_result_groupValues(matchRaw)), ["abcd", "ab", "cd"])
    }

    // MARK: - STDLIB-TEXT-FN-105: String.toRegex / toRegex(option) / toRegex(options)

    func testStringToRegexCreatesEquivalentRegex() {
        let regexRaw = withFlatString("[a-z]+") { data, length, byteCount, hash in
            kk_string_toRegex_flat(data, length, byteCount, hash, nil)
        }
        XCTAssertNotEqual(regexRaw, runtimeNullSentinelInt)
        let patternBack = runtimeString(kk_regex_pattern(regexRaw))
        XCTAssertEqual(patternBack, "[a-z]+")
    }

    func testStringToRegexMatchesSameAsRegexCreate() {
        let direct = withFlatString("ab+c") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let viaToRegex = withFlatString("ab+c") { data, length, byteCount, hash in
            kk_string_toRegex_flat(data, length, byteCount, hash, nil)
        }
        XCTAssertEqual(
            regexFind(direct, input: "abbbc") == runtimeNullSentinelInt,
            regexFind(viaToRegex, input: "abbbc") == runtimeNullSentinelInt
        )
    }

    func testStringToRegexWithOptionIgnoreCase() {
        // ordinal 0 = IGNORE_CASE
        let optionRaw = kk_box_int(0)
        let regexRaw = withFlatString("hello") { data, length, byteCount, hash in
            kk_regex_create_with_option_flat(data, length, byteCount, hash, optionRaw, nil)
        }
        XCTAssertNotEqual(regexRaw, runtimeNullSentinelInt)
        let matchRaw = regexFind(regexRaw, input: "say HELLO world")
        XCTAssertNotEqual(matchRaw, runtimeNullSentinelInt)
        XCTAssertEqual(runtimeString(kk_match_result_value(matchRaw)), "HELLO")
    }

    func testStringToRegexWithOptionPreservesPattern() {
        // ordinal 1 = MULTILINE
        let optionRaw = kk_box_int(1)
        let regexRaw = withFlatString("^foo") { data, length, byteCount, hash in
            kk_regex_create_with_option_flat(data, length, byteCount, hash, optionRaw, nil)
        }
        XCTAssertNotEqual(regexRaw, runtimeNullSentinelInt)
        XCTAssertEqual(runtimeString(kk_regex_pattern(regexRaw)), "^foo")
    }

    func testStringToRegexWithOptionsSetIgnoreCase() {
        // Set<RegexOption> with ordinal 0 = IGNORE_CASE
        let setRaw = registerRuntimeObject(RuntimeSetBox(elements: [kk_box_int(0)]))
        let regexRaw = withFlatString("world") { data, length, byteCount, hash in
            kk_regex_create_with_options_flat(data, length, byteCount, hash, setRaw, nil)
        }
        XCTAssertNotEqual(regexRaw, runtimeNullSentinelInt)
        let matchRaw = regexFind(regexRaw, input: "Hello WORLD!")
        XCTAssertNotEqual(matchRaw, runtimeNullSentinelInt)
        XCTAssertEqual(runtimeString(kk_match_result_value(matchRaw)), "WORLD")
    }

    func testStringToRegexWithEmptyOptionsSet() {
        let setRaw = registerRuntimeObject(RuntimeSetBox(elements: []))
        let regexRaw = withFlatString("[0-9]+") { data, length, byteCount, hash in
            kk_regex_create_with_options_flat(data, length, byteCount, hash, setRaw, nil)
        }
        XCTAssertNotEqual(regexRaw, runtimeNullSentinelInt)
        let matchRaw = regexFind(regexRaw, input: "abc123def")
        XCTAssertNotEqual(matchRaw, runtimeNullSentinelInt)
        XCTAssertEqual(runtimeString(kk_match_result_value(matchRaw)), "123")
    }

    func testMatchGroupCollectionGetAndRange() {
        let regexRaw = withFlatString("(?<lhs>ab)(?<rhs>cd)") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let matchRaw = withFlatString("zzabcdyy") { data, length, byteCount, hash in
            kk_regex_find_flat(regexRaw, data, length, byteCount, hash)
        }
        let groupsRaw = kk_match_result_groups(matchRaw)
        let lhsGroupRaw = withFlatString("lhs") { data, length, byteCount, hash in
            kk_match_group_collection_get_flat(groupsRaw, data, length, byteCount, hash)
        }
        let rhsGroupRaw = withFlatString("rhs") { data, length, byteCount, hash in
            kk_match_group_collection_get_flat(groupsRaw, data, length, byteCount, hash)
        }

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
            kk_regex_create_flat(data, length, byteCount, hash, nil)
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
            kk_string_toRegex_flat(data, length, byteCount, hash, nil)
        }
        XCTAssertEqual(runtimeString(kk_regex_pattern(fromToRegex)), "\\d+")

        let literalRegex = withFlatString("a.b") { data, length, byteCount, hash in
            kk_regex_create_with_option_flat(data, length, byteCount, hash, kk_box_int(3), nil)
        }
        withFlatString("a.b") { data, length, byteCount, hash in
            XCTAssertEqual(kk_unbox_bool(kk_string_matches_regex_flat(data, length, byteCount, hash, literalRegex)), 1)
        }
        withFlatString("axb") { data, length, byteCount, hash in
            XCTAssertEqual(kk_unbox_bool(kk_string_matches_regex_flat(data, length, byteCount, hash, literalRegex)), 0)
        }

        let ignoreCaseOptions = registerRuntimeObject(RuntimeSetBox(elements: [kk_box_int(0)]))
        let ignoreCaseRegex = withFlatString("[a-z]+") { data, length, byteCount, hash in
            kk_regex_create_with_options_flat(data, length, byteCount, hash, ignoreCaseOptions, nil)
        }
        withFlatString("HELLO") { data, length, byteCount, hash in
            XCTAssertEqual(kk_unbox_bool(kk_string_matches_regex_flat(data, length, byteCount, hash, ignoreCaseRegex)), 1)
        }
    }

    func testFlatRegexReceiverRuntimeAPIsUseFlattenedInputFields() {
        let wordRegex = withFlatString("[a-z]+") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }

        let findRaw = withFlatString("123abc456") { data, length, byteCount, hash in
            kk_regex_find_flat(wordRegex, data, length, byteCount, hash)
        }
        XCTAssertNotEqual(findRaw, runtimeNullSentinelInt)
        XCTAssertEqual(runtimeString(kk_match_result_value(findRaw)), "abc")

        let findAllRaw = withFlatString("ab12cd") { data, length, byteCount, hash in
            kk_regex_findAll_flat(wordRegex, data, length, byteCount, hash)
        }
        let findAllValues = runtimeListElements(findAllRaw).map { runtimeString(kk_match_result_value($0)) }
        XCTAssertEqual(findAllValues, ["ab", "cd"])

        let commaRegex = withFlatString(",") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let splitRaw = withFlatString("a,b,c") { data, length, byteCount, hash in
            kk_string_split_regex_flat(data, length, byteCount, hash, commaRegex)
        }
        XCTAssertEqual(runtimeListStrings(splitRaw), ["a", "b", "c"])

        let entireRaw = withFlatString("abc") { data, length, byteCount, hash in
            kk_regex_matchEntire_flat(wordRegex, data, length, byteCount, hash)
        }
        XCTAssertNotEqual(entireRaw, runtimeNullSentinelInt)
        let partialRaw = withFlatString("abc123") { data, length, byteCount, hash in
            kk_regex_matchEntire_flat(wordRegex, data, length, byteCount, hash)
        }
        XCTAssertEqual(partialRaw, runtimeNullSentinelInt)

        withFlatString("123abc") { data, length, byteCount, hash in
            XCTAssertEqual(kk_unbox_bool(kk_regex_containsMatchIn_flat(wordRegex, data, length, byteCount, hash)), 1)
        }
        withFlatString("abc") { data, length, byteCount, hash in
            XCTAssertEqual(kk_unbox_bool(kk_regex_matches_flat(wordRegex, data, length, byteCount, hash)), 1)
        }
        withFlatString("abc123") { data, length, byteCount, hash in
            XCTAssertEqual(kk_unbox_bool(kk_regex_matches_flat(wordRegex, data, length, byteCount, hash)), 0)
        }

        let literalRegex = withFlatString("a.b") { data, length, byteCount, hash in
            kk_regex_from_literal_flat(0, data, length, byteCount, hash)
        }
        withFlatString("a.b") { data, length, byteCount, hash in
            XCTAssertEqual(kk_unbox_bool(kk_regex_matches_flat(literalRegex, data, length, byteCount, hash)), 1)
        }
        withFlatString("axb") { data, length, byteCount, hash in
            XCTAssertEqual(kk_unbox_bool(kk_regex_matches_flat(literalRegex, data, length, byteCount, hash)), 0)
        }

        let namedRegex = withFlatString("(?<lhs>ab)(?<rhs>cd)") { data, length, byteCount, hash in
            kk_regex_create_flat(data, length, byteCount, hash, nil)
        }
        let namedMatch = withFlatString("zzabcdyy") { data, length, byteCount, hash in
            kk_regex_find_flat(namedRegex, data, length, byteCount, hash)
        }
        let groupsRaw = kk_match_result_groups(namedMatch)
        let lhsGroupRaw = withFlatString("lhs") { data, length, byteCount, hash in
            kk_match_group_collection_get_flat(groupsRaw, data, length, byteCount, hash)
        }
        XCTAssertNotEqual(lhsGroupRaw, runtimeNullSentinelInt)
        XCTAssertEqual(runtimeString(kk_match_group_value(lhsGroupRaw)), "ab")
    }
}
