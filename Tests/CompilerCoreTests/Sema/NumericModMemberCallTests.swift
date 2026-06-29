#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NumericModMemberCallTests {
    @Test
    func testNumericModMemberCallsInferKotlinReturnMatrix() throws {
        let source = """
        fun sample(b: Byte, s: Short, i: Int, l: Long, ub: UByte, us: UShort, ui: UInt, ul: ULong, f: Float, d: Double) {
            l.mod(i)
            i.mod(l)
            b.mod(s)
            ul.mod(ub)
            ui.mod(us)
            ub.mod(ul)
            f.mod(1.5f)
            f.mod(d)
            d.mod(f)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let modCalls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID) else {
                return nil
            }
            return ctx.interner.resolve(callee) == "mod" ? exprID : nil
        }

        #expect(modCalls.count == 9, "Expected all mod calls to be present")
        let expectedTypes: [TypeID] = [
            sema.types.intType,
            sema.types.longType,
            sema.types.intType,
            sema.types.ubyteType,
            sema.types.ushortType,
            sema.types.ulongType,
            sema.types.floatType,
            sema.types.doubleType,
            sema.types.doubleType,
        ]

        for (exprID, expectedType) in zip(modCalls, expectedTypes) {
            #expect(sema.bindings.exprTypes[exprID] == expectedType)
        }
    }

    @Test
    func testNumericModRejectsMixedSignedness() throws {
        let source = """
        fun sample(i: Int, l: Long, ui: UInt, ul: ULong) {
            i.mod(ui)
            ui.mod(i)
            l.mod(ul)
            ul.mod(l)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count >= 4, "Expected mixed signedness mod calls to be rejected, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
