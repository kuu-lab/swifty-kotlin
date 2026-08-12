#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-005 / KSP-661: Validates that `Char.isDigit()` resolves
/// through Sema for plain Char receivers as well as literal / branch contexts.
/// The predicate is implemented in bundled Kotlin (kotlin.text.CharPredicates),
/// so the resolved symbol carries no synthetic runtime link.
@Suite
struct CharIsDigitFunctionTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
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
    @Test func testCharIsDigitResolvesInSource() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Char.isDigit() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testCharIsDigitResolvesToRuntimeLink() throws {
        var resolvedLink: String?

        let ctx = try sharedCtx()
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
}
#endif
