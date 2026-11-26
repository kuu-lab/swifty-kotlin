extension CallLowerer {

    func tryScopeFunctionLowering(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction],
        precomputedReceiver: KIRExprID? = nil
    ) -> KIRExprID? {
        guard let scopeKind = sema.bindings.scopeFunctionKind(for: exprID),
              args.count == 1
        else { return nil }

        let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        let previousLambdaAllowance = driver.ctx.pendingLambdaNonLocalReturnAllowance
        driver.ctx.pendingLambdaNonLocalReturnAllowance = allowsNonLocalReturn(
            argumentExpr: args[0].expr,
            argumentIndex: 0,
            ast: ast,
            sema: sema,
            callBinding: sema.bindings.callBinding(for: exprID),
            chosen: sema.bindings.callBinding(for: exprID)?.chosenCallee,
            intrinsicInline: scopeKind == .scopeUsePinned
        )
        defer { driver.ctx.pendingLambdaNonLocalReturnAllowance = previousLambdaAllowance }

        let loweredReceiverID = precomputedReceiver ?? driver.lowerExpr(
            receiverExpr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        switch scopeKind {
        case .scopeUseContents:
            let contentType: TypeID? = sema.bindings.exprTypes[args[0].expr].flatMap { lambdaType in
                if case let .functionType(functionType) = sema.types.kind(of: lambdaType) {
                    return functionType.receiver
                }
                return nil
            } ?? {
                guard let receiverType = sema.bindings.exprTypes[receiverExpr],
                      let classType = resolveClassType(receiverType, sema: sema),
                      let cValueSymbol = sema.symbols.lookup(fqName: [
                          interner.intern("kotlinx"),
                          interner.intern("cinterop"),
                          interner.intern("CValue"),
                      ]),
                      classType.classSymbol == cValueSymbol,
                      let firstArg = classType.args.first
                else {
                    return nil
                }
                switch firstArg {
                case let .invariant(type), let .out(type), let .in(type):
                    return sema.types.makeNonNullable(type)
                case .star:
                    return sema.types.anyType
                }
            }()
            guard let contentType else {
                return nil
            }

            let receiverSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
            let receiverSymExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: contentType)
            instructions.append(.copy(from: loweredReceiverID, to: receiverSymExpr))

            let loweredLambdaID = driver.lowerExpr(
                args[0].expr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

            let result = arena.appendTemporary(type: boundType)
            if let info = driver.ctx.callableValueInfo(for: loweredLambdaID) {
                instructions.append(.call(
                    symbol: info.symbol,
                    callee: info.callee,
                    arguments: info.captureArguments + [receiverSymExpr],
                    result: result,
                    canThrow: false
                ))
            } else {
                return nil
            }
            return result

        case .scopeUse:
            let loweredLambdaID = driver.lowerExpr(
                args[0].expr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let result = arena.appendTemporary(type: boundType
            )
            guard let info = driver.ctx.callableValueInfo(for: loweredLambdaID) else {
                return nil
            }

            // `use` is an inline function: a nested block may own the
            // non-local return before inline expansion exposes it in this
            // block. Every literal use block must expand into its caller
            // together with its cleanup (mirrors scopeUsePinned).
            if case .lambdaLiteral = ast.arena.expr(args[0].expr) {
                arena.transformFunctions { function in
                    guard function.symbol == info.symbol else { return function }
                    return KIRFunction(
                        symbol: function.symbol, name: function.name, params: function.params,
                        returnType: function.returnType, body: function.body,
                        isSuspend: function.isSuspend, isInline: true, isInlineOnly: true,
                        isTailrec: function.isTailrec, sourceRange: function.sourceRange,
                        instructionLocations: function.instructionLocations
                    )
                }
            }

            let intType = sema.types.make(.primitive(.int, .nonNull))

            let exceptionSlot = arena.appendTemporary(type: sema.types.nullableAnyType)
            let exceptionTypeSlot = arena.appendTemporary(type: intType)
            let nullExceptionValue = arena.appendExpr(.null, type: sema.types.nullableAnyType)
            let zeroTypeToken = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: nullExceptionValue, value: .null))
            instructions.append(.constValue(result: zeroTypeToken, value: .intLiteral(0)))
            instructions.append(.copy(from: nullExceptionValue, to: exceptionSlot))
            instructions.append(.copy(from: zeroTypeToken, to: exceptionTypeSlot))

            let finallyLabel = driver.ctx.makeLoopLabel()
            let rethrowLabel = driver.ctx.makeLoopLabel()
            let endLabel = driver.ctx.makeLoopLabel()

            let nonLocalReturnLabel = driver.ctx.makeLoopLabel()
            let nonLocalReturnValue = arena.appendTemporary(type: nil)
            let returningNonLocally = arena.appendTemporary(type: sema.types.booleanType)
            let notReturning = arena.appendExpr(.boolLiteral(false), type: sema.types.booleanType)
            instructions.append(.constValue(result: notReturning, value: .boolLiteral(false)))
            instructions.append(.copy(from: notReturning, to: returningNonLocally))
            instructions.append(.beginNonLocalReturnScope(value: nonLocalReturnValue, target: nonLocalReturnLabel))

            var closureRawArg: KIRExprID? = nil
            if info.hasClosureParam {
                if info.captureArguments.isEmpty {
                    let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    closureRawArg = zeroExpr
                } else if info.captureArguments.count == 1 {
                    closureRawArg = info.captureArguments[0]
                } else {
                    let boxedArgs = makeBoxedCallableCaptureArguments(
                        callableInfo: info,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    closureRawArg = boxedArgs[0]
                }
            }

            var blockInstructions: [KIRInstruction] = []
            let callArgs: [KIRExprID]
            if let closureRawArg {
                callArgs = [closureRawArg, loweredReceiverID]
            } else {
                callArgs = info.captureArguments + [loweredReceiverID]
            }
            blockInstructions.append(.call(symbol: info.symbol, callee: info.callee, arguments: callArgs, result: result, canThrow: true))

            // CODE-001: the beginFinallyGuard/endFinallyGuard pair prevents
            // an outer try/catch/use from re-wrapping this already-routed
            // call if this `use` is itself nested inside one — otherwise the
            // outer pass would race ahead of the close() cleanup below.
            instructions.append(.beginFinallyGuard)
            driver.controlFlowLowerer.appendThrowAwareInstructions(
                blockInstructions,
                exceptionSlot: exceptionSlot,
                exceptionTypeSlot: exceptionTypeSlot,
                thrownTarget: finallyLabel,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions
            )
            instructions.append(.endFinallyGuard)
            instructions.append(.jump(finallyLabel))

            instructions.append(.endNonLocalReturnScope)
            instructions.append(.label(nonLocalReturnLabel))
            instructions.append(.constValue(result: returningNonLocally, value: .boolLiteral(true)))
            instructions.append(.jump(finallyLabel))

            instructions.append(.label(finallyLabel))
            let receiverTypeForDispatch = sema.bindings.exprTypes[receiverExpr]
            let shouldGuardNullableClose = receiverTypeForDispatch.map {
                sema.types.nullability(of: $0) != .nonNull
            } ?? false
            let closeEndLabel: Int32? = shouldGuardNullableClose ? driver.ctx.makeLoopLabel() : nil
            if shouldGuardNullableClose, let closeEndLabel {
                let closeCallLabel = driver.ctx.makeLoopLabel()
                instructions.append(.jumpIfNotNull(value: loweredReceiverID, target: closeCallLabel))
                instructions.append(.jump(closeEndLabel))
                instructions.append(.label(closeCallLabel))
            }
            let closeFinallyName = interner.intern("closeFinally")
            let closeFinallyFQName = [interner.intern("kotlin"), closeFinallyName]
            let closeFinallySymbol = sema.symbols.lookupAll(fqName: closeFinallyFQName).first { symbolID in
                guard sema.symbols.symbol(symbolID)?.kind == .function,
                      let signature = sema.symbols.functionSignature(for: symbolID)
                else {
                    return false
                }
                return signature.receiverType != nil && signature.parameterTypes.count == 1
            }
            let closeResult = arena.appendTemporary(type: sema.types.unitType)
            let closeWithCauseLabel = driver.ctx.makeLoopLabel()
            let closeAfterLabel = driver.ctx.makeLoopLabel()

            // A successful block has no primary exception, so call close()
            // directly. This preserves close-only exception propagation through
            // the enclosing try/catch. The source-backed helper is used only
            // when a primary exception needs suppression handling.
            instructions.append(.jumpIfNotNull(value: exceptionSlot, target: closeWithCauseLabel))

            var directCloseInstructions: [KIRInstruction] = []
            let closeName = interner.intern("close")
            let closeSymbol: SymbolID? = sema.types.closeableInterfaceSymbol.flatMap { closeableSymbol in
                let closeableFQName = sema.symbols.symbol(closeableSymbol)?.fqName ?? []
                return sema.symbols.lookup(fqName: closeableFQName + [closeName])
            }
            let closeDispatch: KIRDispatchKind? = closeSymbol.flatMap { sym in
                resolveVirtualDispatch(callee: sym, receiverTypeID: receiverTypeForDispatch, sema: sema, interner: interner)
            }
            if let closeDispatch, let closeSymbol {
                directCloseInstructions.append(.virtualCall(
                    symbol: closeSymbol,
                    callee: closeName,
                    receiver: loweredReceiverID,
                    arguments: [],
                    result: closeResult,
                    canThrow: true,
                    dispatch: closeDispatch
                ))
            } else {
                var concreteCloseSymbol: SymbolID?
                var concreteCloseName = closeName
                if let recvTypeID = receiverTypeForDispatch,
                   case let .classType(recvClass) = sema.types.kind(of: recvTypeID)
                {
                    let recvSymbol = recvClass.classSymbol
                    if let recvInfo = sema.symbols.symbol(recvSymbol) {
                        let closeCandidateFQ = recvInfo.fqName + [closeName]
                        if let concreteSym = sema.symbols.lookup(fqName: closeCandidateFQ) {
                            concreteCloseSymbol = concreteSym
                            if let extLink = sema.symbols.externalLinkName(for: concreteSym),
                               !extLink.isEmpty
                            {
                                concreteCloseName = interner.intern(extLink)
                            } else {
                                concreteCloseName = sema.symbols.symbol(concreteSym)?.name ?? closeName
                            }
                        }
                    }
                }
                let callSymbol = concreteCloseSymbol ?? closeSymbol
                directCloseInstructions.append(.call(
                    symbol: callSymbol,
                    callee: concreteCloseName,
                    arguments: [loweredReceiverID],
                    result: closeResult,
                    canThrow: true
                ))
            }
            instructions.append(contentsOf: directCloseInstructions)
            instructions.append(.jump(closeAfterLabel))

            instructions.append(.label(closeWithCauseLabel))
            if let closeFinallySymbol {
                instructions.append(.call(
                    symbol: closeFinallySymbol,
                    callee: closeFinallyName,
                    arguments: [loweredReceiverID, exceptionSlot],
                    result: closeResult,
                    canThrow: true
                ))
            } else {
                instructions.append(contentsOf: directCloseInstructions)
            }
            instructions.append(.label(closeAfterLabel))
            if let closeEndLabel {
                instructions.append(.label(closeEndLabel))
            }

            instructions.append(.jumpIfNotNull(value: exceptionSlot, target: rethrowLabel))
            instructions.append(.jump(endLabel))

            instructions.append(.label(rethrowLabel))
            instructions.append(.rethrow(value: exceptionSlot))

            instructions.append(.label(endLabel))
            let afterReturnLabel = driver.ctx.makeLoopLabel()
            instructions.append(.jumpIfEqual(lhs: returningNonLocally, rhs: notReturning, target: afterReturnLabel))
            instructions.append(.resumeNonLocalReturn(nonLocalReturnValue))
            instructions.append(.label(afterReturnLabel))
            return result

        case .scopeUsePinned:
            let loweredLambdaID = driver.lowerExpr(
                args[0].expr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            guard let info = driver.ctx.callableValueInfo(for: loweredLambdaID) else {
                return nil
            }

            if case .lambdaLiteral = ast.arena.expr(args[0].expr) {
                arena.transformFunctions { function in
                    guard function.symbol == info.symbol else { return function }
                    return KIRFunction(
                        symbol: function.symbol, name: function.name, params: function.params,
                        returnType: function.returnType, body: function.body,
                        isSuspend: function.isSuspend, isInline: true, isInlineOnly: true,
                        isTailrec: function.isTailrec, sourceRange: function.sourceRange,
                        instructionLocations: function.instructionLocations
                    )
                }
            }

            let pinFQName: [InternedString] = [
                interner.intern("kotlinx"), interner.intern("cinterop"), interner.intern("pin"),
            ]
            guard let pinSymbol = sema.symbols.lookup(fqName: pinFQName),
                  let pinSignature = sema.symbols.functionSignature(for: pinSymbol)
            else {
                return nil
            }

            let pinnedType: TypeID = sema.bindings.exprTypes[args[0].expr].flatMap { lambdaType in
                if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                    return fnType.params.first
                }
                return nil
            } ?? pinSignature.returnType

            guard case let .classType(pinnedClassType) = sema.types.kind(of: pinnedType),
                  let pinnedClassInfo = sema.symbols.symbol(pinnedClassType.classSymbol)
            else {
                return nil
            }
            let unpinFQName = pinnedClassInfo.fqName + [interner.intern("unpin")]
            guard let unpinSymbol = sema.symbols.lookup(fqName: unpinFQName) else {
                return nil
            }

            func resolvedCalleeName(for symbol: SymbolID, fallback: String) -> InternedString {
                if let extLink = sema.symbols.externalLinkName(for: symbol), !extLink.isEmpty {
                    return interner.intern(extLink)
                }
                return sema.symbols.symbol(symbol)?.name ?? interner.intern(fallback)
            }

            let pinnedResult = arena.appendTemporary(type: pinnedType
            )
            instructions.append(.call(
                symbol: pinSymbol,
                callee: resolvedCalleeName(for: pinSymbol, fallback: "pin"),
                arguments: [loweredReceiverID],
                result: pinnedResult,
                canThrow: false
            ))

            let result = arena.appendTemporary(type: boundType
            )

            let intType = sema.types.make(.primitive(.int, .nonNull))

            let exceptionSlot = arena.appendTemporary(type: sema.types.nullableAnyType)
            let exceptionTypeSlot = arena.appendTemporary(type: intType)
            let nullExceptionValue = arena.appendExpr(.null, type: sema.types.nullableAnyType)
            let zeroTypeToken = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: nullExceptionValue, value: .null))
            instructions.append(.constValue(result: zeroTypeToken, value: .intLiteral(0)))
            instructions.append(.copy(from: nullExceptionValue, to: exceptionSlot))
            instructions.append(.copy(from: zeroTypeToken, to: exceptionTypeSlot))

            let finallyLabel = driver.ctx.makeLoopLabel()
            let rethrowLabel = driver.ctx.makeLoopLabel()
            let endLabel = driver.ctx.makeLoopLabel()

            let nonLocalReturnLabel = driver.ctx.makeLoopLabel()
            let nonLocalReturnValue = arena.appendTemporary(type: nil)
            let returningNonLocally = arena.appendTemporary(type: sema.types.booleanType)
            let notReturning = arena.appendExpr(.boolLiteral(false), type: sema.types.booleanType)
            instructions.append(.constValue(result: notReturning, value: .boolLiteral(false)))
            instructions.append(.copy(from: notReturning, to: returningNonLocally))
            instructions.append(.beginNonLocalReturnScope(value: nonLocalReturnValue, target: nonLocalReturnLabel))

            var closureRawArg: KIRExprID? = nil
            if info.hasClosureParam {
                if info.captureArguments.isEmpty {
                    let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    closureRawArg = zeroExpr
                } else if info.captureArguments.count == 1 {
                    closureRawArg = info.captureArguments[0]
                } else {
                    let boxedArgs = makeBoxedCallableCaptureArguments(
                        callableInfo: info,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    closureRawArg = boxedArgs[0]
                }
            }

            var blockInstructions: [KIRInstruction] = []
            let callArgs: [KIRExprID]
            if let closureRawArg {
                callArgs = [closureRawArg, pinnedResult]
            } else {
                callArgs = info.captureArguments + [pinnedResult]
            }
            blockInstructions.append(.call(symbol: info.symbol, callee: info.callee, arguments: callArgs, result: result, canThrow: true))

            instructions.append(.beginFinallyGuard)
            driver.controlFlowLowerer.appendThrowAwareInstructions(
                blockInstructions,
                exceptionSlot: exceptionSlot,
                exceptionTypeSlot: exceptionTypeSlot,
                thrownTarget: finallyLabel,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions
            )
            instructions.append(.endFinallyGuard)
            instructions.append(.jump(finallyLabel))

            instructions.append(.endNonLocalReturnScope)
            instructions.append(.label(nonLocalReturnLabel))
            instructions.append(.constValue(result: returningNonLocally, value: .boolLiteral(true)))
            instructions.append(.jump(finallyLabel))
            instructions.append(.label(finallyLabel))
            let unpinResult = arena.appendTemporary(type: sema.types.unitType
            )
            instructions.append(.call(
                symbol: unpinSymbol,
                callee: resolvedCalleeName(for: unpinSymbol, fallback: "unpin"),
                arguments: [pinnedResult],
                result: unpinResult,
                canThrow: false
            ))

            instructions.append(.jumpIfNotNull(value: exceptionSlot, target: rethrowLabel))
            instructions.append(.jump(endLabel))

            instructions.append(.label(rethrowLabel))
            instructions.append(.rethrow(value: exceptionSlot))

            instructions.append(.label(endLabel))
            let afterReturnLabel = driver.ctx.makeLoopLabel()
            instructions.append(.jumpIfEqual(lhs: returningNonLocally, rhs: notReturning, target: afterReturnLabel))
            instructions.append(.resumeNonLocalReturn(nonLocalReturnValue))
            instructions.append(.label(afterReturnLabel))
            return result

        case .scopeContext, .scopeMemScoped:
            return nil
        }
    }

    func lowerMemScopedCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.scopeFunctionKind(for: exprID) == .scopeMemScoped,
              args.count == 1
        else { return nil }
        let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType

        let previousLambdaAllowance = driver.ctx.pendingLambdaNonLocalReturnAllowance
        driver.ctx.pendingLambdaNonLocalReturnAllowance = allowsNonLocalReturn(
            argumentExpr: args[0].expr,
            argumentIndex: 0,
            ast: ast,
            sema: sema,
            callBinding: sema.bindings.callBinding(for: exprID),
            chosen: sema.bindings.callBinding(for: exprID)?.chosenCallee
        )
        defer { driver.ctx.pendingLambdaNonLocalReturnAllowance = previousLambdaAllowance }

        let loweredLambdaID = driver.lowerExpr(
            args[0].expr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let memScopeType: TypeID = sema.symbols.lookup(fqName: [
            interner.intern("kotlinx"), interner.intern("cinterop"), interner.intern("MemScope"),
        ]).map { memScopeSymbol in
            sema.types.make(.classType(ClassType(
                classSymbol: memScopeSymbol, args: [], nullability: .nonNull
            )))
        } ?? sema.types.anyType
        let scopeResult = arena.appendTemporary(type: memScopeType)
        instructions.append(.call(callee: interner.intern("kk_memscope_new"), arguments: [], result: scopeResult, canThrow: false))

        let result = arena.appendTemporary(type: boundType)
        let intType = sema.types.make(.primitive(.int, .nonNull))

        let exceptionSlot = arena.appendTemporary(type: sema.types.nullableAnyType)
        let exceptionTypeSlot = arena.appendTemporary(type: intType)
        let nullExceptionValue = arena.appendExpr(.null, type: sema.types.nullableAnyType)
        let zeroTypeToken = arena.appendExpr(.intLiteral(0), type: intType)
        instructions.append(.constValue(result: nullExceptionValue, value: .null))
        instructions.append(.constValue(result: zeroTypeToken, value: .intLiteral(0)))
        instructions.append(.copy(from: nullExceptionValue, to: exceptionSlot))
        instructions.append(.copy(from: zeroTypeToken, to: exceptionTypeSlot))

        let finallyLabel = driver.ctx.makeLoopLabel()
        let rethrowLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()

        var blockInstructions: [KIRInstruction] = []
        if let info = driver.ctx.callableValueInfo(for: loweredLambdaID) {
            var closureRawArg: KIRExprID? = nil
            if info.hasClosureParam {
                if info.captureArguments.isEmpty {
                    let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                    blockInstructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                    closureRawArg = zeroExpr
                } else if info.captureArguments.count == 1 {
                    closureRawArg = info.captureArguments[0]
                } else {
                    let boxedArgs = makeBoxedCallableCaptureArguments(
                        callableInfo: info,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &blockInstructions
                    )
                    closureRawArg = boxedArgs[0]
                }
            }
            let callArgs: [KIRExprID] = closureRawArg.map { [$0, scopeResult] }
                ?? info.captureArguments + [scopeResult]
            blockInstructions.append(.call(symbol: info.symbol, callee: info.callee, arguments: callArgs, result: result, canThrow: true))
        } else {
            blockInstructions.append(.call(
                callee: interner.intern("kk_function_invoke"),
                arguments: [loweredLambdaID, scopeResult],
                result: result,
                canThrow: true
            ))
        }

        instructions.append(.beginFinallyGuard)
        driver.controlFlowLowerer.appendThrowAwareInstructions(
            blockInstructions,
            exceptionSlot: exceptionSlot,
            exceptionTypeSlot: exceptionTypeSlot,
            thrownTarget: finallyLabel,
            sema: sema,
            interner: interner,
            arena: arena,
            instructions: &instructions
        )
        instructions.append(.endFinallyGuard)
        instructions.append(.jump(finallyLabel))

        instructions.append(.label(finallyLabel))
        let clearResult = arena.appendTemporary(type: sema.types.unitType)
        instructions.append(.call(callee: interner.intern("kk_arena_clear"), arguments: [scopeResult], result: clearResult, canThrow: true))

        instructions.append(.jumpIfNotNull(value: exceptionSlot, target: rethrowLabel))
        instructions.append(.jump(endLabel))

        instructions.append(.label(rethrowLabel))
        instructions.append(.rethrow(value: exceptionSlot))

        instructions.append(.label(endLabel))
        return result
    }
}
