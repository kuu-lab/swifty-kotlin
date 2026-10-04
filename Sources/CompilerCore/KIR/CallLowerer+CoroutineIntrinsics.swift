
extension CallLowerer {
    func lowerSuspendCoroutineUninterceptedOrReturnCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let specialKind = sema.bindings.stdlibSpecialCallKind(for: exprID),
              specialKind == .suspendCoroutineUninterceptedOrReturn,
              args.count == 1
        else {
            return nil
        }

        let resultType = sema.bindings.exprType(for: exprID) ?? sema.types.anyType
        let loweredBlockExpr = driver.lowerExpr(
            args[0].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        var blockExpr = loweredBlockExpr
        if let blockType = sema.bindings.exprType(for: args[0].expr),
           case let .functionType(functionType) = sema.types.kind(of: blockType) {
            blockExpr = materializeFunctionValueArgument(
                loweredArgID: loweredBlockExpr,
                argExprID: args[0].expr,
                functionType: functionType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
        let blockResultExpr = arena.appendTemporary(type: sema.types.anyType)
        let thrownResult = arena.appendTemporary(type: sema.types.nullableAnyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("<suspendCoroutineUninterceptedOrReturn>"),
            arguments: [blockExpr],
            result: blockResultExpr,
            canThrow: true,
            thrownResult: thrownResult
        ))
        let continueLabel = driver.ctx.makeLoopLabel()
        let rethrowLabel = driver.ctx.makeLoopLabel()
        instructions.append(.jumpIfNotNull(value: thrownResult, target: rethrowLabel))
        instructions.append(.jump(continueLabel))
        instructions.append(.label(rethrowLabel))
        instructions.append(.rethrow(value: thrownResult))
        instructions.append(.label(continueLabel))

        let suspendedExpr = arena.appendTemporary(type: sema.types.anyType
        )
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_coroutine_suspended"),
            arguments: [],
            result: suspendedExpr,
            canThrow: false,
            thrownResult: nil
        ))

        let suspendLabel = driver.ctx.makeLoopLabel()
        let resumeLabel = driver.ctx.makeLoopLabel()
        instructions.append(.jumpIfEqual(
            lhs: blockResultExpr,
            rhs: suspendedExpr,
            target: suspendLabel
        ))
        instructions.append(.jump(resumeLabel))
        instructions.append(.label(suspendLabel))
        instructions.append(.returnValue(blockResultExpr))
        instructions.append(.label(resumeLabel))

        let resultExpr = arena.appendTemporary(type: resultType)
        instructions.append(.copy(from: blockResultExpr, to: resultExpr))
        return resultExpr
    }
}
