@testable import CompilerCore
import Foundation
import Testing

@Suite
struct UseSiteVarianceFlowTests {

    @Test
    func testUseSiteVarianceBlocksWriteAndPreservesReadType() throws {
        let sources = [
            """
            package sample0

            class E

            class Box<T> {
                fun get(): T = throw E()
                fun set(v: T) {}
            }

            fun readOnly(box: Box<out Any>): Any = box.get()

            fun writeBlocked(box: Box<out Any>) {
                box.set(42)
            }
            """,
            """
            package sample1

            class E

            class Box<T> {
                fun get(): T = throw E()
                fun set(v: T) {}
            }

            fun starRead(box: Box<*>): Any? = box.get()

            fun starWrite(box: Box<*>) {
                box.set(42)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let outPath = paths[0]
            let outGetCall = try #require(firstExprID(in: ast, path: outPath, ctx: ctx) { exprID, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "get"
            })
            #expect(sema.bindings.exprType(for: outGetCall) == sema.types.anyType)

            let starPath = paths[1]
            let starGetCall = try #require(firstExprID(in: ast, path: starPath, ctx: ctx) { exprID, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "get"
            })
            #expect(sema.bindings.exprType(for: starGetCall) == sema.types.nullableAnyType)

            assertHasDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    @Test
    func testUseSiteInProjectionOnInDeclaredParameterIsAccepted() throws {
        // KUU-1381: a use-site `in` on an `in`-declared parameter is a redundant
        // projection — kotlinc accepts it and `Sink<in X>` behaves like `Sink<X>`.
        let source = """
        interface Sink<in T> { fun put(t: T) }
        class IS<T> : Sink<T> { override fun put(t: T) {} }

        val s1: Sink<in Int> = IS<Int>()
        val s2: Sink<in Int> = IS<Any>()
        val f: Sink<*> = IS<Int>()

        fun feed(s: Sink<in Int>) { s.put(9) }
        val call = feed(IS<Any>())
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let hasError = ctx.diagnostics.hasError
            #expect(!hasError, "\(ctx.diagnostics.diagnostics.map { $0.message })")
        }
    }

    @Test
    func testUseSiteInProjectionOnInDeclaredParameterKeepsContravariantDirection() throws {
        // `Sink<in Any>` still rejects `Sink<Int>` — the projection is redundant,
        // not direction-flipping (kotlinc rejects the same shape).
        let source = """
        interface Sink<in T> { fun put(t: T) }
        class IS<T> : Sink<T> { override fun put(t: T) {} }

        val bad: Sink<in Any> = IS<Int>()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }
}
