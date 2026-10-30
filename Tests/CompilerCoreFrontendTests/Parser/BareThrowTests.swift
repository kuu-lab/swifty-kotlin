#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct BareThrowTests {
    @Test
    func rejectsThrowWithoutExpression() throws {
        let ctx = makeContextFromSource("fun main() { throw }")
        try runFrontend(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.map(\.code) == ["KSWIFTK-PARSE-0001"])
    }

    @Test
    func keepsThrowWithExpression() throws {
        let ctx = makeContextFromSource("fun main() { throw IllegalStateException(\"x\") }")
        try runFrontend(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
