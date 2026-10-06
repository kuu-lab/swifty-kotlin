#if canImport(Testing)
import Foundation
@testable import Runtime
import Testing

// MARK: - STDLIB-IO-FN-040 lambda thunks for useLines
//
// Block receives the remaining lines as a boxed Int — a `RuntimeSequenceBox`
// raw pointer whose pull-source drains the reader lazily. We materialise it
// through the sequence source path, read its size, and box the count back as
// an Int — matching the collection HOF lambda ABI consumed by
// `runtimeInvokeCollectionLambda1`.

// MARK: - STDLIB-IO-FN-017 lambda thunks for forEachLine
//
// Action receives each line as a raw String pointer (boxed Int). We extract the
// Swift String value and accumulate it into `forEachLineCollectedLines` so tests
// can assert which lines were visited.

nonisolated(unsafe) private var forEachLineCollectedLines: [String] = []

private let forEachLineCollector: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, lineRaw, outThrown in
    outThrown?.pointee = 0
    if let str = extractString(from: UnsafeMutableRawPointer(bitPattern: lineRaw)) {
        forEachLineCollectedLines.append(str)
    }
    return 0
}

private let forEachLineAlwaysThrows: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "ActionError: forEachLine action threw")
    return 0
}

private let useLinesCountsLines: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, outThrown in
    outThrown?.pointee = 0
    guard let elements = runtimeSequenceSourceElements(from: value) else {
        return kk_box_int(-1)
    }
    return kk_box_int(elements.count)
}

private let useLinesAlwaysThrows: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "BlockError: useLines lambda threw")
    return 0
}

private func fnPtrInt(_ fn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    Int(bitPattern: unsafeBitCast(fn, to: UnsafeRawPointer.self))
}

