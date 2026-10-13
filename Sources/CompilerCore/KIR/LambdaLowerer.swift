struct KIRCallableValueInfo {
    let symbol: SymbolID
    let callee: InternedString
    let captureArguments: [KIRExprID]
    /// True when lambda has closure param for C HOF ABI (filter, map, etc.).
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
        if isRawCallbackParameter, isNonNullableStringStruct(rawKind) {
            return exprID
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

    private func isNonNullableStringStruct(_ kind: TypeKind) -> Bool {
        guard case let .stringStruct(nullability) = kind else {
            return false
        }
        return nullability == .nonNull
    }

    /// Best-effort scan for whether a lowered lambda body performs a call that
    /// requires a suspend context (`.await()`/`.join()`/`delay`/`yield`/a generic
    /// suspend-function-invoke/a Flow operation, or a call to another
    /// already-lowered suspend function). Used to correct a lambda literal's
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

        // Enhanced receiver parameter handling for lambda with receiver types
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
            // For receiver lambdas (e.g., StringBuilder.() -> Unit), the receiver
            // is implicitly passed as the first parameter, but only if there's no
            // active implicit receiver in the current scope
            return baseCount + (needsExplicitReceiver ? 1 : 0)
        }()

        let lambdaParameterTypes: [TypeID] = {
            var types: [TypeID] = []
            // Add receiver parameter first if needed
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
            lambdaParamCount: effectiveParamCount,
            lambdaBodyExprID: bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            receiverType: functionType?.receiver ?? sema.bindings.coroutineScopeLambdaReceiverTypes[exprID]
        )

        // Non-capturing lambda optimization: if no captures, use function pointer directly
        let isNonCapturingLambda = captureSymbols.isEmpty && !needsClosureParam
        if isNonCapturingLambda {
            return lowerNonCapturingLambda(
                exprID: exprID,
                params: params,
                bodyExpr: bodyExpr,
                allowsNonLocalReturn: allowsNonLocalReturn,
                effectiveParamCount: effectiveParamCount,
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
        // Runtime expects (closureRaw, ...valueParams, outThrown). Add closure param as first param.
        let lambdaParameters: [KIRParameter]
        if needsClosureParam {
            let closureParamType = captureBindings.count == 1
                ? captureBindings[0].param.type
                : sema.types.intType
            let closureParam = KIRParameter(
                symbol: syntheticLambdaClosureParamSymbol(lambdaExprID: exprID),
                type: closureParamType
            )
            let valueParams = (0 ..< effectiveParamCount).map { index in
                KIRParameter(
                    symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                    type: lambdaParameterTypes[index]
                )
            }
            lambdaParameters = [closureParam] + valueParams
        } else {
            lambdaParameters = (0 ..< effectiveParamCount).map { index in
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
        driver.ctx.nonLocalReturnTarget = scopeSnapshot.nonLocalReturnTarget ?? scopeSnapshot.currentFunctionSymbol

        var lambdaBody: [KIRInstruction] = [.beginBlock]
        for capture in functionCaptureBindings {
            let captureExpr = arena.appendExpr(.symbolRef(capture.param.symbol), type: capture.param.type)
            lambdaBody.append(.constValue(result: captureExpr, value: .symbolRef(capture.param.symbol)))
            bindCapturedLambdaValue(captureExpr, capture: capture, sema: sema)
            if capture.capturedSymbol == savedReceiverSymbol {
                driver.ctx.setImplicitReceiver(symbol: capture.param.symbol, exprID: captureExpr)
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
            let receiverParamIndex = needsClosureParam ? 1 : 0
            if needsExplicitReceiver, paramIndex == receiverParamIndex {
                driver.ctx.setImplicitReceiver(symbol: lambdaParam.symbol, exprID: normalizedParamExpr)
            }
        }
        if usesClosureRawCapture,
           let closureCapture = captureBindings.first,
           let closureParam = lambdaParameters.first,
           let closureExpr = driver.ctx.localValue(for: closureParam.symbol)
        {
            bindCapturedLambdaValue(closureExpr, capture: closureCapture, sema: sema)
            if closureCapture.capturedSymbol == savedReceiverSymbol {
                driver.ctx.setImplicitReceiver(symbol: closureParam.symbol, exprID: closureExpr)
                driver.ctx.setLocalDeclaredType(closureCapture.declaredType, for: closureParam.symbol)
                bindCapturedOuterLambdaReceiver(closureExpr, type: closureCapture.param.type, sema: sema, overwriteExisting: false)
                if capturesRuntimeScopeReceiver {
                    driver.ctx.runtimeCoroutineScopeReceiverExprIDs.insert(closureExpr)
                }
            }
        }
        // Multi-capture HOF lambda: closureRaw is a packed closure object.
        // Load each capture from the object via kk_array_get_inbounds.
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
                lambdaBody.append(.call(
                    symbol: nil,
                    callee: kkArrayGet,
                    arguments: [closureObjExpr, offsetExpr],
                    result: loadedExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                bindCapturedLambdaValue(loadedExpr, capture: capture, sema: sema)
                if capture.capturedSymbol == savedReceiverSymbol {
                    driver.ctx.setImplicitReceiver(symbol: capture.param.symbol, exprID: loadedExpr)
                    driver.ctx.setLocalDeclaredType(capture.declaredType, for: capture.param.symbol)
                    bindCapturedOuterLambdaReceiver(loadedExpr, type: capture.param.type, sema: sema, overwriteExisting: false)
                    if capturesRuntimeScopeReceiver {
                        driver.ctx.runtimeCoroutineScopeReceiverExprIDs.insert(loadedExpr)
                    }
                }
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
        // Value parameters start after the closure environment parameter (HOF
        // lambdas) and after the explicit receiver parameter (receiver lambdas
        // such as `DeepRecursiveScope<T, R>.(T) -> R`); without the receiver
        // offset a named parameter would alias the receiver slot.
        let valueParamStart = (needsClosureParam ? 1 : 0) + (needsExplicitReceiver ? 1 : 0)
        for (i, paramName) in effectiveParamNames.enumerated() where valueParamStart + i < lambdaParameters.count {
            driver.ctx.registerLambdaParam(symbol: lambdaParameters[valueParamStart + i].symbol, forName: paramName)
        }

        let loweredBody = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &lambdaBody
        )
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
                    isInlineOnly: hasNonLocalReturn
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
               samMethodParamTypes: lambdaParameterTypes,
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
            if let materialized = materializeEscapingCallableValue(
                exprID: exprID,
                lambdaSymbol: lambdaSymbol,
                lambdaName: syntheticLambdaName(for: exprID, interner: interner),
                lambdaReturnType: lambdaReturnType,
                functionType: functionType,
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
                emitRawFunctionArityTag(
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
    /// bindings, including delegate storage -- see `ScopeSnapshot`), keyed
    /// off the *kind* of thing `capturedValue` holds:
    /// - a mutable local's captured value is a box cell (`setMutableCaptureCell`)
    /// - a delegated local's (KSP-491: `val x by lazy { ... }`/`by Prop()`)
    ///   captured value is the delegate *instance*, not a value
    ///   (`setLocalDelegateStorage`) -- reads inside the lambda body must
    ///   still call getValue fresh, exactly like reads in the declaring
    ///   scope (see `ExprLowerer.readLocalDelegateValue`), or a vetoable/
    ///   observable delegate's writes wouldn't be observed from inside the
    ///   lambda
    /// - anything else is a plain captured value (`setLocalValue`)
    private func bindCapturedLambdaValue(
        _ capturedValue: KIRExprID,
        capture: (capturedSymbol: SymbolID, param: KIRParameter, valueExpr: KIRExprID, declaredType: TypeID),
        sema: SemaModule
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
        if sema.symbols.symbol(capture.capturedSymbol)?.kind == .class {
            bindCapturedOuterLambdaReceiver(capturedValue, type: capture.param.type, sema: sema)
        }
        if let semanticSymbol = sema.symbols.symbol(capture.capturedSymbol),
           semanticSymbol.kind == .typeParameter,
           semanticSymbol.flags.contains(.reifiedTypeParameter)
        {
            let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: capture.capturedSymbol)
            driver.ctx.setLocalValue(capturedValue, for: tokenSymbol)
            driver.ctx.setLocalDeclaredType(sema.types.intType, for: tokenSymbol)
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

    // MARK: - Non-Capturing Lambda Optimization

    /// Lowers a non-capturing lambda with optimized function pointer generation
    private func lowerNonCapturingLambda(
        exprID: ExprID,
        params: [InternedString],
        bodyExpr: ExprID,
        allowsNonLocalReturn: Bool,
        effectiveParamCount: Int,
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

        // Create optimized lambda parameters (no capture parameters needed)
        let lambdaParameters = (0 ..< effectiveParamCount).map { index in
            KIRParameter(
                symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                type: lambdaParameterTypes[index]
            )
        }

        // Generate optimized lambda body
        let scopeSnapshot = driver.ctx.saveScope()
        defer { driver.ctx.restoreScope(scopeSnapshot) }
        driver.ctx.resetScopeForFunction()
        driver.ctx.currentLambdaAllowsNonLocalReturn = allowsNonLocalReturn
        driver.ctx.nonLocalReturnTarget = scopeSnapshot.nonLocalReturnTarget ?? scopeSnapshot.currentFunctionSymbol

        var lambdaBody: [KIRInstruction] = [.beginBlock]

        // Set up parameters only (no captures)
        for (paramIndex, lambdaParam) in lambdaParameters.enumerated() {
            let paramExpr = arena.appendExpr(.symbolRef(lambdaParam.symbol), type: lambdaParam.type)
            lambdaBody.append(.constValue(result: paramExpr, value: .symbolRef(lambdaParam.symbol)))
            driver.ctx.setLocalValue(paramExpr, for: lambdaParam.symbol)

            // Handle receiver parameter if needed
            if paramIndex == 0, hasExplicitReceiverParam {
                driver.ctx.setImplicitReceiver(symbol: lambdaParam.symbol, exprID: paramExpr)
            }
        }

        bindCoroutineScopeLambdaReceiver(exprID, sema: sema, arena: arena, interner: interner, instructions: &lambdaBody)
        registerLambdaReceiverValue(lambdaExprID: exprID, hasReceiverParam: functionType?.receiver != nil)

        // Set up parameter name mapping for `it` parameter
        let effectiveParamNames: [InternedString] = if params.isEmpty, let functionType, !functionType.params.isEmpty {
            [interner.intern("it")]
        } else {
            params
        }
        // Named parameters follow the explicit receiver parameter, if any.
        let valueParamStart = hasExplicitReceiverParam ? 1 : 0
        for (i, paramName) in effectiveParamNames.enumerated() where valueParamStart + i < lambdaParameters.count {
            driver.ctx.registerLambdaParam(symbol: lambdaParameters[valueParamStart + i].symbol, forName: paramName)
        }

        // Lower the body
        let loweredBody = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &lambdaBody
        )
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

        // Create optimized function declaration
        let lambdaDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: lambdaSymbol,
                    name: lambdaName,
                    params: lambdaParameters, // No capture parameters
                    returnType: lambdaReturnType,
                    body: lambdaBody,
                    isSuspend: effectiveIsSuspend,
                    isInline: true, // Mark as inline for better optimization
                    isInlineOnly: hasNonLocalReturn
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(lambdaDecl)

        // Handle SAM conversion if needed
        if isSamConversion,
           let boundType,
           case let .classType(interfaceType) = sema.types.kind(of: boundType),
           let samValue = lowerSamWrapperValue(
               exprID,
               interfaceType: interfaceType,
               lambdaSymbol: lambdaSymbol,
               lambdaName: lambdaName,
               lambdaReturnType: lambdaReturnType,
               captureBindings: [], // No captures for non-capturing lambda
               samMethodParamTypes: lambdaParameterTypes,
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            return samValue
        }

        // Create optimized lambda value
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

        if !hasNonLocalReturn {
            emitFunctionDescription(
                value: lambdaValueExpr,
                description: "kotlin.Function\(lambdaParameterTypes.count)",
                identity: true,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
        }

        // Register with no capture arguments for optimization
        driver.ctx.registerCallableValue(
            lambdaValueExpr,
            symbol: lambdaSymbol,
            callee: lambdaName,
            captureArguments: [], // Empty for non-capturing lambda
            hasClosureParam: false
        )

        if !hasNonLocalReturn, let functionType {
            emitRawFunctionArityTag(
                lambdaValueExpr, functionType: functionType, sema: sema,
                arena: arena, interner: interner, instructions: &instructions
            )
        }
        return lambdaValueExpr
    }
}
