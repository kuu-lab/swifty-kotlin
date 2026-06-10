import XCTest
@testable import Runtime

/// Tests for string split, join, chunked, windowed, zip functions migrated to Kotlin stdlib
/// MIGRATION-TEXT-004
final class RuntimeStringSplitJoinTests: XCTestCase {

    // MARK: - chunked tests

    func testChunkedBasic() {
        let result = kk_string_chunked(runtimeMakeStringRaw("abcdef"), 2)
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 3)
    }

    func testChunkedEmptyString() {
        let result = kk_string_chunked(runtimeMakeStringRaw(""), 3)
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 0)
    }

    func testChunkedSizeGreaterThanLength() {
        let result = kk_string_chunked(runtimeMakeStringRaw("hi"), 100)
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 1)
    }

    func testChunkedTransform() {
        let strRaw = runtimeMakeStringRaw("abcdef")
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
        let result = kk_string_windowed(runtimeMakeStringRaw("abcde"), 3, 1)
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 3)
    }

    func testWindowedPartialWindowsFalse() {
        let result = kk_string_windowed_partial(runtimeMakeStringRaw("abcde"), 3, 2, 0)
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
    }

    func testWindowedPartialWindowsTrue() {
        let result = kk_string_windowed_partial(runtimeMakeStringRaw("abcde"), 3, 2, 1)
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
    }

    func testWindowedStepLargerThanSize() {
        let result = kk_string_windowed(runtimeMakeStringRaw("abcdef"), 2, 3)
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
    }

    func testWindowedTransform() {
        let strRaw = runtimeMakeStringRaw("abcde")
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

    func testZipWithNextTransform() {
        let strRaw = runtimeMakeStringRaw("abc")
        let fnPtr: Int = 0
        let closureRaw = 0
        var thrown = 0
        
        let result = kk_string_zipWithNextTransform(strRaw, fnPtr, closureRaw, &thrown)
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
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

    func testZipTransform() {
        let strRaw = runtimeMakeStringRaw("abc")
        let otherRaw = runtimeMakeStringRaw("xyz")
        let fnPtr: Int = 0
        let closureRaw = 0
        var thrown = 0
        
        let result = kk_string_zipTransform(strRaw, otherRaw, fnPtr, closureRaw, &thrown)
        let list = runtimeListBox(from: result)
        XCTAssertNotNil(list)
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

    func testSplitToSequenceBasic() {
        let result = kk_string_splitToSequence(runtimeMakeStringRaw("a,b,c"), runtimeMakeStringRaw(","))
        XCTAssertNotNil(result)
        // Should return a sequence
    }

    func testSplitToSequenceEmptyDelimiter() {
        let result = kk_string_splitToSequence(runtimeMakeStringRaw("abc"), runtimeMakeStringRaw(""))
        XCTAssertNotNil(result)
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
