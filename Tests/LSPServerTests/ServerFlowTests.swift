#if canImport(Testing)
@testable import LSPServer
import Testing

@Suite("LSP.ServerFlow")
struct ServerFlowTests {
    @Test
    func initializeShutdownAndDiagnosticsLifecycle() {
        let uri = "file:///tmp/LSPServerFlow.kt"
        let source = "fun main() {\n    val x: Int = 1\n}\n"

        let openParams = DidOpenTextDocumentParams(
            textDocument: TextDocumentItem(uri: uri, languageId: "kotlin", version: 1, text: source)
        )

        let messages: [[String: Any]] = [
            LSPTestSupport.message(id: 1, method: "initialize", params: [String: Any]()),
            LSPTestSupport.message(method: "initialized", params: [String: Any]()),
            LSPTestSupport.message(method: "textDocument/didOpen", params: JSONCoding.toObject(openParams)!),
            LSPTestSupport.message(id: 2, method: "shutdown"),
            LSPTestSupport.message(method: "exit"),
        ]

        let output = MemoryOutputStream()
        let connection = JSONRPCConnection(input: MemoryInputStream(LSPTestSupport.frame(messages)), output: output)
        let server = Server(connection: connection)

        let exitCode = server.run()
        #expect(exitCode == 0, "shutdown followed by exit should yield exit code 0")

        let sent = LSPTestSupport.decodeMessages(from: output)

        // initialize response carries server capabilities.
        let initializeResponse = sent.first { ($0["id"] as? Int) == 1 }
        #expect(initializeResponse != nil, "Expected an initialize response")
        if let result = initializeResponse?["result"] as? [String: Any],
           let capabilities = result["capabilities"] as? [String: Any]
        {
            #expect((capabilities["hoverProvider"] as? Bool) == true)
            #expect((capabilities["definitionProvider"] as? Bool) == true)
            #expect((capabilities["documentSymbolProvider"] as? Bool) == true)
        } else {
            Issue.record("initialize result should contain capabilities")
        }

        // A publishDiagnostics notification is emitted for the opened document.
        let publish = sent.first { ($0["method"] as? String) == "textDocument/publishDiagnostics" }
        #expect(publish != nil, "Expected a publishDiagnostics notification")
        if let params = publish?["params"] as? [String: Any] {
            #expect((params["uri"] as? String) == uri)
            #expect(params["diagnostics"] != nil)
        }

        // shutdown response present.
        #expect(sent.contains { ($0["id"] as? Int) == 2 }, "Expected a shutdown response")
    }
}
#endif
