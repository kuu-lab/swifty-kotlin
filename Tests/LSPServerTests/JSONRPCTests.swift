#if canImport(Testing)
import Foundation
@testable import LSPServer
import Testing

@Suite("LSP.JSONRPC")
struct JSONRPCTests {
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
}
#endif
