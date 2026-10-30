@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct StrayAtSignParsingTests {
    @Test
    func duplicateAtSignAfterLabelIsRejected() throws {
        let source = "fun main() { x@@ }"
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        #expect(context.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.code == "KSWIFTK-PARSE-0001"
        }, "Expected a syntax diagnostic for the second '@': \(context.diagnostics.diagnostics)")
    }
}
