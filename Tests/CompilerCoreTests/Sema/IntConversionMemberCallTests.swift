#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct IntConversionMemberCallTests {
    @Test func testIntConversionCallsInferRuntimeFriendlyTypes() throws {
        let source = """
        fun sample(x: Int) {
            x.toFloat()
            x.toByte()
            x.toShort()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let expectedTypes: [String: TypeID] = [
                "toFloat": sema.types.floatType,
                "toByte": sema.types.intType,
                "toShort": sema.types.intType,
            ]

            for memberName in expectedTypes.keys {
                let callExpr = try #require(
                    firstExprID(in: ast) { exprID, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr,
                              ctx.interner.resolve(callee) == memberName,
                              let range = ast.arena.exprRange(exprID)
                        else {
                            return false
                        }
                        return !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
                    },
                    "Expected a call expression for \(memberName)"
                )
                #expect(
                    sema.bindings.exprTypes[callExpr] == expectedTypes[memberName],
                    "\(memberName) should infer expected return type"
                )
            }
        }
    }

    @Test func testLongAndDoubleToIntNarrowingConversionInfersIntType() throws {
        let source = """
        fun sample(l: Long, d: Double) {
            l.toInt()
            d.toInt()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            // Collect the last 2 toInt() calls in the arena (user-file calls come after bundled stdlib).
            var toIntCallExprIDs: [ExprID] = []
            for index in ast.arena.exprs.indices.reversed() {
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID) else { continue }
                guard case let .memberCall(_, callee, _, _, _) = expr else { continue }
                if ctx.interner.resolve(callee) == "toInt" {
                    toIntCallExprIDs.insert(exprID, at: 0)
                    if toIntCallExprIDs.count == 2 { break }
                }
            }
            #expect(toIntCallExprIDs.count == 2, "Expected two toInt() calls")
            for exprID in toIntCallExprIDs {
                #expect(
                    sema.bindings.exprTypes[exprID] == sema.types.intType,
                    "Long.toInt() and Double.toInt() should infer Int return type"
                )
            }
        }
    }
}
#endif
