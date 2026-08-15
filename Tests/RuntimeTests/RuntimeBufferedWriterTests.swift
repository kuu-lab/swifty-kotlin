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

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        #expect(fileRaw != 0)

        var thrown = 0
        let writerRaw = __kk_file_bufferedWriter(fileRaw, &thrown)
        #expect(writerRaw != 0)
        #expect(thrown == 0)

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

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        #expect(fileRaw != 0)

        var thrown = 0
        let writerRaw = __kk_file_bufferedWriter(fileRaw, &thrown)
        #expect(writerRaw != 0)
        #expect(thrown == 0)

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

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        #expect(fileRaw != 0)

        var thrown = 0
        let writerRaw = __kk_file_bufferedWriter(fileRaw, &thrown)
        #expect(writerRaw != 0)
        #expect(thrown == 0)

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

        let writerRaw = kk_path_bufferedWriter(
            runtimeTestPathHandle(fileURL.path),
            0,
            kk_box_int(2),
            0
        )
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
        let writerRaw = kk_path_writer(runtimeTestPathHandle(fileURL.path), 0, 0, &thrown)
        #expect(writerRaw != 0)
        #expect(thrown == 0)

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
        let writerRaw = kk_path_writer(runtimeTestPathHandle(fileURL.path), 0, 0, &thrown)
        #expect(writerRaw != 0)
        #expect(thrown == 0)

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
        let writerRaw = kk_path_writer(runtimeTestPathHandle(fileURL.path), 0, 0, &thrown)
        #expect(writerRaw != 0)
        #expect(thrown == 0)

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
        let fileRaw = __kk_file_new(makeStringRaw(fileURL.path))
        #expect(fileRaw != 0)

        let streamRaw = __kk_file_outputStream(fileRaw, &thrown)
        #expect(streamRaw != 0)
        #expect(thrown == 0)

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
        let fileRaw = __kk_file_new(makeStringRaw(fileURL.path))
        #expect(fileRaw != 0)
        let streamRaw = __kk_file_outputStream(fileRaw, &thrown)
        #expect(streamRaw != 0)

        let writerRaw = __kk_output_stream_bufferedWriter_default(streamRaw)
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

    private func runtimeTestFileHandle(_ path: String) -> Int {
        __kk_file_new(makeStringRaw(path))
    }

    private func runtimeTestPathHandle(_ path: String) -> Int {
        kk_path_new(makeStringRaw(path))
    }
}
