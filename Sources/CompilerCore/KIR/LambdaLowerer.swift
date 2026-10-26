struct KIRCallableValueInfo {
    let symbol: SymbolID
    let callee: InternedString
    let captureArguments: [KIRExprID]
    let hasClosureParam: Bool
    /// Raw entry for trampolines that must own the lambda's continuation frames.
    let unboxedSymbol: SymbolID?

    init(
        symbol: SymbolID,
        callee: InternedString,
        captureArguments: [KIRExprID],
        hasClosureParam: Bool,
        unboxedSymbol: SymbolID? = nil
    ) {
        self.symbol = symbol
        self.callee = callee
        self.captureArguments = captureArguments
        self.hasClosureParam = hasClosureParam
        self.unboxedSymbol = unboxedSymbol
    }
}

final class LambdaLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

    func normalizeHOFPrimitiveParameter(
        _ exprID: KIRExprID,
        type: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction],
        isRawCallbackParameter: Bool = false
    ) -> KIRExprID {
        let rawKind = sema.types.kind(of: type)
        let kind = resolveValueClassKind(
            rawKind,
            types: sema.types,
            symbols: sema.symbols
        )
        // String parameters of raw-callback lambdas are bridged from raw handle
        // to flat aggregate by the backend at function entry. Unboxing them here
        // again would pass an already-flat aggregate to kk_string_to_flat and
        // crash, so skip the KIR-level unboxing only for those parameters.
        if isRawCallbackParameter, BoxingCalleeTable.isNonNullableStringStruct(rawKind) {
            return exprID
        }
        if isRawCallbackParameter,
           let valueClassSymbol = nullableUnderlyingValueClassSymbol(
               of: rawKind,
               types: sema.types,
               symbols: sema.symbols
           )
        {
            // A generic callback invokes this adapter through the erased `T`
            // ABI. A nullable-underlying value class arrives as its nominal
            // box, while the typed lambda body expects the raw payload.
            let normalizedExpr = arena.appendTemporary(type: type)
            emitValueClassUnboxCall(
                value: exprID,
                classSymbol: valueClassSymbol,
                result: normalizedExpr,
                resultType: type,
                types: sema.types,
                symbols: sema.symbols,
                interner: interner,
                arena: arena,
                into: &instructions
            )
            return normalizedExpr
        }
        let unboxCallee: InternedString? = {
            // Enum values use their raw ordinal in lambda bodies, while
            // collection HOFs pass elements through Any-erased slots as
            // RuntimeIntBox handles. Normalize both representations before
            // lowering the body (e.g. `entries.find { it.rgb == rgb }`).
            if case let .classType(classType) = rawKind,
               classType.nullability == .nonNull,
               let symbol = sema.symbols.symbol(classType.classSymbol),
               symbol.kind == .enumClass
            {
                return ABILoweringPass.primitiveUnboxingCallee(for: .int, interner: interner)
            }
            return BoxingCalleeTable(interner: interner).unboxCallee(
                for: kind,
                requireNonNull: true
            )
        }()
        guard let unboxCallee else {
            return exprID
        }
        let normalizedExpr = emitNonThrowingCall(
            callee: unboxCallee,
            arg: exprID,
            resultType: type,
            arena: arena,
            into: &instructions
        )
        return normalizedExpr
    }


    /// Best-effort scan for whether a lowered lambda body performs a call that
    /// requires a suspend context. Used to correct a lambda literal's
    /// `isSuspend` when the contextual/expected type it was checked against is
    /// non-suspend (e.g. `List.map`'s plain `(T) -> R` `transform` parameter)
    /// but the body suspends anyway -- see the call sites for why trusting the
    /// contextual type alone causes suspend calls to run without a valid
    /// continuation.
    private func lambdaBodyRequiresSuspend(
        _ body: [KIRInstruction],
        arena: KIRArena,
        interner: StringInterner
    ) -> Bool {
        let suspendIndicatorNames: Set<String> = [
            "kk_kxmini_async_await",
            "kk_job_join",
            "kk_job_await_completion",
            "kk_kxmini_delay",
            "kk_coroutine_yield",
            "__kk_sequence_builder_yield",
            "__kk_iterator_builder_yield",
            "kk_suspend_function_invoke_0",
            "kk_suspend_function_invoke",
            "kk_suspend_function_invoke_2",
            "kk_suspend_function_invoke_3",
            "kk_suspend_function_invoke_4",
            "kk_suspend_function_invoke_5",
            "kk_suspend_function_invoke_6",
            "kk_suspend_coroutine",
            "kk_with_timeout",
            "kk_with_timeout_or_null_throwing",
            "kk_flow_collect",
            "__kk_flow_collectLatest",
            "kk_flow_emit",
        ]
        for instruction in body {
            let calleeInfo: (symbol: SymbolID?, callee: InternedString)?
            switch instruction {
            case let .call(symbol, callee, _, _, _, _, _, _):
                calleeInfo = (symbol, callee)
            case let .virtualCall(symbol, callee, _, _, _, _, _, _):
                calleeInfo = (symbol, callee)
            default:
                calleeInfo = nil
            }
            guard let calleeInfo else { continue }
            if suspendIndicatorNames.contains(interner.resolve(calleeInfo.callee)) {
                return true
            }
            if let symbol = calleeInfo.symbol, arena.function(for: symbol)?.isSuspend == true {
                return true
            }
        }
        return false
    }

    func lowerLambdaLiteralExpr(
        _ exprID: ExprID,
        params: [InternedString],
        bodyExpr: ExprID,
        allowsNonLocalReturn: Bool = false,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        // For SAM-converted lambdas, the bound type is the interface type.
        // Use the stored underlying function type instead.
        let effectiveFuncTypeID: TypeID? = {
            if sema.bindings.isSamConversion(exprID),
               let samFuncType = sema.bindings.samUnderlyingFunctionType(for: exprID)
            {
                return samFuncType
            }
            return boundType
        }()
        let functionType = effectiveFuncTypeID.flatMap { typeID -> FunctionType? in
            guard case let .functionType(functionType) = sema.types.kind(of: typeID) else {
                return nil
            }
            return functionType
        }

        let lambdaName = syntheticLambdaName(for: exprID, interner: interner)
        let isSamConversion = sema.bindings.isSamConversion(exprID)
        let lambdaSymbol: SymbolID = if isSamConversion {
            sema.symbols.define(
                kind: .function,
                name: lambdaName,
                fqName: [lambdaName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        } else {
            driver.ctx.syntheticLambdaSymbol(for: exprID)
        }

        let hasReceiverParam = functionType?.receiver != nil
            && sema.bindings.coroutineScopeLambdaReceiverTypes[exprID] == nil
        let needsClosureParam = sema.bindings.isCollectionHOFLambdaExpr(exprID) && !isSamConversion
        // A receiver lambda always takes its own receiver parameter, even when the
        // enclosing implicit receiver has a compatible type: `"a".run { "b".apply { this } }`
        // must see "b", and `this@run` must still reach "a".
        let needsExplicitReceiver = hasReceiverParam
        let effectiveParamCount: Int = {
            let baseCount: Int = if params.isEmpty, let functionType, !functionType.params.isEmpty {
                functionType.params.count
            } else {
                params.count
            }
            return baseCount + (needsExplicitReceiver ? 1 : 0)
        }()
        let contextParameterTypes = functionType?.contextReceivers ?? []
        let contextParameterCount = contextParameterTypes.count

        let lambdaParameterTypes: [TypeID] = {
            var types = contextParameterTypes
            if needsExplicitReceiver, let receiverType = functionType?.receiver {
                types.append(receiverType)
            }
            let valueParamCount = effectiveParamCount - (needsExplicitReceiver ? 1 : 0)
            for index in 0 ..< valueParamCount {
                if let functionType, index < functionType.params.count {
                    types.append(functionType.params[index])
                } else {
                    types.append(sema.types.anyType)
                }
            }
            return types
        }()
        let substitutedReturnType = functionType?.returnType
            ?? sema.bindings.exprTypes[bodyExpr]
            ?? sema.types.anyType
        // A return the callee declares as a type parameter carries a boxed value
        // at runtime even though the body is checked against the substituted
        // concrete type, so box on the way out.
        let returnsErasedGeneric = !needsClosureParam && !isSamConversion
            && driver.ctx.lambdaReturnsErasedGeneric(for: exprID, ast: ast, sema: sema)
        let lambdaReturnType = erasedLambdaReturnType(
            substitutedReturnType,
            returnsErasedGeneric: returnsErasedGeneric,
            sema: sema,
            interner: interner
        )

        let captureSymbols = computeCaptureSymbolsForLambda(
            lambdaExprID: exprID,
            lambdaParamCount: effectiveParamCount + contextParameterCount,
            lambdaBodyExprID: bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            receiverType: functionType?.receiver ?? sema.bindings.coroutineScopeLambdaReceiverTypes[exprID]
        )

        let isNonCapturingLambda = captureSymbols.isEmpty && !needsClosureParam
        if isNonCapturingLambda {
            return lowerNonCapturingLambda(
                exprID: exprID,
                params: params,
                bodyExpr: bodyExpr,
                allowsNonLocalReturn: allowsNonLocalReturn,
                hasExplicitReceiverParam: needsExplicitReceiver,
                lambdaParameterTypes: lambdaParameterTypes,
                lambdaReturnType: lambdaReturnType,
                substitutedReturnType: substitutedReturnType,
                returnsErasedGeneric: returnsErasedGeneric,
                functionType: functionType,
                isSamConversion: isSamConversion,
                boundType: boundType,
                effectiveFuncTypeID: effectiveFuncTypeID,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        var captureBindings: [(capturedSymbol: SymbolID, param: KIRParameter, valueExpr: KIRExprID, declaredType: TypeID)] = []
        captureBindings.reserveCapacity(captureSymbols.count)
        for (index, symbol) in captureSymbols.enumerated() {
            let declaredType = driver.ctx.localDeclaredType(for: symbol) ?? typeForSymbolReference(symbol, sema: sema)
            guard let captureValueExpr = captureValueExpr(
                for: symbol,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            ) else {
                continue
            }
            let captureType = arena.exprType(captureValueExpr) ?? typeForSymbolReference(symbol, sema: sema)
            let captureParamSymbol = syntheticLambdaCaptureParamSymbol(
                lambdaExprID: exprID,
                captureIndex: index
            )
            let captureParam = KIRParameter(symbol: captureParamSymbol, type: captureType)
            captureBindings.append((
                capturedSymbol: symbol,
                param: captureParam,
                valueExpr: captureValueExpr,
                declaredType: declaredType
            ))
        }

        // For lambdas passed to C HOFs (filter, map, toComponents, etc.),
        // Runtime expects (closureRaw, ...valueParams, outThrown).
        let lambdaParameters: [KIRParameter]
        if needsClosureParam {
            let closureParamType = captureBindings.count == 1
                ? captureBindings[0].param.type
                : sema.types.intType
            let closureParam = KIRParameter(
                symbol: syntheticLambdaClosureParamSymbol(lambdaExprID: exprID),
                type: closureParamType
            )
            let valueParams = (0 ..< lambdaParameterTypes.count).map { index in
                KIRParameter(
                    symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                    type: lambdaParameterTypes[index]
                )
            }
            lambdaParameters = [closureParam] + valueParams
        } else {
            lambdaParameters = (0 ..< lambdaParameterTypes.count).map { index in
                KIRParameter(
                    symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                    type: lambdaParameterTypes[index]
                )
            }
        }
        let usesClosureRawCapture = needsClosureParam && captureBindings.count == 1
        let usesClosureObjectCapture = needsClosureParam && captureBindings.count >= 2
        let functionCaptureBindings = (usesClosureRawCapture || usesClosureObjectCapture) ? [] : captureBindings

        let scopeSnapshot = driver.ctx.saveScope()
        let savedReceiverSymbol = scopeSnapshot.currentImplicitReceiverSymbol
        let capturesRuntimeScopeReceiver = scopeSnapshot.currentImplicitReceiverExprID.map {
            driver.ctx.runtimeCoroutineScopeReceiverExprIDs.contains($0)
        } ?? false
        defer { driver.ctx.restoreScope(scopeSnapshot) }
        driver.ctx.resetScopeForFunction()
        driver.ctx.currentLambdaAllowsNonLocalReturn = allowsNonLocalReturn
        driver.ctx.currentLambdaAllowsNonLocalBreakContinue = allowsNonLocalReturn
        driver.ctx.nonLocalReturnTarget = scopeSnapshot.nonLocalReturnTarget ?? scopeSnapshot.currentFunctionSymbol
        if allowsNonLocalReturn {
            driver.ctx.enclosingLoopControlStack = scopeSnapshot.enclosingLoopControlStack + scopeSnapshot.loopControlStack
            driver.ctx.nextLoopLabel = max(scopeSnapshot.nextLoopLabel, 10000)
        }

        var lambdaBody: [KIRInstruction] = [.beginBlock]
        for capture in functionCaptureBindings {
            let captureExpr = arena.appendExpr(.symbolRef(capture.param.symbol), type: capture.param.type)
            lambdaBody.append(.constValue(result: captureExpr, value: .symbolRef(capture.param.symbol)))
            bindCapturedLambdaValue(captureExpr, capture: capture, sema: sema, arena: arena, interner: interner, instructions: &lambdaBody)
            if capture.capturedSymbol == savedReceiverSymbol {
                // A captured outer `this` is the implicit receiver only when the
                // lambda has no receiver of its own; a `SequenceScope.() -> Unit`-style
                // receiver lambda must keep its receiver param innermost so member
                // calls like `yield` dispatch on it.
                if !needsExplicitReceiver {
                    driver.ctx.setImplicitReceiver(symbol: capture.param.symbol, exprID: captureExpr)
                }
                driver.ctx.setLocalDeclaredType(capture.declaredType, for: capture.param.symbol)
                bindCapturedOuterLambdaReceiver(captureExpr, type: capture.param.type, sema: sema, overwriteExisting: false)
                if capturesRuntimeScopeReceiver {
                    driver.ctx.runtimeCoroutineScopeReceiverExprIDs.insert(captureExpr)
                }
            }
        }
        for (paramIndex, lambdaParam) in lambdaParameters.enumerated() {
            let paramExpr = arena.appendExpr(.symbolRef(lambdaParam.symbol), type: lambdaParam.type)
            lambdaBody.append(.constValue(result: paramExpr, value: .symbolRef(lambdaParam.symbol)))
            let normalizedParamExpr: KIRExprID
            if needsClosureParam, paramIndex > 0 {
                normalizedParamExpr = normalizeHOFPrimitiveParameter(
                    paramExpr,
                    type: lambdaParam.type,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &lambdaBody,
                    isRawCallbackParameter: true
                )
            } else {
                normalizedParamExpr = paramExpr
            }
            driver.ctx.setLocalValue(normalizedParamExpr, for: lambdaParam.symbol)
            // When a parameter is the explicit receiver (from a function-with-receiver type),
            // set it as the implicit receiver so that member calls resolve correctly.
            // For collection-HOF lambdas the closure param is first, so the receiver
            // follows it.
            let receiverParamIndex = (needsClosureParam ? 1 : 0) + contextParameterCount
            if needsExplicitReceiver, paramIndex == receiverParamIndex {
                driver.ctx.setImplicitReceiver(symbol: lambdaParam.symbol, exprID: normalizedParamExpr)
            }
        }
        if usesClosureRawCapture,
           let closureCapture = captureBindings.first,
           let closureParam = lambdaParameters.first,
           let closureExpr = driver.ctx.localValue(for: closureParam.symbol)
        {
            bindCapturedLambdaValue(closureExpr, capture: closureCapture, sema: sema, arena: arena, interner: interner, instructions: &lambdaBody)
            if closureCapture.capturedSymbol == savedReceiverSymbol {
                if !needsExplicitReceiver {
                    driver.ctx.setImplicitReceiver(symbol: closureParam.symbol, exprID: closureExpr)
                }
                driver.ctx.setLocalDeclaredType(closureCapture.declaredType, for: closureParam.symbol)
                bindCapturedOuterLambdaReceiver(closureExpr, type: closureCapture.param.type, sema: sema, overwriteExisting: false)
                if capturesRuntimeScopeReceiver {
                    driver.ctx.runtimeCoroutineScopeReceiverExprIDs.insert(closureExpr)
                }
            }
        }
        // Multi-capture HOF lambda: closureRaw is a packed closure object.
        if usesClosureObjectCapture,
           let closureParam = lambdaParameters.first,
           let closureObjExpr = driver.ctx.localValue(for: closureParam.symbol)
        {
            let kkArrayGet = interner.intern("kk_array_get_inbounds")
            for (captureIndex, capture) in captureBindings.enumerated() {
                let fieldOffset = Int64(captureIndex + 2)
                let offsetExpr = arena.appendExpr(.intLiteral(fieldOffset), type: sema.types.intType)
                lambdaBody.append(.constValue(result: offsetExpr, value: .intLiteral(fieldOffset)))
                let loadedExpr = arena.appendTemporary(type: capture.param.type)
                lambdaBody.append(.call(callee: kkArrayGet, arguments: [closureObjExpr, offsetExpr], result: loadedExpr, canThrow: false))
                bindCapturedLambdaValue(loadedExpr, capture: capture, sema: sema, arena: arena, interner: interner, instructions: &lambdaBody)
                if capture.capturedSymbol == savedReceiverSymbol {
                    if !needsExplicitReceiver {
                        driver.ctx.setImplicitReceiver(symbol: capture.param.symbol, exprID: loadedExpr)
                    }
                    driver.ctx.setLocalDeclaredType(capture.declaredType, for: capture.param.symbol)
                    bindCapturedOuterLambdaReceiver(loadedExpr, type: capture.param.type, sema: sema, overwriteExisting: false)
                    if capturesRuntimeScopeReceiver {
                        driver.ctx.runtimeCoroutineScopeReceiverExprIDs.insert(loadedExpr)
                    }
                }
            }
        }
        // Restore direct-call metadata using this body's environment values,
        // after all raw or packed captures have been bound.
        var capturedValues: [KIRExprID: KIRExprID] = [:]
        for capture in captureBindings {
            if let value = driver.ctx.localValue(for: capture.capturedSymbol)
                ?? driver.ctx.localDelegateStorage(for: capture.capturedSymbol)
            {
                capturedValues[capture.valueExpr] = value
            }
        }
        for capture in captureBindings {
            guard sema.symbols.symbol(capture.capturedSymbol)?.flags.contains(.localFunction) == true,
                  let callable = driver.ctx.callableValueInfo(for: capture.valueExpr),
                  let value = driver.ctx.localValue(for: capture.capturedSymbol)
            else { continue }
            let arguments = callable.captureArguments.map { argument in
                guard let captured = capturedValues[argument] else {
                    preconditionFailure("BuildKIRPhase: missing callable environment in lambda capture")
                }
                return captured
            }
            driver.ctx.registerCallableValue(
                value, symbol: callable.symbol, callee: callable.callee,
                captureArguments: arguments,
                hasClosureParam: callable.hasClosureParam,
                unboxedSymbol: callable.unboxedSymbol
            )
        }

        // The lambda's own receiver parameter is the innermost implicit
        // receiver inside its body, but the closure-capture loops above run
        // after it and re-claim the single active-receiver slot for a
        // captured enclosing `this`. Re-assert the receiver parameter here so
        // e.g. `iterator { yield(w) }` dispatches `yield` on the
        // SequenceScope parameter rather than the captured class instance.
        if needsExplicitReceiver {
            let receiverParam = lambdaParameters[(needsClosureParam ? 1 : 0) + contextParameterCount]
            if let receiverValue = driver.ctx.localValue(for: receiverParam.symbol) {
                driver.ctx.setImplicitReceiver(symbol: receiverParam.symbol, exprID: receiverValue)
            }
        }
        // Publish this lambda's receiver under its per-lambda symbol so that
        // `this@callee` (in this body or a nested lambda that captures it)
        // reads this receiver rather than the innermost implicit one.
        bindCoroutineScopeLambdaReceiver(exprID, sema: sema, arena: arena, interner: interner, instructions: &lambdaBody)
        registerLambdaReceiverValue(lambdaExprID: exprID, hasReceiverParam: hasReceiverParam)
        // Map param names → symbols for nameRef fallback when identifierSymbols is unbound.
        let effectiveParamNames: [InternedString] = if params.isEmpty, let functionType, !functionType.params.isEmpty {
            [interner.intern("it")]
        } else {
            params
        }
        // Value parameters start after the closure environment, context inputs,
        // and explicit receiver so a source name never aliases an ABI-only slot.
        let valueParamStart = (needsClosureParam ? 1 : 0) + contextParameterCount
            + (needsExplicitReceiver ? 1 : 0)
        for (i, paramName) in effectiveParamNames.enumerated() where valueParamStart + i < lambdaParameters.count {
            driver.ctx.registerLambdaParam(symbol: lambdaParameters[valueParamStart + i].symbol, forName: paramName)
        }

        let contextReceiverValues: [KIRLoweringContext.ContextReceiverValue] = contextParameterTypes
            .enumerated()
            .compactMap { index, type in
                let parameterIndex = (needsClosureParam ? 1 : 0) + index
                guard lambdaParameters.indices.contains(parameterIndex),
                      let value = driver.ctx.localValue(for: lambdaParameters[parameterIndex].symbol)
                else {
                    return nil
                }
                return KIRLoweringContext.ContextReceiverValue(type: type, exprID: value)
            }
        let loweredBody = driver.ctx.withContextReceiverValues(contextReceiverValues) {
            driver.lowerExpr(
                bodyExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &lambdaBody
            )
        }
        if !driver.controlFlowLowerer.isTerminatedExpr(loweredBody, arena: arena, sema: sema) {
            let returnedBody = boxErasedReturnValue(
                loweredBody,
                returnType: substitutedReturnType,
                returnsErasedGeneric: returnsErasedGeneric,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &lambdaBody
            )
            lambdaBody.append(.returnValue(returnedBody))
        }
        lambdaBody.append(.endBlock)

        // Coroutine launcher lambdas with an explicit receiver use launcher slot 0
        // for that receiver (for example, the Channel receiver of `produce {}`).
        // Keep that receiver first in the lowered function ABI; ordinary captured
        // lambdas retain the historical capture-first layout.
        let receiverFirstLauncherABI = sema.bindings.isCoroutineLauncherLambdaExpr(exprID)
            && needsExplicitReceiver
        if receiverFirstLauncherABI {
            driver.ctx.receiverFirstLauncherLambdaSymbols.insert(lambdaSymbol)
        }
        let functionParameters = receiverFirstLauncherABI
            ? lambdaParameters + functionCaptureBindings.map(\.param)
            : functionCaptureBindings.map(\.param) + lambdaParameters

        // The expected/contextual function type (e.g. a plain `(T) -> R)` HOF
        // parameter like `List.map`'s `transform`) doesn't always match what the
        // lambda body actually does: Kotlin only requires the *parameter* to be
        // `suspend` when the argument lambda calls suspend functions, but KSwiftK
        // currently still permits a suspend call inside a lambda literal checked
        // against a non-suspend expected type (matching real Kotlin's behavior for
        // `inline` HOFs, but without requiring the HOF itself to be inlined away).
        // If such a lambda is lowered as `isSuspend: false` anyway, it never gets
        // picked up by CoroutineLoweringPass's CPS transform, so its suspend calls
        // run without a valid continuation and corrupt memory at runtime instead
        // of suspending. Detect that mismatch directly from the lowered body so
        // the declared isSuspend always matches what the body actually needs.
        let effectiveIsSuspend = (functionType?.isSuspend ?? false)
            || lambdaBodyRequiresSuspend(lambdaBody, arena: arena, interner: interner)
        let hasNonLocalReturn = lambdaBody.contains { instruction in
            if case .nonLocalReturn = instruction { return true }
            return false
        }
        let hasNonLocalLoopJump = KIRExternalLoopJump.containsExternalJump(in: lambdaBody)
            || sema.bindings.loopJumpLambdaPaths.values.contains { $0.contains(exprID) }

        let lambdaDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: lambdaSymbol,
                    name: lambdaName,
                    params: functionParameters,
                    returnType: lambdaReturnType,
                    body: lambdaBody,
                    isSuspend: effectiveIsSuspend,
                    isInline: false,
                    isInlineOnly: hasNonLocalReturn || hasNonLocalLoopJump
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(lambdaDecl)

        if isSamConversion,
           let boundType,
           case let .classType(interfaceType) = sema.types.kind(of: boundType),
           let samValue = lowerSamWrapperValue(
               exprID,
               interfaceType: interfaceType,
               lambdaSymbol: lambdaSymbol,
               lambdaName: lambdaName,
               lambdaReturnType: lambdaReturnType,
               captureBindings: captureBindings,
               samMethodReceiverType: functionType?.receiver,
               samMethodParamTypes: functionType?.params ?? lambdaParameterTypes,
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            return samValue
        }

        // For SAM-converted lambdas, use the function type (not the interface
        // type) so the KIR callable value machinery dispatches correctly.
        let lambdaValueType = effectiveFuncTypeID
            ?? boundType
            ?? sema.types.make(
                .functionType(
                    FunctionType(
                        params: lambdaParameterTypes,
                        returnType: lambdaReturnType,
                        isSuspend: effectiveIsSuspend,
                        nullability: .nonNull
                    )
                )
            )
        let lambdaValueExpr = arena.appendExpr(.symbolRef(lambdaSymbol), type: lambdaValueType)
        instructions.append(.constValue(result: lambdaValueExpr, value: .symbolRef(lambdaSymbol)))
        emitLambdaEnclosingClassMetadata(
            exprID: exprID,
            value: lambdaValueExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        let captureArgs = (usesClosureRawCapture || usesClosureObjectCapture) ? captureBindings.map(\.valueExpr) : functionCaptureBindings.map(\.valueExpr)
        driver.ctx.registerCallableValue(
            lambdaValueExpr,
            symbol: lambdaSymbol,
            callee: lambdaName,
            captureArguments: captureArgs,
            hasClosureParam: needsClosureParam
        )
        if !captureArgs.isEmpty {
            arena.registerLambdaCaptureArgs(lambdaSymbol, captureArgs: captureArgs)
        }
        // Lambdas passed to runBlocking/launch/async/produce are excluded: their
        // captures are forwarded through CoroutineLoweringPass+LauncherSupport's
        // own launcher-continuation rewrite (BUG-049), which expects to resolve
        // the raw lambda symbol directly rather than a kk_function_create_N
        // boxed closure -- see the coroutineLauncherLambdaExprIDs doc comment.
        // Inline arguments must retain their raw captures even when the return
        // is normal or belongs to a nested lambda.
        if !hasNonLocalReturn,
           !allowsNonLocalReturn,
           !captureArgs.isEmpty,
           !needsClosureParam,
           !isSamConversion,
           !sema.bindings.isCoroutineLauncherLambdaExpr(exprID),
           !sema.bindings.rawSuspendEntryLambdaExprIDs.contains(exprID),
           let functionType
        {
            let functionValueType = sema.bindings.functionValueExpectedType(for: exprID)
                .flatMap { typeID -> FunctionType? in
                    guard case let .functionType(expectedType) = sema.types.kind(of: typeID) else {
                        return nil
                    }
                    return expectedType
                } ?? functionType
            if let materialized = materializeEscapingCallableValue(
                exprID: exprID,
                lambdaSymbol: lambdaSymbol,
                lambdaName: syntheticLambdaName(for: exprID, interner: interner),
                lambdaReturnType: lambdaReturnType,
                functionType: functionValueType,
                captureArguments: captureArgs,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            ) {
                return materialized
            }
        }
        if !hasNonLocalReturn {
            if let functionType {
                emitFunctionValueTypeTag(
                    lambdaValueExpr, functionType: functionType, sema: sema,
                    arena: arena, interner: interner, instructions: &instructions
                )
            }
            emitFunctionDescription(
                value: lambdaValueExpr,
                description: "kotlin.Function\(lambdaParameterTypes.count)",
                identity: true,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
        }
        return lambdaValueExpr
    }

    /// Re-establishes one captured symbol's value inside a lambda body's
    /// fresh scope (`resetScopeForFunction()` clears the outer scope's
    /// bindings, including delegate storage -- see `ScopeSnapshot`).
    ///
    /// A delegated local's (KSP-491: `val x by lazy { ... }`/`by Prop()`)
    /// captured value is the delegate *instance*, not a value
    /// (`setLocalDelegateStorage`) -- reads inside the lambda body must
    /// still call getValue fresh, exactly like reads in the declaring
    /// scope (see `ExprLowerer.readLocalDelegateValue`), or a vetoable/
    /// observable delegate's writes wouldn't be observed from inside the
    /// lambda.
    private func bindCapturedLambdaValue(
        _ capturedValue: KIRExprID,
        capture: (capturedSymbol: SymbolID, param: KIRParameter, valueExpr: KIRExprID, declaredType: TypeID),
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        if sema.symbols.delegateGetValueSymbol(for: capture.capturedSymbol) != nil {
            driver.ctx.setLocalDelegateStorage(capturedValue, for: capture.capturedSymbol)
        } else if let semanticSymbol = sema.symbols.symbol(capture.capturedSymbol),
                  semanticSymbol.kind == .local,
                  (semanticSymbol.flags.contains(.mutable)
                      || sema.bindings.isContractCallsInPlaceInitializedSymbol(capture.capturedSymbol))
        {
            driver.ctx.setMutableCaptureCell(capturedValue, for: capture.capturedSymbol)
        } else {
            driver.ctx.setLocalValue(capturedValue, for: capture.capturedSymbol)
        }
        driver.ctx.setLocalDeclaredType(capture.declaredType, for: capture.capturedSymbol)
        // A nested receiver lambda can still access an enclosing interface
        // member through its captured dispatch receiver and itable slot.
        if let capturedKind = sema.symbols.symbol(capture.capturedSymbol)?.kind,
           capturedKind == .class || capturedKind == .interface
        {
            bindCapturedOuterLambdaReceiver(capturedValue, type: capture.param.type, sema: sema)
        }
        if let semanticSymbol = sema.symbols.symbol(capture.capturedSymbol),
           semanticSymbol.kind == .typeParameter,
           semanticSymbol.flags.contains(.reifiedTypeParameter)
        {
            let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: capture.capturedSymbol)
            let componentSymbol = SyntheticSymbolScheme.reifiedArrayComponentTokenSymbol(for: capture.capturedSymbol)
            let classToken = arena.appendTemporary(type: sema.types.intType)
            let componentToken = arena.appendTemporary(type: sema.types.intType)
            instructions.append(.call(callee: interner.intern("__kk_pair_first"), arguments: [capturedValue], result: classToken, canThrow: false))
            instructions.append(.call(
                callee: interner.intern("__kk_pair_second"), arguments: [capturedValue],
                result: componentToken, canThrow: false
            ))
            driver.ctx.setLocalValue(classToken, for: tokenSymbol)
            driver.ctx.setLocalDeclaredType(sema.types.intType, for: tokenSymbol)
            driver.ctx.setLocalValue(componentToken, for: componentSymbol)
            driver.ctx.setLocalDeclaredType(sema.types.intType, for: componentSymbol)
        }
    }

    private func bindCapturedOuterLambdaReceiver(_ receiver: KIRExprID, type: TypeID, sema: SemaModule, overwriteExisting: Bool = true) {
        guard case let .classType(classType) = sema.types.kind(of: type) else { return }
        // An extension receiver may share the dispatch owner's nominal type.
        if !overwriteExisting, driver.ctx.capturedOuterReceiverExprID(for: classType.classSymbol) != nil {
            return
        }
        driver.ctx.setCapturedOuterReceiver(receiver, for: classType.classSymbol)
        driver.ctx.setLocalValue(receiver, for: classType.classSymbol)
        if let owner = sema.symbols.symbol(classType.classSymbol) {
            driver.ctx.setQualifiedThisReceiver(receiver, for: owner.name)
        }
    }

    private func isFloatingPointValueType(_ type: TypeID, sema: SemaModule) -> Bool {
        switch sema.types.kind(of: type) {
        case .primitive(.double, .nonNull), .primitive(.float, .nonNull): true
        default: false
        }
    }

    private func lowerNonCapturingLambda(
        exprID: ExprID,
        params: [InternedString],
        bodyExpr: ExprID,
        allowsNonLocalReturn: Bool,
        hasExplicitReceiverParam: Bool,
        lambdaParameterTypes: [TypeID],
        lambdaReturnType: TypeID,
        substitutedReturnType: TypeID,
        returnsErasedGeneric: Bool,
        functionType: FunctionType?,
        isSamConversion: Bool,
        boundType: TypeID?,
        effectiveFuncTypeID: TypeID?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let lambdaName = syntheticLambdaName(for: exprID, interner: interner)
        let lambdaSymbol = driver.ctx.syntheticLambdaSymbol(for: exprID)
        let contextParameterTypes = functionType?.contextReceivers ?? []
        let contextParameterCount = contextParameterTypes.count

        let lambdaParameters = (0 ..< lambdaParameterTypes.count).map { index in
            KIRParameter(
                symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                type: lambdaParameterTypes[index]
            )
        }

        let scopeSnapshot = driver.ctx.saveScope()
        defer { driver.ctx.restoreScope(scopeSnapshot) }
        driver.ctx.resetScopeForFunction()
        driver.ctx.currentLambdaAllowsNonLocalReturn = allowsNonLocalReturn
        driver.ctx.currentLambdaAllowsNonLocalBreakContinue = allowsNonLocalReturn
        driver.ctx.nonLocalReturnTarget = scopeSnapshot.nonLocalReturnTarget ?? scopeSnapshot.currentFunctionSymbol
        if allowsNonLocalReturn {
            driver.ctx.enclosingLoopControlStack = scopeSnapshot.enclosingLoopControlStack + scopeSnapshot.loopControlStack
            driver.ctx.nextLoopLabel = max(scopeSnapshot.nextLoopLabel, 10000)
        }

        var lambdaBody: [KIRInstruction] = [.beginBlock]

        for (paramIndex, lambdaParam) in lambdaParameters.enumerated() {
            let paramExpr = arena.appendExpr(.symbolRef(lambdaParam.symbol), type: lambdaParam.type)
            lambdaBody.append(.constValue(result: paramExpr, value: .symbolRef(lambdaParam.symbol)))
            driver.ctx.setLocalValue(paramExpr, for: lambdaParam.symbol)

            if paramIndex == contextParameterCount, hasExplicitReceiverParam {
                driver.ctx.setImplicitReceiver(symbol: lambdaParam.symbol, exprID: paramExpr)
            }
        }

        bindCoroutineScopeLambdaReceiver(exprID, sema: sema, arena: arena, interner: interner, instructions: &lambdaBody)
        registerLambdaReceiverValue(lambdaExprID: exprID, hasReceiverParam: functionType?.receiver != nil)

        let effectiveParamNames: [InternedString] = if params.isEmpty, let functionType, !functionType.params.isEmpty {
            [interner.intern("it")]
        } else {
            params
        }
        let valueParamStart = contextParameterCount + (hasExplicitReceiverParam ? 1 : 0)
        for (i, paramName) in effectiveParamNames.enumerated() where valueParamStart + i < lambdaParameters.count {
            driver.ctx.registerLambdaParam(symbol: lambdaParameters[valueParamStart + i].symbol, forName: paramName)
        }

        let contextReceiverValues: [KIRLoweringContext.ContextReceiverValue] = contextParameterTypes
            .enumerated()
            .compactMap { index, type in
                guard lambdaParameters.indices.contains(index),
                      let value = driver.ctx.localValue(for: lambdaParameters[index].symbol)
                else {
                    return nil
                }
                return KIRLoweringContext.ContextReceiverValue(type: type, exprID: value)
            }
        let loweredBody = driver.ctx.withContextReceiverValues(contextReceiverValues) {
            driver.lowerExpr(
                bodyExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &lambdaBody
            )
        }
        if !driver.controlFlowLowerer.isTerminatedExpr(loweredBody, arena: arena, sema: sema) {
            let returnedBody = boxErasedReturnValue(
                loweredBody,
                returnType: substitutedReturnType,
                returnsErasedGeneric: returnsErasedGeneric,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &lambdaBody
            )
            lambdaBody.append(.returnValue(returnedBody))
        }
        lambdaBody.append(.endBlock)

        // See the matching comment in lowerLambdaLiteralExpr: the expected/
        // contextual functionType doesn't always match what the body actually
        // does, so trust the lowered body over a non-suspend contextual type.
        let effectiveIsSuspend = (functionType?.isSuspend ?? false)
            || lambdaBodyRequiresSuspend(lambdaBody, arena: arena, interner: interner)
        let hasNonLocalReturn = lambdaBody.contains { instruction in
            if case .nonLocalReturn = instruction { return true }
            return false
        }
        let hasNonLocalLoopJump = KIRExternalLoopJump.containsExternalJump(in: lambdaBody)
            || sema.bindings.loopJumpLambdaPaths.values.contains { $0.contains(exprID) }

        let lambdaDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: lambdaSymbol,
                    name: lambdaName,
                    params: lambdaParameters,
                    returnType: lambdaReturnType,
                    body: lambdaBody,
                    isSuspend: effectiveIsSuspend,
                    isInline: !effectiveIsSuspend || hasNonLocalReturn || hasNonLocalLoopJump,
                    isInlineOnly: hasNonLocalReturn || hasNonLocalLoopJump
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(lambdaDecl)

        if isSamConversion,
           let boundType,
           case let .classType(interfaceType) = sema.types.kind(of: boundType),
           let samValue = lowerSamWrapperValue(
               exprID,
               interfaceType: interfaceType,
               lambdaSymbol: lambdaSymbol,
               lambdaName: lambdaName,
               lambdaReturnType: lambdaReturnType,
               captureBindings: [],
               samMethodReceiverType: functionType?.receiver,
               samMethodParamTypes: functionType?.params ?? lambdaParameterTypes,
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            return samValue
        }

        let lambdaValueType = effectiveFuncTypeID
            ?? boundType
            ?? sema.types.make(
                .functionType(
                    FunctionType(
                        params: lambdaParameterTypes,
                        returnType: lambdaReturnType,
                        isSuspend: effectiveIsSuspend,
                        nullability: .nonNull
                    )
                )
            )
        let lambdaValueExpr = arena.appendExpr(.symbolRef(lambdaSymbol), type: lambdaValueType)
        instructions.append(.constValue(result: lambdaValueExpr, value: .symbolRef(lambdaSymbol)))
        emitLambdaEnclosingClassMetadata(
            exprID: exprID,
            value: lambdaValueExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        if !hasNonLocalReturn {
            emitFunctionDescription(
                value: lambdaValueExpr,
                description: "kotlin.Function\(lambdaParameterTypes.count)",
                identity: true,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
        }

        driver.ctx.registerCallableValue(
            lambdaValueExpr,
            symbol: lambdaSymbol,
            callee: lambdaName,
            captureArguments: [],
            hasClosureParam: false
        )

        // The body of a lambda taking a `Double`/`Float` reads that parameter as raw
        // bits, while a consumer that only sees a type-parameter function type
        // (`(T) -> R`) passes a boxed handle. A direct argument is wrapped where the
        // lambda is known, but a value that leaves through a factory return, a
        // property, a field or `id(f)` reaches that consumer unwrapped, so build the
        // box-tolerant function value where the lambda is created, as for a
        // capturing lambda.
        if !hasNonLocalReturn,
           !allowsNonLocalReturn,
           !isSamConversion,
           !sema.bindings.isCoroutineLauncherLambdaExpr(exprID),
           !sema.bindings.rawSuspendEntryLambdaExprIDs.contains(exprID),
           lambdaParameterTypes.contains(where: { isFloatingPointValueType($0, sema: sema) }),
           let functionType
        {
            let functionValueType = sema.bindings.functionValueExpectedType(for: exprID)
                .flatMap { typeID -> FunctionType? in
                    guard case let .functionType(expectedType) = sema.types.kind(of: typeID) else {
                        return nil
                    }
                    return expectedType
                } ?? functionType
            if let materialized = materializeEscapingCallableValue(
                exprID: exprID,
                lambdaSymbol: lambdaSymbol,
                lambdaName: lambdaName,
                lambdaReturnType: lambdaReturnType,
                functionType: functionValueType,
                captureArguments: [],
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            ) {
                return materialized
            }
        }

        if !hasNonLocalReturn, let functionType {
            emitFunctionValueTypeTag(
                lambdaValueExpr, functionType: functionType, sema: sema,
                arena: arena, interner: interner, instructions: &instructions
            )
        }
        return lambdaValueExpr
    }
}
