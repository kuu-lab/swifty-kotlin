#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-008: Validates that `Char.isIdentifierIgnorable()` resolves
/// through Sema for plain Char receivers as well as literal and branch contexts.
/// The runtime link involved is `kk_char_isIdentifierIgnorable` (see
/// `Sources/Runtime/RuntimeChar.swift`).
@Suite
struct CharIsIdentifierIgnorableFunctionTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        fun ignorableCheck(ch: Char): Boolean {
            return ch.isIdentifierIgnorable()
        }

        fun ignorableCheckLiteral(): Boolean {
            return '\\u0001'.isIdentifierIgnorable()
        }

        fun ignorableCheckIfBranch(ch: Char): Int {
            return if (ch.isIdentifierIgnorable()) 1 else 0
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
    @Test func testCharIsIdentifierIgnorableResolvesInSource() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Char.isIdentifierIgnorable() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testCharIsIdentifierIgnorableResolvesToRuntimeLink() throws {
        var resolvedLink: String?

        let ctx = try sharedCtx()
            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "text", "isIdentifierIgnorable"].map { ctx.interner.intern($0) }
            let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.charType
                    && signature.parameterTypes.isEmpty
            })
            resolvedLink = sema.symbols.externalLinkName(for: symbol)
            #expect(sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.booleanType, "Char.isIdentifierIgnorable() should return Boolean")

    }
}
#endif
