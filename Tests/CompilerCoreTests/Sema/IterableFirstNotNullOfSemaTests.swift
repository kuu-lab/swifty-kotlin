#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct IterableFirstNotNullOfSemaTests {
    @Test func testIterableFirstNotNullOfResolvesToRuntimeABIAndNonNullResult() throws {
        let source = """
        fun probe(values: Iterable<Int>) {
            val result: String = values.firstNotNullOf { if (it > 1) "hit" else null }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected firstNotNullOf to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "firstNotNullOf"
            }, "Expected firstNotNullOf member call")
            let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)

            #expect(sema.symbols.externalLinkName(for: chosen) == "kk_iterable_firstNotNullOf")
            #expect(sema.bindings.exprType(for: callExpr) == sema.types.stringType)
        }
    }
}
#endif
