@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-054: Validates that `String.repeat(n)` resolves through
/// Sema for plain String receivers as well as literal / expression contexts.
/// The runtime link involved is `kk_string_repeat_flat`
/// (see `Sources/Runtime/RuntimeStringStdlib.swift`).
@Suite
struct StringRepeatFunctionTests {
    @Test func testStringRepeatResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun repeatTwice(s: String): String {
            return s.repeat(2)
        }

        fun repeatLiteral(): String {
            return "ab".repeat(3)
        }

        fun repeatZero(s: String): String {
            return s.repeat(0)
        }

        fun repeatWithExpression(s: String, n: Int): String {
            return s.repeat(n + 1)
        }

        fun repeatInConcatenation(s: String): String {
            return "[" + s.repeat(2) + "]"
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected String.repeat(n) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testStringRepeatResolvesToBundledKotlinSymbol() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "text", "repeat"].map { ctx.interner.intern($0) }
            let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.stringType
                    && signature.parameterTypes == [sema.types.intType]
            })
            #expect(
                sema.symbols.externalLinkName(for: symbol) == nil,
                "String.repeat(n) is now a bundled Kotlin function and must not have a C external link"
            )
            #expect(
                sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.stringType,
                "String.repeat(n) should return String"
            )
        }
    }

    @Test func testStringRepeatCallBindingResolvesToBundledKotlinSymbol() throws {
        let source = """
        fun makeBanner(token: String): String {
            return token.repeat(4)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "repeat"
            }, "Expected a member call to repeat in the AST")

            let chosenCallee = try #require(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected a call binding for the repeat invocation"
            )
            #expect(
                sema.symbols.externalLinkName(for: chosenCallee) == nil,
                "String.repeat(n) is now a bundled Kotlin function and must not have a C external link"
            )
        }
    }
}
