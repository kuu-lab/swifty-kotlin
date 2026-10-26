@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ExpressionLabelTests {
    @Test func valueExpressionLabelsCompileWithoutUnresolvedReferences() throws {
        let (_, ctx) = try buildASTModule(from: """
        fun value() = target@ 1
        fun nested() = outer@ inner@ if (condition@ true) 1 else 2
        fun control() = 1
        """, includeStdlib: false)

        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
