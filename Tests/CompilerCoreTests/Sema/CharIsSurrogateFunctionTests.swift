#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-015: Validates that `Char.isSurrogate()` resolves through
/// Sema for plain Char receivers as well as literal / branch contexts. The
/// runtime link involved is `kk_char_isSurrogate` (see
/// `Sources/Runtime/RuntimeChar.swift`), which returns true for the entire
/// surrogate range `[0xD800, 0xDFFF]`.
@Suite
struct CharIsSurrogateFunctionTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        fun surrogateCheck(ch: Char): Boolean {
            return ch.isSurrogate()
        }

        fun surrogateCheckHighLiteral(): Boolean {
            return '\\uD800'.isSurrogate()
        }

        fun surrogateCheckLowLiteral(): Boolean {
            return '\\uDFFF'.isSurrogate()
        }

        fun surrogateCheckNonSurrogate(): Boolean {
            return 'A'.isSurrogate()
        }

        fun surrogateCheckIfBranch(ch: Char): Int {
            return if (ch.isSurrogate()) 1 else 0
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
    @Test func testCharIsSurrogateResolvesInSource() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Char.isSurrogate() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testCharIsSurrogateResolvesToRuntimeLink() throws {
        var resolvedLink: String?

        let ctx = try sharedCtx()
            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "text", "isSurrogate"].map { ctx.interner.intern($0) }
            let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.charType
                    && signature.parameterTypes.isEmpty
            })
            resolvedLink = sema.symbols.externalLinkName(for: symbol)
            #expect(sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.booleanType, "Char.isSurrogate() should return Boolean")

    }
}
#endif
