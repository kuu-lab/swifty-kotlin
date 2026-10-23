extension ExprLowerer {
    func lowerSuperRefExpr(
        exprID: ExprID,
        label: InternedString?,
        boundType: TypeID?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        if let label,
           let ownerSymbol = sema.bindings.identifierSymbol(for: exprID)
        {
            if let receiverExprID = driver.ctx.qualifiedThisReceiverExprID(for: label) {
                return receiverExprID
            }
            if let receiverExprID = driver.ctx.localValue(for: ownerSymbol) {
                return receiverExprID
            }
            let outerChainStart = memberExtensionDispatchReceiverExprID(sema: sema)
                ?? driver.ctx.capturedOuterReceiverExprID(reaching: ownerSymbol, sema: sema)
                ?? driver.ctx.activeImplicitReceiverExprID()
            if let receiverExprID = outerChainStart,
               let outerReceiverExprID = resolveOuterChainValue(
                   from: receiverExprID,
                   to: ownerSymbol,
                   sema: sema,
                   arena: arena,
                   interner: interner,
                   instructions: &instructions
               )
            {
                return outerReceiverExprID
            }
        }
        if let boundType,
           let (_, superClassSymbol) = resolveClassTypeSymbol(boundType, sema: sema),
           let dispatchReceiver = memberExtensionDispatchReceiverExprID(sema: sema)
               ?? driver.ctx.capturedOuterReceiverExprID(reaching: superClassSymbol.id, sema: sema)
        {
            return dispatchReceiver
        }
        if let dispatchReceiver = memberExtensionDispatchReceiverExprID(sema: sema) {
            return dispatchReceiver
        }
        if let receiverExprID = driver.ctx.activeImplicitReceiverExprID() {
            return receiverExprID
        }
        let unit = arena.appendExpr(.unit, type: boundType ?? sema.types.errorType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    func lowerThisRefExpr(
        label: InternedString?,
        exprID: ExprID,
        boundType: TypeID?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        if let receiverSymbol = sema.bindings.identifierSymbol(for: exprID),
           let receiverExprID = driver.ctx.localValue(for: receiverSymbol)
        {
            return receiverExprID
        }
        if let receiverSymbol = sema.bindings.identifierSymbol(for: exprID),
           sema.symbols.symbol(receiverSymbol)?.kind == .object
        {
            driver.emitObjectLazyInitGuardIfNeeded(
                objectSymbol: receiverSymbol,
                arena: arena,
                sema: sema,
                interner: interner,
                instructions: &instructions
            )
            let receiverType = boundType ?? sema.symbols.propertyType(for: receiverSymbol) ?? sema.types.anyType
            let receiver = arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
            instructions.append(.constValue(result: receiver, value: .symbolRef(receiverSymbol)))
            return receiver
        }
        if let label,
           let receiverExprID = driver.ctx.qualifiedThisReceiverExprID(for: label)
        {
            return receiverExprID
        }
        // BUG-inner-outer: `this@Outer` from within an inner class's
        // body resolves (Sema binds this `.thisRef` expression's own
        // type to Outer's) to an *enclosing* class, not the active
        // implicit receiver (Inner's own `this`) the fallback below
        // would otherwise silently return. Member extensions use their
        // dispatch receiver as the `$outer` chain's starting point instead
        // of the active extension receiver. This is a no-op when the target
        // is the current class; lambda/object-literal captures use the
        // `qualifiedThisReceiverExprID` lookup above.
        if label != nil,
           let implicitReceiverExprID = driver.ctx.activeImplicitReceiverExprID(),
           let thisRefType = sema.bindings.exprTypes[exprID],
           let (_, targetClassSymbol) = resolveClassTypeSymbol(thisRefType, sema: sema),
           let outerValue = resolveOuterChainValue(
               from: memberExtensionDispatchReceiverExprID(sema: sema)
                   ?? driver.ctx.capturedOuterReceiverExprID(reaching: targetClassSymbol.id, sema: sema)
                   ?? implicitReceiverExprID,
               to: targetClassSymbol.id,
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            return outerValue
        }
        if let receiverExprID = driver.ctx.activeImplicitReceiverExprID() {
            return receiverExprID
        }
        let unit = arena.appendExpr(.unit, type: boundType ?? sema.types.errorType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    private func memberExtensionDispatchReceiverExprID(sema: SemaModule) -> KIRExprID? {
        guard let functionSymbol = driver.ctx.activeFunctionSymbol(),
              let ownerSymbol = sema.symbols.memberExtensionOwnerSymbol(for: functionSymbol)
        else {
            return nil
        }
        return driver.ctx.localValue(for: ownerSymbol)
            ?? driver.ctx.capturedOuterReceiverExprID(for: ownerSymbol)
    }
}