@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeBufferedReaderTests {
    @Test func testBufferedReaderHandlesMixedLineEndingsAndNoTrailingEmptyLine() throws {
        let fileURL = try makeTempFile(contents: "alpha\r\nbeta\rgamma\n")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let readerRaw = openBufferedReader(fileURL.path, outThrown: &thrown)

        #expect(thrown == 0)
        #expect(readerRaw != 0)
        #expect(readString(__kk_buffered_reader_readLine(readerRaw)) == "alpha")
        #expect(readString(__kk_buffered_reader_readLine(readerRaw)) == "beta")
        #expect(readString(__kk_buffered_reader_readLine(readerRaw)) == "gamma")
        #expect(__kk_buffered_reader_readLine(readerRaw) == runtimeNullSentinelInt)
    }

    @Test func testBufferedReaderEmptyFileIsImmediateEOF() throws {
        let fileURL = try makeTempFile(contents: "")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let readerRaw = openBufferedReader(fileURL.path, outThrown: &thrown)

        #expect(thrown == 0)
        #expect(readerRaw != 0)
        #expect(__kk_buffered_reader_readLine(readerRaw) == runtimeNullSentinelInt)
        let linesRaw = __kk_buffered_reader_readLines(readerRaw)
        #expect(runtimeListBox(from: linesRaw)?.elements.count == 0)
    }

    // MARK: - STDLIB-IO-FN-022: BufferedReader.iterator()

    @Test func testBufferedReaderIteratorYieldsLinesInOrder() throws {
        let fileURL = try makeTempFile(contents: "alpha\nbeta\ngamma\n")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let readerRaw = openBufferedReader(fileURL.path, outThrown: &thrown)
        #expect(thrown == 0)
        #expect(readerRaw != 0)

        let iterRaw = __kk_buffered_reader_iterator(readerRaw)
        #expect(iterRaw != 0)
        #expect(runtimeBufferedLineIteratorBox(from: iterRaw) != nil)

        #expect(kk_iterator_hasNext(iterRaw, nil) == 1)
        #expect(readString(kk_iterator_next(iterRaw, nil)) == "alpha")
        #expect(kk_iterator_hasNext(iterRaw, nil) == 1)
        #expect(readString(kk_iterator_next(iterRaw, nil)) == "beta")
        #expect(kk_iterator_hasNext(iterRaw, nil) == 1)
        #expect(readString(kk_iterator_next(iterRaw, nil)) == "gamma")
        #expect(kk_iterator_hasNext(iterRaw, nil) == 0)
    }

    @Test func testBufferedReaderIteratorOnEmptyFileYieldsNoElements() throws {
        let fileURL = try makeTempFile(contents: "")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let readerRaw = openBufferedReader(fileURL.path, outThrown: &thrown)
        #expect(thrown == 0)

        let iterRaw = __kk_buffered_reader_iterator(readerRaw)
        #expect(iterRaw != 0)
        #expect(kk_iterator_hasNext(iterRaw, nil) == 0)
    }

    // MARK: - STDLIB-IO-FN-033: Reader.readText()

    @Test func testReaderReadTextReturnsRemainingContentsAsSingleString() throws {
        let fileURL = try makeTempFile(contents: "alpha\nbeta\ngamma")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let readerRaw = openBufferedReader(fileURL.path, outThrown: &thrown)
        #expect(thrown == 0)
        #expect(readerRaw != 0)

        let textRaw = __kk_reader_readText(readerRaw)
        #expect(readString(textRaw) == "alpha\nbeta\ngamma")
    }

    @Test func testReaderReadTextAfterPartialReadReturnsOnlyTheRemainder() throws {
        let fileURL = try makeTempFile(contents: "alpha\nbeta\ngamma")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let readerRaw = openBufferedReader(fileURL.path, outThrown: &thrown)
        #expect(thrown == 0)

        #expect(readString(__kk_buffered_reader_readLine(readerRaw)) == "alpha")
        let textRaw = __kk_reader_readText(readerRaw)
        #expect(readString(textRaw) == "beta\ngamma")
    }

    @Test func testReaderReadTextOnEmptyFileReturnsEmptyString() throws {
        let fileURL = try makeTempFile(contents: "")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let readerRaw = openBufferedReader(fileURL.path, outThrown: &thrown)
        #expect(thrown == 0)

        let textRaw = __kk_reader_readText(readerRaw)
        #expect(readString(textRaw) == "")
    }

    @Test func testReaderReadTextAfterCloseReturnsEmptyString() throws {
        let fileURL = try makeTempFile(contents: "alpha\nbeta")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let readerRaw = openBufferedReader(fileURL.path, outThrown: &thrown)
        #expect(thrown == 0)
        #expect(__kk_buffered_reader_close(readerRaw) == 0)

        let textRaw = __kk_reader_readText(readerRaw)
        #expect(readString(textRaw) == "")
    }

    @Test func testReaderReadTextHandlesMultilineUTF8Content() throws {
        let fileURL = try makeTempFile(contents: "α\nβ\nγ")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let readerRaw = openBufferedReader(fileURL.path, outThrown: &thrown)
        #expect(thrown == 0)

        let textRaw = __kk_reader_readText(readerRaw)
        #expect(readString(textRaw) == "α\nβ\nγ")
    }

    @Test func testBufferedReaderIteratorAfterCloseYieldsNoElements() throws {
        let fileURL = try makeTempFile(contents: "first\nsecond\n")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let readerRaw = openBufferedReader(fileURL.path, outThrown: &thrown)
        #expect(thrown == 0)
        #expect(__kk_buffered_reader_close(readerRaw) == 0)

        let iterRaw = __kk_buffered_reader_iterator(readerRaw)
        #expect(iterRaw != 0)
        #expect(kk_iterator_hasNext(iterRaw, nil) == 0)
    }

    @Test func testBufferedReaderCloseStopsReading() throws {
        let fileURL = try makeTempFile(contents: "first\nsecond")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let readerRaw = openBufferedReader(fileURL.path, outThrown: &thrown)

        #expect(thrown == 0)
        #expect(readString(__kk_buffered_reader_readLine(readerRaw)) == "first")
        #expect(__kk_buffered_reader_close(readerRaw) == 0)
        #expect(__kk_buffered_reader_readLine(readerRaw) == runtimeNullSentinelInt)
        let linesRaw = __kk_buffered_reader_readLines(readerRaw)
        #expect(runtimeListBox(from: linesRaw)?.elements.count == 0)
    }

    @Test func testBufferedReaderOpenFailureReturnsNoReaderObject() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        let baselineObjectCount = kk_runtime_heap_object_count()

        var thrown = 0
        let readerRaw = openBufferedReader(missingPath, outThrown: &thrown)

        #expect(thrown != 0)
        #expect(readerRaw == 0)
        #expect(kk_runtime_heap_object_count() == baselineObjectCount)
    }

    @Test func testPathBufferedReaderHandlesSmallBufferReads() throws {
        let fileURL = try makeTempFile(contents: "path-alpha\npath-beta")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let readerRaw = openBufferedReader(fileURL.path, bufferSize: 2, outThrown: &thrown)

        #expect(thrown == 0)
        #expect(readerRaw != 0)
        #expect(readString(__kk_buffered_reader_readLine(readerRaw)) == "path-alpha")
        #expect(readString(__kk_buffered_reader_readLine(readerRaw)) == "path-beta")
        #expect(__kk_buffered_reader_readLine(readerRaw) == runtimeNullSentinelInt)
    }

    @Test func testPathBufferedReaderOpenFailureReturnsNoReaderObject() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        let baselineObjectCount = kk_runtime_heap_object_count()

        var thrown = 0
        let readerRaw = openBufferedReader(missingPath, bufferSize: 4096, outThrown: &thrown)

        #expect(thrown != 0)
        #expect(readerRaw == 0)
        #expect(kk_runtime_heap_object_count() == baselineObjectCount)
    }

    // MARK: - STDLIB-IO-FN-040: BufferedReader.useLines

    @Test func testBufferedReaderUseLinesInvokesBlockWithMaterialisedLines() throws {
        let fileURL = try makeTempFile(contents: "alpha\nbeta\ngamma\n")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let readerRaw = openBufferedReader(fileURL.path, outThrown: &thrown)
        #expect(thrown == 0)
        #expect(readerRaw != 0)

        let result = __kk_buffered_reader_useLines(readerRaw, fnPtrInt(useLinesCountsLines), 0, &thrown)
        #expect(thrown == 0)
        #expect(kk_unbox_int(result) == 3)
    }

    @Test func testBufferedReaderUseLinesEmptyFileReturnsZeroLines() throws {
        let fileURL = try makeTempFile(contents: "")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let readerRaw = openBufferedReader(fileURL.path, outThrown: &thrown)
        #expect(thrown == 0)

        let result = __kk_buffered_reader_useLines(readerRaw, fnPtrInt(useLinesCountsLines), 0, &thrown)
        #expect(thrown == 0)
        #expect(kk_unbox_int(result) == 0)
    }

    @Test func testBufferedReaderUseLinesPropagatesThrownFromBlock() throws {
        let fileURL = try makeTempFile(contents: "one\ntwo\n")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let readerRaw = openBufferedReader(fileURL.path, outThrown: &thrown)
        #expect(thrown == 0)

        let result = __kk_buffered_reader_useLines(readerRaw, fnPtrInt(useLinesAlwaysThrows), 0, &thrown)
        #expect(result == 0)
        #expect(thrown != 0, "block exception should surface via outThrown")
    }

    @Test func testBufferedReaderUseLinesClosesReaderAfterBlock() throws {
        let fileURL = try makeTempFile(contents: "first\nsecond\nthird\n")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let readerRaw = openBufferedReader(fileURL.path, outThrown: &thrown)
        #expect(thrown == 0)

        _ = __kk_buffered_reader_useLines(readerRaw, fnPtrInt(useLinesCountsLines), 0, &thrown)
        #expect(thrown == 0)

        // After useLines returns, the reader is closed and yields no further lines
        // (mirrors the JVM `use { }` contract on the underlying Reader).
        #expect(__kk_buffered_reader_readLine(readerRaw) == runtimeNullSentinelInt)
    }

    // MARK: - STDLIB-IO-FN-017: BufferedReader.forEachLine

    @Test func testBufferedReaderForEachLineInvokesActionForEachLine() throws {
        let fileURL = try makeTempFile(contents: "alpha\nbeta\ngamma\n")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        forEachLineCollectedLines = []
        var thrown = 0
        let readerRaw = openBufferedReader(fileURL.path, outThrown: &thrown)
        #expect(thrown == 0)
        #expect(readerRaw != 0)

        _ = __kk_buffered_reader_forEachLine(readerRaw, fnPtrInt(forEachLineCollector), 0, &thrown)
        #expect(thrown == 0)
        #expect(forEachLineCollectedLines == ["alpha", "beta", "gamma"])
    }

    @Test func testBufferedReaderForEachLineEmptyFileInvokesNoAction() throws {
        let fileURL = try makeTempFile(contents: "")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        forEachLineCollectedLines = []
        var thrown = 0
        let readerRaw = openBufferedReader(fileURL.path, outThrown: &thrown)
        #expect(thrown == 0)

        _ = __kk_buffered_reader_forEachLine(readerRaw, fnPtrInt(forEachLineCollector), 0, &thrown)
        #expect(thrown == 0)
        #expect(forEachLineCollectedLines == [], "action should not be called for an empty file")
    }

    @Test func testBufferedReaderForEachLinePropagatesThrownFromAction() throws {
        let fileURL = try makeTempFile(contents: "one\ntwo\n")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let readerRaw = openBufferedReader(fileURL.path, outThrown: &thrown)
        #expect(thrown == 0)

        let result = __kk_buffered_reader_forEachLine(readerRaw, fnPtrInt(forEachLineAlwaysThrows), 0, &thrown)
        #expect(result == 0)
        #expect(thrown != 0, "action exception should surface via outThrown")
    }

    @Test func testBufferedReaderForEachLineDoesNotCloseReaderAfterIteration() throws {
        let fileURL = try makeTempFile(contents: "first\nsecond\n")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let readerRaw = openBufferedReader(fileURL.path, outThrown: &thrown)
        #expect(thrown == 0)

        forEachLineCollectedLines = []
        _ = __kk_buffered_reader_forEachLine(readerRaw, fnPtrInt(forEachLineCollector), 0, &thrown)
        #expect(thrown == 0)
        #expect(forEachLineCollectedLines == ["first", "second"])

        // After forEachLine returns, the reader is still open. All lines have been
        // consumed, so the next readLine returns null sentinel — but the reader handle
        // itself is still valid (not released). This differs from useLines.
        #expect(__kk_buffered_reader_readLine(readerRaw) == runtimeNullSentinelInt,
                "all lines already consumed; reader still open but at EOF")
    }

    private func makeTempFile(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Fixture replacement for the removed `kk_path_bufferedReader` (CLEANUP-STUB-115):
    /// opens `path` directly and boxes the result exactly as that cdecl did.
    private func openBufferedReader(_ path: String, bufferSize: Int = 8192, outThrown: inout Int) -> Int {
        outThrown = 0
        do {
            let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
            return registerRuntimeObject(RuntimeBufferedReaderBox(fileHandle: fileHandle, chunkSize: bufferSize))
        } catch {
            outThrown = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
            return 0
        }
    }

    private func readString(_ raw: Int) -> String? {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw))
    }
}
#endif
