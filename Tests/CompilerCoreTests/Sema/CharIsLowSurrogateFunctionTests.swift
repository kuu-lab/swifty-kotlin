#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-014: Validates that `Char.isLowSurrogate()` resolves through
/// Sema for plain Char receivers as well as literal / branch contexts.
/// KSP-663: This is now a bundled Kotlin source function in kotlin.text
/// (no synthetic `kk_char_isLowSurrogate` runtime link).
@Suite
struct CharIsLowSurrogateFunctionTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        fun lowSurrogateCheck(ch: Char): Boolean {
            return ch.isLowSurrogate()
        }

        fun lowSurrogateCheckLiteralLow(): Boolean {
            return '\\uDC00'.isLowSurrogate()
        }

        fun lowSurrogateCheckLiteralHigh(): Boolean {
            return '\\uD800'.isLowSurrogate()
        }

        fun lowSurrogateCheckLiteralPlain(): Boolean {
            return 'A'.isLowSurrogate()
        }

        fun lowSurrogateCheckIfBranch(ch: Char): Int {
            return if (ch.isLowSurrogate()) 1 else 0
        }
        """,
        """
        package sample1
        fun noop() {}
        """
    ]

    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.sharedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }
    @Test func testCharIsLowSurrogateResolvesInSource() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Char.isLowSurrogate() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testCharIsLowSurrogateResolvesToSourceFunction() throws {
        let ctx = try sharedCtx()
        let sema = try #require(ctx.sema)
        let fq = ["kotlin", "text", "isLowSurrogate"].map { ctx.interner.intern($0) }
        let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == sema.types.charType
                && signature.parameterTypes.isEmpty
        })
        #expect(sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.booleanType, "Char.isLowSurrogate() should return Boolean")
        #expect(sema.symbols.symbol(symbol)?.declSite != nil, "Char.isLowSurrogate() should be backed by Kotlin source")
        #expect(sema.symbols.externalLinkName(for: symbol) == nil, "Char.isLowSurrogate() should have no C external link")
    }
}
#endif
