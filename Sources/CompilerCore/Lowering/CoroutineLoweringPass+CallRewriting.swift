
extension CoroutineLoweringPass {
    func markAmbiguousSymbolExpr(
        _ raw: Int32,
        symbolByExprRaw: inout [Int32: SymbolID],
        ambiguousSymbolExprRaws: inout Set<Int32>
    ) -> Bool {
        var changed = false
        if symbolByExprRaw.removeValue(forKey: raw) != nil {
            changed = true
        }
        if ambiguousSymbolExprRaws.insert(raw).inserted {
            changed = true
        }
        return changed
    }

    struct SuspendRewriteContext {
        let module: KIRModule
        let ctx: KIRContext
        let anyType: TypeID?
        let intType: TypeID?
        let unitType: TypeID?
        let flowCollectCallee: InternedString
        let flowCollectLatestCallee: InternedString
        let withContextCallee: InternedString
        let runtimeWithContextCallee: InternedString
        let withTimeoutCallee: InternedString
        let runtimeWithTimeoutCallee: InternedString
        let withTimeoutOrNullCallee: InternedString
        let runtimeWithTimeoutOrNullCallee: InternedString
        let yieldCallee: InternedString
        let runtimeYieldCallee: InternedString
        let startCoroutineCallee: InternedString
        let createCoroutineCallee: InternedString
        let createCoroutineUninterceptedCallee: InternedString
        let startCoroutineUninterceptedOrReturnCallee: InternedString
        /// Link-time marker callees left behind when the source-backed
        /// receiver-less intrinsics (SuspendFunction0.kt) are inlined.
        let createCoroutineUninterceptedNoReceiverCallee: InternedString
        let startCoroutineUninterceptedOrReturnNoReceiverCallee: InternedString
        /// Marker callees left behind when the source-backed receiver-bearing
        /// intrinsics (SuspendFunction1.kt) are inlined; rewritten like the
        /// receiver-less synthetic forms.
        let createCoroutineUninterceptedWithReceiverCallee: InternedString
        let startCoroutineUninterceptedOrReturnWithReceiverCallee: InternedString
        let runtimeCreateCoroutineUninterceptedCallee: InternedString
        let runtimeStartCoroutineUninterceptedOrReturnCallee: InternedString
        let runtimeContinuationResumeCallee: InternedString
        let continuationFactory: InternedString
        let directSuspendCallCallee: InternedString
        let launcherArgSetCallee: InternedString
        let kxMiniLauncherRuntimeCallees: [InternedString: InternedString]
        let kxMiniLauncherWithContCallees: [InternedString: InternedString]
        let coroutineScopeLaunchCallee: InternedString
        let sequenceBuilderBuildCallee: InternedString
        let sequenceBuilderBuildCoroCallee: InternedString
        let sequenceBuilderYieldAllCallee: InternedString
        let sequenceBuilderYieldCallee: InternedString
        let sequenceClassSymbol: SymbolID?
        let iteratorBuilderBuildCallee: InternedString
        let iteratorBuilderBuildCoroCallee: InternedString
        let sequenceBuilderThunkByOriginalSymbol: [SymbolID: LoweredSuspendFunction]
        let loweredBySymbol: [SymbolID: LoweredSuspendFunction]
        let originalByLoweredName: [InternedString: (original: SymbolID, lowered: LoweredSuspendFunction)]
        let continuationTypeByLoweredSymbol: [SymbolID: TypeID]
        let suspendFunctionArityBySymbol: [SymbolID: Int]
        let loweredByUniqueNameArity: [SuspendCallLookupKey: LoweredSuspendFunction]
        let loweredByUniqueName: [InternedString: LoweredSuspendFunction]
        let launcherThunkByOriginalSymbol: [SymbolID: LoweredSuspendFunction]
    }

    struct CallRewriteInput {
        let instruction: KIRInstruction
        let symbol: SymbolID?
        let callee: InternedString
        let arguments: [KIRExprID]
        let result: KIRExprID?
        let canThrow: Bool
        let thrownResult: KIRExprID?
        let isSuperCall: Bool
    }

    func rewriteSuspendFunctionsAndCallSites(using rewrite: SuspendRewriteContext) {
        rewrite.module.arena.transformFunctions { function in
            var updated = function
            if function.isSuspend,
               let wrapperBody = buildSuspendWrapperBody(for: function, using: rewrite)
            {
                if function.isInline {
                    rewrite.module.inlineBodiesBeforeCoroutineLowering[function.symbol] = function.body
                }
                updated.replaceBody(
                    wrapperBody,
                    locations: Array(repeating: nil, count: wrapperBody.count)
                )
                return updated
            }

            updated.replaceBody(rewriteFunctionBody(function, using: rewrite))
            return updated
        }
        rewrite.module.arena.transformFunctions { function in
            var updated = function
            updated.replaceBody(rewriteCoroutineBuilderBuildCalls(function, using: rewrite))
            return updated
        }
    }

