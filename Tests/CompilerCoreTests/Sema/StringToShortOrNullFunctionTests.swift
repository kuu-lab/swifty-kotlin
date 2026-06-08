@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-TEXT-FN-107: `fun String.toShortOrNull(): Short?` in `kotlin.text`.
///
/// Verifies:
/// - The synthetic stub registered for `String.toShortOrNull` links to the
///   runtime symbol `kk_string_toShortOrNull` declared in
///   `Sources/RuntimeABI/RuntimeABISpec+String.swift`.
/// - The extension resolves cleanly from source code and produces no Sema
///   diagnostics for a call returning `Int?` (Short is widened to Int in ABI).
/// - An elvis fallback on the nullable result type-checks correctly.
final class StringToShortOrNullFunctionTests: XCTestCase {
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

    func testToShortOrNullStubLinksToRuntimeSymbol() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)

            XCTAssertEqual(
                externalLink(for: "toShortOrNull", sema: sema, interner: ctx.interner),
                "kk_string_toShortOrNull",
                "String.toShortOrNull should link to kk_string_toShortOrNull"
            )

            let links = externalLinks(for: "toShortOrNull", sema: sema, interner: ctx.interner)
            XCTAssertTrue(
                links.contains("kk_string_toShortOrNull"),
                "lookupAll for toShortOrNull must include kk_string_toShortOrNull; got: \(links)"
            )
        }
    }

    func testToShortOrNullResolvesOnStringReceiver() throws {
        let source = """
        fun parse(raw: String): Short? {
            return raw.toShortOrNull()
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
                "Expected String.toShortOrNull to resolve cleanly, got: \(diagnosticSummary)"
            )
        }
    }

    func testToShortOrNullOnLiteralWithElvisFallback() throws {
        let source = """
        fun probe(): Int {
            val parsed = "32767".toShortOrNull()
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
                "Expected String.toShortOrNull() on a literal with elvis fallback to type-check cleanly, got: \(diagnosticSummary)"
            )
        }
    }
}
