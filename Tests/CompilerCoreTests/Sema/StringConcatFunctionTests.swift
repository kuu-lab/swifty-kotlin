@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-011: Validates that `String.concat(str)` resolves through
/// Sema for plain String receivers as well as literal / expression contexts.
/// The runtime link involved is `kk_string_concat_flat`.
@Suite
struct StringConcatFunctionTests {
    @Test func testStringConcatResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun concatTwo(a: String, b: String): String {
            return a.concat(b)
        }

        fun concatLiteral(): String {
            return "Hello".concat(" World")
        }

        fun concatEmpty(s: String): String {
            return s.concat("")
        }

        fun concatChained(a: String, b: String, c: String): String {
            return a.concat(b).concat(c)
        }
        """)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let concatCall = try #require(
            lastExprID(in: ast) { exprID, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr,
                      let range = ast.arena.exprRange(exprID)
                else { return false }
                return interner.resolve(callee) == "concat"
                    && args.count == 1
                    && !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
            },
            "Expected a member call to concat in the AST"
        )

        let chosenCallee = try #require(
            sema.bindings.callBinding(for: concatCall)?.chosenCallee,
            "Expected a call binding for the concat invocation"
        )
        #expect(
            sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_concat_flat",
            "String.concat(str) member call must resolve to kk_string_concat_flat"
        )

        let fq = ["kotlin", "text", "concat"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == sema.types.stringType
                && signature.parameterTypes == [sema.types.stringType]
        })
        #expect(
            sema.symbols.externalLinkName(for: symbol) == "kk_string_concat_flat"
        )
        #expect(
            sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.stringType,
            "String.concat(str) should return String"
        )
    }
}
