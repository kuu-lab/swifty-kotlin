
extension CoroutineLoweringPass {
    struct SuspendRewriteContext {
        let module: KIRModule
        let ctx: KIRContext
        let anyType: TypeID?
        let intType: TypeID?
        let unitType: TypeID?
        let flowCollectCallee: InternedString
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
        let runtimeCreateCoroutineUninterceptedCallee: InternedString
        let runtimeStartCoroutineUninterceptedOrReturnCallee: InternedString
        let runtimeContinuationResumeCallee: InternedString
        let continuationFactory: InternedString
        let directSuspendCallCallee: InternedString
        let launcherArgSetCallee: InternedString
        let runtimeRunBlockingWithContCallee: InternedString
        let kxMiniLauncherRuntimeCallees: [InternedString: InternedString]
        let kxMiniLauncherWithContCallees: [InternedString: InternedString]
        let sequenceBuilderBuildCallee: InternedString
        let sequenceBuilderBuildCoroCallee: InternedString
        let sequenceBuilderYieldAllCallee: InternedString
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
                updated.replaceBody(wrapperBody)
                updated.replaceInstructionLocations(Array(repeating: nil, count: wrapperBody.count))
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

        var wrapperBody: [KIRInstruction] = [
            .call(
                symbol: nil,
                callee: rewrite.continuationFactory,
                arguments: [loweredFunctionIDExpr],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            ),
        ]

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
                callee: rewrite.runtimeRunBlockingWithContCallee,
                arguments: [entryPointExpr, continuationExpr],
                result: callResult,
                canThrow: true,
                thrownResult: nil
            )
        )
        wrapperBody.append(.returnValue(callResult))
        return wrapperBody
    }

    func appendWrapperArgumentSetup(
        for function: KIRFunction,
        continuationExpr: KIRExprID,
        using rewrite: SuspendRewriteContext,
        into wrapperBody: inout [KIRInstruction]
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
    ) -> [KIRInstruction] {
        let symbolByExprRaw = propagatedSymbolReferences(
            for: function,
            callableRefTagFunctionCallee: rewrite.ctx.interner.intern("kk_callable_ref_tag_kfunction")
        )
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
        var loweredBody: [KIRInstruction] = []
        loweredBody.reserveCapacity(function.body.count)

        for instruction in function.body {
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

            if let launcherInstructions = rewriteLauncherCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: launcherInstructions)
                continue
            }

            if let collectInstruction = rewriteFlowCollectCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(collectInstruction)
                continue
            }

            if let withContextInstructions = rewriteWithContextCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: withContextInstructions)
                continue
            }

            if let withTimeoutInstructions = rewriteWithTimeoutCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
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

            if let builderInstruction = rewriteCoroutineBuilderBuildCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(builderInstruction)
                continue
            }

            if let createCoroutineInstructions = rewriteCreateCoroutineUninterceptedCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: createCoroutineInstructions)
                continue
            }

            if let startCoroutineInstructions = rewriteStartCoroutineUninterceptedOrReturnCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: startCoroutineInstructions)
                continue
            }

            if let startCoroutineInstructions = rewriteStartCoroutineCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
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
    ) -> [KIRInstruction] {
        let symbolByExprRaw = propagatedSymbolReferences(
            for: function,
            callableRefTagFunctionCallee: rewrite.ctx.interner.intern("kk_callable_ref_tag_kfunction")
        )
        var loweredBody: [KIRInstruction] = []
        loweredBody.reserveCapacity(function.body.count)

        for instruction in function.body {
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
            } else {
                loweredBody.append(instruction)
            }
        }
        return loweredBody
    }

    func propagatedSymbolReferences(
        for function: KIRFunction,
        callableRefTagFunctionCallee: InternedString
    ) -> [Int32: SymbolID] {
        var symbolByExprRaw: [Int32: SymbolID] = [:]
        var ambiguousSymbolExprRaws: Set<Int32> = []

        func markAmbiguousSymbolExpr(_ raw: Int32) -> Bool {
            var changed = false
            if symbolByExprRaw.removeValue(forKey: raw) != nil {
                changed = true
            }
            if ambiguousSymbolExprRaws.insert(raw).inserted {
                changed = true
            }
            return changed
        }

        for instruction in function.body {
            guard case let .constValue(result, .symbolRef(symbol)) = instruction else {
                continue
            }
            let raw = result.rawValue
            if let existing = symbolByExprRaw[raw], existing != symbol {
                _ = markAmbiguousSymbolExpr(raw)
            } else if !ambiguousSymbolExprRaws.contains(raw) {
                symbolByExprRaw[raw] = symbol
            }
        }

        func propagateSymbol(from source: KIRExprID, to destination: KIRExprID) -> Bool {
            let sourceRaw = source.rawValue
            let destinationRaw = destination.rawValue
            if ambiguousSymbolExprRaws.contains(sourceRaw) {
                return markAmbiguousSymbolExpr(destinationRaw)
            }
            guard let symbol = symbolByExprRaw[sourceRaw],
                  !ambiguousSymbolExprRaws.contains(destinationRaw)
            else {
                return false
            }
            if let existing = symbolByExprRaw[destinationRaw] {
                if existing != symbol {
                    return markAmbiguousSymbolExpr(destinationRaw)
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
                    guard callee == callableRefTagFunctionCallee,
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

    func rewriteFlowCollectCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> KIRInstruction? {
        guard call.callee == rewrite.flowCollectCallee,
              call.arguments.count == 3,
              let collectorSymbol = symbolReference(
                  for: call.arguments[1],
                  module: rewrite.module,
                  propagatedSymbols: symbolByExprRaw
              ),
              let loweredCollector = rewrite.loweredBySymbol[collectorSymbol]
        else {
            return nil
        }

        let collectorEntryPoint = rewrite.module.arena.appendExpr(
            .symbolRef(loweredCollector.symbol),
            type: rewrite.intType
        )
        let collectorFunctionID = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(loweredCollector.symbol.rawValue)),
            type: rewrite.intType
        )

        var rewrittenArguments = call.arguments
        rewrittenArguments[1] = collectorEntryPoint
        rewrittenArguments[2] = collectorFunctionID
        return .call(
            symbol: call.symbol,
            callee: call.callee,
            arguments: rewrittenArguments,
            result: call.result,
            canThrow: call.canThrow,
            thrownResult: call.thrownResult,
            isSuperCall: call.isSuperCall
        )
    }

    func rewriteWithContextCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard call.callee == rewrite.withContextCallee,
              call.arguments.count >= 2,
              let referencedSymbol = symbolReference(
                  for: call.arguments[1],
                  module: rewrite.module,
                  propagatedSymbols: symbolByExprRaw
              ),
              let loweredTarget = rewrite.loweredBySymbol[referencedSymbol]
        else {
            return nil
        }

        let dispatcherExpr = call.arguments[0]
        let extraArgs = Array(call.arguments.dropFirst(2))
        let targetArity = rewrite.suspendFunctionArityBySymbol[referencedSymbol] ?? 0
        guard extraArgs.count == targetArity else {
            rewrite.ctx.diagnostics.error(
                "KSWIFTK-CORO-0004",
                "withContext block capture arity mismatch.",
                range: nil
            )
            return [call.instruction]
        }

        let entryTarget: LoweredSuspendFunction
        var rewritten: [KIRInstruction] = []
        let continuationFunctionID = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: rewrite.continuationTypeByLoweredSymbol[loweredTarget.symbol] ?? rewrite.anyType
        )

        if extraArgs.isEmpty {
            entryTarget = loweredTarget
        } else {
            guard let thunk = rewrite.launcherThunkByOriginalSymbol[referencedSymbol] else {
                return [call.instruction]
            }
            entryTarget = thunk
        }

        rewritten.append(.constValue(
            result: continuationFunctionID,
            value: .intLiteral(Int64(loweredTarget.symbol.rawValue))
        ))
        rewritten.append(.call(
            symbol: nil,
            callee: rewrite.continuationFactory,
            arguments: [continuationFunctionID],
            result: continuationExpr,
            canThrow: false,
            thrownResult: nil
        ))

        for (index, argExpr) in extraArgs.enumerated() {
            let slotExpr = rewrite.module.arena.appendExpr(
                .intLiteral(Int64(index)),
                type: rewrite.intType
            )
            rewritten.append(.call(
                symbol: nil,
                callee: rewrite.launcherArgSetCallee,
                arguments: [continuationExpr, slotExpr, argExpr],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
        }

        let entryPointExpr = rewrite.module.arena.appendExpr(
            .symbolRef(entryTarget.symbol),
            type: rewrite.intType
        )
        rewritten.append(.call(
            symbol: nil,
            callee: rewrite.runtimeWithContextCallee,
            arguments: [dispatcherExpr, entryPointExpr, continuationExpr],
            result: call.result,
            canThrow: call.canThrow,
            thrownResult: call.thrownResult
        ))
        return rewritten
    }

    func rewriteDirectSuspendCall(
        call: CallRewriteInput,
        callerContinuationSymbol: SymbolID?,
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard let loweredTarget = resolveLoweredTarget(
            symbol: call.symbol,
            callee: call.callee,
            arity: call.arguments.count,
            using: rewrite
        ) else {
            return nil
        }
        let continuationFunctionID = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        // Synthetic KIR fixtures and non-suspend callers do not carry a lowered
        // caller continuation. Preserve their historical continuation argument
        // shape; only lowered suspend bodies can use the relay ABI below.
        guard let callerContinuationSymbol else {
            let continuationTemp = rewrite.module.arena.appendTemporary(
                type: rewrite.continuationTypeByLoweredSymbol[loweredTarget.symbol] ?? rewrite.anyType
            )
            return [
                .constValue(
                    result: continuationFunctionID,
                    value: .intLiteral(Int64(loweredTarget.symbol.rawValue))
                ),
                .call(
                    symbol: nil,
                    callee: rewrite.continuationFactory,
                    arguments: [continuationFunctionID],
                    result: continuationTemp,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: loweredTarget.symbol,
                    callee: loweredTarget.name,
                    arguments: call.arguments + [continuationTemp],
                    result: call.result,
                    canThrow: call.canThrow,
                    thrownResult: call.thrownResult,
                    isSuperCall: call.isSuperCall
                ),
            ]
        }

        // STDLIB-CORO-BUG-01: a direct call from one suspend function's body to
        // another must relay the callee's completion back into this function's
        // own suspend point through kk_coroutine_call_direct_suspend.
        let childContinuationTemp = rewrite.module.arena.appendTemporary(type: rewrite.continuationTypeByLoweredSymbol[loweredTarget.symbol] ?? rewrite.anyType
        )

        var instructions: [KIRInstruction] = [
            .constValue(
                result: continuationFunctionID,
                value: .intLiteral(Int64(loweredTarget.symbol.rawValue))
            ),
            .call(
                symbol: nil,
                callee: rewrite.continuationFactory,
                arguments: [continuationFunctionID],
                result: childContinuationTemp,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        // A suspend function with parameters is invoked through its launcher
        // thunk (the same adapter launch/async/runBlocking use), which reads
        // the real arguments back out of the child continuation's launcher-arg
        // storage. A 0-arg suspend function's lowered form already matches the
        // (continuation) -> Int entry-point shape directly.
        let entryPointSymbol: SymbolID
        if call.arguments.isEmpty {
            entryPointSymbol = loweredTarget.symbol
        } else {
            let originalSymbol = call.symbol ?? rewrite.originalByLoweredName[loweredTarget.name]?.original
            guard let originalSymbol,
                  let thunk = rewrite.launcherThunkByOriginalSymbol[originalSymbol]
            else {
                return nil
            }
            entryPointSymbol = thunk.symbol
            for (index, argumentExpr) in call.arguments.enumerated() {
                let slotExpr = rewrite.module.arena.appendExpr(
                    .intLiteral(Int64(index)),
                    type: rewrite.intType
                )
                instructions.append(
                    .call(
                        symbol: nil,
                        callee: rewrite.launcherArgSetCallee,
                        arguments: [childContinuationTemp, slotExpr, argumentExpr],
                        result: nil,
                        canThrow: false,
                        thrownResult: nil
                    )
                )
            }
        }

        let entryPointExpr = rewrite.module.arena.appendExpr(
            .symbolRef(entryPointSymbol),
            type: rewrite.intType
        )
        let callerContinuationExpr = rewrite.module.arena.appendExpr(
            .symbolRef(callerContinuationSymbol),
            type: rewrite.anyType
        )
        instructions.append(
            .call(
                symbol: nil,
                callee: rewrite.directSuspendCallCallee,
                arguments: [entryPointExpr, childContinuationTemp, callerContinuationExpr],
                result: call.result,
                canThrow: false,
                thrownResult: nil,
                isSuperCall: call.isSuperCall
            )
        )
        return instructions
    }

    func rewriteWithTimeoutCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        let runtimeCallee: InternedString
        if call.callee == rewrite.withTimeoutCallee {
            runtimeCallee = rewrite.runtimeWithTimeoutCallee
        } else if call.callee == rewrite.withTimeoutOrNullCallee {
            runtimeCallee = rewrite.runtimeWithTimeoutOrNullCallee
        } else {
            return nil
        }

        guard call.arguments.count >= 2,
              let referencedSymbol = symbolReference(
                  for: call.arguments[1],
                  module: rewrite.module,
                  propagatedSymbols: symbolByExprRaw
              ),
              let loweredTarget = rewrite.loweredBySymbol[referencedSymbol]
        else {
            return nil
        }

        let timeMillisExpr = call.arguments[0]
        let extraArgs = Array(call.arguments.dropFirst(2))
        let targetArity = rewrite.suspendFunctionArityBySymbol[referencedSymbol] ?? 0
        guard extraArgs.count == targetArity else {
            rewrite.ctx.diagnostics.error(
                "KSWIFTK-CORO-0005",
                "withTimeout block capture arity mismatch.",
                range: nil
            )
            return [call.instruction]
        }

        let entryTarget: LoweredSuspendFunction
        var rewritten: [KIRInstruction] = []
        let continuationFunctionID = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: rewrite.continuationTypeByLoweredSymbol[loweredTarget.symbol] ?? rewrite.anyType
        )

        if extraArgs.isEmpty {
            entryTarget = loweredTarget
        } else {
            guard let thunk = rewrite.launcherThunkByOriginalSymbol[referencedSymbol] else {
                return [call.instruction]
            }
            entryTarget = thunk
        }

        rewritten.append(.constValue(
            result: continuationFunctionID,
            value: .intLiteral(Int64(loweredTarget.symbol.rawValue))
        ))
        rewritten.append(.call(
            symbol: nil,
            callee: rewrite.continuationFactory,
            arguments: [continuationFunctionID],
            result: continuationExpr,
            canThrow: false,
            thrownResult: nil
        ))

        for (index, argExpr) in extraArgs.enumerated() {
            let slotExpr = rewrite.module.arena.appendExpr(
                .intLiteral(Int64(index)),
                type: rewrite.intType
            )
            rewritten.append(.call(
                symbol: nil,
                callee: rewrite.launcherArgSetCallee,
                arguments: [continuationExpr, slotExpr, argExpr],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
        }

        let entryPointExpr = rewrite.module.arena.appendExpr(
            .symbolRef(entryTarget.symbol),
            type: rewrite.intType
        )
        rewritten.append(.call(
            symbol: nil,
            callee: runtimeCallee,
            arguments: [timeMillisExpr, entryPointExpr, continuationExpr],
            result: call.result,
            canThrow: call.canThrow,
            thrownResult: call.thrownResult
        ))
        return rewritten
    }

    func rewriteYieldCall(
        call: CallRewriteInput,
        using rewrite: SuspendRewriteContext
    ) -> KIRInstruction? {
        guard call.callee == rewrite.yieldCallee else {
            return nil
        }
        return .call(
            symbol: nil,
            callee: rewrite.runtimeYieldCallee,
            arguments: call.arguments,
            result: call.result,
            canThrow: false,
            thrownResult: nil
        )
    }

    func rewriteCoroutineBuilderBuildCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> KIRInstruction? {
        let replacementCallee: InternedString
        if call.callee == rewrite.sequenceBuilderBuildCallee {
            replacementCallee = rewrite.sequenceBuilderBuildCoroCallee
        } else if call.callee == rewrite.iteratorBuilderBuildCallee {
            replacementCallee = rewrite.iteratorBuilderBuildCoroCallee
        } else {
            return nil
        }

        guard let callableExpr = call.arguments.first,
              let referencedSymbol = symbolReference(
                  for: callableExpr,
                  module: rewrite.module,
                  propagatedSymbols: symbolByExprRaw
              ),
              let loweredTarget = rewrite.loweredBySymbol[referencedSymbol]
        else {
            return nil
        }

        let producer: (original: SymbolID, lowered: LoweredSuspendFunction, entryPoint: SymbolID)?
        if replacementCallee == rewrite.sequenceBuilderBuildCoroCallee,
           let innerProducer = sequenceBuilderInnerProducer(
               from: loweredTarget.symbol,
               symbolByExprRaw: symbolByExprRaw,
               using: rewrite
           ),
           let builderThunk = rewrite.sequenceBuilderThunkByOriginalSymbol[innerProducer.original]
        {
            producer = (
                original: innerProducer.original,
                lowered: innerProducer.lowered,
                entryPoint: builderThunk.symbol
            )
        } else {
            producer = nil
        }
        let producerOriginalSymbol = producer?.original ?? referencedSymbol
        let producerLoweredTarget = producer?.lowered ?? loweredTarget

        if replacementCallee == rewrite.sequenceBuilderBuildCoroCallee,
           loweredFunctionContainsCallee(
               symbol: producerLoweredTarget.symbol,
               callee: rewrite.sequenceBuilderYieldAllCallee,
               module: rewrite.module
           )
        {
            return nil
        }
        if replacementCallee == rewrite.sequenceBuilderBuildCoroCallee,
           loweredFunctionContainsAnyCallee(
               symbol: producerLoweredTarget.symbol,
               callees: [
                   rewrite.ctx.interner.intern("kk_coroutine_continuation_new"),
               ],
               module: rewrite.module
           ),
           !loweredFunctionContainsCallee(
               symbol: producerLoweredTarget.symbol,
               callee: rewrite.directSuspendCallCallee,
               module: rewrite.module
           )
        {
            return nil
        }
        if replacementCallee == rewrite.sequenceBuilderBuildCoroCallee,
           loweredFunctionContainsCalleeNamedLike(
               symbol: producerLoweredTarget.symbol,
               module: rewrite.module,
               interner: rewrite.ctx.interner,
               isMatch: { name in
                   name.hasPrefix("kk_lambda_") || name.hasPrefix("kk_suspend_kk_lambda_")
               }
           )
        {
            return nil
        }

        let entryPointSymbol = producer?.entryPoint ?? entryPointSymbol(
            for: producerOriginalSymbol,
            loweredTarget: producerLoweredTarget,
            hasLauncherArg: true,
            using: rewrite
        )
        let entryPointExpr = rewrite.module.arena.appendExpr(
            .symbolRef(entryPointSymbol),
            type: rewrite.intType
        )
        let functionIDExpr = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(producerLoweredTarget.symbol.rawValue)),
            type: rewrite.intType
        )
        let closureRawExpr: KIRExprID
        if call.arguments.count >= 2 {
            closureRawExpr = call.arguments[1]
        } else {
            closureRawExpr = rewrite.module.arena.appendExpr(
                .intLiteral(0),
                type: rewrite.intType
            )
        }

        return .call(
            symbol: nil,
            callee: replacementCallee,
            arguments: [entryPointExpr, functionIDExpr, closureRawExpr],
            result: call.result,
            canThrow: call.canThrow,
            thrownResult: call.thrownResult,
            isSuperCall: call.isSuperCall
        )
    }

    private func sequenceBuilderInnerProducer(
        from loweredAdapterSymbol: SymbolID,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> (original: SymbolID, lowered: LoweredSuspendFunction)? {
        var candidates: [(original: SymbolID, lowered: LoweredSuspendFunction)] = []

        func appendProducer(for entryPointSymbol: SymbolID) {
            if let producer = rewrite.launcherThunkByOriginalSymbol.first(where: {
                $0.value.symbol == entryPointSymbol
            }),
               let lowered = rewrite.loweredBySymbol[producer.key]
            {
                if !candidates.contains(where: { $0.original == producer.key }) {
                    candidates.append((original: producer.key, lowered: lowered))
                }
                return
            }

            if let producer = rewrite.sequenceBuilderThunkByOriginalSymbol.first(where: {
                $0.value.symbol == entryPointSymbol
            }),
               let lowered = rewrite.loweredBySymbol[producer.key]
            {
                if !candidates.contains(where: { $0.original == producer.key }) {
                    candidates.append((original: producer.key, lowered: lowered))
                }
                return
            }

            if let producer = rewrite.loweredBySymbol.first(where: {
                $0.value.symbol == entryPointSymbol
            })
            {
                if !candidates.contains(where: { $0.original == producer.key }) {
                    candidates.append((original: producer.key, lowered: producer.value))
                }
            }
        }

        for decl in rewrite.module.arena.declarations {
            guard case let .function(function) = decl,
                  function.symbol == loweredAdapterSymbol
            else {
                continue
            }
            for instruction in function.body {
                let callee: InternedString?
                switch instruction {
                case let .call(_, instructionCallee, _, _, _, _, _, _):
                    callee = instructionCallee
                case let .virtualCall(_, instructionCallee, _, _, _, _, _, _):
                    callee = instructionCallee
                default:
                    callee = nil
                }

                if callee == rewrite.directSuspendCallCallee,
                   case let .call(_, _, arguments, _, _, _, _, _) = instruction,
                   let entryPointExpr = arguments.first,
                   let entryPointSymbol = symbolReference(
                       for: entryPointExpr,
                       module: rewrite.module,
                       propagatedSymbols: symbolByExprRaw
                   )
                {
                    appendProducer(for: entryPointSymbol)
                    continue
                }

                guard let callee,
                      let producer = rewrite.originalByLoweredName[callee],
                      producer.lowered.symbol != loweredAdapterSymbol
                else {
                    continue
                }
                if !candidates.contains(where: { $0.original == producer.original }) {
                    candidates.append(producer)
                }
            }
            break
        }
        guard candidates.count == 1 else {
            return nil
        }
        return candidates[0]
    }

    private func loweredFunctionContainsCallee(
        symbol: SymbolID,
        callee: InternedString,
        module: KIRModule
    ) -> Bool {
        loweredFunctionContainsAnyCallee(symbol: symbol, callees: [callee], module: module)
    }

    private func loweredFunctionContainsAnyCallee(
        symbol: SymbolID,
        callees: Set<InternedString>,
        module: KIRModule
    ) -> Bool {
        for decl in module.arena.declarations {
            guard case let .function(function) = decl,
                  function.symbol == symbol
            else {
                continue
            }
            return function.body.contains { instruction in
                if case let .call(_, instructionCallee, _, _, _, _, _, _) = instruction {
                    return callees.contains(instructionCallee)
                }
                if case let .virtualCall(_, instructionCallee, _, _, _, _, _, _) = instruction {
                    return callees.contains(instructionCallee)
                }
                return false
            }
        }
        return false
    }

    private func loweredFunctionContainsCalleeNamedLike(
        symbol: SymbolID,
        module: KIRModule,
        interner: StringInterner,
        isMatch: (String) -> Bool
    ) -> Bool {
        for decl in module.arena.declarations {
            guard case let .function(function) = decl,
                  function.symbol == symbol
            else {
                continue
            }
            return function.body.contains { instruction in
                if case let .call(_, instructionCallee, _, _, _, _, _, _) = instruction {
                    return isMatch(interner.resolve(instructionCallee))
                }
                if case let .virtualCall(_, instructionCallee, _, _, _, _, _, _) = instruction {
                    return isMatch(interner.resolve(instructionCallee))
                }
                return false
            }
        }
        return false
    }

    func rewriteCreateCoroutineUninterceptedCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard call.callee == rewrite.createCoroutineUninterceptedCallee || call.callee == rewrite.createCoroutineCallee,
              call.arguments.count == 2 || call.arguments.count == 3
        else {
            return nil
        }

        guard let referencedSymbol = symbolReference(
            for: call.arguments[0],
            module: rewrite.module,
            propagatedSymbols: symbolByExprRaw
        ),
        let loweredTarget = rewrite.loweredBySymbol[referencedSymbol]
        else {
            return nil
        }

        let entryPointSymbol = entryPointSymbol(
            for: referencedSymbol,
            loweredTarget: loweredTarget,
            hasLauncherArg: call.arguments.count == 3,
            using: rewrite
        )
        let entryPointExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let continuationExpr = call.result ?? rewrite.module.arena.appendTemporary(type: rewrite.anyType
        )

        var rewritten: [KIRInstruction] = [
            .constValue(result: entryPointExpr, value: .symbolRef(entryPointSymbol)),
            .call(
                symbol: nil,
                callee: rewrite.runtimeCreateCoroutineUninterceptedCallee,
                arguments: [entryPointExpr, call.arguments[call.arguments.count - 1]],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            )
        ]

        if call.arguments.count == 3 {
            let slotExpr = rewrite.module.arena.appendExpr(.intLiteral(0), type: rewrite.intType)
            rewritten.append(
                .call(
                    symbol: nil,
                    callee: rewrite.launcherArgSetCallee,
                    arguments: [continuationExpr, slotExpr, call.arguments[1]],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }

        return rewritten
    }

    func rewriteStartCoroutineUninterceptedOrReturnCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard call.callee == rewrite.startCoroutineUninterceptedOrReturnCallee,
              call.arguments.count == 2 || call.arguments.count == 3
        else {
            return nil
        }

        guard let referencedSymbol = symbolReference(
            for: call.arguments[0],
            module: rewrite.module,
            propagatedSymbols: symbolByExprRaw
        ),
        let loweredTarget = rewrite.loweredBySymbol[referencedSymbol]
        else {
            return nil
        }

        let entryPointSymbol = entryPointSymbol(
            for: referencedSymbol,
            loweredTarget: loweredTarget,
            hasLauncherArg: call.arguments.count == 3,
            using: rewrite
        )
        let entryPointExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: rewrite.anyType
        )

        var rewritten: [KIRInstruction] = [
            .constValue(result: entryPointExpr, value: .symbolRef(entryPointSymbol)),
            .call(
                symbol: nil,
                callee: rewrite.runtimeCreateCoroutineUninterceptedCallee,
                arguments: [entryPointExpr, call.arguments[call.arguments.count - 1]],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        if call.arguments.count == 3 {
            let slotExpr = rewrite.module.arena.appendExpr(.intLiteral(0), type: rewrite.intType)
            rewritten.append(
                .call(
                    symbol: nil,
                    callee: rewrite.launcherArgSetCallee,
                    arguments: [continuationExpr, slotExpr, call.arguments[1]],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }

        rewritten.append(
            .call(
                symbol: nil,
                callee: rewrite.runtimeStartCoroutineUninterceptedOrReturnCallee,
                arguments: [entryPointExpr, continuationExpr],
                result: call.result,
                canThrow: true,
                thrownResult: call.thrownResult
            )
        )
        return rewritten
    }

    func rewriteStartCoroutineCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard call.callee == rewrite.startCoroutineCallee,
              call.arguments.count == 2 || call.arguments.count == 3
        else {
            return nil
        }

        guard let referencedSymbol = symbolReference(
            for: call.arguments[0],
            module: rewrite.module,
            propagatedSymbols: symbolByExprRaw
        ),
        let loweredTarget = rewrite.loweredBySymbol[referencedSymbol]
        else {
            return nil
        }

        let entryPointExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: rewrite.anyType
        )
        let unitExpr = rewrite.module.arena.appendExpr(
            .unit,
            type: rewrite.unitType
        )

        let entryPointSymbol = entryPointSymbol(
            for: referencedSymbol,
            loweredTarget: loweredTarget,
            hasLauncherArg: call.arguments.count == 3,
            using: rewrite
        )

        var rewritten: [KIRInstruction] = [
            .constValue(result: entryPointExpr, value: .symbolRef(entryPointSymbol)),
            .call(
                symbol: nil,
                callee: rewrite.runtimeCreateCoroutineUninterceptedCallee,
                arguments: [entryPointExpr, call.arguments[call.arguments.count - 1]],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        if call.arguments.count == 3 {
            let slotExpr = rewrite.module.arena.appendExpr(.intLiteral(0), type: rewrite.intType)
            rewritten.append(
                .call(
                    symbol: nil,
                    callee: rewrite.launcherArgSetCallee,
                    arguments: [continuationExpr, slotExpr, call.arguments[1]],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }

        rewritten.append(
            .call(
                symbol: nil,
                callee: rewrite.runtimeContinuationResumeCallee,
                arguments: [continuationExpr, unitExpr],
                result: nil,
                canThrow: false,
                thrownResult: nil
            )
        )

        if let result = call.result {
            rewritten.append(.constValue(result: result, value: .unit))
        }
        return rewritten
    }

    private func entryPointSymbol(
        for referencedSymbol: SymbolID,
        loweredTarget: LoweredSuspendFunction,
        hasLauncherArg: Bool,
        using rewrite: SuspendRewriteContext
    ) -> SymbolID {
        if hasLauncherArg,
           let thunk = rewrite.launcherThunkByOriginalSymbol[referencedSymbol]
        {
            return thunk.symbol
        }
        return loweredTarget.symbol
    }

    func resolveLoweredTarget(
        symbol: SymbolID?,
        callee: InternedString,
        arity: Int,
        using rewrite: SuspendRewriteContext
    ) -> LoweredSuspendFunction? {
        if let symbol,
           let loweredBySymbol = rewrite.loweredBySymbol[symbol]
        {
            return loweredBySymbol
        }
        let byNameArityKey = SuspendCallLookupKey(name: callee, arity: arity)
        if let loweredByNameArity = rewrite.loweredByUniqueNameArity[byNameArityKey] {
            return loweredByNameArity
        }
        return rewrite.loweredByUniqueName[callee]
    }
}
