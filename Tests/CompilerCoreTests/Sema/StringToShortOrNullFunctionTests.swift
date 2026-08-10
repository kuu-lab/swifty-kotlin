#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN-107: `fun String.toShortOrNull(): Short?` in `kotlin.text`.
///
/// Verifies:
/// - The synthetic stub registered for `String.toShortOrNull` links to the
///   runtime symbol `kk_string_toShortOrNull` declared in
///   `Sources/RuntimeABI/RuntimeABISpec+String.swift`.
/// - The extension resolves cleanly from source code and produces no Sema
///   diagnostics for a call returning `Int?` (Short is widened to Int in ABI).
/// - An elvis fallback on the nullable result type-checks correctly.
@Suite
struct StringToShortOrNullFunctionTests {
    @Test
    func testToShortOrNullResolvesInSource() throws {
        let source = """
        fun parse(raw: String): Short? {
            return raw.toShortOrNull()
        }

        fun probe(): Int {
            val parsed = "32767".toShortOrNull()
            return parsed ?: 0
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let fq = ["kotlin", "text", "toShortOrNull"].map { interner.intern($0) }
        let allLinks = Set(sema.symbols.lookupAll(fqName: fq).compactMap { sema.symbols.externalLinkName(for: $0) })
        #expect(
            allLinks.contains("kk_string_toShortOrNull"),
            "lookupAll for toShortOrNull must include kk_string_toShortOrNull; got: \(allLinks)"
        )

        let symbol = try #require(sema.symbols.lookup(fqName: fq))
        #expect(
            sema.symbols.externalLinkName(for: symbol) == "kk_string_toShortOrNull",
            "String.toShortOrNull should link to kk_string_toShortOrNull"
        )
    }
}
#endif
