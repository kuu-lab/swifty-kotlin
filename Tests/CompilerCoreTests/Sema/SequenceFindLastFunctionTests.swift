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

            let packageFQName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("findLast"),
            ]
            let symbols = sema.symbols.lookupAll(fqName: packageFQName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let receiverType = signature.receiverType,
                      case let .classType(classType) = sema.types.kind(of: receiverType),
                      let receiverSymbol = sema.symbols.symbol(classType.classSymbol)
                else { return false }
                return receiverSymbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "sequences", "Sequence"]
            }
            #expect(!symbols.isEmpty, "Expected Sequence.findLast source extension to be registered")
            let hasSyntheticLink = symbols.contains { candidate in
                sema.symbols.externalLinkName(for: candidate) == "kk_sequence_findLast"
            }
            #expect(!hasSyntheticLink, "Expected Sequence.findLast to be backed by source")
        }
    }
}
