extension CallLowerer {
    /// Emits the implicit `inc()`/`dec()` invocation behind `++`/`--`.
    ///
    /// The synthesized call carries no explicit arguments, so every declared
    /// parameter is omitted and must be supplied through the callee's
    /// `<name>$default` stub -- the same convention an explicit `a.inc()`
    /// call already uses. Leading slots follow the direct-call ABI:
    /// local-function captures, then the member-extension dispatch receiver,
    /// then the `++` target itself (see
    /// `CallSupportLowerer.generateDefaultStubFunction`). The stub performs
    /// its own virtual dispatch on the receiver, so it is always invoked
    /// with a direct `.call`.
    func emitIncrementDecrementOperatorCall(
        callBinding: CallBinding,
        operatorName: String,
        receiverArgument: KIRExprID,
        callExprID: ExprID?,
        result: KIRExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) {
        let callee = callBinding.chosenCallee
        let normalized = driver.callSupportLowerer.normalizedCallArguments(
            providedArguments: [],
            callBinding: callBinding,
            chosenCallee: callee,
            spreadFlags: [],
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        var leadingReceivers: [KIRExprID] = []
        if sema.symbols.symbol(callee)?.flags.contains(.localFunction) == true {
            // A local function is materialized as a function object that
            // already carries the lifted capture environment. Reuse those
            // capture values exactly like a direct call does (see
            // `CallLowerer+CallExpr`), falling back to Sema's declaration-time
            // capture list for contexts without callable-value metadata.
            if let callableInfo = driver.ctx.localValue(for: callee)
                .flatMap({ driver.ctx.callableValueInfo(for: $0) }),
               !callableInfo.captureArguments.isEmpty
            {
                leadingReceivers.append(contentsOf: callableInfo.captureArguments)
            } else {
                for capturedSymbol in sema.bindings.localFunctionCaptureSymbols(for: callee) {
                    guard let captureValue = driver.lambdaLowerer.captureValueExpr(
                        for: capturedSymbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    ) else {
                        assertionFailure("BuildKIRPhase: missing local operator capture '\(capturedSymbol)'")
                        continue
                    }
                    leadingReceivers.append(captureValue)
                }
            }
        }
        // Member extensions (`fun T.inc()` declared inside a nominal type)
        // carry the dispatch receiver (`this@Owner`) ahead of the extension
        // receiver; virtual dispatch targets it, not the extension receiver.
        let dispatchReceiver = memberExtensionDispatchReceiver(
            for: callee,
            callExprID: callExprID,
            dispatchReceiverSymbol: callBinding.dispatchReceiverSymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        if let dispatchReceiver {
            leadingReceivers.append(dispatchReceiver)
        }
        var finalArguments = normalized.arguments
        finalArguments.insert(receiverArgument, at: 0)
        appendReifiedTypeTokens(
            chosenCallee: callee,
            callBinding: callBinding,
            sema: sema,
            interner: interner,
            arena: arena,
            instructions: &instructions,
            arguments: &finalArguments
        )
        finalArguments.insert(contentsOf: leadingReceivers, at: 0)
        // KUU-655: an override that inherits its defaults never has its own
        // stub; resolve to the base declaration's stub instead (see
        // `defaultStubOwnerSymbol`). Operators have no `super.` syntax, so no
        // mask "super call" bit applies here.
        let stubOwner = driver.callSupportLowerer.defaultStubOwnerSymbol(
            for: callee, sema: sema, callBinding: callBinding
        )
        let stubSymbol = driver.callSupportLowerer.defaultStubSymbol(for: stubOwner)
        if normalized.hasOmittedDefaultArguments,
           sema.symbols.externalLinkName(for: callee)?.isEmpty ?? true
            || sema.symbols.externalLinkName(for: stubSymbol) != nil
        {
            appendDefaultMaskArguments(
                normalized.defaultMaskWords,
                sema: sema,
                arena: arena,
                instructions: &instructions,
                arguments: &finalArguments
            )
            let stubName = interner.intern(
                (sema.symbols.symbol(callee).map { interner.resolve($0.name) } ?? operatorName) + "$default"
            )
            instructions.append(.call(
                symbol: stubSymbol,
                callee: stubName,
                arguments: finalArguments,
                result: result,
                canThrow: false
            ))
            return
        }
        let loweredCalleeName: InternedString = if let externalLinkName = sema.symbols.externalLinkName(for: callee),
                                                 !externalLinkName.isEmpty
        {
            interner.intern(externalLinkName)
        } else {
            sema.symbols.symbol(callee)?.name ?? interner.intern(operatorName)
        }
        let resolvedMemberName = sema.symbols.symbol(callee)
            .map { interner.resolve($0.name) }
            ?? interner.resolve(loweredCalleeName)
        if emitRuntimeBackedCollectionMemberCallIfNeeded(
            memberName: resolvedMemberName,
            receiverType: arena.exprType(receiverArgument) ?? sema.types.anyType,
            chosenCallee: callee,
            arguments: finalArguments,
            result: result,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) {
            return
        }
        // An open/abstract member operator dispatches on the receiver's
        // runtime type, exactly like `lhs.inc()`; the extension receiver is
        // an ordinary leading argument for member extensions.
        if let virtualInstruction = tryEmitVirtualDispatch(
            chosenCallee: callee,
            calleeName: loweredCalleeName,
            receiverExpr: nil,
            loweredReceiverID: dispatchReceiver ?? receiverArgument,
            isSuperCall: false,
            finalArguments: finalArguments,
            result: result,
            sema: sema,
            arena: arena,
            interner: interner
        ) {
            instructions.append(virtualInstruction)
        } else {
            instructions.append(.call(
                symbol: callee,
                callee: loweredCalleeName,
                arguments: finalArguments,
                result: result,
                canThrow: false
            ))
        }
    }
}
