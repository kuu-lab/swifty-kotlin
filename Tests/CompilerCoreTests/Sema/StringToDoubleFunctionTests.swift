@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-095: Validates that `String.toDouble()` resolves through Sema
/// and links to the runtime bridge `kk_string_toDouble`.
final class StringToDoubleFunctionTests: XCTestCase {
    func testStringToDoubleResolvesInSource() throws {
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
        XCTAssertTrue(
            errors.isEmpty,
            "Expected String.toDouble() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testStringToDoubleResolvesToRuntimeLink() throws {
        var resolvedLink: String?
        var resolvedReturnType: TypeID?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fq = ["kotlin", "text", "toDouble"].map { ctx.interner.intern($0) }
            let symbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.stringType
                    && signature.parameterTypes.isEmpty
            })
            resolvedLink = sema.symbols.externalLinkName(for: symbol)
            resolvedReturnType = sema.symbols.functionSignature(for: symbol)?.returnType
            XCTAssertEqual(
                resolvedReturnType,
                sema.types.doubleType,
                "String.toDouble() should return Double"
            )
        }
        XCTAssertEqual(resolvedLink, "kk_string_toDouble")
    }

    func testStringToDoubleCallBindsToRuntimeBridge() throws {
        let source = """
        fun parse(value: String): Double {
            return value.toDouble()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "toDouble" && args.isEmpty
                },
                "Expected member call to toDouble() in AST"
            )

            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected call binding for toDouble"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_string_toDouble",
                "String.toDouble() should resolve to kk_string_toDouble"
            )
        }
    }
}
