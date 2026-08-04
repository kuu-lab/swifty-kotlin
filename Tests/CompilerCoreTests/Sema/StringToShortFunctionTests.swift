#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN-106: `fun String.toShort(): Short` in `kotlin.text`.
///
/// Verifies:
/// - The synthetic stub registered for `String.toShort` links to the runtime
///   symbol `kk_string_toShort_flat` declared in
///   `Sources/RuntimeABI/RuntimeABISpec+ABIParity.swift`.
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
            allLinks.contains("kk_string_toShort"),
            "lookupAll for toShort must include kk_string_toShort; got: \(allLinks)"
        )

        let symbol = try #require(sema.symbols.lookup(fqName: fq))
        #expect(
            sema.symbols.externalLinkName(for: symbol) == "kk_string_toShort",
            "String.toShort should link to kk_string_toShort"
        )
    }
}
#endif
