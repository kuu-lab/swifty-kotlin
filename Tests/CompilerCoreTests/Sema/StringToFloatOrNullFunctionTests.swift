@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN-098: `fun String.toFloatOrNull(): Float?` in `kotlin.text`.
///
/// Verifies:
/// - The synthetic stub registered for `String.toFloatOrNull` links to the
///   runtime symbol `kk_string_toFloatOrNull` declared in
///   `Sources/RuntimeABI/RuntimeABISpec+String.swift`.
/// - The extension resolves cleanly from source code and produces no Sema
///   diagnostics for a call returning `Float?`.
@Suite
struct StringToFloatOrNullFunctionTests {
    @Test
    func testToFloatOrNullResolvesAndLinksToRuntimeSymbol() throws {
        let ctx = makeContextFromSource("""
        fun parse(raw: String): Float? {
            return raw.toFloatOrNull()
        }

        fun safeParse(raw: String): Float {
            return raw.toFloatOrNull() ?: 0.0f
        }
        """)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected String.toFloatOrNull to resolve")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let directFq = ["kotlin", "text", "toFloatOrNull"].map { interner.intern($0) }
        let directSymbol = try #require(
            sema.symbols.lookupAll(fqName: directFq).first { symbolID in
                guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                return sig.receiverType == sema.types.stringType && sig.parameterTypes.isEmpty
            }
        )
        let directLink = sema.symbols.externalLinkName(for: directSymbol)
        #expect(
            directLink == nil || directLink?.isEmpty == true,
            "String.toFloatOrNull should be source-backed and not have a direct external link"
        )

        let returnType = try #require(sema.symbols.functionSignature(for: directSymbol)?.returnType)
        #expect(
            returnType == sema.types.make(.primitive(.float, .nullable)),
            "String.toFloatOrNull() should return Float?"
        )

        let privateFq = ["kotlin", "text", "__kk_string_toFloatOrNull"].map { interner.intern($0) }
        let privateSymbol = sema.symbols.lookup(fqName: privateFq)
        #expect(
            sema.symbols.externalLinkName(for: privateSymbol!) == "__kk_string_toFloatOrNull",
            "__kk_string_toFloatOrNull should link to __kk_string_toFloatOrNull"
        )
    }
}
