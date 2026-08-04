#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-053 / KSP-404: Validates that both overloads of
/// `kotlin.text.removeSurrounding` resolve through Sema for `String` receivers.
/// Both overloads are bundled Kotlin source
/// (`Stdlib/kotlin/text/StringPrefixSuffix.kt`) and carry no runtime external link.
@Suite
struct StringRemoveSurroundingFunctionTests {
    @Test func testRemoveSurroundingResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stripBrackets(s: String): String {
            return s.removeSurrounding("[")
        }

        fun stripTripleAsterisk(): String {
            return "***star***".removeSurrounding("***")
        }

        fun stripExactMatch(): String {
            return "ab".removeSurrounding("ab")
        }

        fun stripNoMatchSingle(s: String): String {
            return "abc".removeSurrounding("ab")
        }

        fun stripChained(s: String): String {
            return s.removeSurrounding("(").removeSurrounding(")")
        }

        fun stripDiv(s: String): String {
            return s.removeSurrounding("<div>", "</div>")
        }

        fun stripBracketItem(): String {
            return "[item]".removeSurrounding("[", "]")
        }

        fun stripNoMatchPair(): String {
            return "no-match".removeSurrounding("<", ">")
        }

        fun stripFromExpression(value: Int): String {
            return value.toString().removeSurrounding("(", ")")
        }
        """)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let fq = ["kotlin", "text", "removeSurrounding"].map { ctx.interner.intern($0) }
        let symbols = sema.symbols.lookupAll(fqName: fq)

        let oneArgSymbol = try #require(symbols.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == sema.types.stringType
                && signature.parameterTypes.count == 1
                && signature.returnType == sema.types.stringType
        })
        #expect(
            sema.symbols.externalLinkName(for: oneArgSymbol) == nil,
            "String.removeSurrounding(delimiter) should be source-backed after KSP-404"
        )

        let twoArgSymbol = try #require(symbols.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == sema.types.stringType
                && signature.parameterTypes.count == 2
                && signature.returnType == sema.types.stringType
        })
        #expect(
            sema.symbols.externalLinkName(for: twoArgSymbol) == nil,
            "String.removeSurrounding(prefix, suffix) should be source-backed after KSP-404"
        )
    }
}
#endif
