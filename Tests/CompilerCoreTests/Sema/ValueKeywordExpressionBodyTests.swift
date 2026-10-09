#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct ValueKeywordExpressionBodyTests {
    @Test
    func bareValueInExpressionBodyPreservesNextFunctionBody() throws {
        let ctx = makeContextFromSource(KotlinSourceFixtures.valueKeywordExpressionBody)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)
    }

    @Test
    func bareValueAfterAssignmentNewlinePreservesNextFunctionBody() throws {
        let ctx = makeContextFromSource(
            KotlinSourceFixtures.valueKeywordExpressionBodyAfterAssignmentNewline
        )
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)
    }
}
#endif
