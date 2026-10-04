import Foundation
@testable import Runtime
import Testing

@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeFileIOTests {
    @Test func testReadTextReturnsUtf8Contents() throws {
        let fileURL = try makeTempFile(contents: "alpha\nbeta")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let fileRaw = runtimeTestFileHandle(fileURL.path)
        var thrown = 0
        let textRaw = __kk_file_readText(fileRaw, &thrown)

        #expect(thrown == 0)
        #expect(readString(textRaw) == "alpha\nbeta")
    }

    @Test func testStringByteInputStreamFlatDefaultCharsetYieldsUtf8Bytes() {
        withFlatString("A\u{00E9}") { data, length, byteCount, hash in
            let streamRaw = __kk_string_byteInputStream_flat(data, length, byteCount, hash)
            #expect(readInputStreamBytes(streamRaw) == [65, 195, 169])
        }
    }

    @Test func testStringByteInputStreamFlatExplicitCharsetYieldsEncodedBytes() {
        withFlatString("AB") { data, length, byteCount, hash in
            let streamRaw = __kk_string_byteInputStream_charset_flat(
                data,
                length,
                byteCount,
                hash,
                __kk_charset_utf_16be()
            )
            #expect(readInputStreamBytes(streamRaw) == [0, 65, 0, 66])
        }
    }

    @Test func testByteArrayInputStreamRangeValid() {
        let array = makeByteArray([10, 20, 30, 40, 50])
        var thrown = 0
        let streamRaw = __kk_bytearray_inputStream_range(array, 1, 3, &thrown)
        #expect(thrown == 0)
        #expect(readInputStreamBytes(streamRaw) == [20, 30, 40])
    }

    @Test func testByteArrayInputStreamRangeOverflowDoesNotTrap() {
        let array = makeByteArray([1, 2, 3])
        var thrown = 0

        // Int.max offset
        _ = __kk_bytearray_inputStream_range(array, Int.max, 1, &thrown)
        #expect(thrown != 0)

        // Int.max length
        thrown = 0
        _ = __kk_bytearray_inputStream_range(array, 0, Int.max, &thrown)
        #expect(thrown != 0)

        // offset + length would overflow
        thrown = 0
        _ = __kk_bytearray_inputStream_range(array, Int.max - 1, 2, &thrown)
        #expect(thrown != 0)

        // Int.min offset or length
        thrown = 0
        _ = __kk_bytearray_inputStream_range(array, Int.min, 1, &thrown)
        #expect(thrown != 0)

        thrown = 0
        _ = __kk_bytearray_inputStream_range(array, 0, Int.min, &thrown)
        #expect(thrown != 0)
    }

    private func makeByteArray(_ bytes: [Int]) -> Int {
        let array = kk_array_new(bytes.count)
        for (index, byte) in bytes.enumerated() {
            _ = kk_array_set(array, index, byte, nil)
        }
        return array
    }

    private func makeTempFile(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func runtimeTestFileHandle(_ path: String) -> Int {
        __kk_file_new(runtimeStringRaw(path))
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
            let byte = __kk_input_stream_read(streamRaw, &thrown)
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
