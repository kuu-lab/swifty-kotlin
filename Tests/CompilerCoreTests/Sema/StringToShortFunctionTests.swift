#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN-106: `fun String.toShort(): Short` in `kotlin.text`.
///
/// Verifies:
/// - `String.toShort` is source-backed after KSP-414 and no longer exposes a
///   public `kk_string_toShort` runtime link; it bridges through the private
///   `__kk_string_toShort` runtime symbol.
/// - The extension resolves cleanly from source code on both a parameter
///   receiver and a string-literal receiver (Short is widened to Int in ABI).
@Suite
struct StringToShortFunctionTests {
    @Test
    func testToShortResolvesInSource() throws {
        let source = """
        fun parse(raw: String): Short {
            return raw.toShort()
        }

        fun probe(): Int {
            return "1000".toShort().toInt()
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let fq = ["kotlin", "text", "toShort"].map { interner.intern($0) }
        let allLinks = Set(sema.symbols.lookupAll(fqName: fq).compactMap { sema.symbols.externalLinkName(for: $0) })
        #expect(
            !allLinks.contains("kk_string_toShort") && !allLinks.contains("__kk_string_toShort"),
            "lookupAll for toShort must not include public or private string parse links; got: \(allLinks)"
        )

        let symbol = try #require(sema.symbols.lookup(fqName: fq))
        #expect(
            sema.symbols.externalLinkName(for: symbol) == nil,
            "String.toShort should be source-backed and have no C external link"
        )

        let bridgeFq = ["kotlin", "text", "__kk_string_toShort"].map { interner.intern($0) }
        #expect(
            sema.symbols.externalLinkName(for: try #require(sema.symbols.lookup(fqName: bridgeFq))) == "__kk_string_toShort",
            "Private __kk_string_toShort bridge should be registered"
        )
    }
}
#endif
