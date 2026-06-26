import XCTest
@testable import Runtime

/// Tests for string split, join, chunked, windowed, zip functions migrated to Kotlin stdlib
/// MIGRATION-TEXT-004
final class RuntimeStringSplitJoinTests: XCTestCase {

    private func runtimeMakeStringRaw(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: max(1, value.utf8.count)) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
            }
        }
    }

    private func runtimeStringFromRaw(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    private func runtimeMakeListRaw(_ elements: [Int]) -> Int {
        registerRuntimeObject(RuntimeListBox(elements: elements))
    }

    // MARK: - chunked tests

    func testChunkedTransformFunctionExists() {
        // Verify the function symbol exists. Cannot invoke with a real lambda at the
        // runtime level without a compiled Kotlin closure.
        let fn: (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = kk_string_chunked_sequence_transform
        XCTAssertNotNil(fn as Any)
    }

    // MARK: - windowed tests

    func testWindowedTransformFunctionExists() {
        let fn: (Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = kk_string_windowedSequence_transform
        XCTAssertNotNil(fn as Any)
    }

    // MARK: - zipWithNext tests

    func testZipWithNextEmpty() {
        let result = kk_string_zipWithNext(runtimeMakeStringRaw(""))
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 0)
    }

    func testZipWithNextSingleChar() {
        let result = kk_string_zipWithNext(runtimeMakeStringRaw("a"))
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 0)
    }

    func testZipWithNextBasic() {
        let result = kk_string_zipWithNext(runtimeMakeStringRaw("abc"))
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 2)
    }

    func testZipWithNextTransformFunctionExists() {
        let fn: (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = kk_string_zipWithNextTransform
        XCTAssertNotNil(fn as Any)
    }

    // MARK: - zip tests

    func testZipBasic() {
        let result = kk_string_zip(runtimeMakeStringRaw("abc"), runtimeMakeStringRaw("xyz"))
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 3)
    }

    func testZipLengthMismatch() {
        let result = kk_string_zip(runtimeMakeStringRaw("abc"), runtimeMakeStringRaw("xy"))
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 2) // Shorter side
    }

    func testZipTransformFunctionExists() {
        let fn: (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = kk_string_zipTransform
        XCTAssertNotNil(fn as Any)
    }

    // MARK: - joinToString tests

    func testJoinToStringBasic() {
        let elements = [runtimeMakeStringRaw("a"), runtimeMakeStringRaw("b"), runtimeMakeStringRaw("c")]
        let listRaw = runtimeMakeListRaw(elements)
        let separator = runtimeMakeStringRaw(", ")
        let prefix = runtimeMakeStringRaw("")
        let postfix = runtimeMakeStringRaw("")
        
        let result = kk_string_joinToString(listRaw, separator, prefix, postfix)
        let resultStr = runtimeStringFromRaw(result)
        XCTAssertEqual(resultStr, "a, b, c")
    }

    func testJoinToStringWithPrefixPostfix() {
        let elements = [runtimeMakeStringRaw("a"), runtimeMakeStringRaw("b")]
        let listRaw = runtimeMakeListRaw(elements)
        let separator = runtimeMakeStringRaw(", ")
        let prefix = runtimeMakeStringRaw("[")
        let postfix = runtimeMakeStringRaw("]")
        
        let result = kk_string_joinToString(listRaw, separator, prefix, postfix)
        let resultStr = runtimeStringFromRaw(result)
        XCTAssertEqual(resultStr, "[a, b]")
    }

    // MARK: - splitToSequence tests

    private func seqStrings(_ seqRaw: Int) -> [String] {
        let listRaw = kk_sequence_to_list(seqRaw, nil)
        guard let list = runtimeListBox(from: listRaw) else { return [] }
        return list.elements.map { runtimeStringFromRaw($0) }
    }

    func testSplitToSequenceBasic() {
        let result = kk_string_splitToSequence(runtimeMakeStringRaw("a,b,c"), runtimeMakeStringRaw(","))
        XCTAssertEqual(seqStrings(result), ["a", "b", "c"])
    }

    func testSplitToSequenceEmptyDelimiter() {
        let result = kk_string_splitToSequence(runtimeMakeStringRaw("abc"), runtimeMakeStringRaw(""))
        XCTAssertEqual(seqStrings(result), ["abc"])
    }

    func testSplitToSequenceEmptyString() {
        let result = kk_string_splitToSequence(runtimeMakeStringRaw(""), runtimeMakeStringRaw(","))
        XCTAssertEqual(seqStrings(result), [""])
    }

    func testSplitToSequenceNoDelimiterMatch() {
        let result = kk_string_splitToSequence(runtimeMakeStringRaw("hello"), runtimeMakeStringRaw(","))
        XCTAssertEqual(seqStrings(result), ["hello"])
    }

    func testSplitToSequenceMultiCharDelimiter() {
        let result = kk_string_splitToSequence(runtimeMakeStringRaw("one::two::three"), runtimeMakeStringRaw("::"))
        XCTAssertEqual(seqStrings(result), ["one", "two", "three"])
    }

    // MARK: - split tests (existing bridge functions)

    func testSplitBasic() {
        let result = kk_string_split(runtimeMakeStringRaw("a,b,c"), runtimeMakeStringRaw(","))
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 3)
    }

    func testSplitWithLimit() {
        let result = kk_string_split_limit(
            runtimeMakeStringRaw("a,b,c,d"),
            runtimeMakeStringRaw(","),
            0, // ignoreCase
            2  // limit
        )
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 2)
    }

    func testSplitWithIgnoreCase() {
        let result = kk_string_split_limit(
            runtimeMakeStringRaw("A,B,C"),
            runtimeMakeStringRaw(","),
            1, // ignoreCase
            0  // limit
        )
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 3)
    }
}
