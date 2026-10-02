#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReceiverBuilderInferenceTests {
    private let builder = """
    class Builder<T> {
        fun use(block: () -> T) {}
    }
    fun <R> build(builder: Builder<R>.() -> Unit): R = null as R
    """

    @Test func callbackResultInfersBuilderType() throws {
        try expectIntResult(builder + """

        fun main() {
            val result = build { use { 1 } }
            println(result)
        }
        """)
    }

    @Test func multipleCallbacksAndNestedCallsInferBuilderType() throws {
        try expectIntResult(builder + """

        fun <T> identity(value: T): T = value
        fun main() {
            val result = build {
                use { identity(1) }
                use { 2 }
            }
            println(result + 1)
        }
        """)
    }

    @Test func memberExtensionCallbackInfersBuilderType() throws {
        try expectIntResult("""
        class Clause<T>
        class Choice<R> {
            fun <T> Clause<T>.onResult(block: (T) -> R) {}
        }
        fun <R> choose(builder: Choice<R>.() -> Unit): R = null as R
        fun main() {
            val clause = Clause<Int>()
            val result = choose { clause.onResult { it + 1 } }
            println(result)
        }
        """, callee: "choose")
    }

    @Test func expectedTypeAndExplicitArgumentsRemainSupported() throws {
        try expectIntResult(builder + """

        fun main() {
            val expected: Int = build { use { 1 } }
            val explicit = build<Int> { use { 2 } }
            println(expected + explicit)
        }
        """, callCount: 2)
    }

    @Test func inheritedMemberExtensionUsesDispatchTypeArguments() throws {
        try expectIntResult("""
        class Clause<T>
        open class Choice<R> {
            fun <T> Clause<T>.onResult(block: (T) -> R) {}
        }
        class DerivedChoice<R> : Choice<R>()
        fun <R> choose(builder: DerivedChoice<R>.() -> Unit): R = null as R
        fun main() {
            val clause = Clause<Int>()
            val inferred = choose { clause.onResult { it + 1 } }
            val expected: Int = choose { clause.onResult { it + 2 } }
            val explicit = choose<Int> { clause.onResult { it + 3 } }
            println(inferred + expected + explicit)
        }
        """, callee: "choose", callCount: 3)
    }

    @Test func boundedBuilderRejectsIncompatibleCallback() throws {
        let source = """
        class Builder<T> { fun use(block: () -> T) {} }
        fun <R : Number> build(builder: Builder<R>.() -> Unit): R = null as R
        fun main() { val result = build { use { "wrong" } } }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func expectedTypeRejectsIncompatibleCallback() throws {
        let ctx = makeContextFromSource(builder + """

        fun main() { val result: Int = build { use { "wrong" } } }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func emptyBuilderStillReportsUninferredType() throws {
        let ctx = makeContextFromSource(builder + """

        fun main() { val result = build {} }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-INFER", in: ctx)
    }

    private func expectIntResult(_ source: String, callee: String = "build", callCount: Int = 1) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let calls = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(calleeID, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(calleeID)
                else { return false }
                return ctx.interner.resolve(name) == callee
            }
            #expect(calls.count == callCount)
            #expect(calls.allSatisfy { sema.bindings.exprType(for: $0) == sema.types.intType })
        }
    }
}
#endif
