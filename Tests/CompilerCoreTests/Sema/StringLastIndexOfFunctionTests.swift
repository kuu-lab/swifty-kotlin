@testable import CompilerCore
import Testing

/// KSP-408: Validates that `CharSequence.lastIndexOf` resolves through Sema for
/// the (Char, startIndex, ignoreCase) overload alongside the String overloads
/// (bundled Kotlin source, `StringIndexOf.kt`).
@Suite
struct StringLastIndexOfFunctionTests {
    @Test func testStringSearchDefaultArgumentsAndImplicitReceiverResolve() throws {
        let ctx = makeContextFromSource("""
        fun String.findDelimiter(delimiter: String): Int {
            return indexOf(delimiter)
        }

        fun lastChar(value: String): Int {
            return value.lastIndexOf('l')
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected implicit String receiver and lastIndexOf(Char) defaults to resolve, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testLastIndexOfCharResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun findChar(value: CharSequence): Int {
            return value.lastIndexOf('o', 10, false)
        }

        fun findCharIgnoreCase(value: String): Int {
            return value.lastIndexOf('O', 10, true)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected CharSequence.lastIndexOf(Char, Int, Boolean) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testLastIndexOfCharReturnsInt() throws {
        let source = """
        fun probe(value: CharSequence): Int {
            return value.lastIndexOf('z', 0, false)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected CharSequence.lastIndexOf(Char,...) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callExpr = try #require(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "lastIndexOf"
        }, "Expected lastIndexOf member call")
        #expect(sema.bindings.exprType(for: callExpr) == sema.types.intType)
    }
}
