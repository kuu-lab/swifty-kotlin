@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-054: Validates that `String.repeat(n)` resolves through
/// Sema for plain String receivers as well as literal / expression contexts.
/// `String.repeat(n)` is implemented as bundled Kotlin source, not a C runtime
/// external link.
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
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let repeatCall = try #require(
            lastExprID(in: ast) { exprID, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr,
                      let range = ast.arena.exprRange(exprID)
                else { return false }
                return interner.resolve(callee) == "repeat"
                    && args.count == 1
                    && !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
            },
            "Expected member call to repeat in AST"
        )

        let chosenCallee = try #require(
            sema.bindings.callBinding(for: repeatCall)?.chosenCallee,
            "Expected a call binding for the repeat invocation"
        )
        #expect(
            sema.symbols.externalLinkName(for: chosenCallee) == nil,
            "String.repeat(n) is now a bundled Kotlin function and must not have a C external link"
        )

        let fq = ["kotlin", "text", "repeat"].map { interner.intern($0) }
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
