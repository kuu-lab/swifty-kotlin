#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-008: Validates that `buildStringBuilder` resolves as a
/// StringBuilder-returning builder DSL.
@Suite
struct BuildStringBuilderFunctionTests {
    @Test func testBuildStringBuilderResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun greeting(): StringBuilder = buildStringBuilder {
            append("Hello")
            appendLine()
            append("world")
        }

        fun build(): String {
            val sb: StringBuilder = buildStringBuilder { append("abc") }
            sb.append("d")
            return sb.toString()
        }

        fun buildWithCapacity(): StringBuilder = buildStringBuilder(capacity = 16) {
            append("capacity")
        }

        fun buildSingle(): StringBuilder = buildStringBuilder { append("test") }
        """)

        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "buildStringBuilder should resolve without errors, got: \(ctx.diagnostics.diagnostics)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let callID = try #require(
            firstExprID(in: ast) { _, expr in
                guard case let .call(calleeID, _, _, _) = expr,
                      let calleeExpr = ast.arena.expr(calleeID),
                      case let .nameRef(name, _) = calleeExpr
                else { return false }
                return ctx.interner.resolve(name) == "buildStringBuilder"
            },
            "Expected a call to buildStringBuilder in the AST"
        )

        let kind = sema.bindings.builderDSLKind(for: callID)
        #expect(kind == nil, "buildStringBuilder should not be treated as a builder DSL")
    }
}
#endif
