@testable import CompilerCore
import Foundation
import Testing

@Suite
struct UseSiteVarianceFlowTests {
    private func firstExprID(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

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
}