    func buildSuspendWrapperBody(
        for function: KIRFunction,
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard let loweredTarget = rewrite.loweredBySymbol[function.symbol] else {
            return nil
        }

        let continuationType = rewrite.continuationTypeByLoweredSymbol[loweredTarget.symbol]
            ?? rewrite.anyType
            ?? function.returnType
        let loweredFunctionIDExpr = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(loweredTarget.symbol.rawValue)),
            type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: continuationType
        )

        var wrapperBody = KIRLoweringEmitContext()
        wrapperBody.append(
            .call(
                symbol: nil,
                callee: rewrite.continuationFactory,
                arguments: [loweredFunctionIDExpr],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            )
        )

        let entryPointSymbol: SymbolID
        if function.params.isEmpty {
            entryPointSymbol = loweredTarget.symbol
        } else {
            guard let thunk = rewrite.launcherThunkByOriginalSymbol[function.symbol] else {
                return nil
            }
            entryPointSymbol = thunk.symbol
            appendWrapperArgumentSetup(
                for: function,
                continuationExpr: continuationExpr,
                using: rewrite,
                into: &wrapperBody
            )
        }

        let entryPointExpr = rewrite.module.arena.appendExpr(
            .symbolRef(entryPointSymbol),
            type: rewrite.intType
        )
        let callResult = rewrite.module.arena.appendTemporary(type: function.returnType
        )
        wrapperBody.append(
            .call(
                symbol: nil,
                callee: rewrite.ctx.interner.intern("kk_coroutine_call_suspend_wrapper"),
                arguments: [entryPointExpr, continuationExpr],
                result: callResult,
                canThrow: true,
                thrownResult: nil
            )
        )
        wrapperBody.append(.returnValue(callResult))
        return wrapperBody.instructions
    }

    func appendWrapperArgumentSetup(
        for function: KIRFunction,
        continuationExpr: KIRExprID,
        using rewrite: SuspendRewriteContext,
        into wrapperBody: inout KIRLoweringEmitContext
    ) {
        for (index, parameter) in function.params.enumerated() {
            let slotExpr = rewrite.module.arena.appendExpr(
                .intLiteral(Int64(index)),
                type: rewrite.intType
            )
            let argumentExpr = rewrite.module.arena.appendExpr(
                .symbolRef(parameter.symbol),
                type: parameter.type
            )
            wrapperBody.append(
                .call(
                    symbol: nil,
                    callee: rewrite.launcherArgSetCallee,
                    arguments: [continuationExpr, slotExpr, argumentExpr],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }
    }

    func rewriteFunctionBody(
        _ function: KIRFunction,
        using rewrite: SuspendRewriteContext
    ) -> KIRLoweringEmitContext {
        let symbolByExprRaw = propagatedSymbolReferences(
            for: function,
            interner: rewrite.ctx.interner,
            callableRefTagFunctionCallee: rewrite.ctx.interner.intern("kk_callable_ref_tag_kfunction")
        )
        // A callable value which is materialized by LambdaLowerer is normally
        // recorded in callableValueInfoByExprID.  Closure conversion can
        // leave only the `kk_function_create_N` instruction in the body,
        // however, so recover that ABI information from the producer as well.
        // Flow builders need the original adapter symbol and its packed
        // closure object to rebuild the launcher continuation below.
        var functionValueInfoByExprRaw: [Int32: KIRCallableValueInfo] = [:]
        for instruction in function.body {
            if case let .copy(from, to) = instruction,
               let info = functionValueInfoByExprRaw[from.rawValue]
            {
                functionValueInfoByExprRaw[to.rawValue] = info
            }
            if case let .call(_, callee, arguments, result, _, _, _, _) = instruction,
               rewrite.ctx.interner.resolve(callee) == "kk_function_value_fn_ptr",
               let argument = arguments.first,
               let result,
               let info = functionValueInfoByExprRaw[argument.rawValue]
            {
                functionValueInfoByExprRaw[result.rawValue] = info
            }
            guard case let .call(_, callee, arguments, result, _, _, _, _) = instruction,
                  rewrite.ctx.interner.resolve(callee).hasPrefix("kk_function_create_"),
                  let result,
                  arguments.count >= 2,
                  let functionSymbol = symbolReference(
                      for: arguments[0],
                      module: rewrite.module,
                      propagatedSymbols: symbolByExprRaw
                  )
            else {
                continue
            }
            functionValueInfoByExprRaw[result.rawValue] = KIRCallableValueInfo(
                symbol: functionSymbol,
                callee: callee,
                captureArguments: [arguments[1]],
                hasClosureParam: true
            )
        }
        // STDLIB-CORO-BUG-01: a lowered suspend function's own continuation is
        // always its last parameter (see CoroutineLoweringPass.run appending
        // continuationParameterSymbol). rewriteDirectSuspendCall needs it to
        // relay a nested suspend call's completion back to this function's
        // own suspend point instead of orphaning it on a throwaway
        // continuation. `isSuspend` alone can't distinguish a lowered suspend
        // function from an ordinary non-suspend function with parameters (both
        // have isSuspend == false), and resolveLoweredTarget's name/arity
        // fallback means a same-named/arity non-suspend function can still
        // match a suspend target -- so positively check that `function` is
        // itself a lowered suspend body (present as a key in
        // continuationTypeByLoweredSymbol) rather than inferring it from
        // isSuspend being false.
        let callerContinuationSymbol = rewrite.continuationTypeByLoweredSymbol[function.symbol] != nil
            ? function.params.last?.symbol
            : nil
        var loweredBody = KIRLoweringEmitContext()
        loweredBody.instructions.reserveCapacity(function.body.count)

        for (index, instruction) in function.body.enumerated() {
            loweredBody.currentSourceRange = index < function.instructionLocations.count
                ? function.instructionLocations[index]
                : nil
            guard case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall, _) = instruction else {
                loweredBody.append(instruction)
                continue
            }
            let call = CallRewriteInput(
                instruction: instruction,
                symbol: symbol,
                callee: callee,
                arguments: arguments,
                result: result,
                canThrow: canThrow,
                thrownResult: thrownResult,
                isSuperCall: isSuperCall
            )

            if let createInstructions = rewriteSuspendFunctionValueCreation(
                call: call, symbolByExprRaw: symbolByExprRaw, using: rewrite
            ) {
                loweredBody.append(contentsOf: createInstructions)
                continue
            }

            if rewrite.ctx.interner.resolve(callee).hasPrefix("kk_suspend_function_invoke"),
               callerContinuationSymbol == nil
            {
                let noContinuation = rewrite.module.arena.appendExpr(.intLiteral(0), type: rewrite.intType)
                loweredBody.append(.call(
                    symbol: symbol, callee: callee, arguments: arguments + [noContinuation],
                    result: result, canThrow: canThrow, thrownResult: thrownResult,
                    isSuperCall: isSuperCall
                ))
                continue
            }

            if let launcherInstructions = rewriteLauncherCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                functionValueInfoByExprRaw: functionValueInfoByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: launcherInstructions)
                continue
            }

            if let collectInstructions = rewriteFlowCollectCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: collectInstructions)
                continue
            }

            if let producerFlowCreateInstructions = rewriteProducerFlowCreateCall(
                call: call,
                functionValueInfoByExprRaw: functionValueInfoByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: producerFlowCreateInstructions)
                continue
            }

            if let flowCreateInstructions = rewriteFlowCreateCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                functionValueInfoByExprRaw: functionValueInfoByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: flowCreateInstructions)
                continue
            }

            if let withContextInstructions = rewriteWithContextCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                functionValueInfoByExprRaw: functionValueInfoByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: withContextInstructions)
                continue
            }

            if let withTimeoutInstructions = rewriteWithTimeoutCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                functionValueInfoByExprRaw: functionValueInfoByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: withTimeoutInstructions)
                continue
            }

            if let yieldInstruction = rewriteYieldCall(
                call: call,
                using: rewrite
            ) {
                loweredBody.append(yieldInstruction)
                continue
            }

            if let isLazyInstructions = rewriteCoroutineStartIsLazyCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: isLazyInstructions)
                continue
            }

            if let builderInstruction = rewriteCoroutineBuilderBuildCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(builderInstruction)
                continue
            }

            if let deepRecursiveNew = rewriteDeepRecursiveFunctionNewCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(deepRecursiveNew)
                continue
            }

            if let createCoroutineInstructions = rewriteCreateCoroutineUninterceptedCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                functionValueInfoByExprRaw: functionValueInfoByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: createCoroutineInstructions)
                continue
            }

            if let startCoroutineInstructions = rewriteStartCoroutineUninterceptedOrReturnCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                functionValueInfoByExprRaw: functionValueInfoByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: startCoroutineInstructions)
                continue
            }

            if let startCoroutineInstructions = rewriteStartCoroutineCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                functionValueInfoByExprRaw: functionValueInfoByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: startCoroutineInstructions)
                continue
            }

            if let directCallInstructions = rewriteDirectSuspendCall(
                call: call,
                callerContinuationSymbol: callerContinuationSymbol,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: directCallInstructions)
                continue
            }

            loweredBody.append(instruction)
        }
        return loweredBody
    }

    func rewriteCoroutineBuilderBuildCalls(
        _ function: KIRFunction,
        using rewrite: SuspendRewriteContext
    ) -> KIRLoweringEmitContext {
        let symbolByExprRaw = propagatedSymbolReferences(
            for: function,
            interner: rewrite.ctx.interner,
            callableRefTagFunctionCallee: rewrite.ctx.interner.intern("kk_callable_ref_tag_kfunction")
        )
        var loweredBody = KIRLoweringEmitContext()
        loweredBody.instructions.reserveCapacity(function.body.count)

        for (index, instruction) in function.body.enumerated() {
            loweredBody.currentSourceRange = index < function.instructionLocations.count
                ? function.instructionLocations[index]
                : nil
            guard case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall, _) = instruction else {
                loweredBody.append(instruction)
                continue
            }
            let call = CallRewriteInput(
                instruction: instruction,
                symbol: symbol,
                callee: callee,
                arguments: arguments,
                result: result,
                canThrow: canThrow,
                thrownResult: thrownResult,
                isSuperCall: isSuperCall
            )
            if let builderInstruction = rewriteCoroutineBuilderBuildCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(builderInstruction)
            } else if let deepRecursiveNew = rewriteDeepRecursiveFunctionNewCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(deepRecursiveNew)
            } else {
                loweredBody.append(instruction)
            }
        }
        return loweredBody
    }

    func propagatedSymbolReferences(
        for function: KIRFunction,
        interner: StringInterner,
        callableRefTagFunctionCallee: InternedString
    ) -> [Int32: SymbolID] {
        var symbolByExprRaw: [Int32: SymbolID] = [:]
        var ambiguousSymbolExprRaws: Set<Int32> = []

        for instruction in function.body {
            guard case let .constValue(result, .symbolRef(symbol)) = instruction else {
                continue
            }
            let raw = result.rawValue
            if let existing = symbolByExprRaw[raw], existing != symbol {
                _ = markAmbiguousSymbolExpr(
                    raw,
                    symbolByExprRaw: &symbolByExprRaw,
                    ambiguousSymbolExprRaws: &ambiguousSymbolExprRaws
                )
            } else if !ambiguousSymbolExprRaws.contains(raw) {
                symbolByExprRaw[raw] = symbol
            }
        }

        func propagateSymbol(from source: KIRExprID, to destination: KIRExprID) -> Bool {
            let sourceRaw = source.rawValue
            let destinationRaw = destination.rawValue
            if ambiguousSymbolExprRaws.contains(sourceRaw) {
                return markAmbiguousSymbolExpr(
                    destinationRaw,
                    symbolByExprRaw: &symbolByExprRaw,
                    ambiguousSymbolExprRaws: &ambiguousSymbolExprRaws
                )
            }
            guard let symbol = symbolByExprRaw[sourceRaw],
                  !ambiguousSymbolExprRaws.contains(destinationRaw)
            else {
                return false
            }
            if let existing = symbolByExprRaw[destinationRaw] {
                if existing != symbol {
                    return markAmbiguousSymbolExpr(
                        destinationRaw,
                        symbolByExprRaw: &symbolByExprRaw,
                        ambiguousSymbolExprRaws: &ambiguousSymbolExprRaws
                    )
                }
                return false
            }
            symbolByExprRaw[destinationRaw] = symbol
            return true
        }

        var propagated = true

        while propagated {
            propagated = false
            for instruction in function.body {
                switch instruction {
                case let .copy(from, to):
                    if propagateSymbol(from: from, to: to) {
                        propagated = true
                    }
                case let .call(_, callee, arguments, result, _, _, _, _):
                    let name = interner.resolve(callee)
                    guard callee == callableRefTagFunctionCallee
                        || name.hasPrefix("kk_function_create_")
                        || name == "kk_suspend_function_create"
                        || name == "kk_function_value_fn_ptr",
                          let result,
                          let callableExpr = arguments.first
                    else {
                        continue
                    }
                    if propagateSymbol(from: callableExpr, to: result) {
                        propagated = true
                    }
                default:
                    continue
                }
            }
        }

        return symbolByExprRaw
    }

    func symbolReference(
        for exprID: KIRExprID,
        module: KIRModule,
        propagatedSymbols: [Int32: SymbolID]
    ) -> SymbolID? {
        if let expr = module.arena.expr(exprID),
           case let .symbolRef(symbol) = expr
        {
            return symbol
        }
        if let symbol = propagatedSymbols[exprID.rawValue] {
            return symbol
        }
        return module.arena.callableValueInfo(for: exprID)?.symbol
    }
}
