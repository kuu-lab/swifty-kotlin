
extension CoroutineLoweringPass {
    func rewriteFlowCollectCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard call.callee == rewrite.flowCollectCallee || call.callee == rewrite.flowCollectLatestCallee,
              call.arguments.count == 3
        else {
            return nil
        }
        let collectorExpr = call.arguments[1]
        let collectorSymbol = symbolReference(
            for: collectorExpr,
            module: rewrite.module,
            propagatedSymbols: symbolByExprRaw
        )
        let collectorCallableInfo = rewrite.module.arena.callableValueInfo(for: collectorExpr)

        var prefixInstructions = KIRLoweringEmitContext()
        let collectorEntryPoint: KIRExprID
        let collectorEnvPtr: KIRExprID
        let collectorContinuationArg: KIRExprID
        if let collectorSymbol, let loweredCollector = rewrite.loweredBySymbol[collectorSymbol] {
            // Suspend collector: its body contains a suspend call (e.g.
            // `collect { delay(1); ... }`), so it was CPS-rewritten. Route
            // through its suspend entry point; the runtime treats a nonzero
            // fourth argument as the function ID used to build a new
            // continuation for the suspend collector ABI.
            collectorEntryPoint = rewrite.module.arena.appendExpr(
                .symbolRef(loweredCollector.symbol),
                type: rewrite.intType
            )
            collectorContinuationArg = rewrite.module.arena.appendExpr(
                .intLiteral(Int64(loweredCollector.symbol.rawValue)),
                type: rewrite.intType
            )
            collectorEnvPtr = flowCollectorEnvironmentPointerExpr(
                for: collectorExpr,
                using: rewrite,
                into: &prefixInstructions
            )
        } else if let collectorSymbol,
                  let callableInfo = collectorCallableInfo,
                  callableInfo.symbol == collectorSymbol,
                  callableInfo.hasClosureParam,
                  let function = rewrite.module.arena.function(for: collectorSymbol),
                  !function.isInlineOnly
        {
            // Non-suspend collector that has already been adapted to the
            // `(closureRaw, value, outThrown) -> result` ABI used by the
            // runtime (e.g. a local `val` lambda that CallLowerer wrapped in
            // a collection-HOF adapter). Invoke it directly and pass the
            // packed capture environment.
            collectorEntryPoint = rewrite.module.arena.appendExpr(
                .symbolRef(collectorSymbol),
                type: rewrite.intType
            )
            collectorContinuationArg = rewrite.module.arena.appendExpr(
                .intLiteral(0),
                type: rewrite.intType
            )
            collectorEnvPtr = flowCollectorEnvironmentPointerExpr(
                for: collectorExpr,
                using: rewrite,
                into: &prefixInstructions
            )
        } else {
            // BUG-134: the collector expression is a boxed `Function1` value
            // (e.g. a lambda passed through a function parameter or a variable)
            // rather than a raw closure-aware function pointer. The runtime ABI
            // needs a `(closureRaw, value, outThrown) -> result` entry point and
            // its closure, so recover them with the same `kk_function_value_*`
            // accessors `CallLowerer.splitCallableLambdaArgument` uses for
            // ordinary collection HOF arguments.
            let fnPtrResult = rewrite.module.arena.appendTemporary(type: rewrite.intType)
            prefixInstructions.append(.call(
                symbol: nil,
                callee: rewrite.ctx.interner.intern("kk_function_value_fn_ptr"),
                arguments: [collectorExpr],
                result: fnPtrResult,
                canThrow: false,
                thrownResult: nil
            ))
            let closureRawResult = rewrite.module.arena.appendTemporary(type: rewrite.intType)
            prefixInstructions.append(.call(
                symbol: nil,
                callee: rewrite.ctx.interner.intern("kk_function_value_closure_raw"),
                arguments: [collectorExpr],
                result: closureRawResult,
                canThrow: false,
                thrownResult: nil
            ))
            collectorEntryPoint = fnPtrResult
            collectorEnvPtr = closureRawResult
            collectorContinuationArg = rewrite.module.arena.appendExpr(
                .intLiteral(0),
                type: rewrite.intType
            )
        }

