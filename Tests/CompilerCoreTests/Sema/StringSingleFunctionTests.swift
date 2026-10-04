@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-066 / KSP-402: validates that String.single() resolves
/// through bundled Kotlin source across multiple call sites.
@Suite
struct StringSingleFunctionTests {
    @Test func testStringSingleResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun singleOf(s: String): Char {
            return s.single()
        }

        fun singleOfLiteral(): Char {
            return "x".single()
        }

        fun singleInBranch(s: String, take: Boolean): Char {
            return if (take) s.single() else "y".single()
        }

        fun callsBoth(s: String): Char {
            val a = s.single()
            val b = "z".single()
            return if (a == b) a else b
        }
        """)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let singleFq = ["kotlin", "text", "single"].map { interner.intern($0) }
        let singleSymbol = try #require(sema.symbols.lookupAll(fqName: singleFq).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == sema.types.stringType
                && signature.parameterTypes.isEmpty
        })
        #expect(sema.symbols.externalLinkName(for: singleSymbol) == nil, "single should be source-backed")
        #expect(sema.symbols.symbol(singleSymbol)?.flags.contains(.synthetic) == false, "single should not be synthetic")
        #expect(sema.symbols.functionSignature(for: singleSymbol)?.returnType == sema.types.charType, "single should return Char")

        let singleOrNullFq = ["kotlin", "text", "singleOrNull"].map { interner.intern($0) }
        let singleOrNullSymbol = try #require(sema.symbols.lookupAll(fqName: singleOrNullFq).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == sema.types.stringType
                && signature.parameterTypes.isEmpty
        })
        #expect(sema.symbols.externalLinkName(for: singleOrNullSymbol) == nil, "singleOrNull should be source-backed")
        #expect(sema.symbols.symbol(singleOrNullSymbol)?.flags.contains(.synthetic) == false, "singleOrNull should not be synthetic")
        #expect(
            sema.symbols.functionSignature(for: singleOrNullSymbol)?.returnType == sema.types.makeNullable(sema.types.charType),
            "singleOrNull should return Char?"
        )
    }
}
