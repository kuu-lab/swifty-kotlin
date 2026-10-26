#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct TryPostfixIncrementTypingTests {
    @Test func testTryBranchKeepsScalarPostfixIncrementOldValueType() throws {
        let ctx = makeContextFromSources([
            """
            var counter = 0

            fun postfixWithFinally(): Int {
                counter = 1
                return try { counter++ } finally { counter++ }
            }

            fun postfixWithCatchAndFinally(): Int {
                counter = 1
                return try { counter++ }
                catch (e: Throwable) { 42 }
                finally { counter++ }
            }

            fun prefixWithFinally(): Int {
                counter = 1
                return try { ++counter } finally { counter++ }
            }

            fun postfixWithTrailingValue(): Int {
                return try { counter++; counter } finally { counter++ }
            }
            """,
        ])

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let tryExprIDs = allExprIDs(in: ast, path: ctx.options.inputs[0], ctx: ctx) { _, expr in
            if case .tryExpr = expr { return true }
            return false
        }
        let tryTypes = try tryExprIDs.map { try #require(sema.bindings.exprType(for: $0)) }
        #expect(tryTypes.count == 4)
        #expect(tryTypes.allSatisfy { $0 == sema.types.intType })
    }

    @Test func testDiscardedTryPostfixIncrementRemainsAStatement() throws {
        let ctx = makeContextFromSources([
            """
            var counter = 0

            fun discardTryResult() {
                try { counter++ } finally { counter++ }
                counter++
            }
            """,
        ])

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
