#if canImport(Testing)
import Foundation
@testable import LSPServer
import Testing

@Suite("LSP.JSONRPC")
struct JSONRPCTests {
    @Test
    func acceptsFrameAtOrBelowMaxBodyBytes() {
        let connection = JSONRPCConnection(
            input: MemoryInputStream(LSPTestSupport.frame(["x": 1])),
            output: MemoryOutputStream(),
            maxBodyBytes: 16
        )

        let received = connection.receive()
        #expect((received?["x"] as? Int) == 1)
        #expect(connection.receive() == nil)
    }

    @Test
    func roundTripSingleMessage() {
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": ["rootUri": "file:///tmp"],
        ]
        let input = MemoryInputStream(LSPTestSupport.frame(message))
        let connection = JSONRPCConnection(input: input, output: MemoryOutputStream())

        let received = connection.receive()
        #expect((received?["method"] as? String) == "initialize")
        #expect((received?["id"] as? Int) == 1)
        #expect(connection.receive() == nil, "Stream should be exhausted after one message")
    }

    @Test
    func readsMultipleMessagesAcrossChunkBoundaries() {
        let first = LSPTestSupport.frame(["jsonrpc": "2.0", "method": "a"])
        let second = LSPTestSupport.frame(["jsonrpc": "2.0", "method": "b"])
        // Split the combined stream at an arbitrary mid-point to exercise buffering.
        var combined = first
        combined.append(second)
        let mid = combined.count / 2
        let chunks = [combined.prefix(mid), combined.suffix(from: mid)].map { Data($0) }

        let connection = JSONRPCConnection(input: MemoryInputStream(chunks: chunks), output: MemoryOutputStream())
        #expect((connection.receive()?["method"] as? String) == "a")
        #expect((connection.receive()?["method"] as? String) == "b")
        #expect(connection.receive() == nil)
    }

    @Test
    func sendProducesParseableFrame() {
        let output = MemoryOutputStream()
        let connection = JSONRPCConnection(input: MemoryInputStream(Data()), output: output)
        connection.send(["jsonrpc": "2.0", "id": 7, "result": NSNull()])

        let text = String(decoding: output.data, as: UTF8.self)
        #expect(text.hasPrefix("Content-Length: "), "Frame must start with the header")

        let messages = LSPTestSupport.decodeMessages(from: output)
        #expect(messages.count == 1)
        #expect((messages.first?["id"] as? Int) == 7)
    }

    @Test
    func dropsNegativeContentLengthAndRecovers() {
        let invalid = Data("Content-Length: -1\r\n\r\n".utf8)
        let valid = LSPTestSupport.frame(["x": 1])
        let connection = JSONRPCConnection(
            input: MemoryInputStream(chunks: [invalid + valid]),
            output: MemoryOutputStream()
        )

        #expect((connection.receive()?["x"] as? Int) == 1)
        #expect(connection.receive() == nil)
    }

    @Test
    func dropsOversizedContentLengthAndRecovers() {
        let oversizedBody = Data("{\"note\":\"line1\r\n\r\nContent-Length: 999\r\n\r\nline2\"}".utf8)
        let oversized = Data("Content-Length: \(oversizedBody.count)\r\n\r\n".utf8) + oversizedBody
        let valid = LSPTestSupport.frame(["x": 1])
        let connection = JSONRPCConnection(
            input: MemoryInputStream(chunks: [oversized + valid]),
            output: MemoryOutputStream(),
            maxBodyBytes: 16
        )

        #expect((connection.receive()?["x"] as? Int) == 1)
        #expect(connection.receive() == nil)
    }

    @Test
    func dropsNonNumericContentLengthAndRecovers() {
        let malformed = Data("Content-Length: not-a-number\r\n\r\n".utf8)
        let valid = LSPTestSupport.frame(["x": 1])
        let connection = JSONRPCConnection(
            input: MemoryInputStream(chunks: [malformed + valid]),
            output: MemoryOutputStream()
        )

        #expect((connection.receive()?["x"] as? Int) == 1)
        #expect(connection.receive() == nil)
    }

    @Test
    func nearIntMaxContentLengthDoesNotTrap() {
        let header = Data("Content-Length: 9223372036854775807\r\n\r\n".utf8)
        let connection = JSONRPCConnection(
            input: MemoryInputStream(header),
            output: MemoryOutputStream()
        )

        #expect(connection.receive() == nil)
    }

    @Test
    func returnsNilWhenHeaderTerminatorMissingPastMaxHeaderBytes() {
        let chunks: [Data] = [
            Data("Content-Length: 1".utf8),
            Data("Content-Length: 2".utf8),
            Data("Content-Length: 3".utf8),
        ]
        let connection = JSONRPCConnection(
            input: MemoryInputStream(chunks: chunks),
            output: MemoryOutputStream(),
            maxHeaderBytes: 16
        )

        #expect(connection.receive() == nil)
    }
}
#endif
