@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct BareObjectCompoundAssignTests {
    @Test
    func bareObjectUsesItsUnitReturningPlusAssign() throws {
        let ctx = makeContextFromSource("""
        fun mutate() { X += 1 }
        object X { operator fun plusAssign(value: Int) {} }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let assignments = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id),
                  ctx.sourceManager.origin(of: range.start.file) == .user
            else { return nil }
            guard case let .compoundAssign(_, name, _, _) = ast.arena.expr(id),
                  name == ctx.interner.intern("X")
            else { return nil }
            return id
        }
        let assignment = try #require(assignments.first)
        let receiver = try #require(sema.bindings.identifierSymbol(for: assignment))
        #expect(sema.symbols.symbol(receiver)?.kind == .object)
        let call = try #require(sema.bindings.callBinding(for: assignment))
        #expect(sema.symbols.symbol(call.chosenCallee)?.name == ctx.interner.intern("plusAssign"))
        #expect(sema.symbols.functionSignature(for: call.chosenCallee)?.returnType == sema.types.unitType)
    }

    @Test
    func bareObjectInfersExpressionBodiedPlusAssignReturnTypeBeforeUse() throws {
        let ctx = makeContextFromSource("""
        fun mutate() { X += 1 }
        object X { operator fun plusAssign(value: Any) = Unit }
        """)
        try runToKIR(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func mutableAliasRetainsPlusAssignAndPlusAmbiguity() throws {
        let ctx = makeContextFromSource("""
        object X {
            operator fun plusAssign(value: Int) {}
            operator fun plus(value: Int): X = this
        }
        fun mutate() { var alias = X; alias += 1 }
        """)
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0302" })
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0013" })
    }

    @Test
    func inapplicablePlusAssignFallsBackToPlusBeforeRejectingReassignment() throws {
        let ctx = makeContextFromSource("""
        object X {
            operator fun plusAssign(value: String) {}
            operator fun plus(value: Int): X = this
        }
        fun mutate() { X += 1 }
        """)
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0014" })
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0013" })
    }
}
