@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ComparisonOperatorChainingTests {
    @Test
    func rejectsRelationalChainsButKeepsEqualityChains() throws {
        let source = """
        fun lessThanChain() = 1 < 2 < 3
        fun lessOrEqualChain() = 1 <= 2 <= 3
        fun greaterThanChain() = 1 > 2 > 3
        fun greaterOrEqualChain() = 1 >= 2 >= 3
        fun equalityChain(): Boolean = 1 == 1 == true
        fun ordinaryComparisons(): Boolean = 1 < 2 && 2 < 3
        """
        var context: CompilationContext?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            context = ctx
        }

        let ctx = try #require(context)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 4, "Expected only the four relational chains to fail, got: \(errors)")
    }
}
