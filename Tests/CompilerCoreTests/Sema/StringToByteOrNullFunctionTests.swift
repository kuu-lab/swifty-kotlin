#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN-091: `fun String.toByteOrNull(): Byte?` in `kotlin.text`.
///
/// Verifies:
/// - `String.toByteOrNull` is source-backed after KSP-414 and no longer
///   exposes a public `kk_string_toByteOrNull` runtime link; it bridges through
///   the private `__kk_string_toByteOrNull` runtime symbol.
/// - The extension resolves cleanly from source code and produces no Sema
///   diagnostics for a call returning `Byte?`.
/// - An elvis fallback on the nullable result type-checks correctly, narrowing
///   the fallback integer literal to `Byte`.
@Suite
struct StringToByteOrNullFunctionTests {
    @Test
    func testToByteOrNullResolvesInSource() throws {
        let source = """
        fun parse(raw: String): Byte? {
            return raw.toByteOrNull()
        }

        fun probe(): Byte {
            val parsed = "127".toByteOrNull()
            return parsed ?: 0
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let fq = ["kotlin", "text", "toByteOrNull"].map { interner.intern($0) }
        let allLinks = Set(sema.symbols.lookupAll(fqName: fq).compactMap { sema.symbols.externalLinkName(for: $0) })
        #expect(
            !allLinks.contains("kk_string_toByteOrNull") && !allLinks.contains("__kk_string_toByteOrNull"),
            "lookupAll for toByteOrNull must not include public or private string parse links; got: \(allLinks)"
        )

        let directLink = sema.symbols.lookupAll(fqName: fq).first.flatMap { sema.symbols.externalLinkName(for: $0) }
        #expect(
            directLink == nil,
            "String.toByteOrNull should be source-backed and have no C external link"
        )

        let bridgeFq = ["kotlin", "text", "__kk_string_toByteOrNull"].map { interner.intern($0) }
        #expect(
            sema.symbols.externalLinkName(for: try #require(sema.symbols.lookup(fqName: bridgeFq))) == "__kk_string_toByteOrNull",
            "Private __kk_string_toByteOrNull bridge should be registered"
        )
    }
}
#endif
