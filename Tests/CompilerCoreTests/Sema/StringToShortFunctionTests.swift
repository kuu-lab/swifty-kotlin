@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-TEXT-FN-106: `fun String.toShort(): Short` in `kotlin.text`.
///
/// Verifies:
/// - The synthetic stub registered for `String.toShort` links to the runtime
///   symbol `kk_string_toShort_flat` declared in
///   `Sources/RuntimeABI/RuntimeABISpec+ABIParity.swift`.
/// - The extension resolves cleanly from source code on both a parameter
///   receiver and a string-literal receiver (Short is widened to Int in ABI).
final class StringToShortFunctionTests: XCTestCase {
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

    func testToShortStubLinksToRuntimeSymbol() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)

            XCTAssertEqual(
                externalLink(for: "toShort", sema: sema, interner: ctx.interner),
                "kk_string_toShort_flat",
                "String.toShort should link to kk_string_toShort_flat"
            )

            let links = externalLinks(for: "toShort", sema: sema, interner: ctx.interner)
            XCTAssertTrue(
                links.contains("kk_string_toShort_flat"),
                "lookupAll for toShort must include kk_string_toShort_flat; got: \(links)"
            )
        }
    }

    func testToShortResolvesOnStringReceiver() throws {
        let source = """
        fun parse(raw: String): Short {
            return raw.toShort()
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
                "Expected String.toShort to resolve cleanly, got: \(diagnosticSummary)"
            )
        }
    }

    func testToShortOnLiteralResolves() throws {
        let source = """
        fun probe(): Int {
            return "1000".toShort().toInt()
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
                "Expected String.toShort() on a literal to type-check cleanly, got: \(diagnosticSummary)"
            )
        }
    }
}
