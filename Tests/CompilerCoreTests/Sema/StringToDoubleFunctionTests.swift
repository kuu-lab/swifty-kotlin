@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-095: Validates that `String.toDouble()` resolves through Sema
/// and links to the runtime bridge `kk_string_toDouble`.
@Suite
struct StringToDoubleFunctionTests {
    @Test func testStringToDoubleResolvesInSource() throws {
        let ctx = makeContextFromSource("""
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
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected String.toDouble() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testStringToDoubleResolvesToRuntimeLink() throws {
        var resolvedLink: String?
        var resolvedReturnType: TypeID?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "text", "toDouble"].map { ctx.interner.intern($0) }
            let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.stringType
                    && signature.parameterTypes.isEmpty
            })
            resolvedLink = sema.symbols.externalLinkName(for: symbol)
            resolvedReturnType = sema.symbols.functionSignature(for: symbol)?.returnType
            #expect(
                resolvedReturnType == sema.types.doubleType,
                "String.toDouble() should return Double"
            )
        }
        #expect(resolvedLink == "kk_string_toDouble")
    }

    @Test func testStringToDoubleCallBindsToRuntimeBridge() throws {
        let source = """
        fun parse(value: String): Double {
            return value.toDouble()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            // Exclude bundled stdlib source (e.g. kotlin.random.Random's own
            // `Long.toDouble()` call in doubleFromParts, KSP-466) so this only
            // matches the test's own String-receiver fixture call. Numeric
            // `.toDouble()` widening conversions are compiler intrinsics with no
            // callBinding, unlike the String.toDouble() runtime bridge this test
            // targets, so a bundled numeric toDouble() call being matched first
            // would otherwise make callBinding(for:) nil here.
            let callExpr = try #require(
                firstExprID(in: ast) { exprID, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr,
                          ctx.interner.resolve(callee) == "toDouble",
                          args.isEmpty,
                          let range = ast.arena.exprRange(exprID)
                    else { return false }
                    return !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
                },
                "Expected member call to toDouble() in AST"
            )

            let chosenCallee = try #require(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected call binding for toDouble"
            )
            #expect(
                sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_toDouble",
                "String.toDouble() should resolve to kk_string_toDouble"
            )
        }
    }
}
