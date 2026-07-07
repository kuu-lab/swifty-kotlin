@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN-086: `fun String.toBigIntegerOrNull(): BigInteger?` in `kotlin.text`.
@Suite
struct StringToBigIntegerOrNullFunctionTests {
    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    @Test func testToBigIntegerOrNullStubLinksToRuntimeSymbol() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)

            let directLink = externalLink(for: "toBigIntegerOrNull", sema: sema, interner: ctx.interner)
            #expect(
                directLink == nil || directLink?.isEmpty == true,
                "String.toBigIntegerOrNull should be source-backed and not have a direct external link"
            )
            #expect(
                externalLink(for: "__kk_string_toBigIntegerOrNull", sema: sema, interner: ctx.interner) == "__kk_string_toBigIntegerOrNull",
                "__kk_string_toBigIntegerOrNull should link to __kk_string_toBigIntegerOrNull"
            )
        }
    }

    @Test func testToBigIntegerOrNullResolvesAsNullableBigInteger() throws {
        let source = """
        import java.math.BigInteger

        fun parse(raw: String): BigInteger? {
            return raw.toBigIntegerOrNull()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected String.toBigIntegerOrNull to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toBigIntegerOrNull"
            })
            let bigIntegerSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("java"),
                ctx.interner.intern("math"),
                ctx.interner.intern("BigInteger"),
            ]))
            let bigIntegerType = try #require(sema.symbols.propertyType(for: bigIntegerSymbol))

            #expect(
                sema.bindings.exprType(for: callExpr) == sema.types.makeNullable(bigIntegerType)
            )
            #expect(
                sema.bindings.callBinding(for: callExpr).flatMap {
                    sema.symbols.externalLinkName(for: $0.chosenCallee)
                } == "kk_string_toBigIntegerOrNull"
            )
        }
    }
}
