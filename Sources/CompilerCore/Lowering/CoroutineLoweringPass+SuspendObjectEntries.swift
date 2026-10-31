extension CoroutineLoweringPass {
    /// KUU-3802 — reserved itable method slot under which a nominal
    /// `SuspendFunctionN` implementor's invoke launcher thunk is registered,
    /// alongside the ordinary `invoke` bridge at slot 0. The value sits far
    /// outside the method-slot range any declared interface member occupies;
    /// Runtime reads it back as `runtimeSuspendInvokeEntryMethodSlot`.
    static let suspendInvokeEntryMethodSlot = Int64(UInt32.max)

    /// Locates `kk_object_register_itable_method` calls that bind a
    /// `SuspendFunctionN` interface slot to a suspend `invoke` implementation
    /// and pairs each with the launcher thunk runtime dispatch needs.
    ///
    /// A nominal class implementing a suspend function type
    /// (`class C : suspend () -> T`) constructs through the ordinary object
    /// path: it is never wrapped in a `RuntimeFunctionValueBox`, so the
    /// suspend invoke dispatchers (`kk_suspend_function_invoke*` /
    /// `kk_create_coroutine_unintercepted_*`) cannot reach its invoke state
    /// machine and the coroutine builders trap. The launcher thunk — the
    /// `(continuation, outThrown)` entry point a callable box carries in
    /// `suspendEntryPoint` — is what the runtime needs; it is registered under
    /// `suspendInvokeEntryMethodSlot` by `appendSuspendObjectEntryRegistration`.
    ///
    /// Registration sites pair `kk_object_register_itable_iface(object, typeID,
    /// slot)` with `kk_object_register_itable_method(object, slot, method,
    /// fn)`, reusing the same slot expression, so the interface's stable type
    /// ID recovered from the former keys the latter.
    ///
    /// - Returns: method-registration instruction index → the object, the
    ///   shared interface-slot expression, and the thunk to register.
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

        // Propagate integer literals through `.copy` so the interface
        // registration's type-ID argument is recoverable even when the literal
        // reaches the call through a temporary. Mirrors the convergence scheme
        // in `propagatedSymbolReferences`: an expr raw that receives two
        // distinct values is marked ambiguous and excluded, which both keeps
        // the scan sound and guarantees the fixpoint loop terminates.
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

    /// Resolves the launcher thunk for the function pointer an itable method
    /// registration installs. Registrations carry either the implementation
    /// itself or a `kk_itable_bridge_<iface>_<impl>_<id>` adapter whose middle
    /// component is the implementation's symbol id; only suspend functions
    /// lowered by this pass own launcher thunks.
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

    /// Emits the reserved-slot twin of a `SuspendFunctionN` itable method
    /// registration: the same `(object, ifaceSlot)` pair, bound to the invoke
    /// launcher thunk at `suspendInvokeEntryMethodSlot`.
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
