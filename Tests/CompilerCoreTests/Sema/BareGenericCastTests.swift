@testable import CompilerCore
import Testing

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
        #expect(casts.count == 6)
        for (index, cast) in casts.enumerated() {
            let target = try #require(sema.bindings.castTargetType(for: cast))
            guard case let .classType(targetClass) = sema.types.kind(of: target) else {
                Issue.record("Expected a nominal cast target")
                continue
            }
            let expectedArgs: [TypeArg] = switch index {
            case 4: [.invariant(sema.types.intType), .invariant(sema.types.stringType)]
            case 5: [.star, .star]
            default: [.invariant(sema.types.stringType), .invariant(sema.types.intType)]
            }
            #expect(targetClass.args == expectedArgs)
            #expect(targetClass.nullability == (index == 3 ? .nullable : .nonNull))
            let result = try #require(sema.bindings.exprType(for: cast))
            #expect(sema.types.nullability(of: result) == ([2, 3].contains(index) ? .nullable : .nonNull))
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
}
