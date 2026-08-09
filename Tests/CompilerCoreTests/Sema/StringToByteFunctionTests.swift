#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-090: Validates that `String.toByte()` and `String.toByte(radix)`
/// resolve through Sema as extension functions in `kotlin.text`.
///
/// - The no-arg overload links to `kk_string_toByte_flat`.
/// - The radix overload links to `kk_string_toByte_radix_flat`.
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
        #expect(allLinks.contains("kk_string_toByte"))
        #expect(allLinks.contains("kk_string_toByte_radix"))
    }
}
#endif
