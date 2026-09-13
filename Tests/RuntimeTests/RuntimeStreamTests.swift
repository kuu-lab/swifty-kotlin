#if canImport(Testing)
import Foundation
@testable import Runtime
import Testing

@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeStreamTests {
    // NOTE (CLEANUP-STUB-107): This suite used to also cover
    // testInputStreamReadAvailableSkipAndClose, testInputStreamReadIntoByteArrayLikeBuffer,
    // testInputStreamCopyToTransfersBytesAndReturnsCount, and
    // testInputStreamCopyToEmptyStreamReturnsZero. Their fixtures built a File-backed
    // InputStream via the now-deleted `__kk_file_inputStream` (File's own member facade).
    // There is no Path-based (or other) replacement entry point for constructing a
    // file-backed InputStream — `Sources/Runtime/RuntimePath.swift` has no
    // `kk_path_inputStream`/`kk_path_*Input*` cdecl at all. Rather than invent a new
    // production API or reach for a materially different fixture, those four tests were
    // deleted; see the task report for what alive primitives lost coverage as a result and
    // the alternatives that were considered but not applied.

    @Test func testOutputStreamWriteByteAndBytesPersistToFile() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let pathRaw = runtimeTestPathHandle(fileURL.path)
        var thrown = 0
        let streamRaw = kk_path_outputStream(pathRaw, 0)
        #expect(streamRaw != 0)

        _ = __kk_output_stream_write_byte(streamRaw, 65, &thrown)
        let bytesRaw = registerRuntimeObject(RuntimeListBox(elements: [66, 67]))
        _ = __kk_output_stream_write_bytes(streamRaw, bytesRaw, &thrown)
        _ = __kk_output_stream_flush(streamRaw, &thrown)
        _ = __kk_output_stream_close(streamRaw)

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(contents == "ABC")
    }

    private func runtimeTestPathHandle(_ path: String) -> Int {
        let bytes = Array(path.utf8)
        let stringRaw = bytes.withUnsafeBufferPointer { buffer -> Int in
            let baseAddress = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0x1)!
            return Int(bitPattern: kk_string_from_utf8(baseAddress, Int32(bytes.count)))
        }
        return kk_path_new(stringRaw)
    }
}
#endif
