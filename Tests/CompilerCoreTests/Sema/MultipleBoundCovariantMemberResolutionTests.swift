#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct MultipleBoundCovariantMemberResolutionTests {
    @Test func covariantReturnSelectionUsesEveryTypeParameterBound() throws {
        let ctx = makeContextFromSource("""
        interface A {
            fun foo(): Any?
            fun bar(): String
        }
        interface B { fun foo(): String }
        class Both : A, B {
            override fun foo() = "OK"
            override fun bar() = "ok"
        }
        fun <T> useAB(x: T): String where T : A, T : B =
            if (x.foo().length != 2 || x.foo() != "OK" || x.bar() != "ok") "FAIL" else "OK"
        fun <T> useBA(x: T): String where T : B, T : A =
            if (x.foo().length != 2 || x.foo() != "OK" || x.bar() != "ok") "FAIL" else "OK"
        fun <T : B> useOneBound(x: T): String = x.foo()

        interface StringChoice { fun choose(value: String?): String }
        interface IntChoice { fun choose(value: Int?): Int }
        fun <T> ambiguousChoice(x: T): Any? where T : StringChoice, T : IntChoice = x.choose(null)
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "Expected only the intentionally ambiguous overload, got: \(errors)")
        #expect(
            errors.first?.code == "KSWIFTK-SEMA-0003",
            "Expected ambiguous overload diagnostic, got: \(errors)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let fooCalls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, name, _, _, _) = expr,
                  name == ctx.interner.intern("foo")
            else {
                return nil
            }
            return exprID
        }
        #expect(fooCalls.count == 5)
        for call in fooCalls {
            #expect(sema.bindings.callBinding(for: call)?.chosenCallee != nil)
            #expect(sema.bindings.exprType(for: call) == sema.types.stringType)
        }
    }
}
#endif
