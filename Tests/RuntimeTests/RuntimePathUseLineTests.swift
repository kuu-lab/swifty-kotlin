import Foundation
@testable import Runtime
import Testing

// MARK: - STDLIB-IO-PATH-FN-038: Path.useLines lambda thunks
//
// `kk_path_useLines` / `kk_path_useLines_default` materialise all lines from a
// file into a RuntimeListBox and call the block once via the collection HOF ABI:
//   RuntimeCollectionLambda1 = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int
// Arguments: (closureRaw, listRaw, outThrown). These file-scope globals
// accumulate state across the @convention(c) closure boundary.

nonisolated(unsafe) private var _useLinesReceivedSize: Int32 = -1

private func resetRuntimePathUseLineTestState() {
    _useLinesReceivedSize = -1
}

// Signature matches RuntimeCollectionLambda1: (closureRaw, value, outThrown) -> Int
private let captureListSize: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, listRaw, outThrown in
    outThrown?.pointee = 0
    guard let ptr = UnsafeMutableRawPointer(bitPattern: listRaw),
          let list = tryCast(ptr, to: RuntimeListBox.self)
    else { return 0 }
    _useLinesReceivedSize = Int32(list.elements.count)
    return listRaw
}

private let useLinesAlwaysThrows: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "BlockError: useLines lambda threw")
    return 0
}

private func fnPtrInt2(_ fn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    Int(bitPattern: unsafeBitCast(fn, to: UnsafeRawPointer.self))
}

/// Tests for STDLIB-IO-PATH-FN-038: Path.useLines
///
/// Covers `kk_path_useLines` (with charset) and `kk_path_useLines_default`.
@Suite(.runtimeIsolation(.gcOnly, resetAdditionalState: resetRuntimePathUseLineTestState))
struct RuntimePathUseLineTests {
    // MARK: - Helpers

    private func makeStringRaw(_ value: String) -> Int {
        let bytes = Array(value.utf8)
        return bytes.withUnsafeBufferPointer { buffer -> Int in
            let baseAddress = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0x1)!
            return Int(bitPattern: kk_string_from_utf8(baseAddress, Int32(bytes.count)))
        }
    }

    private func makePathRaw(_ path: String) -> Int {
        kk_path_new(makeStringRaw(path))
    }

    // MARK: - kk_path_useLines_default

    @Test func testUseLinesDefaultInvokesBlockOnceWithAllLines() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "alpha\nbeta\ngamma".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = makePathRaw(fileURL.path)
        _useLinesReceivedSize = -1
        var thrown = 0
        _ = kk_path_useLines_default(pathRaw, fnPtrInt2(captureListSize), 0, &thrown)

        #expect(thrown == 0)
        #expect(_useLinesReceivedSize == 3, "block should receive a list with all 3 lines")
    }

    @Test func testUseLinesDefaultEmptyFilePassesEmptyList() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = makePathRaw(fileURL.path)
        _useLinesReceivedSize = -1
        var thrown = 0
        _ = kk_path_useLines_default(pathRaw, fnPtrInt2(captureListSize), 0, &thrown)

        #expect(thrown == 0)
        #expect(_useLinesReceivedSize == 0)
    }

    @Test func testUseLinesDefaultTrailingNewlineDoesNotAddEmptyElement() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "line1\nline2\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = makePathRaw(fileURL.path)
        _useLinesReceivedSize = -1
        var thrown = 0
        _ = kk_path_useLines_default(pathRaw, fnPtrInt2(captureListSize), 0, &thrown)

        #expect(thrown == 0)
        #expect(_useLinesReceivedSize == 2)
    }

    @Test func testUseLinesDefaultNonExistentFileThrows() {
        let pathRaw = makePathRaw("/nonexistent/\(UUID().uuidString).txt")
        var thrown = 0
        _ = kk_path_useLines_default(pathRaw, fnPtrInt2(captureListSize), 0, &thrown)
        #expect(thrown != 0, "non-existent file should set outThrown")
    }

    @Test func testUseLinesDefaultLambdaThrownPropagates() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "line1\nline2".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = makePathRaw(fileURL.path)
        var thrown = 0
        _ = kk_path_useLines_default(pathRaw, fnPtrInt2(useLinesAlwaysThrows), 0, &thrown)
        #expect(thrown != 0, "lambda exception should propagate through useLines")
    }

    @Test func testUseLinesDefaultReturnValueForwardedFromBlock() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "a\nb\nc".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = makePathRaw(fileURL.path)
        var thrown = 0
        let result = kk_path_useLines_default(pathRaw, fnPtrInt2(captureListSize), 0, &thrown)
        #expect(thrown == 0)
        // captureListSize returns the list handle — result must be non-zero
        #expect(result != 0, "return value from block should be forwarded")
    }

    // MARK: - kk_path_useLines (with charset)

    @Test func testUseLinesWithDefaultCharsetPassesAllLines() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try "one\ntwo\nthree".write(to: fileURL, atomically: true, encoding: .utf8)

        let pathRaw = makePathRaw(fileURL.path)
        _useLinesReceivedSize = -1
        var thrown = 0
        // charsetRaw == 0 selects UTF-8 (default)
        _ = kk_path_useLines(pathRaw, 0, fnPtrInt2(captureListSize), 0, &thrown)

        #expect(thrown == 0)
        #expect(_useLinesReceivedSize == 3)
    }

    @Test func testUseLinesWithDefaultCharsetNonExistentFileThrows() {
        let pathRaw = makePathRaw("/nonexistent/\(UUID().uuidString).txt")
        var thrown = 0
        _ = kk_path_useLines(pathRaw, 0, fnPtrInt2(captureListSize), 0, &thrown)
        #expect(thrown != 0)
    }
}
