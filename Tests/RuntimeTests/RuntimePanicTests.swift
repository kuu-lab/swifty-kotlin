@testable import Runtime
import XCTest

final class RuntimePanicTests: XCTestCase {
    func testRuntimePanicMessageIncludesDiagnosticCodeAndPayload() {
        let message = "panic payload"
        let rendered = message.withCString { cstr in
            runtimePanicMessage(fromCString: cstr)
        }
        XCTAssertTrue(rendered.contains(runtimePanicDiagnosticCode))
        XCTAssertTrue(rendered.contains(message))
    }

    func testRuntimeStructuredPanicMessageIncludesDiagnosticCodeAndPayload() {
        let payload = "structured panic payload"
        let rendered = runtimeStructuredPanicMessage(payload)
        XCTAssertTrue(rendered.contains(runtimePanicDiagnosticCode))
        XCTAssertTrue(rendered.contains(payload))
        XCTAssertTrue(rendered.hasPrefix("KSwiftK panic ["))
    }
}
