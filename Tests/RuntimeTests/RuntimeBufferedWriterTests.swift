import Foundation
@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeBufferedWriterTests {
    // MARK: - STDLIB-IO-FN-010: File.bufferedWriter()

    @Test func testFileBufferedWriterWritesAndTruncatesExistingContent() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "old-content".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let writerRaw = openBufferedWriter(fileURL.path)
        #expect(writerRaw != 0)

        #expect(__kk_buffered_writer_write(writerRaw, makeStringRaw("hello"), &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_buffered_writer_new_line(writerRaw, &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_buffered_writer_write(writerRaw, makeStringRaw("world"), &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_buffered_writer_flush(writerRaw, &thrown) == 0)
        #expect(thrown == 0)

        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "hello\nworld")
        #expect(__kk_buffered_writer_close(writerRaw) == 0)
    }

    @Test func testFileBufferedWriterCreatesFileWhenMissing() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let writerRaw = openBufferedWriter(fileURL.path)
        #expect(writerRaw != 0)

        #expect(__kk_buffered_writer_write(writerRaw, makeStringRaw("created"), &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_buffered_writer_flush(writerRaw, &thrown) == 0)
        #expect(thrown == 0)

        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "created")
        #expect(__kk_buffered_writer_close(writerRaw) == 0)
    }

    @Test func testFileBufferedWriterWritesUtf8MultibyteContent() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let writerRaw = openBufferedWriter(fileURL.path)
        #expect(writerRaw != 0)

        #expect(__kk_buffered_writer_write(writerRaw, makeStringRaw("日本語テスト"), &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_buffered_writer_flush(writerRaw, &thrown) == 0)
        #expect(thrown == 0)

        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "日本語テスト")
        #expect(__kk_buffered_writer_close(writerRaw) == 0)
    }

    @Test func testPathBufferedWriterWritesAndTruncatesFile() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "old-content".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let writerRaw = openBufferedWriter(fileURL.path, bufferSize: 2)
        #expect(writerRaw != 0)

        var thrown = 0
        #expect(__kk_buffered_writer_write(writerRaw, makeStringRaw("alpha"), &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_buffered_writer_new_line(writerRaw, &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_buffered_writer_write(writerRaw, makeStringRaw("beta"), &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_buffered_writer_flush(writerRaw, &thrown) == 0)
        #expect(thrown == 0)

        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "alpha\nbeta")
        #expect(__kk_buffered_writer_close(writerRaw) == 0)
    }

    // MARK: - STDLIB-IO-PATH-FN-042: Path.writer()

    @Test func testPathWriterWritesAndTruncatesExistingContent() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "old-content".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let writerRaw = openBufferedWriter(fileURL.path)
        #expect(writerRaw != 0)

        #expect(__kk_buffered_writer_write(writerRaw, makeStringRaw("hello"), &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_buffered_writer_new_line(writerRaw, &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_buffered_writer_write(writerRaw, makeStringRaw("world"), &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_buffered_writer_flush(writerRaw, &thrown) == 0)
        #expect(thrown == 0)

        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "hello\nworld")
        #expect(__kk_buffered_writer_close(writerRaw) == 0)
    }

    @Test func testPathWriterCreatesFileWhenMissing() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let writerRaw = openBufferedWriter(fileURL.path)
        #expect(writerRaw != 0)

        #expect(__kk_buffered_writer_write(writerRaw, makeStringRaw("created"), &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_buffered_writer_flush(writerRaw, &thrown) == 0)
        #expect(thrown == 0)

        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "created")
        #expect(__kk_buffered_writer_close(writerRaw) == 0)
    }

    @Test func testPathWriterWritesUtf8MultibyteContent() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let writerRaw = openBufferedWriter(fileURL.path)
        #expect(writerRaw != 0)

        #expect(__kk_buffered_writer_write(writerRaw, makeStringRaw("日本語テスト"), &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_buffered_writer_flush(writerRaw, &thrown) == 0)
        #expect(thrown == 0)

        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "日本語テスト")
        #expect(__kk_buffered_writer_close(writerRaw) == 0)
    }

    // STDLIB-IO-FN-009: OutputStream.bufferedWriter(charset)
    @Test func testOutputStreamBufferedWriterWritesUtf8Bytes() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "old-content".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let streamRaw = openOutputStream(fileURL.path)
        #expect(streamRaw != 0)

        // charsetRaw = 0 corresponds to UTF-8 (mirrors Charsets.UTF_8).
        let writerRaw = __kk_output_stream_bufferedWriter(streamRaw, 0)
        #expect(writerRaw != 0)

        #expect(__kk_buffered_writer_write(writerRaw, makeStringRaw("hello"), &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_buffered_writer_new_line(writerRaw, &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_buffered_writer_write(writerRaw, makeStringRaw("world"), &thrown) == 0)
        #expect(thrown == 0)
        #expect(__kk_buffered_writer_flush(writerRaw, &thrown) == 0)
        #expect(thrown == 0)

        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "hello\nworld")
        #expect(__kk_buffered_writer_close(writerRaw) == 0)
    }

    @Test func testOutputStreamBufferedWriterDefaultUsesUtf8() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let streamRaw = openOutputStream(fileURL.path)
        #expect(streamRaw != 0)

        // __kk_output_stream_bufferedWriter_default (File's no-charset-arg facade) is gone;
        // charsetRaw = 0 selects the same UTF-8 default on the surviving charset-taking primitive.
        let writerRaw = __kk_output_stream_bufferedWriter(streamRaw, 0)
        #expect(writerRaw != 0)

        #expect(__kk_buffered_writer_write(writerRaw, makeStringRaw("默认 utf-8"), &thrown) == 0)
        #expect(__kk_buffered_writer_flush(writerRaw, &thrown) == 0)
        #expect(thrown == 0)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "默认 utf-8")
        #expect(__kk_buffered_writer_close(writerRaw) == 0)
    }

    private func makeStringRaw(_ value: String) -> Int {
        let bytes = Array(value.utf8)
        return bytes.withUnsafeBufferPointer { buffer in
            let baseAddress = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0x1)!
            return Int(bitPattern: kk_string_from_utf8(baseAddress, Int32(bytes.count)))
        }
    }

    /// Fixture replacement for the removed `kk_path_bufferedWriter`/`kk_path_writer`
    /// (CLEANUP-STUB-115): creates/truncates `path` and boxes the result exactly as
    /// those cdecls did (charset fixed to UTF-8, matching every call site below).
    private func openBufferedWriter(_ path: String, bufferSize: Int = 8192) -> Int {
        if !FileManager.default.fileExists(atPath: path) {
            _ = FileManager.default.createFile(atPath: path, contents: Data())
        }
        guard let fileHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) else {
            return 0
        }
        fileHandle.truncateFile(atOffset: 0)
        return registerRuntimeObject(RuntimeBufferedWriterBox(fileHandle: fileHandle, bufferSize: bufferSize, encoding: .utf8))
    }

    /// Fixture replacement for the removed `kk_path_outputStream` (CLEANUP-STUB-115).
    private func openOutputStream(_ path: String) -> Int {
        if !FileManager.default.fileExists(atPath: path) {
            _ = FileManager.default.createFile(atPath: path, contents: Data())
        }
        guard let fileHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) else {
            return 0
        }
        fileHandle.truncateFile(atOffset: 0)
        return registerRuntimeObject(RuntimeOutputStreamBox(fileHandle: fileHandle))
    }
}
