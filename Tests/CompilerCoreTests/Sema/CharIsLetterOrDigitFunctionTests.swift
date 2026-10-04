#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-012 / KSP-661: Validates that `Char.isLetterOrDigit()`
/// resolves through Sema. The predicate is implemented in bundled Kotlin
/// (kotlin.text.CharPredicates), so it carries no synthetic runtime link.
@Suite
struct CharIsLetterOrDigitFunctionTests {
    @Test func testCharIsLetterOrDigitResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun probe(ch: Char): Boolean {
            return ch.isLetterOrDigit()
        }

        fun probeLiteralLetter(): Boolean {
            return 'a'.isLetterOrDigit()
        }

        fun probeLiteralDigit(): Boolean {
            return '7'.isLetterOrDigit()
        }

        fun probeLiteralNonLetterOrDigit(): Boolean {
            return '!'.isLetterOrDigit()
        }

        fun probeInBranch(ch: Char): Int {
            return if (ch.isLetterOrDigit()) 1 else 0
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Char.isLetterOrDigit() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let fq = ["kotlin", "text", "isLetterOrDigit"].map { interner.intern($0) }
        let sym = try #require(
            sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.charType
                    && signature.parameterTypes.isEmpty
            },
            "Expected synthetic kotlin.text.isLetterOrDigit extension on Char"
        )
        #expect(sema.symbols.externalLinkName(for: sym) == nil)
        #expect(
            sema.symbols.functionSignature(for: sym)?.returnType == sema.types.booleanType,
            "Char.isLetterOrDigit() should return Boolean"
        )
    }
}
#endif
