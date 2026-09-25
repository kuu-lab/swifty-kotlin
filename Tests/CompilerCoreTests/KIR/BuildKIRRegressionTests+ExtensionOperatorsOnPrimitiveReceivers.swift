#if canImport(Testing)
@testable import CompilerCore
import Testing

// Regression coverage for extension operators declared on a primitive
// receiver (e.g. `operator fun Int.times(v: Vec)`) whose parameter type the
// built-in primitive fast paths do not accept. Both Sema (the primitive
// special-case in CallTypeChecker+MemberCallInferenceRegularPrimitiveSpecials
// and the primitive guard in ExprTypeChecker.collectOperatorCandidates) and
// KIR lowering (CallLowerer+LegacyMemberLikeCalls's name-based `kk_op_*`
// dispatch and CallLowerer+Operators's string-add shortcut) used to ignore
// argument applicability and silently miscompile these calls.
extension BuildKIRRegressionTests {
    @Test func testBuildKIRUsesExtensionOperatorSymbolForPrimitiveReceiverBinaryTimesExpression() throws {
        let source = """
        class Vec {
            operator fun times(k: Int): Vec = this
        }
        operator fun Int.times(v: Vec): Vec = v
        fun useOperator(n: Int, a: Vec): Vec = n * a
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)

        let operatorExprID = try #require(topLevelExpressionBodyExprID(
            named: "useOperator",
            ast: ast,
            interner: ctx.interner
        ))
        guard let operatorExpr = ast.arena.expr(operatorExprID),
              case let .binary(op, _, _, _) = operatorExpr
        else {
            Issue.record("Expected useOperator body to be a binary expression.")
            return
        }
        #expect(op == .multiply)
        let resolvedBinding = try #require(sema.bindings.callBindings[operatorExprID])
        let chosenSymbol = resolvedBinding.chosenCallee
        let chosenSemanticSymbol = try #require(sema.symbols.symbol(chosenSymbol))
        #expect(ctx.interner.resolve(chosenSemanticSymbol.name) == "times")
        let signature = try #require(sema.symbols.functionSignature(for: chosenSymbol))
        // The chosen callee must be the top-level `Int.times(Vec)` extension
        // (it has a receiver clause), not a hijacked primitive fast path.
        #expect(signature.receiverType != nil)

        try BuildKIRPhase().run(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "useOperator", in: module, interner: ctx.interner)

        #expect(body.contains { instruction in
            guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
            return symbol == chosenSymbol
        })
        #expect(!extractCallees(from: body, interner: ctx.interner).contains("kk_op_mul"))
    }

    @Test func testBuildKIRUsesExtensionOperatorSymbolForPrimitiveReceiverMemberCallTimesExpression() throws {
        let source = """
        class Vec {
            operator fun times(k: Int): Vec = this
        }
        operator fun Int.times(v: Vec): Vec = v
        fun useMemberCall(n: Int, a: Vec): Vec = n.times(a)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)

        let memberExprID = try #require(topLevelExpressionBodyExprID(
            named: "useMemberCall",
            ast: ast,
            interner: ctx.interner
        ))
        guard let memberExpr = ast.arena.expr(memberExprID),
              case .memberCall = memberExpr
        else {
            Issue.record("Expected useMemberCall body to be a member call expression.")
            return
        }
        let resolvedBinding = try #require(sema.bindings.callBindings[memberExprID])
        let chosenSymbol = resolvedBinding.chosenCallee
        let chosenSemanticSymbol = try #require(sema.symbols.symbol(chosenSymbol))
        #expect(ctx.interner.resolve(chosenSemanticSymbol.name) == "times")
        let signature = try #require(sema.symbols.functionSignature(for: chosenSymbol))
        #expect(signature.receiverType != nil)

        try BuildKIRPhase().run(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "useMemberCall", in: module, interner: ctx.interner)

        #expect(body.contains { instruction in
            guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
            return symbol == chosenSymbol
        })
        #expect(!extractCallees(from: body, interner: ctx.interner).contains("kk_op_mul"))
    }

    @Test func testBuildKIRUsesExtensionOperatorSymbolForPrimitiveReceiverBinaryPlusStringExpression() throws {
        let source = """
        operator fun Int.plus(s: String): String = "$this+$s"
        fun useOperator(n: Int, s: String): String = n + s
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)

        let operatorExprID = try #require(topLevelExpressionBodyExprID(
            named: "useOperator",
            ast: ast,
            interner: ctx.interner
        ))
        guard let operatorExpr = ast.arena.expr(operatorExprID),
              case let .binary(op, _, _, _) = operatorExpr
        else {
            Issue.record("Expected useOperator body to be a binary expression.")
            return
        }
        #expect(op == .add)
        let resolvedBinding = try #require(sema.bindings.callBindings[operatorExprID])
        let chosenSymbol = resolvedBinding.chosenCallee
        let chosenSemanticSymbol = try #require(sema.symbols.symbol(chosenSymbol))
        #expect(ctx.interner.resolve(chosenSemanticSymbol.name) == "plus")
        let signature = try #require(sema.symbols.functionSignature(for: chosenSymbol))
        #expect(signature.receiverType != nil)

        try BuildKIRPhase().run(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "useOperator", in: module, interner: ctx.interner)

        #expect(body.contains { instruction in
            guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
            return symbol == chosenSymbol
        })
        #expect(!extractCallees(from: body, interner: ctx.interner).contains("__kk_string_concat_flat"))
    }
}
#endif
