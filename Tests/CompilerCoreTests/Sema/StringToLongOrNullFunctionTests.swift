@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN-103: `fun String.toLongOrNull(): Long?` in `kotlin.text`.
///
/// Verifies that the synthetic extension resolves to the runtime bridge and
/// exposes the `Long?` return type.
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
            externalLink(for: "toLongOrNull", sema: sema, interner: ctx.interner) == "kk_string_toLongOrNull",
            "String.toLongOrNull should link to kk_string_toLongOrNull"
        )

        let links = externalLinks(for: "toLongOrNull", sema: sema, interner: ctx.interner)
        #expect(
            links.contains("kk_string_toLongOrNull"),
            "lookupAll for toLongOrNull must include kk_string_toLongOrNull; got: \(links)"
        )
    }
}
