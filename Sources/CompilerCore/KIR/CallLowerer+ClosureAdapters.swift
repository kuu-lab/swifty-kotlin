/// Closure-argument synthesis and callable-adapter helpers for
/// CallLowerer: `appendClosureArgumentsIfNeeded`,
/// `makeCollectionHOFCallableAdapter`, `makeClosureThunkCallableAdapter`.
///
/// Split out from `CallLowerer.swift`.
extension CallLowerer {
    func appendCallableCaptureLoads(
        callableInfo: KIRCallableValueInfo,
        closureExpr: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        body: inout [KIRInstruction]
    ) -> [KIRExprID] {
        var callArguments: [KIRExprID] = []
        if callableInfo.captureArguments.count >= 2 {
            let arrayGet = interner.intern("kk_array_get_inbounds")
            for (captureIndex, captureExpr) in callableInfo.captureArguments.enumerated() {
                let captureType = arena.exprType(captureExpr) ?? sema.types.anyType
                let offsetExpr = arena.appendExpr(.intLiteral(Int64(captureIndex + 2)), type: sema.types.intType)
                body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(captureIndex + 2))))
                let loadedExpr = arena.appendTemporary(type: captureType
                )
                body.append(.call(
                    symbol: nil,
                    callee: arrayGet,
                    arguments: [closureExpr, offsetExpr],
                    result: loadedExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                callArguments.append(loadedExpr)
            }
        } else if !callableInfo.captureArguments.isEmpty {
            callArguments.append(closureExpr)
        }
        return callArguments
    }

    func makeBoxedCallableCaptureArguments(
        callableInfo: KIRCallableValueInfo,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        if callableInfo.captureArguments.count >= 2 {
            let slotCountExpr = arena.appendExpr(
                .intLiteral(Int64(2 + callableInfo.captureArguments.count)),
                type: sema.types.intType
            )
            instructions.append(.constValue(
                result: slotCountExpr,
                value: .intLiteral(Int64(2 + callableInfo.captureArguments.count))
            ))
            let classIDExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            instructions.append(.constValue(result: classIDExpr, value: .intLiteral(0)))
            let closureObjExpr = arena.appendTemporary(type: sema.types.anyType
            )
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_object_new"),
                arguments: [slotCountExpr, classIDExpr],
                result: closureObjExpr,
                canThrow: false,
                thrownResult: nil
            ))
            for (captureIndex, captureArg) in callableInfo.captureArguments.enumerated() {
                let offsetExpr = arena.appendExpr(
                    .intLiteral(Int64(captureIndex + 2)),
                    type: sema.types.intType
                )
                instructions.append(.constValue(
                    result: offsetExpr,
                    value: .intLiteral(Int64(captureIndex + 2))
                ))
                let unusedResult = arena.appendTemporary(type: sema.types.anyType
                )
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_set"),
                    arguments: [closureObjExpr, offsetExpr, captureArg],
                    result: unusedResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
            return [closureObjExpr]
        }
        return callableInfo.captureArguments
    }

    func makeClosureThunkExpandedArguments(
        prefixArguments: [KIRExprID] = [],
        loweredArgID: KIRExprID,
        argExprID: ExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        var finalArgs = prefixArguments
        var lambdaID = loweredArgID
        var resolvedCallableInfo = driver.ctx.callableValueInfo(for: lambdaID)
        if let callableInfo = resolvedCallableInfo,
           !callableInfo.hasClosureParam,
           let adaptedInfo = makeClosureThunkCallableAdapter(
               callableInfo: callableInfo,
               loweredArgID: lambdaID,
               argExprID: argExprID,
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
            )
        {
            let adaptedExpr = arena.appendExpr(
                .symbolRef(adaptedInfo.symbol),
                type: arena.exprType(lambdaID) ?? sema.types.anyType
            )
            instructions.append(.constValue(result: adaptedExpr, value: .symbolRef(adaptedInfo.symbol)))
            driver.ctx.registerCallableValue(
                adaptedExpr,
                symbol: adaptedInfo.symbol,
                callee: adaptedInfo.callee,
                captureArguments: adaptedInfo.captureArguments,
                hasClosureParam: adaptedInfo.hasClosureParam
            )
            lambdaID = adaptedExpr
            resolvedCallableInfo = adaptedInfo
        }
        if let callableInfo = resolvedCallableInfo {
            let fnPtrExpr = arena.appendExpr(.symbolRef(callableInfo.symbol), type: sema.types.intType)
            instructions.append(.constValue(result: fnPtrExpr, value: .symbolRef(callableInfo.symbol)))
            finalArgs.append(fnPtrExpr)
        } else {
            finalArgs.append(lambdaID)
        }
        finalArgs.append(makeClosureRawOrBoxedArgument(
            callableInfo: resolvedCallableInfo,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ))
        return finalArgs
    }

    func makeCollectionHOFExpandedArguments(
        loweredArgID: KIRExprID,
        argExprID: ExprID,
        adaptOnlyWhenCapturing: Bool = false,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        var loweredCallableID = loweredArgID
        var callableInfo = driver.ctx.callableValueInfo(for: loweredArgID)
        if let originalCallableInfo = callableInfo,
           !originalCallableInfo.hasClosureParam,
           !adaptOnlyWhenCapturing || !originalCallableInfo.captureArguments.isEmpty,
           let adapted = makeCollectionHOFCallableAdapter(
                callableInfo: originalCallableInfo,
                loweredArgID: loweredArgID,
                argExprID: argExprID,
                sema: sema,
                arena: arena,
                interner: interner,
                namePrefix: "kk_compare_values_hof_adapter",
                symbolIDOffsetBase: -710_000
           )
        {
            let adaptedExpr = arena.appendExpr(
                .symbolRef(adapted.symbol),
                type: arena.exprType(loweredArgID) ?? sema.types.anyType
            )
            instructions.append(.constValue(result: adaptedExpr, value: .symbolRef(adapted.symbol)))
            driver.ctx.registerCallableValue(
                adaptedExpr,
                symbol: adapted.symbol,
                callee: adapted.callee,
                captureArguments: adapted.captureArguments,
                hasClosureParam: adapted.hasClosureParam
            )
            loweredCallableID = adaptedExpr
            callableInfo = adapted
        }

        var finalArgs: [KIRExprID] = [loweredCallableID]
        finalArgs.append(makeClosureRawOrBoxedArgument(
            callableInfo: callableInfo,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ))
        return finalArgs
    }

    private func makeCollectionHOFSelectorArgument(
        loweredArgID: KIRExprID,
        argExprID: ExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> (loweredArgID: KIRExprID, callableInfo: KIRCallableValueInfo?) {
        let loweredSelectorID = loweredArgID
        var selectorCallableInfo = driver.ctx.callableValueInfo(for: loweredArgID)
        if selectorCallableInfo == nil,
           case let .symbolRef(symbol)? = arena.expr(loweredSelectorID),
           let function = arena.function(for: symbol)
        {
            selectorCallableInfo = KIRCallableValueInfo(
                symbol: function.symbol,
                callee: function.name,
                captureArguments: arena.lambdaCaptureArgsBySymbol[function.symbol] ?? [],
                hasClosureParam: function.params.count >= 2
            )
        }
        if let callableInfo = selectorCallableInfo,
           !callableInfo.hasClosureParam,
           let adaptedInfo = makeCollectionHOFCallableAdapter(
                callableInfo: callableInfo,
                loweredArgID: loweredSelectorID,
                argExprID: argExprID,
                sema: sema,
                arena: arena,
                interner: interner,
                namePrefix: "kk_compare_values_hof_adapter",
                symbolIDOffsetBase: -710_000
           )
        {
            selectorCallableInfo = adaptedInfo
        }
        // callableInfo.symbol is always the raw function pointer to invoke through.
        // loweredArgID may instead be a boxed/materialized callable value (e.g. a
        // selector read from a local variable rather than an inline lambda literal),
        // so re-point the selector at a fresh reference to the resolved symbol
        // instead of reusing loweredArgID, which would pass the boxed object where
        // a function pointer is expected.
        guard let callableInfo = selectorCallableInfo else {
            return (loweredSelectorID, nil)
        }
        let fnPtrExpr = arena.appendExpr(
            .symbolRef(callableInfo.symbol),
            type: arena.exprType(loweredSelectorID) ?? sema.types.anyType
        )
        instructions.append(.constValue(result: fnPtrExpr, value: .symbolRef(callableInfo.symbol)))
        driver.ctx.registerCallableValue(
            fnPtrExpr,
            symbol: callableInfo.symbol,
            callee: callableInfo.callee,
            captureArguments: callableInfo.captureArguments,
            hasClosureParam: callableInfo.hasClosureParam
        )
        return (fnPtrExpr, callableInfo)
    }

    private func makeClosureRawArgument(
        callableInfo: KIRCallableValueInfo?,
        sema: SemaModule,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        if let callableInfo,
           let closureRaw = callableInfo.captureArguments.first
        {
            return closureRaw
        }
        let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
        instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
        return zeroExpr
    }

    /// Builds the single `closureRaw` slot for the `(fnPtr, closureRaw)` ABI:
    /// 2+ captures are packed into a boxed closure object (so the lambda body's
    /// `kk_array_get_inbounds` unpacking has something valid to read), a single
    /// capture is passed raw, and no captures / no callable info yields 0.
    /// Every call site that produces a closureRaw argument for a
    /// collection-HOF-marked lambda must go through this — using
    /// `callableInfo.captureArguments.first` directly silently drops captures
    /// beyond the first once there are 2 or more.
    private func makeClosureRawOrBoxedArgument(
        callableInfo: KIRCallableValueInfo?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard let callableInfo else {
            return makeClosureRawArgument(callableInfo: nil, sema: sema, arena: arena, instructions: &instructions)
        }
        let boxedCaptureArguments = makeBoxedCallableCaptureArguments(
            callableInfo: callableInfo,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        if let boxedCaptureArgument = boxedCaptureArguments.first {
            return boxedCaptureArgument
        }
        return makeClosureRawArgument(callableInfo: callableInfo, sema: sema, arena: arena, instructions: &instructions)
    }

    func materializeFunctionValueArgument(
        loweredArgID: KIRExprID,
        argExprID: ExprID,
        functionType: FunctionType,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // Suspend callables are lowered through coroutine launcher/invoke paths,
        // not the ordinary kk_function_create_N function-value ABI.
        guard !functionType.isSuspend else {
            return loweredArgID
        }

        var loweredCallableID = loweredArgID
        var callableInfo = driver.ctx.callableValueInfo(for: loweredArgID)
        if callableInfo == nil,
           case let .symbolRef(symbol)? = arena.expr(loweredCallableID),
           let function = arena.function(for: symbol)
        {
            callableInfo = KIRCallableValueInfo(
                symbol: function.symbol,
                callee: function.name,
                captureArguments: arena.lambdaCaptureArgsBySymbol[function.symbol] ?? [],
                hasClosureParam: function.params.count >= functionType.params.count + 1
            )
        }

        guard var resolvedCallableInfo = callableInfo else {
            return loweredArgID
        }

        if !resolvedCallableInfo.hasClosureParam,
           let adaptedInfo = makeCollectionHOFCallableAdapter(
                callableInfo: resolvedCallableInfo,
                loweredArgID: loweredCallableID,
                argExprID: argExprID,
                sema: sema,
                arena: arena,
                interner: interner,
                namePrefix: "kk_function_value_adapter",
                symbolIDOffsetBase: -720_000
           )
        {
            let adaptedExpr = arena.appendExpr(
                .symbolRef(adaptedInfo.symbol),
                type: arena.exprType(loweredCallableID) ?? sema.types.anyType
            )
            instructions.append(.constValue(result: adaptedExpr, value: .symbolRef(adaptedInfo.symbol)))
            driver.ctx.registerCallableValue(
                adaptedExpr,
                symbol: adaptedInfo.symbol,
                callee: adaptedInfo.callee,
                captureArguments: adaptedInfo.captureArguments,
                hasClosureParam: adaptedInfo.hasClosureParam
            )
            loweredCallableID = adaptedExpr
            resolvedCallableInfo = adaptedInfo
        }

        let valueArity = functionType.params.count + (functionType.receiver == nil ? 0 : 1)
        let createCallee: InternedString
        switch valueArity {
        case 0:
            createCallee = interner.intern("kk_function_create_0")
        case 1:
            createCallee = interner.intern("kk_function_create_1")
        case 2:
            createCallee = interner.intern("kk_function_create_2")
        default:
            return loweredArgID
        }

        let fnPtrExpr = arena.appendExpr(
            .symbolRef(resolvedCallableInfo.symbol),
            type: sema.types.intType
        )
        instructions.append(.constValue(result: fnPtrExpr, value: .symbolRef(resolvedCallableInfo.symbol)))
        let closureRaw = makeFunctionValueClosureRawArgument(
            callableInfo: resolvedCallableInfo,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        let materialized = arena.appendTemporary(type: sema.types.make(.functionType(functionType)))
        instructions.append(.call(
            symbol: nil,
            callee: createCallee,
            arguments: [fnPtrExpr, closureRaw],
            result: materialized,
            canThrow: false,
            thrownResult: nil
        ))
        driver.ctx.registerCallableValue(
            materialized,
            symbol: resolvedCallableInfo.symbol,
            callee: resolvedCallableInfo.callee,
            captureArguments: [closureRaw],
            hasClosureParam: true
        )
        return materialized
    }

    func materializeSourceBackedFunctionValueArguments(
        chosenCallee: SymbolID?,
        sourceArgExprs: [ExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID]
    ) {
        guard let chosenCallee,
              sema.symbols.externalLinkName(for: chosenCallee)?.isEmpty ?? true,
              let signature = sema.symbols.functionSignature(for: chosenCallee)
        else {
            return
        }

        // Inline calls consume lambda arguments directly during inline
        // expansion. Wrapping those arguments in a runtime function object
        // disconnects their thrown-result slot from the caller's try/catch.
        // Materialization is only needed for non-inline source-backed bodies
        // that invoke a function-valued parameter at runtime.
        if sema.symbols.symbol(chosenCallee)?.flags.contains(.inlineFunction) == true {
            return
        }

        let valueArgOffset = signature.receiverType == nil ? 0 : 1
        for parameterIndex in signature.parameterTypes.indices {
            let finalArgIndex = valueArgOffset + parameterIndex
            guard finalArgIndex < arguments.count,
                  parameterIndex < sourceArgExprs.count,
                  !signature.valueParameterIsVararg.indices.contains(parameterIndex)
                    || !signature.valueParameterIsVararg[parameterIndex]
            else {
                continue
            }
            let parameterType = sema.types.makeNonNullable(signature.parameterTypes[parameterIndex])
            guard case let .functionType(functionType) = sema.types.kind(of: parameterType) else {
                continue
            }
            arguments[finalArgIndex] = materializeFunctionValueArgument(
                loweredArgID: arguments[finalArgIndex],
                argExprID: sourceArgExprs[parameterIndex],
                functionType: functionType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
    }

    private func appendCollectionHOFSelectorPair(
        _ selector: (loweredArgID: KIRExprID, callableInfo: KIRCallableValueInfo?),
        to arrayExpr: KIRExprID,
        selectorOffset: Int,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let fnIndexExpr = arena.appendExpr(.intLiteral(Int64(selectorOffset * 2)), type: sema.types.intType)
        instructions.append(.constValue(result: fnIndexExpr, value: .intLiteral(Int64(selectorOffset * 2))))
        let fnSetResult = arena.appendTemporary(type: sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [arrayExpr, fnIndexExpr, selector.loweredArgID],
            result: fnSetResult,
            canThrow: false,
            thrownResult: nil
        ))

        let closureRaw = makeClosureRawOrBoxedArgument(
            callableInfo: selector.callableInfo,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        let closureIndexExpr = arena.appendExpr(.intLiteral(Int64(selectorOffset * 2 + 1)), type: sema.types.intType)
        instructions.append(.constValue(result: closureIndexExpr, value: .intLiteral(Int64(selectorOffset * 2 + 1))))
        let closureSetResult = arena.appendTemporary(type: sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [arrayExpr, closureIndexExpr, closureRaw],
            result: closureSetResult,
            canThrow: false,
            thrownResult: nil
        ))
    }

    func appendClosureArgumentsIfNeeded(
        _ loweredArguments: [KIRExprID],
        originalArgs: [CallArgument],
        chosenCallee: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        guard let externalLinkName = sema.symbols.externalLinkName(for: chosenCallee) else {
            return loweredArguments
        }

        if (externalLinkName == "kk_comparator_nulls_first_of"
            || externalLinkName == "kk_comparator_nulls_last_of"),
           loweredArguments.count == 1
        {
            let zeroClosureExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            instructions.append(.constValue(result: zeroClosureExpr, value: .intLiteral(0)))
            return [loweredArguments[0], zeroClosureExpr]
        }

        // Worker.execute has an explicit receiver followed by:
        // (mode, producer, job). The runtime ABI expects both lambdas as
        // (fnPtr, closureRaw) pairs.
        if externalLinkName == "kk_worker_execute",
           loweredArguments.count == originalArgs.count + 1,
           originalArgs.count == 3
        {
            let producerArgs = makeClosureThunkExpandedArguments(
                loweredArgID: loweredArguments[2],
                argExprID: originalArgs[1].expr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            let jobArgs = makeCollectionHOFExpandedArguments(
                loweredArgID: loweredArguments[3],
                argExprID: originalArgs[2].expr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            return [loweredArguments[0], loweredArguments[1]] + producerArgs + jobArgs
        }
        if externalLinkName == "kk_worker_execute",
           loweredArguments.count == originalArgs.count,
           originalArgs.count == 4
        {
            let producerArgs = makeClosureThunkExpandedArguments(
                loweredArgID: loweredArguments[2],
                argExprID: originalArgs[2].expr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            let jobArgs = makeCollectionHOFExpandedArguments(
                loweredArgID: loweredArguments[3],
                argExprID: originalArgs[3].expr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            return [loweredArguments[0], loweredArguments[1]] + producerArgs + jobArgs
        }

        let atomicReferenceUpdateRuntimeNames: Set<String> = [
            "kk_atomic_ref_getAndUpdate",
            "kk_atomic_ref_updateAndGet",
            "kk_atomic_ref_array_fetchAndUpdateAt",
            "kk_atomic_ref_array_updateAt",
            "kk_atomic_ref_array_updateAndFetchAt",
        ]
        if atomicReferenceUpdateRuntimeNames.contains(externalLinkName),
           let transformID = loweredArguments.last,
           let transformArg = originalArgs.last,
           let adaptedTransform = makeAtomicReferenceUpdateFunctionValue(
               loweredArgID: transformID,
               argExprID: transformArg.expr,
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            var finalArguments = loweredArguments
            finalArguments[finalArguments.count - 1] = adaptedTransform
            return finalArguments
        }

        guard loweredArguments.count == originalArgs.count else {
            return loweredArguments
        }

        if externalLinkName == "kk_suspend_coroutine", loweredArguments.count == 1 {
            return makeClosureThunkExpandedArguments(
                loweredArgID: loweredArguments[0],
                argExprID: originalArgs[0].expr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }

        // STDLIB-SEQ-002: 1-arg generateSequence(nextFunction) → kk_sequence_generate_noarg(fnPtr, closureRaw)
        if externalLinkName == "kk_sequence_generate_noarg", loweredArguments.count == 1 {
            let lambdaID = loweredArguments[0]
            let callableInfo = sema.bindings.isCollectionHOFLambdaExpr(originalArgs[0].expr)
                ? driver.ctx.callableValueInfo(for: lambdaID)
                : nil
            return [lambdaID, makeClosureRawOrBoxedArgument(
                callableInfo: callableInfo,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )]
        }

        // sequence { ... } builder: expand the receiver lambda to (fnPtr, closureRaw).
        // Capturing builder lambdas need the same closure-aware adapter shape as
        // collection HOFs so the runtime can call (closureRaw, builderRaw, outThrown).
        if externalLinkName == "kk_sequence_builder_build", loweredArguments.count == 1 {
            return makeCollectionHOFExpandedArguments(
                loweredArgID: loweredArguments[0],
                argExprID: originalArgs[0].expr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }

        let legacyNames: Set = ["kk_require_lazy", "kk_check_lazy", "kk_precondition_assert_lazy", "kk_sequence_generate"]
        if legacyNames.contains(externalLinkName), loweredArguments.count == 2 {
            var seedArgument = loweredArguments[0]
            if externalLinkName == "kk_sequence_generate",
               let seedCallableInfo = driver.ctx.callableValueInfo(for: loweredArguments[0]),
               let seedFunctionType = sema.bindings.exprTypes[originalArgs[0].expr],
               case let .functionType(functionType) = sema.types.kind(of: sema.types.makeNonNullable(seedFunctionType)),
               functionType.params.isEmpty
            {
                let seedResult = arena.appendTemporary(type: sema.types.makeNonNullable(functionType.returnType)
                )
                instructions.append(.call(
                    symbol: seedCallableInfo.symbol,
                    callee: seedCallableInfo.callee,
                    arguments: seedCallableInfo.captureArguments,
                    result: seedResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                seedArgument = seedResult
            }

            // Multi-capture lambdas (>= 2 captures) must be packed into a
            // closure object here, matching the (closureRaw, ...) ABI that
            // LambdaLowerer generates for these collection-HOF-marked
            // lambdas. Forwarding captureArguments.first directly hands the
            // lambda body a raw capture value instead of a closure object,
            // which it then misreads via kk_array_get_inbounds — wrong
            // values for small offsets, out-of-bounds crashes for larger
            // ones.
            let callableInfo = sema.bindings.isCollectionHOFLambdaExpr(originalArgs[1].expr)
                ? driver.ctx.callableValueInfo(for: loweredArguments[1])
                : nil
            let finalArgs = [seedArgument, loweredArguments[1], makeClosureRawOrBoxedArgument(
                callableInfo: callableInfo,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )]
            return finalArgs
        }

        // STDLIB-590 / STDLIB-KOTLIN-ROOT-CLOSE-001: Function0 runtime entry
        // points receive lambda arguments as (fnPtr, closureRaw).
        let function0RuntimeNames: Set<String> = [
            "kk_auto_closeable_create",
            "kk_runtime_result_run_catching",
        ]
        if function0RuntimeNames.contains(externalLinkName), loweredArguments.count == 1 {
            return makeClosureThunkExpandedArguments(
                loweredArgID: loweredArguments[0],
                argExprID: originalArgs[0].expr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }

        // STDLIB-325: synchronized(lock) { block } — expand block lambda to
        // (lock, fnPtr, closureRaw) while preserving the runtime outThrown slot.
        if externalLinkName == "kk_synchronized", loweredArguments.count == 2 {
            return makeClosureThunkExpandedArguments(
                prefixArguments: [loweredArguments[0]],
                loweredArgID: loweredArguments[1],
                argExprID: originalArgs[1].expr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }

        // kotlin.DeepRecursiveFunction { block } — expand the callable argument
        // to (fnPtr, closureRaw) so runtime can retain both the entry point and
        // the captured environment. Multi-capture lambdas are packed into a
        // closure object, reusing the same adapter strategy as collection HOFs.
        if externalLinkName == "kk_deep_recursive_function_new", loweredArguments.count == 1 {
            return makeCollectionHOFExpandedArguments(
                loweredArgID: loweredArguments[0],
                argExprID: originalArgs[0].expr,
                adaptOnlyWhenCapturing: true,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }

        if externalLinkName == "kk_comparator_from_selector_primitive"
            || externalLinkName == "kk_comparator_from_selector_primitive_descending",
           loweredArguments.count == 1
        {
            var finalArgs = makeClosureThunkExpandedArguments(
                loweredArgID: loweredArguments[0],
                argExprID: originalArgs[0].expr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            let selectorType = sema.bindings.exprType(for: originalArgs[0].expr) ?? sema.types.anyType
            let primitiveKindRaw: Int32 = switch sema.types.kind(of: sema.types.makeNonNullable(selectorType)) {
            case let .functionType(functionType):
                switch sema.types.kind(of: sema.types.makeNonNullable(functionType.returnType)) {
                case .primitive(.int, _), .primitive(.ubyte, _), .primitive(.ushort, _):
                    0
                case .primitive(.long, _):
                    1
                case .primitive(.uint, _):
                    2
                case .primitive(.ulong, _):
                    3
                case .primitive(.boolean, _):
                    4
                case .primitive(.char, _):
                    5
                case .primitive(.float, _):
                    6
                case .primitive(.double, _):
                    7
                default:
                    0
                }
            default:
                0
            }
            let kindExpr = arena.appendExpr(.intLiteral(Int64(primitiveKindRaw)), type: sema.types.intType)
            instructions.append(.constValue(result: kindExpr, value: .intLiteral(Int64(primitiveKindRaw))))
            finalArgs.append(kindExpr)
            return finalArgs
        }

        if externalLinkName == "kk_comparator_from_comparator_selector" ||
            externalLinkName == "kk_comparator_from_comparator_selector_descending",
           loweredArguments.count == 2
        {
            return makeClosureThunkExpandedArguments(
                prefixArguments: [loweredArguments[0]],
                loweredArgID: loweredArguments[1],
                argExprID: originalArgs[1].expr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }

        // Fixed-arity comparator factories take one (fnPtr, closureRaw) pair
        // per selector. The selector expressions are lowered as ordinary
        // arguments first, so expand them here before emitting the ABI call.
        let fixedComparatorSelectorCount: Int? = switch externalLinkName {
        case "kk_comparator_from_multi_selectors": 2
        case "kk_comparator_from_multi_selectors3": 3
        case "kk_compareValuesBy1": 1
        case "kk_compareValuesBy": 2
        case "kk_compareValuesBy3": 3
        default: nil
        }
        if let selectorCount = fixedComparatorSelectorCount {
            let selectorOffset = externalLinkName.hasPrefix("kk_compareValuesBy") ? 2 : 0
            guard loweredArguments.count == selectorOffset + selectorCount,
                  originalArgs.count == selectorOffset + selectorCount
            else {
                return loweredArguments
            }
            var expanded = Array(loweredArguments.prefix(selectorOffset))
            for index in 0..<selectorCount {
                let argumentIndex = selectorOffset + index
                let selector = makeCollectionHOFSelectorArgument(
                    loweredArgID: loweredArguments[argumentIndex],
                    argExprID: originalArgs[argumentIndex].expr,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                expanded.append(selector.loweredArgID)
                expanded.append(makeClosureRawOrBoxedArgument(
                    callableInfo: selector.callableInfo,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                ))
            }
            return expanded
        }

        // compareBy(vararg selectors): pack selector (fnPtr, closureRaw) pairs into a runtime array.
        if externalLinkName == "kk_comparator_from_multi_selectors_vararg", loweredArguments.count >= 4 {
            let slotCount = loweredArguments.count * 2
            let countExpr = arena.appendExpr(.intLiteral(Int64(slotCount)), type: sema.types.intType)
            instructions.append(.constValue(result: countExpr, value: .intLiteral(Int64(slotCount))))
            let arrayExpr = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_new"),
                arguments: [countExpr],
                result: arrayExpr,
                canThrow: false,
                thrownResult: nil
            ))

            for i in 0..<loweredArguments.count {
                let selector = makeCollectionHOFSelectorArgument(
                    loweredArgID: loweredArguments[i],
                    argExprID: originalArgs[i].expr,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )

                appendCollectionHOFSelectorPair(
                    selector,
                    to: arrayExpr,
                    selectorOffset: i,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }
            return [arrayExpr]
        }

        if externalLinkName == "kk_compareValuesByVararg", loweredArguments.count >= 6 {
            let selectorCount = loweredArguments.count - 2
            let slotCount = selectorCount * 2
            let countExpr = arena.appendExpr(.intLiteral(Int64(slotCount)), type: sema.types.intType)
            instructions.append(.constValue(result: countExpr, value: .intLiteral(Int64(slotCount))))
            let arrayExpr = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_new"),
                arguments: [countExpr],
                result: arrayExpr,
                canThrow: false,
                thrownResult: nil
            ))

            for argIndex in 2..<loweredArguments.count {
                let selectorOffset = argIndex - 2
                let selector = makeCollectionHOFSelectorArgument(
                    loweredArgID: loweredArguments[argIndex],
                    argExprID: originalArgs[argIndex].expr,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )

                appendCollectionHOFSelectorPair(
                    selector,
                    to: arrayExpr,
                    selectorOffset: selectorOffset,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }
            return [loweredArguments[0], loweredArguments[1], arrayExpr]
        }

        if externalLinkName == "kk_compareValuesByComparator",
           loweredArguments.count == 4
        {
            var finalArgs: [KIRExprID] = [loweredArguments[0], loweredArguments[1], loweredArguments[2]]
            let selector = makeCollectionHOFSelectorArgument(
                loweredArgID: loweredArguments[3],
                argExprID: originalArgs[3].expr,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            finalArgs.append(selector.loweredArgID)
            finalArgs.append(makeClosureRawOrBoxedArgument(
                callableInfo: selector.callableInfo,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            ))
            return finalArgs
        }

        // compareValuesBy: expand selector lambda args to (fnPtr, closureRaw) pairs.
        // kk_compareValuesBy1(a, b, selector) → (a, b, selectorFn, selectorClosureRaw)
        // kk_compareValuesBy(a, b, sel1, sel2) → (a, b, sel1Fn, sel1Closure, sel2Fn, sel2Closure)
        // kk_compareValuesBy3(a, b, sel1, sel2, sel3) → (a, b, sel1Fn, sel1Closure, sel2Fn, sel2Closure, sel3Fn, sel3Closure)
        let compareValuesbyNames: Set = ["kk_compareValuesBy1", "kk_compareValuesBy", "kk_compareValuesBy3"]
        if compareValuesbyNames.contains(externalLinkName), loweredArguments.count >= 3 {
            // First 2 arguments (a, b) pass through unchanged
            var finalArgs = [loweredArguments[0], loweredArguments[1]]
            // Remaining arguments are selector lambdas that need expansion
            for i in 2..<loweredArguments.count {
                let selector = makeCollectionHOFSelectorArgument(
                    loweredArgID: loweredArguments[i],
                    argExprID: originalArgs[i].expr,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                finalArgs.append(selector.loweredArgID)
                finalArgs.append(makeClosureRawOrBoxedArgument(
                    callableInfo: selector.callableInfo,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                ))
            }
            return finalArgs
        }

        return loweredArguments
    }

    func makeAtomicReferenceUpdateFunctionValue(
        loweredArgID: KIRExprID,
        argExprID: ExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let callableInfo = driver.ctx.callableValueInfo(for: loweredArgID) else {
            return nil
        }
        let callableType = arena.exprType(loweredArgID) ?? sema.bindings.exprTypes[argExprID] ?? sema.types.anyType
        let nonNullCallableType = sema.types.makeNonNullable(callableType)
        guard case let .functionType(functionType) = sema.types.kind(of: nonNullCallableType),
              functionType.params.count == 1,
              isStringRawBridgeType(functionType.params[0], sema: sema)
                || isStringRawBridgeType(functionType.returnType, sema: sema)
        else {
            return nil
        }

        let adapterSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let adapterName = interner.intern("kk_atomic_ref_update_adapter_\(argExprID.rawValue)_\(adapterSymbol.rawValue)")
        let closureParam = KIRParameter(
            symbol: driver.ctx.allocateSyntheticGeneratedSymbol(),
            type: sema.types.intType
        )
        let rawValueParam = KIRParameter(
            symbol: driver.ctx.allocateSyntheticGeneratedSymbol(),
            type: sema.types.intType
        )

        var body: [KIRInstruction] = [.beginBlock]
        let closureExpr = arena.appendExpr(.symbolRef(closureParam.symbol), type: closureParam.type)
        body.append(.constValue(result: closureExpr, value: .symbolRef(closureParam.symbol)))
        let rawValueExpr = arena.appendExpr(.symbolRef(rawValueParam.symbol), type: rawValueParam.type)
        body.append(.constValue(result: rawValueExpr, value: .symbolRef(rawValueParam.symbol)))

        var callArguments = appendCallableCaptureLoads(
            callableInfo: callableInfo,
            closureExpr: closureExpr,
            sema: sema,
            arena: arena,
            interner: interner,
            body: &body
        )
        callArguments.append(bridgeAtomicReferenceUpdateArgument(
            rawValueExpr,
            parameterType: functionType.params[0],
            sema: sema,
            arena: arena,
            interner: interner,
            body: &body
        ))

        let lambdaCanThrow = callableRequiresThrownChannel(callableInfo.symbol, arena: arena)
        let callResult = arena.appendTemporary(type: functionType.returnType)
        let thrownResult = lambdaCanThrow
            ? arena.appendTemporary(type: sema.types.nullableAnyType)
            : nil
        body.append(.call(
            symbol: callableInfo.symbol,
            callee: callableInfo.callee,
            arguments: callArguments,
            result: callResult,
            canThrow: lambdaCanThrow,
            thrownResult: thrownResult
        ))
        if let thrownResult {
            let continueLabel = driver.ctx.makeLoopLabel()
            let rethrowLabel = driver.ctx.makeLoopLabel()
            body.append(.jumpIfNotNull(value: thrownResult, target: rethrowLabel))
            body.append(.jump(continueLabel))
            body.append(.label(rethrowLabel))
            body.append(.rethrow(value: thrownResult))
            body.append(.label(continueLabel))
        }

        body.append(.returnValue(callResult))
        body.append(.endBlock)

        let adapterDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: adapterSymbol,
                    name: adapterName,
                    params: [closureParam, rawValueParam],
                    returnType: functionType.returnType,
                    body: body,
                    isSuspend: functionType.isSuspend,
                    isInline: false
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(adapterDecl)

        let adapterExpr = arena.appendExpr(.symbolRef(adapterSymbol), type: sema.types.intType)
        instructions.append(.constValue(result: adapterExpr, value: .symbolRef(adapterSymbol)))
        let closureRaw = makeFunctionValueClosureRawArgument(
            callableInfo: callableInfo,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        let materialized = arena.appendTemporary(type: callableType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_function_create_1"),
            arguments: [adapterExpr, closureRaw],
            result: materialized,
            canThrow: false,
            thrownResult: nil
        ))
        driver.ctx.registerCallableValue(
            materialized,
            symbol: adapterSymbol,
            callee: adapterName,
            captureArguments: [closureRaw],
            hasClosureParam: true
        )
        return materialized
    }

    private func isStringRawBridgeType(_ type: TypeID, sema: SemaModule) -> Bool {
        sema.types.makeNonNullable(type) == sema.types.stringType
    }

    private func bridgeAtomicReferenceUpdateArgument(
        _ rawValueExpr: KIRExprID,
        parameterType: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        body: inout [KIRInstruction]
    ) -> KIRExprID {
        guard isStringRawBridgeType(parameterType, sema: sema) else {
            return rawValueExpr
        }
        let stringTag = arena.appendExpr(.intLiteral(3), type: sema.types.intType)
        body.append(.constValue(result: stringTag, value: .intLiteral(3)))
        let bridged = arena.appendTemporary(type: sema.types.stringType)
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_any_to_string"),
            arguments: [rawValueExpr, stringTag],
            result: bridged,
            canThrow: false,
            thrownResult: nil
        ))
        return bridged
    }

    private func makeFunctionValueClosureRawArgument(
        callableInfo: KIRCallableValueInfo,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boxedCaptureArguments = makeBoxedCallableCaptureArguments(
            callableInfo: callableInfo,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        if let closureRaw = boxedCaptureArguments.first {
            return closureRaw
        }
        let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
        instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
        return zeroExpr
    }

    func makeClosureThunkCallableAdapter(
        callableInfo: KIRCallableValueInfo,
        loweredArgID: KIRExprID,
        argExprID: ExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRCallableValueInfo? {
        let callableType = arena.exprType(loweredArgID) ?? sema.bindings.exprTypes[argExprID] ?? sema.types.anyType
        let nonNullCallableType = sema.types.makeNonNullable(callableType)
        guard case let .functionType(functionType) = sema.types.kind(of: nonNullCallableType),
              functionType.params.isEmpty
        else {
            return nil
        }

        let adapterSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
        let adapterName = interner.intern("kk_closure_thunk_adapter_\(argExprID.rawValue)_\(adapterSymbol.rawValue)")
        let closureParam = KIRParameter(
            symbol: driver.ctx.allocateSyntheticGeneratedSymbol(),
            type: sema.types.intType
        )

        var body: [KIRInstruction] = [.beginBlock]
        let closureExpr = arena.appendExpr(.symbolRef(closureParam.symbol), type: closureParam.type)
        body.append(.constValue(result: closureExpr, value: .symbolRef(closureParam.symbol)))

        let callArguments = appendCallableCaptureLoads(
            callableInfo: callableInfo,
            closureExpr: closureExpr,
            sema: sema,
            arena: arena,
            interner: interner,
            body: &body
        )

        let lambdaCanThrow = callableRequiresThrownChannel(callableInfo.symbol, arena: arena)
        let callResult = arena.appendTemporary(type: functionType.returnType
        )
        let thrownResult = lambdaCanThrow
            ? arena.appendTemporary(type: sema.types.nullableAnyType
            )
            : nil
        body.append(.call(
            symbol: callableInfo.symbol,
            callee: callableInfo.callee,
            arguments: callArguments,
            result: callResult,
            canThrow: lambdaCanThrow,
            thrownResult: thrownResult
        ))
        if let thrownResult {
            let continueLabel = driver.ctx.makeLoopLabel()
            let rethrowLabel = driver.ctx.makeLoopLabel()
            body.append(.jumpIfNotNull(value: thrownResult, target: rethrowLabel))
            body.append(.jump(continueLabel))
            body.append(.label(rethrowLabel))
            body.append(.rethrow(value: thrownResult))
            body.append(.label(continueLabel))
        }

        switch sema.types.kind(of: functionType.returnType) {
        case .unit, .nothing(.nonNull), .nothing(.nullable):
            body.append(.returnUnit)
        default:
            body.append(.returnValue(callResult))
        }
        body.append(.endBlock)

        let adapterDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: adapterSymbol,
                    name: adapterName,
                    params: [closureParam],
                    returnType: functionType.returnType,
                    body: body,
                    isSuspend: functionType.isSuspend,
                    isInline: false
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(adapterDecl)

        let adapterCaptureArguments = makeBoxedCallableCaptureArguments(
            callableInfo: callableInfo,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        return KIRCallableValueInfo(
            symbol: adapterSymbol,
            callee: adapterName,
            captureArguments: adapterCaptureArguments,
            hasClosureParam: true
        )
    }

}
