/// Lowerings for the residual `use` / `usePinned` / `useContents`
/// scope-function family.
///
/// Split out from `CallLowerer+MemberCalls.swift`.
extension CallLowerer {

    // MARK: - Scope Function Lowering (STDLIB-004)

    /// Attempts to lower a residual scope function call (use/usePinned/useContents).
    /// Returns nil if the expression is not a scope function call.
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
            chosen: sema.bindings.callBinding(for: exprID)?.chosenCallee
        )
        defer { driver.ctx.pendingLambdaNonLocalReturnAllowance = previousLambdaAllowance }

        // Lower the receiver expression (or use precomputed one for safe calls).
        let loweredReceiverID = precomputedReceiver ?? driver.lowerExpr(
            receiverExpr,
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        switch scopeKind {
        case .scopeUseContents:
            // useContents: lambda has the contained C variable as implicit receiver.
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

            let savedReceiverExprID = driver.ctx.activeImplicitReceiverExprID()
            let savedReceiverSymbol = driver.ctx.activeImplicitReceiverSymbol()
            driver.ctx.setLocalValue(receiverSymExpr, for: receiverSymbol)
            driver.ctx.setImplicitReceiver(symbol: receiverSymbol, exprID: receiverSymExpr)

            let loweredLambdaID = driver.lowerExpr(
                args[0].expr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

            driver.ctx.restoreImplicitReceiver(symbol: savedReceiverSymbol, exprID: savedReceiverExprID)

            let result = arena.appendTemporary(type: boundType)
            if let info = driver.ctx.callableValueInfo(for: loweredLambdaID) {
                instructions.append(.call(
                    symbol: info.symbol,
                    callee: info.callee,
                    arguments: info.captureArguments,
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                return nil
            }
            return result

        case .scopeUse:
            // use: like `let`, lambda takes `it` as explicit parameter,
            // but receiver.close() is called in a finally block (try-finally semantics).
            // If the block throws, close() is still called before the exception propagates.
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

            let intType = sema.types.make(.primitive(.int, .nonNull))

            // Exception tracking slots for try-finally.
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

            // try: invoke the block lambda.
            // Collection-HOF-marked lambdas take a leading closureRaw argument:
            // no captures -> 0, one capture -> the raw capture value, two or more
            // -> a packed closure object built by makeBoxedCallableCaptureArguments.
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
            blockInstructions.append(.call(
                symbol: info.symbol,
                callee: info.callee,
                arguments: callArgs,
                result: result,
                canThrow: true,
                thrownResult: nil
            ))

            // Wrap block call with throw-aware instructions so exceptions are
            // captured into exceptionSlot and control jumps to finallyLabel.
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

            // finally: call close() on the receiver via virtual dispatch.
            // close() is an interface method on Closeable and requires dynamic dispatch
            // through the itable so that concrete implementations are invoked correctly.
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
            let closeName = interner.intern("close")
            let closeResult = arena.appendTemporary(type: sema.types.unitType
            )
            // Resolve the close() symbol from the AutoCloseable interface and use
            // virtualCall with interface dispatch instead of a static .call.
            let closeSymbol: SymbolID? = sema.types.closeableInterfaceSymbol.flatMap { closeableSymbol in
                let closeableFQName = sema.symbols.symbol(closeableSymbol)?.fqName ?? []
                return sema.symbols.lookup(fqName: closeableFQName + [closeName])
            }
            let closeDispatch: KIRDispatchKind? = closeSymbol.flatMap { sym in
                resolveVirtualDispatch(callee: sym, receiverTypeID: receiverTypeForDispatch, sema: sema, interner: interner)
            }
            if let closeDispatch, let closeSymbol {
                instructions.append(.virtualCall(
                    symbol: closeSymbol,
                    callee: closeName,
                    receiver: loweredReceiverID,
                    arguments: [],
                    result: closeResult,
                    canThrow: true,
                    thrownResult: nil,
                    dispatch: closeDispatch
                ))
            } else {
                // Fallback: if virtual dispatch is not needed (e.g. final class with
                // no subtypes), resolve the concrete close() method on the receiver type
                // so that the static call targets the correct mangled name.
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
                            // Prefer the externalLinkName (e.g. __kk_buffered_writer_close) over
                            // the Kotlin symbol name (which would just be "close") so that the
                            // generated .call instruction targets the correct runtime C function.
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
                instructions.append(.call(
                    symbol: callSymbol,
                    callee: concreteCloseName,
                    arguments: [loweredReceiverID],
                    result: closeResult,
                    canThrow: true,
                    thrownResult: nil
                ))
            }
            if let closeEndLabel {
                instructions.append(.label(closeEndLabel))
            }

            // After finally: rethrow if an exception was caught, otherwise continue.
            instructions.append(.jumpIfNotNull(value: exceptionSlot, target: rethrowLabel))
            instructions.append(.jump(endLabel))

            instructions.append(.label(rethrowLabel))
            instructions.append(.rethrow(value: exceptionSlot))

            instructions.append(.label(endLabel))
            return result

        case .scopeUsePinned:
            // usePinned (STDLIB-CINTEROP-FN-042): pin() the receiver, invoke
            // block(pinned) inside a try, then unpin() in a finally block.
            // Shaped like scopeUse's try-finally, but: (a) the call that produces
            // the value handed to the lambda is pin() itself, not the receiver, and
            // (b) cleanup is a concrete call to Pinned<T>.unpin(), not a virtual
            // dispatch to close() — Pinned is a final synthetic class.
            let loweredLambdaID = driver.lowerExpr(
                args[0].expr,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            guard let info = driver.ctx.callableValueInfo(for: loweredLambdaID) else {
                return nil
            }

            let pinFQName: [InternedString] = [
                interner.intern("kotlinx"), interner.intern("cinterop"), interner.intern("pin"),
            ]
            guard let pinSymbol = sema.symbols.lookup(fqName: pinFQName),
                  let pinSignature = sema.symbols.functionSignature(for: pinSymbol)
            else {
                return nil
            }

            // The lambda's inferred parameter type is the concrete Pinned<T>;
            // fall back to pin()'s own (generic) return type if unavailable.
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
                canThrow: false,
                thrownResult: nil
            ))

            let result = arena.appendTemporary(type: boundType
            )

            let intType = sema.types.make(.primitive(.int, .nonNull))

            // Exception tracking slots for try-finally.
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

            // try: invoke the block lambda with the pinned handle.
            // Collection-HOF-marked lambdas take a leading closureRaw argument
            // (see scopeUse above).
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
            blockInstructions.append(.call(
                symbol: info.symbol,
                callee: info.callee,
                arguments: callArgs,
                result: result,
                canThrow: true,
                thrownResult: nil
            ))

            // CODE-001: guard against an outer try/catch/use re-wrapping this
            // already-routed call if `usePinned` is itself nested inside one
            // (see the matching guard in the scopeUse case above).
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

            // finally: unpin() the handle. Concrete call — Pinned is a final
            // synthetic class, so no virtual dispatch is needed.
            instructions.append(.label(finallyLabel))
            let unpinResult = arena.appendTemporary(type: sema.types.unitType
            )
            instructions.append(.call(
                symbol: unpinSymbol,
                callee: resolvedCalleeName(for: unpinSymbol, fallback: "unpin"),
                arguments: [pinnedResult],
                result: unpinResult,
                canThrow: false,
                thrownResult: nil
            ))

            // After finally: rethrow if an exception was caught, otherwise continue.
            instructions.append(.jumpIfNotNull(value: exceptionSlot, target: rethrowLabel))
            instructions.append(.jump(endLabel))

            instructions.append(.label(rethrowLabel))
            instructions.append(.rethrow(value: exceptionSlot))

            instructions.append(.label(endLabel))
            return result

        case .scopeContext:
            return nil // context is handled in lowerCallExpr
        }
    }
}
