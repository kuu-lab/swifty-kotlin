#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-006: Validates that `buildString` (kotlin.text inline builder) resolves
/// through Sema and produces `String` return type. The runtime lowers `buildString { }` to
/// `kk_build_string` and the optional capacity overload to `kk_build_string_with_capacity`.
@Suite
struct BuildStringFunctionTests {
    @Test func testBuildStringResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun greeting(): String = buildString {
            append("Hello, ")
            append("world!")
        }

        fun lengthOfBuilt(): Int {
            return buildString { append("abc") }.length
        }

        fun build(): String {
            val s: String = buildString { append("x") }
            return s
        }

        fun withCapacity(): String = buildString(64) {
            append("capacity hint")
        }

        fun withNamedCapacity(): String = buildString(capacity = 16) {
            append("named capacity")
        }

        fun withImplicitReceiver(): String = buildString {
            this.append("explicit this")
            append("implicit")
        }

        fun nested(): String {
            val prefix = "pre"
            return prefix + buildString { append("suffix") }
        }

        fun buildSingle(): String = buildString { append("test") }
        """)

        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "buildString should resolve without errors, got: \(ctx.diagnostics.diagnostics)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let callID = try #require(
            firstExprID(in: ast) { _, expr in
                guard case let .call(calleeID, _, _, _) = expr,
                      let calleeExpr = ast.arena.expr(calleeID),
                      case let .nameRef(name, _) = calleeExpr
                else { return false }
                return ctx.interner.resolve(name) == "buildString"
            },
            "Expected a call to buildString in the AST"
        )

        let kind = sema.bindings.builderDSLKind(for: callID)
        #expect(kind == nil, "buildString should not be treated as a builder DSL")
    }
}
#endif
