#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-005 / KSP-661: Validates that `Char.isDigit()` resolves
/// through Sema for plain Char receivers as well as literal / branch contexts.
/// The predicate is implemented in bundled Kotlin (kotlin.text.CharPredicates),
/// so the resolved symbol carries no synthetic runtime link.
@Suite
struct CharIsDigitFunctionTests {
    @Test func testCharIsDigitResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun digitCheck(ch: Char): Boolean {
            return ch.isDigit()
        }

        fun digitCheckLiteral(): Boolean {
            return '7'.isDigit()
        }

        fun digitCheckNonDigit(): Boolean {
            return 'A'.isDigit()
        }

        fun digitCheckIfBranch(ch: Char): Int {
            return if (ch.isDigit()) 1 else 0
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Char.isDigit() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testCharIsDigitResolvesToRuntimeLink() throws {
        var resolvedLink: String?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "text", "isDigit"].map { ctx.interner.intern($0) }
            let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.charType
                    && signature.parameterTypes.isEmpty
            })
            resolvedLink = sema.symbols.externalLinkName(for: symbol)
            #expect(sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.booleanType, "Char.isDigit() should return Boolean")
        }
        // KSP-661: bundled Kotlin 実装へ移行済みのため合成スタブの外部リンクを持たない。
        #expect(resolvedLink == nil)
    }
}
#endif
