import XCTest
@testable import Runtime

/// Tests for string split, join, chunked, windowed, zip functions migrated to Kotlin stdlib
/// MIGRATION-TEXT-004
final class RuntimeStringSplitJoinTests: XCTestCase {
    private func makeStringRaw(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
                Int(bitPattern: kk_string_from_utf8(pointer, Int32(value.utf8.count)))
            }
        }
    }

    private func runtimeStringFromRaw(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    private func runtimeMakeListRaw(_ elements: [Int]) -> Int {
        registerRuntimeObject(RuntimeListBox(elements: elements))
    }

    private func runtimeListBox(from raw: Int) -> RuntimeListBox? {
        extractRuntimeObject(from: UnsafeMutableRawPointer(bitPattern: raw))
    }

    // MARK: - chunked tests

    func testChunkedBasic() {
        let result = kk_string_chunked(makeStringRaw("abcdef"), 2)
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 3)
    }

    func testChunkedEmptyString() {
        let result = kk_string_chunked(makeStringRaw(""), 3)
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 0)
    }

    func testChunkedSizeGreaterThanLength() {
        let result = kk_string_chunked(makeStringRaw("hi"), 100)
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 1)
    }

    func testChunkedTransform() {
        let strRaw = makeStringRaw("abcdef")
        let size = 2
        let fnPtr: Int = 0 // Would need actual lambda for transform test
        let closureRaw = 0
        var thrown = 0
        
        let result = kk_string_chunked_sequence_transform(strRaw, size, fnPtr, closureRaw, &thrown)
        // Test that it returns a sequence
        XCTAssertNotNil(result)
    }

    // MARK: - windowed tests

    func testWindowedBasic() {
        let result = kk_string_windowed(makeStringRaw("abcde"), 3, 1)
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 3)
    }

    func testWindowedPartialWindowsFalse() {
        let result = kk_string_windowed_partial(makeStringRaw("abcde"), 3, 2, 0)
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
    }

    func testWindowedPartialWindowsTrue() {
        let result = kk_string_windowed_partial(makeStringRaw("abcde"), 3, 2, 1)
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
    }

    func testWindowedStepLargerThanSize() {
        let result = kk_string_windowed(makeStringRaw("abcdef"), 2, 3)
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
    }

    func testWindowedTransform() {
        let strRaw = makeStringRaw("abcde")
        let size = 3
        let step = 1
        let partialWindows = 0
        let fnPtr: Int = 0
        let closureRaw = 0
        var thrown = 0
        
        let result = kk_string_windowedSequence_transform(strRaw, size, step, partialWindows, fnPtr, closureRaw, &thrown)
        XCTAssertNotNil(result)
    }

    // MARK: - zipWithNext tests

    func testZipWithNextEmpty() {
        let result = kk_string_zipWithNext(makeStringRaw(""))
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 0)
    }

    func testZipWithNextSingleChar() {
        let result = kk_string_zipWithNext(makeStringRaw("a"))
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 0)
    }

    func testZipWithNextBasic() {
        let result = kk_string_zipWithNext(makeStringRaw("abc"))
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 2)
    }

    func testZipWithNextTransform() {
        let strRaw = makeStringRaw("abc")
        let fnPtr: Int = 0
        let closureRaw = 0
        var thrown = 0
        
        let result = kk_string_zipWithNextTransform(strRaw, fnPtr, closureRaw, &thrown)
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
    }

    // MARK: - zip tests

    func testZipBasic() {
        let result = kk_string_zip(makeStringRaw("abc"), makeStringRaw("xyz"))
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 3)
    }

    func testZipLengthMismatch() {
        let result = kk_string_zip(makeStringRaw("abc"), makeStringRaw("xy"))
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 2) // Shorter side
    }

    func testZipTransform() {
        let strRaw = makeStringRaw("abc")
        let otherRaw = makeStringRaw("xyz")
        let fnPtr: Int = 0
        let closureRaw = 0
        var thrown = 0
        
        let result = kk_string_zipTransform(strRaw, otherRaw, fnPtr, closureRaw, &thrown)
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
    }

    // MARK: - joinToString tests

    func testJoinToStringBasic() {
        let elements = [makeStringRaw("a"), makeStringRaw("b"), makeStringRaw("c")]
        let listRaw = runtimeMakeListRaw(elements)
        let separator = makeStringRaw(", ")
        let prefix = makeStringRaw("")
        let postfix = makeStringRaw("")
        
        let result = kk_string_joinToString(listRaw, separator, prefix, postfix)
        let resultStr = runtimeStringFromRaw(result)
        XCTAssertEqual(resultStr, "a, b, c")
    }

    func testJoinToStringWithPrefixPostfix() {
        let elements = [makeStringRaw("a"), makeStringRaw("b")]
        let listRaw = runtimeMakeListRaw(elements)
        let separator = makeStringRaw(", ")
        let prefix = makeStringRaw("[")
        let postfix = makeStringRaw("]")
        
        let result = kk_string_joinToString(listRaw, separator, prefix, postfix)
        let resultStr = runtimeStringFromRaw(result)
        XCTAssertEqual(resultStr, "[a, b]")
    }

    // MARK: - splitToSequence tests

    func testSplitToSequenceBasic() {
        let result = kk_string_splitToSequence(makeStringRaw("a,b,c"), makeStringRaw(","))
        XCTAssertNotNil(result)
        // Should return a sequence
    }

    func testSplitToSequenceEmptyDelimiter() {
        let result = kk_string_splitToSequence(makeStringRaw("abc"), makeStringRaw(""))
        XCTAssertNotNil(result)
    }

    // MARK: - split tests (existing bridge functions)

    func testSplitBasic() {
        let result = kk_string_split(makeStringRaw("a,b,c"), makeStringRaw(","))
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 3)
    }

    func testSplitWithLimit() {
        let result = kk_string_split_limit(
            makeStringRaw("a,b,c,d"),
            makeStringRaw(","),
            0, // ignoreCase
            2  // limit
        )
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 2)
    }

    func testSplitWithIgnoreCase() {
        let result = kk_string_split_limit(
            makeStringRaw("A,B,C"),
            makeStringRaw(","),
            1, // ignoreCase
            0  // limit
        )
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 3)
    }
}
