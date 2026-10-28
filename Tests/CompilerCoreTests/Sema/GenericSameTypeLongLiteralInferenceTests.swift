#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct GenericSameTypeLongLiteralInferenceTests {
    @Test(arguments: [false, true])
    func longLiteralsAndCallResultsContextualizeOtherIntegerLiterals(useCache: Bool) throws {
        try withTemporaryFile(contents: """
        fun <T> eq(a: T, b: T): Boolean = a == b
        fun longResult(): Long = 0L

        fun main() {
            eq(0, 0L)
            eq(0, longResult())
            val value: Long = 0
            eq(0, value)
        }
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path], frontendFlags: useCache ? ["sema-cache"] : [], includeStdlib: false
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let equalityCalls = ast.arena.exprs.enumerated().compactMap { index, expr -> ExprID? in
                let id = ExprID(rawValue: Int32(index))
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee),
                      ctx.interner.resolve(name) == "eq",
                      let range = ast.arena.exprRange(id),
                      ctx.sourceManager.path(of: range.start.file) == path
                else {
                    return nil
                }
                return id
            }

            #expect(equalityCalls.count == 3)
            for call in equalityCalls {
                let binding = try #require(sema.bindings.callBinding(for: call))
                #expect(binding.substitutedTypeArguments == [sema.types.longType])
                guard case let .call(_, _, arguments, _) = ast.arena.expr(call),
                      let firstArgument = arguments.first
                else {
                    Issue.record("Expected eq call with an integer literal argument")
                    continue
                }
                #expect(sema.bindings.exprType(for: firstArgument.expr) == sema.types.longType)
            }
        }
    }
}
#endif
