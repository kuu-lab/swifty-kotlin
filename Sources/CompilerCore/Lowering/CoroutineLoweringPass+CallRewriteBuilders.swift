
extension CoroutineLoweringPass {
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

        // The inner-producer search, the bail-out predicates below, and the
        // nested yieldAll callee lookup all resolve functions in this module,
        // so index them once instead of re-scanning arena.declarations per query.
        let functionBySymbol: [SymbolID: KIRFunction]
        if replacementCallee == rewrite.sequenceBuilderBuildCoroCallee {
            functionBySymbol = Dictionary(
                rewrite.module.arena.declarations.lazy.compactMap { decl -> (SymbolID, KIRFunction)? in
                    guard case let .function(function) = decl else {
                        return nil
                    }
                    return (function.symbol, function)
                },
                uniquingKeysWith: { first, _ in first }
            )
        } else {
            functionBySymbol = [:]
        }

        let producer: (original: SymbolID, lowered: LoweredSuspendFunction, entryPoint: SymbolID)?
        if replacementCallee == rewrite.sequenceBuilderBuildCoroCallee,
           let innerProducer = sequenceBuilderInnerProducer(
               from: loweredTarget.symbol,
               functionBySymbol: functionBySymbol,
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
        let producerFunction = functionBySymbol[producerLoweredTarget.symbol]

        if let producerFunction {
            if loweredFunctionContainsAnyCallee(
                producerFunction,
                callees: [
                    rewrite.ctx.interner.intern("kk_coroutine_continuation_new"),
                ]
            ),
               !loweredFunctionContainsCallee(
                   producerFunction,
                   callee: rewrite.directSuspendCallCallee
               )
            {
                return nil
            }
            if loweredFunctionContainsCalleeNamedLike(
                producerFunction,
                interner: rewrite.ctx.interner,
                isMatch: { name in
                    name.hasPrefix("kk_lambda_") || name.hasPrefix("kk_suspend_kk_lambda_")
                }
            ) {
                return nil
            }
            if loweredFunctionContainsCallee(
                producerFunction,
                callee: rewrite.sequenceBuilderYieldCallee
            ),
               loweredFunctionContainsCallee(
                   producerFunction,
                   callee: rewrite.sequenceBuilderYieldAllCallee
               )
            {
                return nil
            }
            if loweredFunctionContainsCallee(
                producerFunction,
                callee: rewrite.sequenceBuilderYieldAllCallee
            ),
               !loweredFunctionContainsYieldAllOfSequence(
                   producerFunction,
                   functionBySymbol: functionBySymbol,
                   using: rewrite
               )
            {
                return nil
            }
        }

        let chosenEntryPoint: SymbolID
        if replacementCallee == rewrite.sequenceBuilderBuildCoroCallee,
           let producerEntryPoint = producer?.entryPoint {
            chosenEntryPoint = producerEntryPoint
        } else if replacementCallee == rewrite.sequenceBuilderBuildCoroCallee,
                  let builderThunk = rewrite.sequenceBuilderThunkByOriginalSymbol[producerOriginalSymbol] {
            chosenEntryPoint = builderThunk.symbol
        } else {
            chosenEntryPoint = entryPointSymbol(
                for: producerOriginalSymbol,
                loweredTarget: producerLoweredTarget,
                hasLauncherArg: true,
                using: rewrite
            )
        }
        let entryPointExpr = rewrite.module.arena.appendExpr(
            .symbolRef(chosenEntryPoint),
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
        functionBySymbol: [SymbolID: KIRFunction],
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

        guard let adapterFunction = functionBySymbol[loweredAdapterSymbol] else {
            return nil
        }
        for instruction in adapterFunction.body {
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
        guard candidates.count == 1 else {
            return nil
        }
        return candidates[0]
    }

    private func loweredFunctionContainsYieldAllOfSequence(
        _ function: KIRFunction,
        functionBySymbol: [SymbolID: KIRFunction],
        using rewrite: SuspendRewriteContext
    ) -> Bool {
        guard let sequenceClassSymbol = rewrite.sequenceClassSymbol,
              let types = rewrite.ctx.sema?.types
        else {
            return false
        }
        for instruction in function.body {
            let callSymbol: SymbolID?
            let instructionCallee: InternedString
            switch instruction {
            case let .call(sym, callee, _, _, _, _, _, _):
                callSymbol = sym
                instructionCallee = callee
            case let .virtualCall(sym, callee, _, _, _, _, _, _):
                callSymbol = sym
                instructionCallee = callee
            default:
                continue
            }
            guard instructionCallee == rewrite.sequenceBuilderYieldAllCallee,
                  let callSymbol,
                  let calleeFunction = functionBySymbol[callSymbol],
                  let firstParamType = calleeFunction.params.first?.type
            else {
                continue
            }
            let normalizedType = types.makeNonNullable(firstParamType)
            if case let .classType(classType) = types.kind(of: normalizedType),
               classType.classSymbol == sequenceClassSymbol {
                return true
            }
        }
        return false
    }

    private func loweredFunctionContainsCallee(
        _ function: KIRFunction,
        callee: InternedString
    ) -> Bool {
        loweredFunctionContainsAnyCallee(function, callees: [callee])
    }

    private func loweredFunctionContainsAnyCallee(
        _ function: KIRFunction,
        callees: Set<InternedString>
    ) -> Bool {
        function.body.contains { instruction in
            if case let .call(_, instructionCallee, _, _, _, _, _, _) = instruction {
                return callees.contains(instructionCallee)
            }
            if case let .virtualCall(_, instructionCallee, _, _, _, _, _, _) = instruction {
                return callees.contains(instructionCallee)
            }
            return false
        }
    }

    private func loweredFunctionContainsCalleeNamedLike(
        _ function: KIRFunction,
        interner: StringInterner,
        isMatch: (String) -> Bool
    ) -> Bool {
        function.body.contains { instruction in
            if case let .call(_, instructionCallee, _, _, _, _, _, _) = instruction {
                return isMatch(interner.resolve(instructionCallee))
            }
            if case let .virtualCall(_, instructionCallee, _, _, _, _, _, _) = instruction {
                return isMatch(interner.resolve(instructionCallee))
            }
            return false
        }
    }

    func rewriteDeepRecursiveFunctionNewCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> KIRInstruction? {
        let newCallee = rewrite.ctx.interner.intern("__kk_deep_recursive_function_new")
        guard call.callee == newCallee else {
            return nil
        }

        // The constructor call may be `(block)`, `(fnPtr, closureRaw)`, or
        // `(instance, fnPtr[, closureRaw])`. Find the suspend lambda among the
        // arguments rather than assuming a fixed slot.
        var lambdaIndex: Int?
        var referencedSymbol: SymbolID?
        var loweredTarget: LoweredSuspendFunction?
        for (index, argument) in call.arguments.enumerated() {
            guard let symbol = symbolReference(
                for: argument,
                module: rewrite.module,
                propagatedSymbols: symbolByExprRaw
            ),
            let lowered = rewrite.loweredBySymbol[symbol]
            else {
                continue
            }
            (lambdaIndex, referencedSymbol, loweredTarget) = (index, symbol, lowered)
            break
        }
        guard let lambdaIndex, let referencedSymbol, let loweredTarget else {
            return nil
        }

        let chosenEntryPoint = entryPointSymbol(
            for: referencedSymbol,
            loweredTarget: loweredTarget,
            hasLauncherArg: true,
            using: rewrite
        )
        let entryPointExpr = rewrite.module.arena.appendExpr(
            .symbolRef(chosenEntryPoint),
            type: rewrite.intType
        )
        let functionIDExpr = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(loweredTarget.symbol.rawValue)),
            type: rewrite.intType
        )
        let closureRawExpr = deepRecursiveClosureRaw(
            call: call,
            lambdaIndex: lambdaIndex,
            referencedSymbol: referencedSymbol,
            symbolByExprRaw: symbolByExprRaw,
            using: rewrite
        )
        let launcherArgCount = rewrite.suspendFunctionArityBySymbol[referencedSymbol] ?? 2
        let launcherArgCountExpr = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(launcherArgCount)),
            type: rewrite.intType
        )

        return .call(
            symbol: nil,
            callee: newCallee,
            arguments: [entryPointExpr, functionIDExpr, closureRawExpr, launcherArgCountExpr],
            result: call.result,
            canThrow: call.canThrow,
            thrownResult: call.thrownResult,
            isSuperCall: call.isSuperCall
        )
    }

    private func deepRecursiveClosureRaw(
        call: CallRewriteInput,
        lambdaIndex: Int,
        referencedSymbol: SymbolID,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> KIRExprID {
        if let candidate = call.arguments.dropFirst(lambdaIndex + 1).first {
            let isLoweredLambda = symbolReference(
                for: candidate,
                module: rewrite.module,
                propagatedSymbols: symbolByExprRaw
            ).map { rewrite.loweredBySymbol[$0] != nil } ?? false
            if !isLoweredLambda {
                return candidate
            }
        }
        if let first = rewrite.module.arena.lambdaCaptureArgsBySymbol[referencedSymbol]?.first {
            return first
        }
        return rewrite.module.arena.appendExpr(
            .intLiteral(0),
            type: rewrite.intType
        )
    }
}