        prefixInstructions.append(.call(
            symbol: call.symbol,
            callee: call.callee,
            arguments: [call.arguments[0], collectorEntryPoint, collectorEnvPtr, collectorContinuationArg],
            result: call.result,
            canThrow: call.canThrow,
            thrownResult: call.thrownResult,
            isSuperCall: call.isSuperCall
        ))
        return prefixInstructions.instructions
    }

    /// Threads a capturing `flow { }` builder's captured values into its emitter.
    ///
    /// `lowerFlowExpressions` rewrites `flow { }` to `kk_flow_create(emitter, 0)`
    /// before suspend lowering exists, so the second argument is a placeholder and
    /// the emitter's captured values are dropped (the runtime invoked it with a
    /// null environment). By this point the emitter lambda has been lowered to a
    /// suspend state machine with a launcher thunk that reads its captures from a
    /// continuation's launcher-arg slots — the same mechanism `launch { }` uses.
    /// Populate such a continuation and route `kk_flow_create` through the thunk.
    /// Non-capturing builders keep the direct-emitter ABI and are left untouched.
    func rewriteFlowCreateCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        functionValueInfoByExprRaw: [Int32: KIRCallableValueInfo],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard call.callee == rewrite.ctx.interner.intern("kk_flow_create"),
              call.arguments.count == 2,
              let callableInfo = rewrite.module.arena.callableValueInfo(for: call.arguments[0])
                  ?? functionValueInfoByExprRaw[call.arguments[0].rawValue],
              let loweredTarget = rewrite.loweredBySymbol[callableInfo.symbol]
        else {
            return nil
        }

        // A non-capturing builder still suspends (`delay`, `emit` backpressure),
        // so it must ride the suspend-entry path too: with no parameters the
        // lowered target is directly callable as the entry point, matching the
        // `channelFlow`/`callbackFlow` rewrite below.
        let entryPointSymbol: SymbolID
        let targetArity = rewrite.suspendFunctionArityBySymbol[loweredTarget.symbol] ?? 0
        if targetArity == 0 {
            entryPointSymbol = loweredTarget.symbol
        } else {
            guard let thunk = rewrite.launcherThunkByOriginalSymbol[callableInfo.symbol] else {
                return nil
            }
            entryPointSymbol = thunk.symbol
        }

        let loweredFunctionIDExpr = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(loweredTarget.symbol.rawValue)),
            type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(
            type: rewrite.continuationTypeByLoweredSymbol[loweredTarget.symbol] ?? rewrite.intType
        )
        var rewritten: [KIRInstruction] = [
            .call(
                symbol: nil,
                callee: rewrite.continuationFactory,
                arguments: [loweredFunctionIDExpr],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        for (index, argExpr) in callableInfo.captureArguments.enumerated() {
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

        let thunkRefExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType)
        rewritten.append(.constValue(result: thunkRefExpr, value: .symbolRef(entryPointSymbol)))
        rewritten.append(.call(
            symbol: call.symbol,
            callee: call.callee,
            arguments: [thunkRefExpr, continuationExpr],
            result: call.result,
            canThrow: call.canThrow,
            thrownResult: call.thrownResult,
            isSuperCall: call.isSuperCall
        ))
        return rewritten
    }

    /// Threads the producer receiver and captured values into a real channel
    /// builder. The runtime bridge uses the same launcher-continuation layout
    /// as `produce { }`, but stores the channel handle in slot zero so the
    /// lowered `ProducerScope` receiver is reconstructed by the launcher thunk.
    func rewriteProducerFlowCreateCall(
        call: CallRewriteInput,
        functionValueInfoByExprRaw: [Int32: KIRCallableValueInfo],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        let interner = rewrite.ctx.interner
        guard call.callee == interner.intern("kk_channel_flow_create")
            || call.callee == interner.intern("kk_callback_flow_create"),
            call.arguments.count == 2
        else {
            return nil
        }

        guard let callableInfo = rewrite.module.arena.callableValueInfo(for: call.arguments[0])
            ?? functionValueInfoByExprRaw[call.arguments[0].rawValue],
            let loweredTarget = rewrite.loweredBySymbol[callableInfo.symbol]
        else {
            return nil
        }
        let originalSymbol = callableInfo.symbol
        let captureArguments = callableInfo.captureArguments
        let entryPointSymbol: SymbolID
        let targetArity = rewrite.suspendFunctionArityBySymbol[loweredTarget.symbol] ?? 0
        if targetArity == 0 {
            entryPointSymbol = loweredTarget.symbol
        } else {
            guard let thunk = rewrite.launcherThunkByOriginalSymbol[originalSymbol] else {
                return nil
            }
            entryPointSymbol = thunk.symbol
        }

        let continuationFunctionID = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(loweredTarget.symbol.rawValue)),
            type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(
            type: rewrite.continuationTypeByLoweredSymbol[loweredTarget.symbol] ?? rewrite.anyType
        )
        var rewritten: [KIRInstruction] = [
            .call(
                symbol: nil,
                callee: rewrite.continuationFactory,
                arguments: [continuationFunctionID],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        // Slot zero is reserved for the runtime-created channel and becomes
        // the ProducerScope receiver. Lexical captures follow it.
        for (index, argExpr) in captureArguments.enumerated() {
            let slotExpr = rewrite.module.arena.appendExpr(
                .intLiteral(Int64(index + 1)),
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
            .symbolRef(entryPointSymbol),
            type: rewrite.intType
        )
        rewritten.append(.call(
            symbol: call.symbol,
            callee: call.callee,
            arguments: [entryPointExpr, continuationExpr],
            result: call.result,
            canThrow: call.canThrow,
            thrownResult: call.thrownResult,
            isSuperCall: call.isSuperCall
        ))
        return rewritten
    }

    /// Recovers the closure-capture environment pointer for a Flow collector
    /// lambda, matching the `(fnPtr, envPtr)` convention ordinary HOF callees
    /// use (e.g. `kk_list_map`). Falls back to a null pointer when the lambda
    /// captures nothing, and packs multiple captures into a closure object
    /// the same way `CallLowerer.splitCallableLambdaArgument` does.
    func flowCollectorEnvironmentPointerExpr(
        for lambdaID: KIRExprID,
        using rewrite: SuspendRewriteContext,
        into instructions: inout KIRLoweringEmitContext
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
}
