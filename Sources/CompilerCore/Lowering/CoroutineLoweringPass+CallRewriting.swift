
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
        let launcherArgSetCallee: InternedString
        let runtimeRunBlockingWithContCallee: InternedString
        let kxMiniLauncherRuntimeCallees: [InternedString: InternedString]
        let kxMiniLauncherWithContCallees: [InternedString: InternedString]
        let sequenceBuilderBuildCallee: InternedString
        let sequenceBuilderBuildCoroCallee: InternedString
        let sequenceBuilderYieldAllCallee: InternedString
        let iteratorBuilderBuildCallee: InternedString
        let iteratorBuilderBuildCoroCallee: InternedString
        let loweredBySymbol: [SymbolID: LoweredSuspendFunction]
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
                using: rewrite
            ) {
                loweredBody.append(contentsOf: directCallInstructions)
                continue
            }

            loweredBody.append(instruction)
        }
        return loweredBody
    }

    func propagatedSymbolReferences(
        for function: KIRFunction,
        callableRefTagFunctionCallee: InternedString
    ) -> [Int32: SymbolID] {
        // Uses insert-if-absent (not last-write-wins): `to`/`result` can be a
        // control-flow merge point (e.g. the shared result slot of an if/else
        // expression) fed by multiple mutually exclusive `.copy` sources.
        // Overwriting on every mismatch never converges in that case: each
        // pass flips the slot between the two source symbols forever. See the
        // identical fix in CoroutineLoweringPass+Flow.swift's symbolByExprRaw.
        var symbolByExprRaw: [Int32: SymbolID] = [:]
        var propagated = true

        while propagated {
            propagated = false
            for instruction in function.body {
                switch instruction {
                case let .constValue(result, .symbolRef(symbol)):
                    if symbolByExprRaw[result.rawValue] == nil {
                        symbolByExprRaw[result.rawValue] = symbol
                        propagated = true
                    }
                case let .copy(from, to):
                    if let symbol = symbolByExprRaw[from.rawValue],
                       symbolByExprRaw[to.rawValue] == nil
                    {
                        symbolByExprRaw[to.rawValue] = symbol
                        propagated = true
                    }
                case let .call(_, callee, arguments, result, _, _, _, _):
                    guard callee == callableRefTagFunctionCallee,
                          let result,
                          let callableExpr = arguments.first,
                          let symbol = symbolByExprRaw[callableExpr.rawValue],
                          symbolByExprRaw[result.rawValue] == nil
                    else {
                        continue
                    }
                    symbolByExprRaw[result.rawValue] = symbol
                    propagated = true
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
        let continuationTemp = rewrite.module.arena.appendTemporary(type: rewrite.continuationTypeByLoweredSymbol[loweredTarget.symbol] ?? rewrite.anyType
        )

        var loweredArguments = call.arguments
        loweredArguments.append(continuationTemp)
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
                arguments: loweredArguments,
                result: call.result,
                canThrow: call.canThrow,
                thrownResult: nil,
                isSuperCall: call.isSuperCall
            ),
        ]
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

        if replacementCallee == rewrite.sequenceBuilderBuildCoroCallee,
           loweredFunctionContainsCallee(
               symbol: loweredTarget.symbol,
               callee: rewrite.sequenceBuilderYieldAllCallee,
               module: rewrite.module
           )
        {
            return nil
        }
        if replacementCallee == rewrite.sequenceBuilderBuildCoroCallee,
           loweredFunctionContainsAnyCallee(
               symbol: loweredTarget.symbol,
               callees: [
                   rewrite.ctx.interner.intern("kk_coroutine_continuation_new"),
                   rewrite.ctx.interner.intern("kk_range_iterator"),
                   rewrite.ctx.interner.intern("kk_range_hasNext"),
                   rewrite.ctx.interner.intern("kk_range_next"),
               ],
               module: rewrite.module
           )
        {
            return nil
        }
        if replacementCallee == rewrite.sequenceBuilderBuildCoroCallee,
           loweredFunctionContainsCalleeNamedLike(
               symbol: loweredTarget.symbol,
               module: rewrite.module,
               interner: rewrite.ctx.interner,
               isMatch: { name in
                   name.hasPrefix("kk_lambda_") || name.hasPrefix("kk_suspend_kk_lambda_")
               }
           )
        {
            return nil
        }

        let entryPointSymbol = entryPointSymbol(
            for: referencedSymbol,
            loweredTarget: loweredTarget,
            hasLauncherArg: true,
            using: rewrite
        )
        let entryPointExpr = rewrite.module.arena.appendExpr(
            .symbolRef(entryPointSymbol),
            type: rewrite.intType
        )
        let functionIDExpr = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(loweredTarget.symbol.rawValue)),
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
