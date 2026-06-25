@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-TEXT-FN-096: `fun String.toDoubleOrNull(): Double?` in `kotlin.text`.
///
/// Verifies:
/// - The synthetic stub registered for `String.toDoubleOrNull` links to the
///   runtime symbol `kk_string_toDoubleOrNull` declared in
///   `Sources/RuntimeABI/RuntimeABISpec+String.swift`.
/// - The extension resolves cleanly from source code and produces no Sema
///   diagnostics for a call returning `Double?`.
/// - Elvis fallback (`?: 0.0`) type-checks correctly with the nullable return.
final class StringToDoubleOrNullFunctionTests: XCTestCase {
    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    private func externalLinks(for member: String, sema: SemaModule, interner: StringInterner) -> Set<String> {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        return Set(
            sema.symbols.lookupAll(fqName: fq)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
    }

    func testToDoubleOrNullStubLinksToRuntimeSymbol() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)

            XCTAssertEqual(
                externalLink(for: "toDoubleOrNull", sema: sema, interner: ctx.interner),
                "kk_string_toDoubleOrNull",
                "String.toDoubleOrNull should link to kk_string_toDoubleOrNull"
            )

            let links = externalLinks(for: "toDoubleOrNull", sema: sema, interner: ctx.interner)
            XCTAssertTrue(
                links.contains("kk_string_toDoubleOrNull"),
                "lookupAll for toDoubleOrNull must include kk_string_toDoubleOrNull; got: \(links)"
            )
        }
    }

    func testToDoubleOrNullInfersNullableDoubleType() throws {
        let source = """
        fun probe(text: String) {
            val result: Double? = text.toDoubleOrNull()
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected String.toDoubleOrNull() to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toDoubleOrNull"
            })

            XCTAssertEqual(
                sema.bindings.exprType(for: callExpr),
                sema.types.makeNullable(sema.types.doubleType)
            )
        }
    }

    func testToDoubleOrNullOnLiteralAndElvisFallback() throws {
        let source = """
        fun probe(): Double {
            val parsed: Double? = "3.14".toDoubleOrNull()
            return parsed ?: 0.0
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected String.toDoubleOrNull() with Elvis fallback to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "toDoubleOrNull"
            })

            XCTAssertEqual(
                sema.bindings.exprType(for: callExpr),
                sema.types.makeNullable(sema.types.doubleType)
            )
        }
    }

    func testToDoubleOrNullResolvesOnStringReceiver() throws {
        let source = """
        fun parse(raw: String): Double? {
            return raw.toDoubleOrNull()
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
                "Expected String.toDoubleOrNull to resolve cleanly, got: \(diagnosticSummary)"
            )
        }
    }
}
