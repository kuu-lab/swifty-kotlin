@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-TEXT-FN-091: `fun String.toByteOrNull(): Byte?` in `kotlin.text`.
///
/// Verifies:
/// - The synthetic stub registered for `String.toByteOrNull` links to the
///   runtime symbol `kk_string_toByteOrNull` declared in
///   `Sources/RuntimeABI/RuntimeABISpec+StringParsing.swift`.
/// - The extension resolves cleanly from source code and produces no Sema
///   diagnostics for a call returning `Int?` (Byte is widened to Int in ABI).
/// - An elvis fallback on the nullable result type-checks correctly.
final class StringToByteOrNullFunctionTests: XCTestCase {
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

    func testToByteOrNullStubLinksToRuntimeSymbol() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)

            XCTAssertEqual(
                externalLink(for: "toByteOrNull", sema: sema, interner: ctx.interner),
                "kk_string_toByteOrNull",
                "String.toByteOrNull should link to kk_string_toByteOrNull"
            )

            let links = externalLinks(for: "toByteOrNull", sema: sema, interner: ctx.interner)
            XCTAssertTrue(
                links.contains("kk_string_toByteOrNull"),
                "lookupAll for toByteOrNull must include kk_string_toByteOrNull; got: \(links)"
            )
        }
    }

    func testToByteOrNullResolvesOnStringReceiver() throws {
        let source = """
        fun parse(raw: String): Byte? {
            return raw.toByteOrNull()
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
                "Expected String.toByteOrNull to resolve cleanly, got: \(diagnosticSummary)"
            )
        }
    }

    func testToByteOrNullOnLiteralWithElvisFallback() throws {
        let source = """
        fun probe(): Int {
            val parsed = "127".toByteOrNull()
            return parsed ?: 0
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
                "Expected String.toByteOrNull() on a literal with elvis fallback to type-check cleanly, got: \(diagnosticSummary)"
            )
        }
    }
}
