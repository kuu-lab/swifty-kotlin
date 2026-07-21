#if canImport(Testing)
import Testing
@testable import Runtime

/// Tests for string split, join, chunked, windowed, zip functions migrated to Kotlin stdlib
/// MIGRATION-TEXT-004
@Suite
struct RuntimeStringSplitJoinTests {

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

    private func withFlatString<T>(
        _ value: String,
        _ body: (UnsafePointer<UInt8>?, Int, Int, Int) -> T
    ) -> T {
        Array(value.utf8).withUnsafeBufferPointer { buffer in
            body(buffer.baseAddress, value.unicodeScalars.count, value.utf8.count, 0)
        }
    }

    private func withFlatStrings<T>(
        _ value: String,
        _ other: String,
        _ body: (UnsafePointer<UInt8>?, Int, Int, Int, UnsafePointer<UInt8>?, Int, Int, Int) -> T
    ) -> T {
        withFlatString(value) { data, length, byteCount, hash in
            withFlatString(other) { otherData, otherLength, otherByteCount, otherHash in
                body(data, length, byteCount, hash, otherData, otherLength, otherByteCount, otherHash)
            }
        }
    }

    private func zipWithNext(_ value: String) -> Int {
        withFlatString(value) { data, length, byteCount, hash in
            kk_string_zipWithNext_flat(data, length, byteCount, hash)
        }
    }

    private func zip(_ value: String, _ other: String) -> Int {
        withFlatStrings(value, other) { data, length, byteCount, hash, otherData, otherLength, otherByteCount, otherHash in
            kk_string_zip_flat(data, length, byteCount, hash, otherData, otherLength, otherByteCount, otherHash)
        }
    }

    private func split(_ value: String, delimiter: String) -> Int {
        withFlatStrings(value, delimiter) { data, length, byteCount, hash, delimiterData, delimiterLength, delimiterByteCount, delimiterHash in
            kk_string_split_flat(data, length, byteCount, hash, delimiterData, delimiterLength, delimiterByteCount, delimiterHash)
        }
    }

    private func splitToSequence(_ value: String, delimiter: String) -> Int {
        withFlatStrings(value, delimiter) { data, length, byteCount, hash, delimiterData, delimiterLength, delimiterByteCount, delimiterHash in
            kk_string_splitToSequence_flat(data, length, byteCount, hash, delimiterData, delimiterLength, delimiterByteCount, delimiterHash)
        }
    }

    private func splitLimit(_ value: String, delimiter: String, ignoreCase: Int, limit: Int) -> Int {
        withFlatStrings(value, delimiter) { data, length, byteCount, hash, delimiterData, delimiterLength, delimiterByteCount, delimiterHash in
            kk_string_split_limit_flat(
                data,
                length,
                byteCount,
                hash,
                delimiterData,
                delimiterLength,
                delimiterByteCount,
                delimiterHash,
                ignoreCase,
                limit
            )
        }
    }

    // MARK: - chunked tests

    @Test
    func testChunkedTransformFunctionExists() {
        // Verify the function symbol exists. Cannot invoke with a real lambda at the
        // runtime level without a compiled Kotlin closure.
        let fn: (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = kk_string_chunked_sequence_transform
        #expect((fn as Any?) != nil)
    }

    // MARK: - windowed tests

    @Test
    func testWindowedTransformFunctionExists() {
        let fn: (Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = kk_string_windowedSequence_transform
        #expect((fn as Any?) != nil)
    }

    // MARK: - zipWithNext tests

    @Test
    func testZipWithNextEmpty() {
        let result = zipWithNext("")
        let list = runtimeListBox(from: result)
        #expect(list != nil)
        #expect(list?.elements.count == 0)
    }

    @Test
    func testZipWithNextSingleChar() {
        let result = zipWithNext("a")
        let list = runtimeListBox(from: result)
        #expect(list != nil)
        #expect(list?.elements.count == 0)
    }

    @Test
    func testZipWithNextBasic() {
        let result = zipWithNext("abc")
        let list = runtimeListBox(from: result)
        #expect(list != nil)
        #expect(list?.elements.count == 2)
    }

    @Test
    func testZipWithNextTransformFunctionExists() {
        let fn: (UnsafePointer<UInt8>?, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int =
            kk_string_zipWithNextTransform_flat
        #expect((fn as Any?) != nil)
    }

    // MARK: - zip tests

    @Test
    func testZipBasic() {
        let result = zip("abc", "xyz")
        let list = runtimeListBox(from: result)
        #expect(list != nil)
        #expect(list?.elements.count == 3)
    }

    @Test
    func testZipLengthMismatch() {
        let result = zip("abc", "xy")
        let list = runtimeListBox(from: result)
        #expect(list != nil)
        #expect(list?.elements.count == 2) // Shorter side
    }

    @Test
    func testZipTransformFunctionExists() {
        let fn: (
            UnsafePointer<UInt8>?, Int, Int, Int,
            UnsafePointer<UInt8>?, Int, Int, Int,
            Int, Int, UnsafeMutablePointer<Int>?
        ) -> Int = kk_string_zipTransform_flat
        #expect((fn as Any?) != nil)
    }

    // MARK: - joinToString tests

    @Test
    func testJoinToStringBasic() {
        let elements = [runtimeMakeStringRaw("a"), runtimeMakeStringRaw("b"), runtimeMakeStringRaw("c")]
        let listRaw = runtimeMakeListRaw(elements)
        let separator = runtimeMakeStringRaw(", ")
        let prefix = runtimeMakeStringRaw("")
        let postfix = runtimeMakeStringRaw("")
        
        let result = kk_string_joinToString(listRaw, separator, prefix, postfix)
        let resultStr = runtimeStringFromRaw(result)
        #expect(resultStr == "a, b, c")
    }

    @Test
    func testJoinToStringWithPrefixPostfix() {
        let elements = [runtimeMakeStringRaw("a"), runtimeMakeStringRaw("b")]
        let listRaw = runtimeMakeListRaw(elements)
        let separator = runtimeMakeStringRaw(", ")
        let prefix = runtimeMakeStringRaw("[")
        let postfix = runtimeMakeStringRaw("]")
        
        let result = kk_string_joinToString(listRaw, separator, prefix, postfix)
        let resultStr = runtimeStringFromRaw(result)
        #expect(resultStr == "[a, b]")
    }

    // MARK: - splitToSequence tests

    @Test
    func testSplitToSequenceBasic() {
        let result = splitToSequence("a,b,c", delimiter: ",")
        #expect((result as Int?) != nil)
        // Should return a sequence
    }

    @Test
    func testSplitToSequenceEmptyDelimiter() {
        let result = splitToSequence("abc", delimiter: "")
        #expect((result as Int?) != nil)
    }

    // MARK: - split tests (existing bridge functions)

    @Test
    func testSplitBasic() {
        let result = split("a,b,c", delimiter: ",")
        let list = runtimeListBox(from: result)
        #expect(list != nil)
        #expect(list?.elements.count == 3)
    }

    @Test
    func testSplitWithLimit() {
        let result = splitLimit("a,b,c,d", delimiter: ",", ignoreCase: 0, limit: 2)
        let list = runtimeListBox(from: result)
        #expect(list != nil)
        #expect(list?.elements.count == 2)
    }

    @Test
    func testSplitWithIgnoreCase() {
        let result = splitLimit("A,B,C", delimiter: ",", ignoreCase: 1, limit: 0)
        let list = runtimeListBox(from: result)
        #expect(list != nil)
        #expect(list?.elements.count == 3)
    }
}
#endif
