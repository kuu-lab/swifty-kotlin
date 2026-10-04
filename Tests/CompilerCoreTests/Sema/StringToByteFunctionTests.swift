#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-090: Validates that `String.toByte()` and `String.toByte(radix)`
/// resolve through Sema as extension functions in `kotlin.text`.
///
/// After KSP-414 the members are source-backed and no longer expose public `kk_`
/// links; they bridge through private `__kk_string_toByte` / `__kk_string_toByte_radix`.
@Suite
struct StringToByteFunctionTests {
    @Test func testToByteResolvesInSource() throws {
        let source = """
        fun parseByte(s: String): Int {
            return s.toByte().toInt()
        }

        fun parseHexByte(s: String): Int {
            return s.toByte(16).toInt()
        }

        fun parseBinaryByte(s: String): Int {
            return s.toByte(2).toInt()
        }

        fun decimal(): Int {
            return "42".toByte().toInt()
        }

        fun hex(): Int {
            return "7f".toByte(16).toInt()
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let fq = ["kotlin", "text", "toByte"].map { interner.intern($0) }
        let allLinks = Set(sema.symbols.lookupAll(fqName: fq).compactMap { sema.symbols.externalLinkName(for: $0) })
        #expect(
            !allLinks.contains("kk_string_toByte") && !allLinks.contains("__kk_string_toByte"),
            "String.toByte should not expose a kk_ or __kk_ external link; got: \(allLinks)"
        )
        #expect(
            !allLinks.contains("kk_string_toByte_radix") && !allLinks.contains("__kk_string_toByte_radix"),
            "String.toByte(radix) should not expose a kk_ or __kk_ external link; got: \(allLinks)"
        )

        let bridgeLinks = Set(
            sema.symbols.lookupAll(fqName: ["kotlin", "text", "__kk_string_toByte"].map { interner.intern($0) })
                .compactMap { sema.symbols.externalLinkName(for: $0) }
            + sema.symbols.lookupAll(fqName: ["kotlin", "text", "__kk_string_toByte_radix"].map { interner.intern($0) })
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        #expect(
            bridgeLinks.contains("__kk_string_toByte") && bridgeLinks.contains("__kk_string_toByte_radix"),
            "Private __kk_string_toByte bridges should be registered; got: \(bridgeLinks)"
        )
    }
}
#endif
