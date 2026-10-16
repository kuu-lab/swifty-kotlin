/// `this` / `super` reference lowering used by
/// `ExprLowerer.lowerExpr`: implicit and labeled receiver
/// resolution through the active-receiver and outer-class chains.
///
/// Split out from `ExprLowerer+ControlFlowAndBlocks.swift`.
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
            if let receiverExprID = driver.ctx.activeImplicitReceiverExprID(),
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
        if let label,
           let receiverExprID = driver.ctx.qualifiedThisReceiverExprID(for: label)
        {
            return receiverExprID
        }
        // BUG-inner-outer: `this@Outer` from within an inner class's
        // body resolves (Sema binds this `.thisRef` expression's own
        // type to Outer's) to an *enclosing* class, not the active
        // implicit receiver (Inner's own `this`) the fallback below
        // would otherwise silently return. Walk the `$outer` chain
        // from the active implicit receiver to Outer's instance
        // instead. A no-op when this `.thisRef` names the innermost
        // receiver's own class already (0 hops) or isn't reachable
        // through any `$outer` link (e.g. inside a lambda/object
        // literal, where `qualifiedThisReceiverExprID` above is the
        // right mechanism).
        if label != nil,
           let implicitReceiverExprID = driver.ctx.activeImplicitReceiverExprID(),
           let thisRefType = sema.bindings.exprTypes[exprID],
           let (_, targetClassSymbol) = resolveClassTypeSymbol(thisRefType, sema: sema),
           let outerValue = resolveOuterChainValue(
               from: implicitReceiverExprID,
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
}
