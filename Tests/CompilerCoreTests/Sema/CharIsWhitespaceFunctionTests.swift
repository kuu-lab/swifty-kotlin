#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-019: Validates that `Char.isWhitespace()` resolves through Sema
/// for plain Char receivers as well as literal / branch contexts. The runtime
/// link involved is `kk_char_isWhitespace` (see `Sources/Runtime/RuntimeChar.swift`).
@Suite
struct CharIsWhitespaceFunctionTests {
    @Test func testCharIsWhitespaceResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun whitespaceCheck(ch: Char): Boolean {
            return ch.isWhitespace()
        }

        fun whitespaceCheckLiteral(): Boolean {
            return ' '.isWhitespace()
        }

        fun whitespaceCheckTab(): Boolean {
            return '\t'.isWhitespace()
        }

        fun whitespaceCheckNonWhitespace(): Boolean {
            return 'A'.isWhitespace()
        }

        fun whitespaceCheckIfBranch(ch: Char): Int {
            return if (ch.isWhitespace()) 1 else 0
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Char.isWhitespace() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testCharIsWhitespaceResolvesToRuntimeLink() throws {
        var resolvedLink: String?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "text", "isWhitespace"].map { ctx.interner.intern($0) }
            let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.charType
                    && signature.parameterTypes.isEmpty
            })
            resolvedLink = sema.symbols.externalLinkName(for: symbol)
            #expect(sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.booleanType, "Char.isWhitespace() should return Boolean")
        }
        #expect(resolvedLink == "kk_char_isWhitespace")
    }

    @Test func testCharIsWhitespaceResolvesAtCallSite() throws {
        let ctx = makeContextFromSource("""
        fun probe(ch: Char) {
            ch.isWhitespace()
        }
        """)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let callExpr = try #require(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "isWhitespace"
        }, "Expected member call to isWhitespace in AST")

        #expect(sema.bindings.exprTypes[callExpr] != sema.types.errorType)
        #expect(sema.bindings.exprTypes[callExpr] == sema.types.booleanType)

        let chosen = sema.bindings.callBinding(for: callExpr)?.chosenCallee
            ?? sema.bindings.identifierSymbol(for: callExpr)
        #expect(chosen.flatMap { sema.symbols.externalLinkName(for: $0) } == "kk_char_isWhitespace")
    }
}
#endif
