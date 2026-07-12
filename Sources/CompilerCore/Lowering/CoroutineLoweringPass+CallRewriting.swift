
extension CoroutineLoweringPass {
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

            if let collectInstructions = rewriteFlowCollectCall(
                call: call,
                symbolByExprRaw: symbolByExprRaw,
                using: rewrite
            ) {
                loweredBody.append(contentsOf: collectInstructions)
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
    ) -> [KIRInstruction]? {
        guard call.callee == rewrite.flowCollectCallee || call.callee == rewrite.flowCollectLatestCallee,
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

        var prefixInstructions: [KIRInstruction] = []
        let collectorEntryPoint = rewrite.module.arena.appendExpr(
            .symbolRef(loweredCollector.symbol),
            type: rewrite.intType
        )
        let collectorFunctionID = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(loweredCollector.symbol.rawValue)),
            type: rewrite.intType
        )
        // The collector lambda may capture outer variables (e.g. `collect {
        // capturedList.add(it) }`). `call.arguments[1]` still refers to the
        // original (pre-CPS) lambda expr, so its capture info is recoverable
        // from the same KIRArena.callableValueInfo registry ordinary HOF
        // lambdas use (see CallLowerer.splitCallableLambdaArgument). Without
        // this, the runtime always invoked the collector with a null
        // environment pointer and captured values were silently dropped.
        let collectorEnvPtr = flowCollectorEnvironmentPointerExpr(
            for: call.arguments[1],
            using: rewrite,
            into: &prefixInstructions
        )

        prefixInstructions.append(.call(
            symbol: call.symbol,
            callee: call.callee,
            arguments: [call.arguments[0], collectorEntryPoint, collectorEnvPtr, collectorFunctionID],
            result: call.result,
            canThrow: call.canThrow,
            thrownResult: call.thrownResult,
            isSuperCall: call.isSuperCall
        ))
        return prefixInstructions
    }

    /// Recovers the closure-capture environment pointer for a Flow collector
    /// lambda, matching the `(fnPtr, envPtr)` convention ordinary HOF callees
    /// use (e.g. `kk_list_map`). Falls back to a null pointer when the lambda
    /// captures nothing, and packs multiple captures into a closure object
    /// the same way `CallLowerer.splitCallableLambdaArgument` does.
    func flowCollectorEnvironmentPointerExpr(
        for lambdaID: KIRExprID,
        using rewrite: SuspendRewriteContext,
        into instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard let captureArguments = rewrite.module.arena.callableValueInfo(for: lambdaID)?.captureArguments,
              !captureArguments.isEmpty
        else {
            let zeroExpr = rewrite.module.arena.appendExpr(.intLiteral(0), type: rewrite.intType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            return zeroExpr
        }

        if captureArguments.count == 1 {
            return captureArguments[0]
        }

        let kkObjectNew = rewrite.ctx.interner.intern("kk_object_new")
        let kkArraySet = rewrite.ctx.interner.intern("kk_array_set")
        let slotCount = Int64(2 + captureArguments.count)
        let slotCountExpr = rewrite.module.arena.appendExpr(.intLiteral(slotCount), type: rewrite.intType)
        instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
        let classIDExpr = rewrite.module.arena.appendExpr(.intLiteral(0), type: rewrite.intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(0)))
        let closureObjExpr = rewrite.module.arena.appendTemporary(type: rewrite.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: kkObjectNew,
            arguments: [slotCountExpr, classIDExpr],
            result: closureObjExpr,
            canThrow: false,
            thrownResult: nil
        ))
        for (captureIndex, captureArg) in captureArguments.enumerated() {
            let fieldOffset = Int64(captureIndex + 2)
            let offsetExpr = rewrite.module.arena.appendExpr(.intLiteral(fieldOffset), type: rewrite.intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(fieldOffset)))
            let unusedResult = rewrite.module.arena.appendTemporary(type: rewrite.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: kkArraySet,
                arguments: [closureObjExpr, offsetExpr, captureArg],
                result: unusedResult,
                canThrow: false,
                thrownResult: nil
            ))
        }
        return closureObjExpr
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

        let producer: (original: SymbolID, lowered: LoweredSuspendFunction, entryPoint: SymbolID)?
        if replacementCallee == rewrite.sequenceBuilderBuildCoroCallee,
           let innerProducer = sequenceBuilderInnerProducer(from: loweredTarget.symbol, using: rewrite),
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
        using rewrite: SuspendRewriteContext
    ) -> (original: SymbolID, lowered: LoweredSuspendFunction)? {
        var candidates: [(original: SymbolID, lowered: LoweredSuspendFunction)] = []
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
