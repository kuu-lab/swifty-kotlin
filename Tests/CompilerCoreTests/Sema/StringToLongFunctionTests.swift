@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-TEXT-FN-102: `fun String.toLong(): Long` in `kotlin.text`.
///
/// Verifies:
/// - The synthetic stub registered for `String.toLong` links to the
///   runtime symbol `kk_string_toLong_flat` declared in
///   `Sources/RuntimeABI/RuntimeABISpec+String.swift`.
/// - A call expression `value.toLong()` resolves through sema to that bridge
///   and produces no diagnostics.
final class StringToLongFunctionTests: XCTestCase {
    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    func testToLongStubLinksToRuntimeSymbol() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)

            XCTAssertEqual(
                externalLink(for: "toLong", sema: sema, interner: ctx.interner),
                "kk_string_toLong_flat",
                "String.toLong() should link to kk_string_toLong_flat"
            )
        }
    }

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
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected String.toLong() to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "toLong" && args.isEmpty
                },
                "Expected member call to toLong() in AST"
            )

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected call binding for toLong"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_string_toLong_flat",
                "String.toLong() should resolve to kk_string_toLong_flat"
            )
        }
    }
}
