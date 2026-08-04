@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN-102: `fun String.toLong(): Long` in `kotlin.text`.
///
/// Verifies that the synthetic extension resolves to the runtime bridge and
/// exposes the `Long` return type.
@Suite
struct StringToLongFunctionTests {
    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    @Test
    func testToLongResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun parse(raw: String): Long {
            return raw.toLong()
        }
        """)

        try runSema(ctx)

        let diagnosticSummary = ctx.diagnostics.diagnostics
            .map { "\($0.code): \($0.message)" }
            .joined(separator: " | ")
        #expect(
            !(ctx.diagnostics.hasError),
            "Expected String.toLong() to resolve cleanly, got: \(diagnosticSummary)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callExpr = try #require(
            firstExprID(in: ast) { exprID, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                guard ctx.interner.resolve(callee) == "toLong" && args.isEmpty else { return false }
                guard let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee else { return false }
                return sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_toLong"
            },
            "Expected member call to toLong() resolving to kk_string_toLong in AST"
        )

        let chosenCallee = try #require(
            sema.bindings.callBinding(for: callExpr)?.chosenCallee,
            "Expected call binding for toLong"
        )
        #expect(
            sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_toLong",
            "String.toLong() should resolve to kk_string_toLong"
        )

        #expect(
            externalLink(for: "toLong", sema: sema, interner: ctx.interner) == "kk_string_toLong",
            "String.toLong should link to kk_string_toLong"
        )
    }
}
