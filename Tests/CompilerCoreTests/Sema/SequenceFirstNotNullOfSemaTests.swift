@testable import CompilerCore
import Foundation
import Testing

@Suite
struct SequenceFirstNotNullOfSemaTests {
    @Test func testSequenceFirstNotNullOfResolvesToBundledSourceAndNonNullResult() throws {
        let source = """
        fun probe(values: Sequence<Int>) {
            val result: String = values.firstNotNullOf { if (it > 1) "hit" else null }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                Comment(rawValue: "Expected firstNotNullOf to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "firstNotNullOf"
            }, "Expected firstNotNullOf member call")
            let chosenCallee = try #require(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected firstNotNullOf call binding"
            )
            let chosenFQName = try #require(sema.symbols.symbol(chosenCallee)?.fqName)
                .map(ctx.interner.resolve)
            #expect(
                chosenFQName == ["kotlin", "sequences", "firstNotNullOf"],
                "Expected the Sequence extension declaration, got \(chosenFQName)"
            )
            #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            #expect(sema.bindings.exprType(for: callExpr) == sema.types.stringType)
        }
    }
}
