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
    // There is no (other) replacement entry point for constructing a file-backed
    // InputStream. Rather than invent a new production API or reach for a materially
    // different fixture, those four tests were deleted; see the task report for what
    // alive primitives lost coverage as a result and the alternatives that were
    // considered but not applied.
    //
    // NOTE (CLEANUP-STUB-115): the OutputStream fixture below used to go through
    // `kk_path_new`/`kk_path_outputStream` (`kotlin.io.path.Path`'s runtime
    // primitives) to obtain a file-backed `RuntimeOutputStreamBox`. Path's synthetic
    // stubs and its Runtime `kk_path_*` cdecls were removed entirely, so the fixture
    // now opens the `FileHandle` and boxes it directly — the same construction
    // `kk_path_outputStream` used to perform internally.

    @Test func testOutputStreamWriteByteAndBytesPersistToFile() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var thrown = 0
        let streamRaw = openOutputStream(fileURL.path)
        #expect(streamRaw != 0)

        _ = __kk_output_stream_write_byte(streamRaw, 65, &thrown)
        let bytesRaw = registerRuntimeObject(RuntimeListBox(elements: [66, 67]))
        _ = __kk_output_stream_write_bytes(streamRaw, bytesRaw, &thrown)
        _ = __kk_output_stream_flush(streamRaw, &thrown)
        _ = __kk_output_stream_close(streamRaw)

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(contents == "ABC")
    }

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
#endif
