@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN-103: `fun String.toLongOrNull(): Long?` in `kotlin.text`.
///
/// Verifies that the extension is source-backed after KSP-414 and bridges
/// through the private `__kk_string_toLongOrNull` runtime symbol.
@Suite
struct StringToLongOrNullFunctionTests {
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

    @Test
    func testToLongOrNullResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun parse(raw: String): Long? {
            return raw.toLongOrNull()
        }
        """)

        try runSema(ctx)

        let diagnosticSummary = ctx.diagnostics.diagnostics
            .map { "\($0.code): \($0.message)" }
            .joined(separator: " | ")
        #expect(
            !(ctx.diagnostics.hasError),
            "Expected String.toLongOrNull to resolve cleanly, got: \(diagnosticSummary)"
        )

        let sema = try #require(ctx.sema)

        #expect(
            externalLink(for: "toLongOrNull", sema: sema, interner: ctx.interner) == nil,
            "String.toLongOrNull should be source-backed and have no public C link"
        )

        let links = externalLinks(for: "toLongOrNull", sema: sema, interner: ctx.interner)
        #expect(
            !links.contains("kk_string_toLongOrNull") && !links.contains("__kk_string_toLongOrNull"),
            "lookupAll for toLongOrNull must not include public or private string parse links; got: \(links)"
        )

        #expect(
            externalLink(for: "__kk_string_toLongOrNull", sema: sema, interner: ctx.interner) == "__kk_string_toLongOrNull",
            "Private __kk_string_toLongOrNull bridge should be registered"
        )
    }
}
