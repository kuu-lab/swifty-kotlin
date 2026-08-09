#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-021: Validates that `kotlin.text.titlecase` resolves through
/// Sema as a `Char` extension (Kotlin spec defines it as
/// `fun Char.titlecase(): String`). The related no-arg `titlecaseChar()`
/// overload returning `Char` is also exposed. KSP-662 以降は bundled Kotlin
/// (kotlin.text.CharConversions) 実装のため、合成スタブの外部リンクを持たない。
@Suite
struct CharTitlecaseFunctionTests {
    @Test func testTitlecaseResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun titlecaseOfLiteral(): String {
            return 'a'.titlecase()
        }

        fun toTitle(ch: Char): String {
            return ch.titlecase()
        }

        fun toTitleChar(ch: Char): Char {
            return ch.titlecaseChar()
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected titlecase/titlecaseChar to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let titlecaseFQ = ["kotlin", "text", "titlecase"].map { interner.intern($0) }
        let titlecaseSymbol = try #require(
            sema.symbols.lookupAll(fqName: titlecaseFQ).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == sema.types.charType
                    && signature.parameterTypes.isEmpty
            },
            "Char.titlecase() must be registered as an extension function"
        )
        #expect(sema.symbols.externalLinkName(for: titlecaseSymbol) == nil)

        let titlecaseSignature = try #require(sema.symbols.functionSignature(for: titlecaseSymbol))
        #expect(titlecaseSignature.returnType == sema.types.stringType, "Char.titlecase() should return String per Kotlin spec")

        let titlecaseCharFQ = ["kotlin", "text", "titlecaseChar"].map { interner.intern($0) }
        let titlecaseCharSymbol = try #require(
            sema.symbols.lookupAll(fqName: titlecaseCharFQ).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == sema.types.charType
                    && signature.parameterTypes.isEmpty
            },
            "Char.titlecaseChar() must be registered as an extension function"
        )
        #expect(sema.symbols.externalLinkName(for: titlecaseCharSymbol) == nil)

        let titlecaseCharSignature = try #require(sema.symbols.functionSignature(for: titlecaseCharSymbol))
        #expect(titlecaseCharSignature.returnType == sema.types.charType, "Char.titlecaseChar() should return Char per Kotlin spec")
    }
}
#endif
