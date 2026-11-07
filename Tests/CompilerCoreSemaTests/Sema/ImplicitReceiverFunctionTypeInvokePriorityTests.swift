#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// KUU-4310: on a function-typed implicit receiver, unqualified
/// `invoke(args)` is the implicit-receiver member `this.invoke`. Kotlin's
/// call tower resolves receiver members before package/import/star-import
/// scope tiers, so an *applicable* scope-level `invoke` must not win merely
/// by resolving — the KUU-4271 fallback only covers scope candidates that
/// all fail. When `this.invoke` itself is inapplicable the tower continues
/// outward and the scope candidate still wins.
@Suite
struct ImplicitReceiverFunctionTypeInvokePriorityTests {
    @Test
    func applicableScopeInvokeYieldsToFunctionTypeReceiverInvoke() throws {
        let scope = """
        package a
        fun invoke(x: Int): String = "scope:$x"
        """
        let use = """
        package b
        import a.*
        fun ((Int) -> Unit).callIt() {
            val r = invoke(5)
            val check: Unit = r
        }
        """
        try withTemporaryFiles(contents: [scope, use]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(nameRefCallExprID(named: "invoke", in: ast, interner: ctx.interner))
            #expect(sema.bindings.exprType(for: call) == sema.types.unitType)
            #expect(sema.bindings.callableValueCallBinding(for: call)?.implicitInvokeReceiverExpr != nil)
        }
    }

    @Test
    func samePackageScopeInvokeYieldsToFunctionTypeReceiverInvoke() throws {
        let source = """
        package b
        fun invoke(x: Int): String = "scope:$x"
        fun ((Int) -> Unit).callIt() {
            val r = invoke(5)
            val check: Unit = r
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(nameRefCallExprID(named: "invoke", in: ast, interner: ctx.interner))
            #expect(sema.bindings.exprType(for: call) == sema.types.unitType)
        }
    }

    /// The receiver-tier candidate only wins while it is applicable: an
    /// argument `this.invoke` cannot accept continues the tower outward to
    /// the scope `invoke` (kotlinc resolves `invoke("x")` here to
    /// `a.invoke(String): String`).
    @Test
    func inapplicableReceiverInvokeFallsThroughToScopeInvoke() throws {
        let scope = """
        package a
        fun invoke(x: String): String = "scope:$x"
        """
        let use = """
        package b
        import a.*
        fun ((Int) -> Unit).callIt() {
            val r = invoke("x")
            val check: String = r
        }
        """
        try withTemporaryFiles(contents: [scope, use]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(nameRefCallExprID(named: "invoke", in: ast, interner: ctx.interner))
            #expect(sema.bindings.exprType(for: call) == sema.types.stringType)
        }
    }

    /// kotlinc keeps the receiver-tier candidate even when its return type
    /// mismatches the expected type — the error surfaces at the use site,
    /// not by falling through to a scope overload.
    @Test
    func expectedTypeMismatchKeepsReceiverInvoke() throws {
        let scope = """
        package a
        fun invoke(x: Int): String = "scope:$x"
        """
        let use = """
        package b
        import a.*
        fun ((Int) -> Unit).callIt() {
            val s: String = invoke(5)
        }
        """
        try withTemporaryFiles(contents: [scope, use]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(nameRefCallExprID(named: "invoke", in: ast, interner: ctx.interner))
            #expect(sema.bindings.exprType(for: call) == sema.types.unitType)
        }
    }

    /// A local function named `invoke` occupies a nearer tower level than
    /// the implicit receiver and keeps its priority.
    @Test
    func localFunctionInvokeKeepsPrecedence() throws {
        let source = """
        package b
        fun ((Int) -> Unit).callIt() {
            fun invoke(x: Int): String = "local:$x"
            val r = invoke(5)
            val check: String = r
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(nameRefCallExprID(named: "invoke", in: ast, interner: ctx.interner))
            #expect(sema.bindings.exprType(for: call) == sema.types.stringType)
        }
    }

    /// A local function-typed value named `invoke` shadows the receiver
    /// member the same way.
    @Test
    func localValueInvokeKeepsPrecedence() throws {
        let source = """
        package b
        fun ((Int) -> Unit).callIt() {
            val invoke: (Int) -> String = { "local:$it" }
            val r = invoke(5)
            val check: String = r
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(nameRefCallExprID(named: "invoke", in: ast, interner: ctx.interner))
            #expect(sema.bindings.exprType(for: call) == sema.types.stringType)
        }
    }

    /// KUU-4209: inside a nested lambda that supplies its own receiver, an
    /// unqualified `invoke(...)` still reaches the *outer* function-typed
    /// receiver — the `flow { emit(invoke()) }` shape of kotlinx-coroutines'
    /// `(() -> T).asFlow()`. The binding must record a labeled `this` so KIR
    /// captures the outer receiver instead of reading the innermost `this`.
    @Test
    func invokeResolvesOnOuterFunctionTypedReceiverInsideNestedLambda() throws {
        let source = """
        package b
        class Box
        fun (() -> Int).callInLambda(block: Box.() -> Unit): Int {
            var result = -1
            val l: Box.() -> Unit = { result = invoke() }
            l(Box())
            return result
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(nameRefCallExprID(named: "invoke", in: ast, interner: ctx.interner))
            #expect(sema.bindings.exprType(for: call) == sema.types.intType)
            let binding = try #require(sema.bindings.callableValueCallBinding(for: call))
            let receiverExpr = try #require(binding.implicitInvokeReceiverExpr)
            guard case let .thisRef(label, _) = ast.arena.expr(receiverExpr) else {
                Issue.record("expected synthesized thisRef, got \(String(describing: ast.arena.expr(receiverExpr)))")
                return
            }
            #expect(label != nil)
        }
    }

    /// The innermost function-typed receiver still wins when the tower
    /// holds function-typed receivers at several levels.
    @Test
    func innermostFunctionTypedReceiverInvokeWins() throws {
        let source = """
        package b
        class Box
        fun (() -> Int).outer(block: (() -> Int).() -> Unit): Int {
            var result = -1
            val l: (() -> Int).() -> Unit = { result = invoke() + invoke() }
            l({ 20 })
            return result
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let calls = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      let calleeExpr = ast.arena.expr(callee),
                      case let .nameRef(name, _) = calleeExpr
                else { return false }
                return ctx.interner.resolve(name) == "invoke"
            }
            #expect(calls.count == 2)
            for call in calls {
                let binding = try #require(sema.bindings.callableValueCallBinding(for: call))
                let receiverExpr = try #require(binding.implicitInvokeReceiverExpr)
                // Both invokes target the lambda's own `() -> Int` receiver,
                // so the synthesized this must be unlabeled.
                guard case let .thisRef(label, _) = ast.arena.expr(receiverExpr) else {
                    Issue.record("expected synthesized thisRef")
                    return
                }
                #expect(label == nil)
            }
        }
    }
}
#endif
