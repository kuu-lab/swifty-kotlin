@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN-102: `fun String.toLong(): Long` in `kotlin.text`.
///
/// Verifies:
/// - The synthetic stub registered for `String.toLong` links to the
///   runtime symbol `kk_string_toLong_flat` declared in
///   `Sources/RuntimeABI/RuntimeABISpec+String.swift`.
/// - A call expression `value.toLong()` resolves through sema to that bridge
///   and produces no diagnostics.
@Suite
struct StringToLongFunctionTests {
    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    @Test
    func testToLongStubLinksToRuntimeSymbol() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)

            #expect(
                externalLink(for: "toLong", sema: sema, interner: ctx.interner) == "kk_string_toLong",
                "String.toLong() should link to kk_string_toLong"
            )
        }
    }

    @Test
    func testToLongCallResolvesToRuntimeBridge() throws {
        let source = """
        fun parse(raw: String): Long {
            return raw.toLong()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
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
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "toLong" && args.isEmpty
                },
                "Expected member call to toLong() in AST"
            )

            let chosenCallee = try #require(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected call binding for toLong"
            )
            #expect(
                sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_toLong",
                "String.toLong() should resolve to kk_string_toLong"
            )
        }
    }
}
