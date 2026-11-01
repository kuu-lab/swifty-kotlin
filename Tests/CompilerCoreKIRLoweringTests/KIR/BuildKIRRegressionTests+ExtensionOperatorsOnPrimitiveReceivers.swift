#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

// Regression coverage for extension operators declared on a primitive
// receiver (e.g. `operator fun Int.times(v: Vec)`) whose parameter type the
// built-in primitive fast paths do not accept. Both Sema (the primitive
// special-case in CallTypeChecker+MemberCallInferenceRegularPrimitiveSpecials
// and the primitive guard in ExprTypeChecker.collectOperatorCandidates) and
// KIR lowering (CallLowerer+LegacyMemberLikeCalls's name-based `kk_op_*`
// dispatch and CallLowerer+Operators's string-add shortcut) used to ignore
// argument applicability and silently miscompile these calls.
extension BuildKIRRegressionTests {
    @Test func testBuildKIRUsesPrimitiveContainsExtensionInWhenCondition() throws {
        let source = """
        operator fun Int.contains(value: Int): Boolean = this == 2 && value == 1
        fun matchIn(): Int = when (1) { in 2 -> 1; else -> 0 }
        fun matchNotIn(): Int = when (1) { !in 3 -> 1; else -> 0 }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let module = try #require(ctx.kir)
            for functionName in ["matchIn", "matchNotIn"] {
                let whenID = try #require(topLevelExpressionBodyExprID(
                    named: functionName,
                    ast: ast,
                    interner: ctx.interner
                ))
                guard case let .whenExpr(_, branches, _, _) = ast.arena.expr(whenID),
                      let conditionID = branches.first?.conditions.first
                else {
                    Issue.record("Expected \(functionName) to contain an in/not-in condition.")
                    continue
                }
                let chosenCallee = try #require(sema.bindings.callBindings[conditionID]?.chosenCallee)
                let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
                #expect(signature.receiverType != nil, "Expected the scoped Int.contains extension to be bound.")

                let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)
                #expect(body.contains { instruction in
                    guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
                    return symbol == chosenCallee
                }, "Expected \(functionName) to call its resolved Int.contains extension.")
                #expect(!extractCallees(from: body, interner: ctx.interner).contains(runtimeCallee(.opContains)))
            }
        }
    }

    @Test(arguments: ["plus", "times", "div", "rem"])
    func testBuildKIRUsesCharArithmeticExtensionForExplicitCall(name: String) throws {
        let rhsType = name == "plus" ? "Char" : "Int"
        let source = """
        operator fun Char.\(name)(other: \(rhsType)): Int = this.code + 7
        fun useMemberCall(c: Char, other: \(rhsType)): Int = c.\(name)(other)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let exprID = try #require(topLevelExpressionBodyExprID(named: "useMemberCall", ast: ast, interner: ctx.interner))
        let chosen = try #require(sema.bindings.callBindings[exprID]?.chosenCallee)
        try BuildKIRPhase().run(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "useMemberCall", in: module, interner: ctx.interner)
        #expect(body.contains { instruction in
            guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
            return symbol == chosen
        })
        #expect(!body.contains { instruction in
            if case .binary = instruction { return true }
            return false
        })
    }

    @Test(arguments: [
        "private fun Long.floorDiv(value: Int): Int = value + 100\nfun useMemberCall(n: Long, d: Int): Int = n.floorDiv(d)",
        "private fun Int.mod(value: Int): Int = value + 80\nfun useMemberCall(n: Int, d: Int): Int = n.mod(d)",
        "class Holder {\n    fun Long.mod(value: Int): Int = value + 40\n    fun useMemberCall(n: Long, d: Int): Int = n.mod(d)\n}",
    ])
    func testBuildKIRUsesUserNumericExtensionOverFloorIntrinsic(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        try BuildKIRPhase().run(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "useMemberCall", in: module, interner: ctx.interner)
        let callees = Set(extractCallees(from: body, interner: ctx.interner))
        #expect(!callees.isDisjoint(with: ["floorDiv", "mod"]), "Expected a call to the user extension, got \(callees)")
        #expect(callees.isDisjoint(with: ["kk_op_floor_div", "kk_op_floor_mod", "kk_op_lfloor_mod"]))
    }

    @Test
    func testBuildKIRLowersExplicitCharPlusStringToFlatConcat() throws {
        let ctx = makeContextFromSource("fun useMemberCall(c: Char, s: String): String = c.plus(s)")
        try runSema(ctx)
        try BuildKIRPhase().run(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "useMemberCall", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(callees.contains(runtimeCallee(.stringConcatFlat)))
        #expect(!callees.contains("plus"))
    }

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
        #expect(chosenSemanticSymbol.name == ctx.interner.intern(BinaryOp.multiply.kotlinFunctionName))
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
        #expect(!extractCallees(from: body, interner: ctx.interner).contains(runtimeCallee(.opMul)))
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
        #expect(chosenSemanticSymbol.name == ctx.interner.intern(BinaryOp.multiply.kotlinFunctionName))
        let signature = try #require(sema.symbols.functionSignature(for: chosenSymbol))
        #expect(signature.receiverType != nil)

        try BuildKIRPhase().run(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "useMemberCall", in: module, interner: ctx.interner)

        #expect(body.contains { instruction in
            guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
            return symbol == chosenSymbol
        })
        #expect(!extractCallees(from: body, interner: ctx.interner).contains(runtimeCallee(.opMul)))
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
        #expect(chosenSemanticSymbol.name == KnownCompilerNames(interner: ctx.interner).plus)
        let signature = try #require(sema.symbols.functionSignature(for: chosenSymbol))
        #expect(signature.receiverType != nil)

        try BuildKIRPhase().run(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "useOperator", in: module, interner: ctx.interner)

        #expect(body.contains { instruction in
            guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
            return symbol == chosenSymbol
        })
        #expect(!extractCallees(from: body, interner: ctx.interner).contains(runtimeCallee(.stringConcatFlat)))
    }
}
#endif
