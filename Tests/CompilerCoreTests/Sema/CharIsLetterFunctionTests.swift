#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-011: Validates that `Char.isLetter()` resolves through Sema
/// and links to the runtime helper `kk_char_isLetter`.
@Suite
struct CharIsLetterFunctionTests {
    @Test func testCharIsLetterResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun probe(ch: Char): Boolean {
            return ch.isLetter()
        }

        fun probeLiteral(): Boolean {
            return 'a'.isLetter()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Char.isLetter() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testCharIsLetterStubHasCorrectExternalLink() throws {
        var capturedSema: SemaModule?
        var capturedInterner: StringInterner?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            capturedSema = try #require(ctx.sema)
            capturedInterner = ctx.interner
        }
        let sema = try #require(capturedSema)
        let interner = try #require(capturedInterner)

        let fq = ["kotlin", "text", "isLetter"].map { interner.intern($0) }
        let sym = try #require(
            sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.charType
                    && signature.parameterTypes.isEmpty
            },
            "Expected synthetic kotlin.text.isLetter extension on Char"
        )
        #expect(sema.symbols.externalLinkName(for: sym) == "kk_char_isLetter")
    }
}
#endif
