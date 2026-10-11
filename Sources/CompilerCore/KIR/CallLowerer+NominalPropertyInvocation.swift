extension CallLowerer {
    /// Read the property once, before its value arguments, and dispatch invoke
    /// on that value rather than on the expression used to read the property.
    func tryLowerNominalPropertyInvocation(
        _ exprID: ExprID, receiverExpr: ExprID, args: [CallArgument],
        precomputedReceiver: KIRExprID? = nil,
        shared: KIRLoweringSharedContext, emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID? {
        let sema = shared.sema
        guard let property = sema.bindings.invokeOperatorPropertyCalls[exprID],
              let call = sema.bindings.callBindings[exprID],
              sema.symbols.externalLinkName(for: call.chosenCallee)?.hasPrefix("kk_function_invoke") != true
        else { return nil }
        let arena = shared.arena
        let receiver = precomputedReceiver ?? driver.lowerExpr(receiverExpr, shared: shared, emit: &instructions)
        guard let value = lowerStoredMemberPropertyReadValue(
            propertySymbol: property.property, callExprID: exprID, receiverExpr: receiverExpr, loweredReceiverID: receiver,
            resultType: property.propertyType, ast: shared.ast, sema: sema, arena: arena, interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers, instructions: &instructions.instructions
        ) else { return nil }
        let loweredArgs = args.enumerated().map { index, argument in
            let value = driver.lowerExpr(argument.expr, shared: shared, emit: &instructions)
            return needsEvaluationOrderFreeze(argument.expr, ast: shared.ast, sema: sema)
                && anyExpressionMayMutateState(args[(index + 1)...].map(\.expr), ast: shared.ast)
                ? freezeEvaluationOrderOperand(value, arena: arena, instructions: &instructions.instructions) : value
        }
        let normalized = driver.callSupportLowerer.normalizedCallArguments(
            providedArguments: loweredArgs, callBinding: call, chosenCallee: call.chosenCallee,
            spreadFlags: args.map(\.isSpread), argumentLabels: args.map(\.label), sourceArgExprs: args.map(\.expr),
            ast: shared.ast, sema: sema, arena: arena, interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers, instructions: &instructions.instructions
        )
        var arguments = normalized.arguments
        if sema.symbols.functionSignature(for: call.chosenCallee)?.receiverType != nil {
            arguments.insert(value, at: 0)
        }
        let result = arena.appendTemporary(type: property.resultType)
        emitMemberCallInstruction(
            normalized: normalized, callBinding: call, chosenCallee: call.chosenCallee,
            calleeName: shared.interner.intern("invoke"),
            receiver: MemberCallReceiver(expr: receiverExpr, loweredID: value, typeOverride: property.propertyType),
            result: result, isSuperCall: false, qualifiedSuperType: nil,
            sema: sema, arena: arena, interner: shared.interner, instructions: &instructions.instructions,
            arguments: arguments, sourceArgExprs: args.map(\.expr), sourceArgLabels: args.map(\.label), callExprID: exprID
        )
        return result
    }
}
