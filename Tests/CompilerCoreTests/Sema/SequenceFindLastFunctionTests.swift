@testable import CompilerCore
import Foundation
import Testing

@Suite
struct SequenceFindLastFunctionTests {
    @Test func testSequenceFindLastInfersNullableElementType() throws {
        let source = """
        fun probe(values: Sequence<Int>) {
            val result: Int? = values.findLast { it > 1 }
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                ctx.diagnostics.diagnostics.isEmpty,
                Comment(rawValue: "Expected findLast to type-check cleanly, got: \(ctx.diagnostics.diagnostics)")
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "findLast"
            })

            #expect(
                sema.bindings.exprType(for: callExpr) == sema.types.makeNullable(sema.types.intType)
            )

            let fqName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("sequences"),
                ctx.interner.intern("Sequence"),
                ctx.interner.intern("findLast"),
            ]
            let v = sema.symbols.lookupAll(fqName: fqName).contains { candidate in
                sema.symbols.externalLinkName(for: candidate) == "kk_sequence_findLast"
            }
            #expect(v)
        }
    }
}
