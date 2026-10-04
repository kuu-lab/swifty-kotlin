#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct WhenConditionKeyTests {
    private func conditionLists(in ctx: CompilationContext) throws -> [[ExprID]] {
        let ast = try #require(ctx.ast)
        let path = try #require(ctx.options.inputs.first)
        return allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
            if case .whenExpr = expr { return true }
            return false
        }.compactMap { id in
            guard case let .whenExpr(_, branches, _, _) = ast.arena.expr(id) else { return nil }
            return branches.flatMap(\.conditions)
        }
    }

    private func key(for id: ExprID, in ctx: CompilationContext) throws -> String? {
        whenConditionKey(
            for: id, ast: try #require(ctx.ast), sema: try #require(ctx.sema), interner: ctx.interner
        )
    }

    private func deduplicated(_ conditions: [ExprID], in ctx: CompilationContext) throws -> [ExprID] {
        deduplicateWhenConditions(
            conditions, ast: try #require(ctx.ast), sema: try #require(ctx.sema), interner: ctx.interner
        )
    }

    @Test func inheritedPropertiesOnDistinctObjectsHaveDistinctKeys() throws {
        let ctx = makeContextFromSource("""
        open class M(val value: String) {
            object Get : M("GET")
            object Post : M("POST")
            companion object {
                fun parse(method: String): M = when (method) {
                    Get.value -> Get
                    Post.value -> Post
                    else -> M(method)
                }
            }
        }
        fun supported(method: String): Boolean = when (method) {
            M.Get.value, M.Post.value -> true
            else -> false
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        assertNoDiagnostic("KSWIFTK-SEMA-0072", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0073", in: ctx)

        let lists = try conditionLists(in: ctx)
        #expect(lists.count == 2)
        let sema = try #require(ctx.sema)
        for conditions in lists {
            #expect(conditions.count == 2)
            let first = try #require(conditions.first)
            let last = try #require(conditions.last)
            #expect(sema.bindings.identifierSymbols[first] == sema.bindings.identifierSymbols[last])
            #expect(try #require(key(for: first, in: ctx)) != #require(key(for: last, in: ctx)))
            #expect(try deduplicated(conditions, in: ctx) == conditions)
        }
    }

    @Test func distinctLocalAndNestedPropertyReceiversAreNotDeduplicated() throws {
        let ctx = makeContextFromSource("""
        class M(val value: String)
        class Holder(val method: M)
        fun direct(x: String, left: M, right: M): Int = when (x) {
            left.value -> 1
            right.value -> 2
            else -> 0
        }
        fun nested(x: String, left: Holder, right: Holder): Int = when (x) {
            left.method.value, right.method.value -> 1
            else -> 0
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        assertNoDiagnostic("KSWIFTK-SEMA-0072", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0073", in: ctx)

        let lists = try conditionLists(in: ctx)
        #expect(lists.count == 2)
        for conditions in lists {
            #expect(conditions.count == 2)
            let keys = try conditions.map { try #require(key(for: $0, in: ctx)) }
            #expect(Set(keys).count == 2)
            #expect(try deduplicated(conditions, in: ctx) == conditions)
        }
    }

    @Test func repeatedPropertyOnSameReceiverStillReportsDuplicates() throws {
        let ctx = makeContextFromSource("""
        open class M(val value: String) {
            object Get : M("GET")
        }
        fun classify(x: String): Int = when (x) {
            M.Get.value, M.Get.value -> 1
            M.Get.value -> 2
            else -> 0
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        assertHasDiagnostic("KSWIFTK-SEMA-0072", in: ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0073", in: ctx)

        let conditions = try #require(conditionLists(in: ctx).first)
        #expect(conditions.count == 3)
        #expect(try deduplicated(conditions, in: ctx) == [conditions[0]])
    }

    @Test(arguments: [
        """
        import Color.Red
        enum class Color { Red, Blue }
        fun classify(x: Color): Int = when (x) {
            Color.Red, Red -> 1
            Color.Red -> 2
            else -> 0
        }
        """,
        """
        import State.Ready
        sealed class State {
            object Ready : State()
        }
        fun classify(x: State): Int = when (x) {
            State.Ready, Ready -> 1
            State.Ready -> 2
            else -> 0
        }
        """,
        """
        import Tokens.value
        object Tokens { const val value: String = "GET" }
        fun classify(x: String): Int = when (x) {
            Tokens.value, value -> 1
            Tokens.value -> 2
            else -> 0
        }
        """,
    ])
    func qualifiedAndImportedSingletonValuesKeepSymbolIdentity(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        assertHasDiagnostic("KSWIFTK-SEMA-0072", in: ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0073", in: ctx)

        let conditions = try #require(conditionLists(in: ctx).first)
        #expect(conditions.count == 3)
        #expect(try deduplicated(conditions, in: ctx) == [conditions[0]])
    }

    @Test func arbitraryReceiverExpressionsAndCallsHaveNoCanonicalKey() throws {
        let ctx = makeContextFromSource("""
        class M(val value: String)
        fun method(value: String): M = M(value)
        object Factory {
            fun next(): String = "GET"
        }
        fun classify(x: String): Int = when (x) {
            method("GET").value, method("POST").value -> 1
            Factory.next(), Factory.next() -> 2
            else -> 0
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        assertNoDiagnostic("KSWIFTK-SEMA-0072", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0073", in: ctx)

        let conditions = try #require(conditionLists(in: ctx).first)
        #expect(conditions.count == 4)
        for condition in conditions {
            #expect(try key(for: condition, in: ctx) == nil)
        }
        #expect(try deduplicated(conditions, in: ctx) == conditions)
    }
}
#endif
