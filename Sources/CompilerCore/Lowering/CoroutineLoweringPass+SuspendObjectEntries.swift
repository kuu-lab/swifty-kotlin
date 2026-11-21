extension CoroutineLoweringPass {
    /// KUU-3802 — reserved itable method slot under which a nominal
    /// `SuspendFunctionN` implementor's invoke launcher thunk is registered,
    /// alongside the ordinary `invoke` bridge at slot 0. The value sits far
    /// outside the method-slot range any declared interface member occupies;
    /// Runtime reads it back as `runtimeSuspendInvokeEntryMethodSlot`.
    static let suspendInvokeEntryMethodSlot = Int64(UInt32.max)

    func suspendObjectEntryRegistrations(
        in function: KIRFunction,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [Int: (objectExpr: KIRExprID, slotExpr: KIRExprID, thunkSymbol: SymbolID)] {
        guard let sema = rewrite.ctx.sema else { return [:] }
        var suspendInterfaceTypeIDs: Set<Int64> = []
        for (_, symbol) in sema.types.suspendFunctionNInterfaceSymbols {
            suspendInterfaceTypeIDs.insert(
                RuntimeTypeCheckToken.stableNominalTypeID(
                    symbol: symbol, sema: sema, interner: rewrite.ctx.interner
                )
            )
        }
        guard !suspendInterfaceTypeIDs.isEmpty else { return [:] }

        let interner = rewrite.ctx.interner
        let ifaceRegisterCallee = interner.intern("kk_object_register_itable_iface")
        let methodRegisterCallee = interner.intern("kk_object_register_itable_method")

        var intLiteralByExprRaw: [Int32: Int64] = [:]
        var ambiguousLiteralExprRaws: Set<Int32> = []
        for instruction in function.body {
            guard case let .constValue(result, .intLiteral(value)) = instruction else {
                continue
            }
            let raw = result.rawValue
            if let existing = intLiteralByExprRaw[raw], existing != value {
                intLiteralByExprRaw.removeValue(forKey: raw)
                ambiguousLiteralExprRaws.insert(raw)
            } else if !ambiguousLiteralExprRaws.contains(raw) {
                intLiteralByExprRaw[raw] = value
            }
        }

        var propagated = true
        while propagated {
            propagated = false
            for instruction in function.body {
                guard case let .copy(from, to) = instruction else {
                    continue
                }
                let sourceRaw = from.rawValue
                let destinationRaw = to.rawValue
                if ambiguousLiteralExprRaws.contains(sourceRaw) {
                    if ambiguousLiteralExprRaws.insert(destinationRaw).inserted {
                        intLiteralByExprRaw.removeValue(forKey: destinationRaw)
                        propagated = true
                    }
                    continue
                }
                guard let value = intLiteralByExprRaw[sourceRaw],
                      !ambiguousLiteralExprRaws.contains(destinationRaw)
                else {
                    continue
                }
                if let existing = intLiteralByExprRaw[destinationRaw] {
                    if existing != value {
                        intLiteralByExprRaw.removeValue(forKey: destinationRaw)
                        ambiguousLiteralExprRaws.insert(destinationRaw)
                        propagated = true
                    }
                    continue
                }
                intLiteralByExprRaw[destinationRaw] = value
                propagated = true
            }
        }

        var suspendSlotExprRaws: Set<Int32> = []
        var registrations: [Int: (objectExpr: KIRExprID, slotExpr: KIRExprID, thunkSymbol: SymbolID)] = [:]
        for (index, instruction) in function.body.enumerated() {
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction else {
                continue
            }
            if callee == ifaceRegisterCallee,
               arguments.count == 3,
               let interfaceTypeID = intLiteralByExprRaw[arguments[1].rawValue],
               suspendInterfaceTypeIDs.contains(interfaceTypeID)
            {
                suspendSlotExprRaws.insert(arguments[2].rawValue)
                continue
            }
            guard callee == methodRegisterCallee,
                  arguments.count == 4,
                  suspendSlotExprRaws.contains(arguments[1].rawValue),
                  let functionSymbol = symbolByExprRaw[arguments[3].rawValue],
                  let thunkSymbol = suspendInvokeThunkSymbol(
                      forRegisteredSymbol: functionSymbol,
                      using: rewrite
                  )
            else {
                continue
            }
            registrations[index] = (
                objectExpr: arguments[0],
                slotExpr: arguments[1],
                thunkSymbol: thunkSymbol
            )
        }
        return registrations
    }

    private func suspendInvokeThunkSymbol(
        forRegisteredSymbol functionSymbol: SymbolID,
        using rewrite: SuspendRewriteContext
    ) -> SymbolID? {
        if let thunk = rewrite.launcherThunkByOriginalSymbol[functionSymbol] {
            return thunk.symbol
        }
        guard let bridgeName = rewrite.module.arena.function(for: functionSymbol)?.name else {
            return nil
        }
        let resolvedName = rewrite.ctx.interner.resolve(bridgeName)
        guard resolvedName.hasPrefix("kk_itable_bridge_") else {
            return nil
        }
        let components = resolvedName.split(separator: "_")
        guard components.count == 6,
              let implementationRaw = Int32(components[4])
        else {
            return nil
        }
        return rewrite.launcherThunkByOriginalSymbol[SymbolID(rawValue: implementationRaw)]?.symbol
    }

    func appendSuspendObjectEntryRegistration(
        objectExpr: KIRExprID,
        slotExpr: KIRExprID,
        thunkSymbol: SymbolID,
        into loweredBody: inout KIRLoweringEmitContext,
        using rewrite: SuspendRewriteContext
    ) {
        let sentinelExpr = rewrite.module.arena.appendExpr(
            .intLiteral(Self.suspendInvokeEntryMethodSlot),
            type: rewrite.intType
        )
        loweredBody.append(.constValue(
            result: sentinelExpr,
            value: .intLiteral(Self.suspendInvokeEntryMethodSlot)
        ))
        let thunkExpr = rewrite.module.arena.appendExpr(
            .symbolRef(thunkSymbol),
            type: rewrite.intType
        )
        loweredBody.append(.constValue(
            result: thunkExpr,
            value: .symbolRef(thunkSymbol)
        ))
        let registerResult = rewrite.module.arena.appendTemporary(type: rewrite.intType)
        loweredBody.append(.call(
            callee: rewrite.ctx.interner.intern("kk_object_register_itable_method"),
            arguments: [objectExpr, slotExpr, sentinelExpr, thunkExpr],
            result: registerResult,
            canThrow: false
        ))
    }
}
