@testable import CompilerCore
import Foundation
import Testing

@Suite
struct SequenceFirstNotNullOfOrNullSemaTests {
    @Test func testSequenceFirstNotNullOfOrNullResolvesToBundledSourceAndInfersNullableTransformResult() throws {
        let source = """
        fun probe(values: Sequence<Int>) {
            val result: String? = values.firstNotNullOfOrNull { if (it > 1) "hit" else null }
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)

            #expect(
                ctx.diagnostics.diagnostics.isEmpty,
                Comment(rawValue: "Expected firstNotNullOfOrNull to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "firstNotNullOfOrNull"
            })

            #expect(
                sema.bindings.exprType(for: callExpr) == sema.types.makeNullable(sema.types.stringType)
            )

            let chosenCallee = try #require(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected firstNotNullOfOrNull call binding"
            )
            let chosenFQName = try #require(sema.symbols.symbol(chosenCallee)?.fqName)
                .map(ctx.interner.resolve)
            #expect(
                chosenFQName == ["kotlin", "sequences", "firstNotNullOfOrNull"],
                "Expected the Sequence extension declaration, got \(chosenFQName)"
            )
            #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
        }
    }
}
