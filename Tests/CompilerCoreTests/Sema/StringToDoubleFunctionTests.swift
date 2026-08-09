@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-095: Validates that `String.toDouble()` resolves through Sema
/// and links to the runtime bridge `kk_string_toDouble`.
@Suite
struct StringToDoubleFunctionTests {
    @Test func testStringToDoubleResolvesInSource() throws {
        let source = """
        fun parseFromVariable(text: String): Double {
            return text.toDouble()
        }

        fun parseFromLiteral(): Double {
            return "3.14".toDouble()
        }

        fun parseNegative(): Double {
            return "-2.5".toDouble()
        }

        fun parseInExpression(text: String): Double {
            return text.toDouble() + 1.0
        }

        fun parseInIfBranch(text: String): Double {
            return if (text.isNotEmpty()) text.toDouble() else 0.0
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected String.toDouble() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let callExpr = try #require(
            lastExprID(in: ast) { exprID, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr,
                      let range = ast.arena.exprRange(exprID)
                else { return false }
                return interner.resolve(callee) == "toDouble"
                    && args.isEmpty
                    && !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
            },
            "Expected member call to toDouble() in AST"
        )

        let chosenCallee = try #require(
            sema.bindings.callBinding(for: callExpr)?.chosenCallee,
            "Expected call binding for toDouble"
        )
        #expect(
            sema.symbols.externalLinkName(for: chosenCallee) == nil || sema.symbols.externalLinkName(for: chosenCallee)?.isEmpty == true,
            "String.toDouble() should resolve to standard library function (no direct external link)"
        )

        let fq = ["kotlin", "text", "toDouble"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == sema.types.stringType
                && signature.parameterTypes.isEmpty
        })
        #expect(
            sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.doubleType,
            "String.toDouble() should return Double"
        )

        let directLink = sema.symbols.externalLinkName(for: symbol)
        #expect(directLink == nil || directLink?.isEmpty == true)

        let privateFq = ["kotlin", "text", "__kk_string_toDouble"].map { interner.intern($0) }
        let privateSymbol = sema.symbols.lookup(fqName: privateFq)
        #expect(privateSymbol != nil)
        #expect(sema.symbols.externalLinkName(for: privateSymbol!) == "__kk_string_toDouble")
    }
}
