#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN-107: `fun String.toShortOrNull(): Short?` in `kotlin.text`.
///
/// Verifies:
/// - `String.toShortOrNull` is source-backed after KSP-414 and no longer
///   exposes a public `kk_string_toShortOrNull` runtime link; it bridges through
///   the private `__kk_string_toShortOrNull` runtime symbol.
/// - The extension resolves cleanly from source code and produces no Sema
///   diagnostics for a call returning `Short?`.
/// - An elvis fallback on the nullable result type-checks correctly, narrowing
///   the fallback integer literal to `Short`.
@Suite
struct StringToShortOrNullFunctionTests {
    @Test
    func testToShortOrNullResolvesInSource() throws {
        let source = """
        fun parse(raw: String): Short? {
            return raw.toShortOrNull()
        }

        fun probe(): Short {
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
            !allLinks.contains("kk_string_toShortOrNull") && !allLinks.contains("__kk_string_toShortOrNull"),
            "lookupAll for toShortOrNull must not include public or private string parse links; got: \(allLinks)"
        )

        let symbol = try #require(sema.symbols.lookup(fqName: fq))
        #expect(
            sema.symbols.externalLinkName(for: symbol) == nil,
            "String.toShortOrNull should be source-backed and have no C external link"
        )

        let bridgeFq = ["kotlin", "text", "__kk_string_toShortOrNull"].map { interner.intern($0) }
        #expect(
            sema.symbols.externalLinkName(for: try #require(sema.symbols.lookup(fqName: bridgeFq))) == "__kk_string_toShortOrNull",
            "Private __kk_string_toShortOrNull bridge should be registered"
        )
    }
}
#endif
