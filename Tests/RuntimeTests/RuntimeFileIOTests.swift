import Foundation
@testable import Runtime
import Testing

// MARK: - STDLIB-IO-FN-016: File.forEachBlock lambda thunks
// Lambda ABI: (closureRaw: Int, bytesRaw: Int, bytesReadRaw: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int
private nonisolated(unsafe) var forEachBlockAccumulator: Int = 0
private nonisolated(unsafe) var forEachBlockChunkCount: Int = 0

// Counts total bytesRead across all callback invocations
private let forEachBlockCountBytes: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, bytesReadRaw, outThrown in
    outThrown?.pointee = 0
    forEachBlockAccumulator += kk_unbox_int(bytesReadRaw)
    return 0
}

// Counts chunks and accumulates bytesRead
private let forEachBlockCountChunks: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, bytesReadRaw, outThrown in
    outThrown?.pointee = 0
    forEachBlockChunkCount += 1
    forEachBlockAccumulator += kk_unbox_int(bytesReadRaw)
    return 0
}

@Suite(.serialized, .runtimeIsolation(.gcOnly, resetAdditionalState: {
    forEachBlockAccumulator = 0
    forEachBlockChunkCount = 0
}))
struct RuntimeFileIOTests {
    @Test func testReadTextReturnsUtf8Contents() throws {
        let fileURL = try makeTempFile(contents: "alpha\nbeta")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let textRaw = kk_file_readText(fileRaw, &thrown)

        #expect(thrown == 0)
        #expect(readString(textRaw) == "alpha\nbeta")
    }

    @Test func testAppendTextCreatesAndAppendsFile() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0

        #expect(kk_file_appendText(fileRaw, runtimeStringRaw("alpha"), &thrown) == 0)
        #expect(thrown == 0)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "alpha")

        #expect(kk_file_appendText(fileRaw, runtimeStringRaw("\nbeta"), &thrown) == 0)
        #expect(thrown == 0)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "alpha\nbeta")
    }

    @Test func testReadBytesReturnsSignedByteValues() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([0, 127, 128, 255]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let bytesRaw = kk_file_readBytes(fileRaw, &thrown)

        #expect(thrown == 0)
        #expect(runtimeListBox(from: bytesRaw)?.elements == [0, 127, -128, -1])
    }

    // STDLIB-IO-FN-001: File.appendBytes(array: ByteArray)
    @Test func testAppendBytesCreatesAndAppendsFile() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0

        // Write initial bytes [1, 2, 3]
        let bytesRaw1 = registerRuntimeObject(RuntimeListBox(elements: [1, 2, 3]))
        #expect(kk_file_appendBytes(fileRaw, bytesRaw1, &thrown) == 0)
        #expect(thrown == 0)
        #expect(try Data(contentsOf: fileURL) == Data([1, 2, 3]))

        // Append additional bytes [4, 5]
        let bytesRaw2 = registerRuntimeObject(RuntimeListBox(elements: [4, 5]))
        #expect(kk_file_appendBytes(fileRaw, bytesRaw2, &thrown) == 0)
        #expect(thrown == 0)
        #expect(try Data(contentsOf: fileURL) == Data([1, 2, 3, 4, 5]))
    }

    @Test func testAppendBytesHandlesSignedByteValues() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0

        // Kotlin Byte range: -128 to 127; -1 maps to 0xFF, -128 to 0x80
        let bytesRaw = registerRuntimeObject(RuntimeListBox(elements: [0, 127, -128, -1]))
        #expect(kk_file_appendBytes(fileRaw, bytesRaw, &thrown) == 0)
        #expect(thrown == 0)
        #expect(try Data(contentsOf: fileURL) == Data([0, 127, 128, 255]))
    }

    @Test func testStringByteInputStreamFlatDefaultCharsetYieldsUtf8Bytes() {
        withFlatString("A\u{00E9}") { data, length, byteCount, hash in
            let streamRaw = kk_string_byteInputStream_flat(data, length, byteCount, hash)
            #expect(readInputStreamBytes(streamRaw) == [65, 195, 169])
        }
    }

    @Test func testStringByteInputStreamFlatExplicitCharsetYieldsEncodedBytes() {
        withFlatString("AB") { data, length, byteCount, hash in
            let streamRaw = kk_string_byteInputStream_charset_flat(
                data,
                length,
                byteCount,
                hash,
                __kk_charset_utf_16be()
            )
            #expect(readInputStreamBytes(streamRaw) == [0, 65, 0, 66])
        }
    }

    // STDLIB-IO-FN-016: File.forEachBlock — default blockSize accumulates all bytes
    @Test func testForEachBlockDefaultBlockSizeAccumulatesAllBytes() throws {
        let bytes: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(bytes).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)

        forEachBlockAccumulator = 0
        let fnPtr = Int(bitPattern: unsafeBitCast(
            forEachBlockCountBytes as @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int,
            to: UnsafeRawPointer.self
        ))
        var thrown = 0
        _ = kk_file_forEachBlock(fileRaw, fnPtr, 0, &thrown)

        #expect(thrown == 0)
        #expect(forEachBlockAccumulator == 8)
    }

    // STDLIB-IO-FN-016: File.forEachBlock — explicit blockSize splits data into chunks
    @Test func testForEachBlockWithExplicitBlockSizeProcessesChunks() throws {
        let bytes: [UInt8] = [10, 20, 30, 40, 50, 60]
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(bytes).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)

        forEachBlockChunkCount = 0
        forEachBlockAccumulator = 0
        let fnPtr = Int(bitPattern: unsafeBitCast(
            forEachBlockCountChunks as @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int,
            to: UnsafeRawPointer.self
        ))
        // blockSize = 2 → should produce 3 chunks of 2 bytes each
        let blockSizeRaw = kk_box_int(2)
        var thrown = 0
        _ = kk_file_forEachBlock_blockSize(fileRaw, blockSizeRaw, fnPtr, 0, &thrown)

        #expect(thrown == 0)
        #expect(forEachBlockChunkCount == 3)
        #expect(forEachBlockAccumulator == 6) // 3 chunks × 2 bytes each
    }

    private func makeTempFile(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func runtimeTestFileHandle(_ path: String) -> Int {
        kk_file_new(runtimeStringRaw(path))
    }

    private func runtimeStringRaw(_ value: String) -> Int {
        let bytes = Array(value.utf8)
        return bytes.withUnsafeBufferPointer { buffer -> Int in
            let baseAddress = buffer.baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0x1)!
            return Int(bitPattern: kk_string_from_utf8(baseAddress, Int32(bytes.count)))
        }
    }

    private func withFlatString<T>(
        _ value: String,
        _ body: (UnsafePointer<UInt8>?, Int, Int, Int) -> T
    ) -> T {
        var length = 0
        var byteCount = 0
        var hash = 0
        let data = runtimeRegisterFlatString(
            value,
            outLength: &length,
            outByteCount: &byteCount,
            outHash: &hash
        )
        return body(data.map { UnsafePointer($0) }, length, byteCount, hash)
    }

    private func readInputStreamBytes(_ streamRaw: Int) -> [Int] {
        var result: [Int] = []
        var thrown = 0
        while true {
            let byte = kk_input_stream_read(streamRaw, &thrown)
            #expect(thrown == 0)
            if byte < 0 {
                return result
            }
            result.append(byte)
        }
    }

    private func readString(_ raw: Int) -> String? {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw))
    }
}
