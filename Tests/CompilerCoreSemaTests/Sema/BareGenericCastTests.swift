@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct BareGenericCastTests {
    @Test
    func inheritedMemberExtensionPreservesSourceArguments() throws {
        let ctx = makeContextFromSource("""
        open class Desc<T : Any, R>(val t: T, val defaultValue: R?)
        class ArgD<T : Any, R>(t: T, dv: R?) : Desc<T, R>(t, dv)
        internal inline fun <reified T : Any> Any?.cast(): T = this as T
        fun <T : Any> f(d: Desc<T, List<T>>): Int =
            with((d.cast<Desc<T, List<T>>>()) as ArgD) {
                defaultValue?.toList()
                1
            }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func bareCastBindingsPreserveArgumentsAndNullability() throws {
        let ctx = makeContextFromSource("""
        open class Base<A, B>
        open class Middle<X, Y> : Base<Y, X>()
        class Child<P, Q> : Middle<P, Q>()
        fun direct(x: Child<String, Int>) = x as Child
        fun inherited(x: Base<Int, String>) = x as Child
        fun safe(x: Base<Int, String>?) = x as? Child
        fun nullable(x: Base<Int, String>?) = x as Child?
        fun explicit(x: Base<Int, String>) = x as Child<Int, String>
        fun projected(x: Base<Int, String>) = x as Child<*, *>
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        var casts: [ExprID] = []
        _ = firstExprID(in: ast) { id, expr in
            if isUserSourceExpr(id, in: ctx), case .asCast = expr { casts.append(id) }
            return false
        }
        struct ExpectedCast {
            let args: (TypeSystem) -> [TypeArg]
            let targetNullability: Nullability
            let resultNullability: Nullability
        }

        let expectedCasts: [ExpectedCast] = [
            // direct: x as Child
            ExpectedCast(
                args: { [.invariant($0.stringType), .invariant($0.intType)] },
                targetNullability: .nonNull,
                resultNullability: .nonNull
            ),
            // inherited: x as Child
            ExpectedCast(
                args: { [.invariant($0.stringType), .invariant($0.intType)] },
                targetNullability: .nonNull,
                resultNullability: .nonNull
            ),
            // safe: x as? Child
            ExpectedCast(
                args: { [.invariant($0.stringType), .invariant($0.intType)] },
                targetNullability: .nonNull,
                resultNullability: .nullable
            ),
            // nullable: x as Child?
            ExpectedCast(
                args: { [.invariant($0.stringType), .invariant($0.intType)] },
                targetNullability: .nullable,
                resultNullability: .nullable
            ),
            // explicit: x as Child<Int, String>
            ExpectedCast(
                args: { [.invariant($0.intType), .invariant($0.stringType)] },
                targetNullability: .nonNull,
                resultNullability: .nonNull
            ),
            // projected: x as Child<*, *>
            ExpectedCast(
                args: { _ in [.star, .star] },
                targetNullability: .nonNull,
                resultNullability: .nonNull
            ),
        ]

        #expect(casts.count == expectedCasts.count)
        for (cast, expected) in zip(casts, expectedCasts) {
            let target = try #require(sema.bindings.castTargetType(for: cast))
            guard case let .classType(targetClass) = sema.types.kind(of: target) else {
                Issue.record("Expected a nominal cast target")
                continue
            }
            #expect(targetClass.args == expected.args(sema.types))
            #expect(targetClass.nullability == expected.targetNullability)
            let result = try #require(sema.bindings.exprType(for: cast))
            #expect(sema.types.nullability(of: result) == expected.resultNullability)
        }
    }

    @Test
    func unrelatedSourceDoesNotInventArguments() throws {
        let ctx = makeContextFromSource("""
        class Box<T>(val value: T)
        fun probe(x: Any) = x as Box
        """)
        try runSema(ctx)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let cast = try #require(firstExprID(in: ast) { id, expr in
            guard isUserSourceExpr(id, in: ctx), case .asCast = expr else { return false }
            return true
        })
        let target = try #require(sema.bindings.castTargetType(for: cast))
        guard case let .classType(targetClass) = sema.types.kind(of: target) else {
            Issue.record("Expected a nominal cast target")
            return
        }
        #expect(targetClass.args.isEmpty)
    }

    @Test
    func castInsideConsumedExpressionNarrowsLocalForLaterStatements() throws {
        // `(next as Node).removed()` evaluates `next as Node`
        // unconditionally, so `next` is `Node` for following statements even
        // though the cast is nested inside the initializer expression
        // (LockFreeLinkedList.remove's `finishRemove(next)` pattern).
        let ctx = makeContextFromSource("""
        open class Node {
            fun removed(): Node = this
        }
        fun finishRemove(node: Node) {}
        fun test(x: Any) {
            val next = x
            val removed = (next as Node).removed()
            finishRemove(next)
            finishRemove(removed)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func castOnConditionallyEvaluatedPathDoesNotNarrowLocal() throws {
        // The elvis RHS and a `?.` call's arguments only run conditionally;
        // a cast there must not narrow the variable for following code.
        let ctx = makeContextFromSource("""
        class Node
        fun finishRemove(node: Node) {}
        fun test(x: Node?, y: Any, z: Node?) {
            x ?: (y as Node)
            z?.let { (y as Node) }
            finishRemove(y)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "got: \(ctx.diagnostics.diagnostics)")
    }
}
