#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct RangeNothingOperandTests {
    @Test
    func controlFlowExpressionsResolveRangeOverloadsFromTheirPeerOperand() throws {
        let ctx = makeContextFromSource("""
        fun continueReceiver() {
            for (i in 0..1) {
                for (j in continue downTo 1) {}
            }
        }

        fun continueArgument() {
            for (i in 0..1) {
                for (j in 1 downTo continue) {}
            }
        }

        fun breakReceiver() {
            for (i in 0..1) {
                for (j in break downTo 1) {}
            }
        }

        fun breakArgument() {
            for (i in 0..1) {
                for (j in 1 downTo break) {}
            }
        }

        fun returnArgument() {
            val range = 1 downTo return
        }

        fun returnRangeToReceiver() {
            val range = return..1
        }

        fun returnRangeToArgument() {
            val range = 1..return
        }

        fun returnRangeUntilReceiver() {
            val range = return..<1
        }

        fun returnRangeUntilArgument() {
            val range = 1..<return
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors.map { "\($0.code): \($0.message)" })")

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let rangeExpressions = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard case let .binary(op, lhs, rhs, _) = ast.arena.expr(id),
                  [.rangeTo, .rangeUntil, .downTo].contains(op),
                  sema.bindings.exprType(for: lhs) == sema.types.nothingType
                    || sema.bindings.exprType(for: rhs) == sema.types.nothingType
            else {
                return nil
            }
            return id
        }
        #expect(rangeExpressions.count == 9)
        #expect(rangeExpressions.allSatisfy { sema.bindings.callBinding(for: $0) != nil })
    }
}
#endif
