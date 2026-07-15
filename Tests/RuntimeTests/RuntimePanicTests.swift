#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimePanicTests {
    @Test
    func testRuntimePanicMessageIncludesDiagnosticCodeAndPayload() {
        let message = "panic payload"
        let rendered = message.withCString { cstr in
            runtimePanicMessage(fromCString: cstr)
        }
        #expect(rendered.contains(runtimePanicDiagnosticCode))
        #expect(rendered.contains(message))
    }

    @Test
    func testRuntimeStructuredPanicMessageIncludesDiagnosticCodeAndPayload() {
        let payload = "structured panic payload"
        let rendered = runtimeStructuredPanicMessage(payload)
        #expect(rendered.contains(runtimePanicDiagnosticCode))
        #expect(rendered.contains(payload))
        #expect(rendered.hasPrefix("KSwiftK panic ["))
    }
}
#endif
