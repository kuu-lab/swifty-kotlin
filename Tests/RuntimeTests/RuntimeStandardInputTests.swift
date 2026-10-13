import Foundation
@testable import Runtime
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeStandardInputTests {
    @Test
    func stdioBytesSkipBulkReadsAndEOFPreserveInputStreamContract() throws {
        let stream = try makeStream([65, 66, 255, 128])
        defer { stream.close() }
        let raw = registerRuntimeObject(stream)
        var thrown = 0
        #expect(__kk_input_stream_read(raw, &thrown) == 65)
        #expect(thrown == 0)
        #expect(__kk_input_stream_skip(raw, 1, &thrown) == 1)
        #expect(thrown == 0)
        let buffer = RuntimeListBox(elements: [0, 0])
        let bufferRaw = registerRuntimeObject(buffer)
        #expect(__kk_input_stream_read_bytes(raw, bufferRaw, &thrown) == 1)
        #expect(buffer[0] == -1)
        #expect(thrown == 0)
        #expect(stream.readAllBytes() == [-128])
        #expect(stream.readError == nil)
        #expect(__kk_input_stream_read(raw, &thrown) == -1)
        #expect(__kk_input_stream_read(raw, &thrown) == -1)
        #expect(thrown == 0)
    }

    @Test
    func emptyBulkReadReturnsZeroAndClosedStreamRaisesIOException() throws {
        let stream = try makeStream([])
        let raw = registerRuntimeObject(stream)
        let empty = registerRuntimeObject(RuntimeListBox(elements: []))
        var thrown = 0
        #expect(__kk_input_stream_read_bytes(raw, empty, &thrown) == 0)
        #expect(thrown == 0)
        stream.close()
        stream.close()
        #expect(__kk_input_stream_read(raw, &thrown) == -1)
        #expect(thrown != 0)
        let error = try #require(UnsafeMutableRawPointer(bitPattern: thrown))
        #expect(tryCast(error, to: RuntimeIOExceptionBox.self) != nil)
    }

    @Test
    func constructionDoesNotConsumeInputAndDrainingUsesCurrentPosition() throws {
        let file = try #require(tmpfile())
        fputc(65, file)
        fputc(255, file)
        rewind(file)
        let stream = RuntimeStdioInputStreamBox(stream: file)
        defer { stream.close() }
        #expect(ftell(file) == 0)
        #expect(stream.available() == 0)
        #expect(ftell(file) == 0)
        #expect(stream.readByte() == 65)
        #expect(stream.drainRemaining() == Data([255]))
        #expect(stream.readByte() == -1)
        #expect(stream.readError == nil)
    }

    private func makeStream(_ bytes: [UInt8]) throws -> RuntimeStdioInputStreamBox {
        let file = try #require(tmpfile())
        for byte in bytes {
            fputc(Int32(byte), file)
        }
        rewind(file)
        return RuntimeStdioInputStreamBox(stream: file)
    }
}
