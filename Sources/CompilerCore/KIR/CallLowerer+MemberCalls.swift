
/// Main member-call dispatcher.
///
/// Specialized lowering families live in adjacent `CallLowerer+*MemberCall*.swift` files.
extension CallLowerer {
    // KSP-496: simpleName/qualifiedName/isInstance/cast/safeCast/the boolean
    // flags/visibility/annotations/members/constructors/primaryConstructor/
    // memberProperties/declaredMemberProperties/functions/memberFunctions/
    // declaredMemberFunctions/nestedClasses/supertypes moved to ordinary
    // Kotlin extension declarations (Sources/CompilerCore/Stdlib/kotlin/reflect/).
    //
    // The remaining names stay here:
    // - findAnnotation/findAssociatedObject take a reified type argument,
    //   which this compiler only supports via a small special-cased
    //   allowlist (like typeOf<T>()).
    // - properties is not a real kotlin-stdlib name (only the `member`/
    //   `declaredMember`-prefixed variants exist upstream); diff cases rely
    //   on freely shadowing it with a real user-declared extension.
    private static let kclassMembers: Set<String> = [
        "findAnnotation", "findAssociatedObject", "properties",
    ]

    func lowerMemberCallExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        driver: KIRLoweringDriver,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let propertyConstantInitializers = shared.propertyConstantInitializers

        if let lateinitStatus = tryLowerLateinitIsInitialized(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions.instructions
        ) {
            return lateinitStatus
        }

        // ── KCallable metadata → shared reflection bridge ─────────────────
        if let kPropertyResult = tryLowerKPropertyMemberAccess(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions.instructions
        ) {
            return kPropertyResult
        }

        // ── KFunction<*>.name/returnType/parameters/... → kk_kfunction_get_*(receiver) ──
        if let kFunctionResult = tryLowerKFunctionMemberAccess(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions.instructions
        ) {
            return kFunctionResult
        }

        // ── KParameter.index/name/type/isOptional/kind → kk_kparameter_*(receiver) ──
        if let kParameterResult = tryLowerKParameterMemberAccess(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions.instructions
        ) {
            return kParameterResult
        }

        // ── KFunction<*>.call(...) → kk_kfunction_call_N(receiver, args...) ──
        if let kFunctionCallResult = tryLowerKFunctionCallInvocation(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions.instructions
        ) {
            return kFunctionCallResult
        }

        // ── Int/Long/.../Double.compareTo(other) → kk_primitive_compareTo(...) ──
        if let primitiveCompareResult = tryLowerPrimitiveCompareTo(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions.instructions
        ) {
            return primitiveCompareResult
        }

        // ── Number.toDouble/toFloat/toLong/toInt/toShort/toByte() on an erased
        //    receiver → kk_number_to_primitive(receiver, slot, kind) (KSP-1540) ──
        if let numberConversionResult = tryLowerNumberConversion(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: calleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions.instructions
        ) {
            return numberConversionResult
        }

        let callee = interner.resolve(calleeName)
        let isFlowReceiver = if sema.bindings.isFlowExpr(receiverExpr) {
            true
        } else if sema.bindings.flowElementType(forExpr: receiverExpr) != nil {
            true
        } else if case .nameRef = ast.arena.expr(receiverExpr),
                  let receiverSymbol = sema.bindings.identifierSymbol(for: receiverExpr),
                  sema.bindings.flowElementType(forSymbol: receiverSymbol) != nil
        {
            true
        } else {
            false
        }
        // KSP-499 Stage 3: skip this hard-coded Flow intrinsic dispatch when a
        // real bundled/user Kotlin declaration exists for this exact (Flow
        // owner, member name, arity) — mirrors the same priority check added
        // to the Sema layer (CallTypeChecker+MemberCallInferenceCollectionFlow.swift).
        // Without this, Sema could resolve the call to a genuine Kotlin
        // implementation while KIR lowering still silently rewrote it to the
        // native intrinsic below.
        let hasBundledFlowDeclaration: Bool = {
            guard let receiverType = sema.bindings.exprTypes[receiverExpr],
                  case let .classType(classType) = sema.types.kind(of: receiverType),
                  let ownerSymbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return false
            }
            return sema.bundledIndex.contains(
                ownerFQName: ownerSymbol.fqName,
                name: calleeName,
                arity: args.count
            )
        }()
        if isFlowReceiver, !hasBundledFlowDeclaration {
            if callee == "transform", args.count == 1 {
                let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
                let result = arena.appendTemporary(type: boundType
                )
                let loweredReceiver = driver.lowerExpr(
                    receiverExpr,
                    shared: shared,
                    emit: &instructions
                )
                let loweredLambda = driver.lowerExpr(
                    args[0].expr,
                    shared: shared,
                    emit: &instructions
                )
                // RuntimeFlowTag.transform = 11
                let transformTag: Int64 = 11
                let tagExpr = arena.appendExpr(.intLiteral(transformTag), type: sema.types.intType)
                instructions.append(.constValue(result: tagExpr, value: .intLiteral(transformTag)))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_flow_emit"),
                    arguments: [loweredReceiver, loweredLambda, tagExpr],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ))
                return result
            }
            if callee == "single", args.isEmpty {
                let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
                let result = arena.appendTemporary(type: boundType
                )
                let loweredReceiver = driver.lowerExpr(
                    receiverExpr,
                    shared: shared,
                    emit: &instructions
                )
                let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
                instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("__kk_flow_single"),
                    arguments: [loweredReceiver, zeroExpr],
                    result: result,
                    canThrow: true,
                    thrownResult: nil
                ))
                return result
            }
        }

        // `CoroutineContext.cancel()` is a context-wide cancellation entrypoint
        // and must lower directly to the dedicated runtime ABI.
        if callee == "cancel",
           let receiverType = sema.bindings.exprTypes[receiverExpr],
           isCoroutineContextReceiverType(receiverType, sema: sema, interner: interner)
        {
            let receiverID = driver.lowerExpr(
                receiverExpr,
                shared: shared,
                emit: &instructions
            )
            let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.unitType
            let result = arena.appendTemporary(type: resultType
            )
            let loweredArgs: [KIRExprID]
            switch args.count {
            case 0:
                loweredArgs = []
            case 1:
                loweredArgs = [
                    driver.lowerExpr(
                        args[0].expr,
                        shared: shared,
                        emit: &instructions
                    ),
                ]
            default:
                loweredArgs = []
            }
            let runtimeCallee = interner.intern(args.isEmpty ? "kk_context_cancel_no_cause" : "kk_context_cancel")
            instructions.append(.call(
                symbol: nil,
                callee: runtimeCallee,
                arguments: [receiverID] + loweredArgs,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        // ── T::class.findAnnotation<A>() / T::class.findAssociatedObject<A>() ──
        // KSP-496: simpleName/qualifiedName/isInstance/cast/safeCast/the
        // boolean flags now resolve as ordinary Kotlin extension declarations
        // (Sources/CompilerCore/Stdlib/kotlin/reflect/) through the normal
        // member-call path below this block. Only
        // findAnnotation/findAssociatedObject remain special-cased here — see
        // CallLowerer.kclassMembers for why.
        if case let .callableRef(_, refMember, _) = ast.arena.expr(receiverExpr),
           refMember == KnownCompilerNames(interner: interner).className,
           let classRefTargetType = sema.bindings.classRefTargetType(for: receiverExpr)
        {
            let callee = interner.resolve(calleeName)
            if CallLowerer.kclassMembers.contains(callee) {
                return lowerKClassReflectMemberCall(
                    exprID,
                    classRefTargetType: classRefTargetType,
                    memberName: callee,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions.instructions
                )
            }
        }

        // KSP-496: KClass-typed variable receiver — findAnnotation/findAssociatedObject only (see note above).
        if let receiverType = sema.bindings.exprTypes[receiverExpr],
           isKClassReceiverType(receiverType, sema: sema, interner: interner)
        {
            let callee = interner.resolve(calleeName)
            if CallLowerer.kclassMembers.contains(callee) {
                return lowerKClassVarReflectMemberCall(
                    exprID,
                    receiverExpr: receiverExpr,
                    memberName: callee,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions.instructions
                )
            }
        }

        // --- Scope functions: run, apply, use, usePinned, useContents (STDLIB-004) ---
        if let scopeResult = tryScopeFunctionLowering(
            exprID,
            receiverExpr: receiverExpr,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions.instructions
        ) {
            return scopeResult
        }

        // Receiver-lambda invocation: `receiver.localVar()` where localVar has
        // a function-with-receiver type (e.g. `sb.action()` with action: StringBuilder.() -> Unit).
        // Some frontends may also encode the receiver as the first parameter of a regular
        // function type (`(StringBuilder) -> Unit`), so we mirror the type-checker
        // fallback here when needed.
        if let callableBinding = sema.bindings.callableValueCalls[exprID],
           case let .functionType(fnType) = sema.types.kind(of: callableBinding.functionType),
           case let .localValue(localSym) = callableBinding.target,
           let receiverExprType = sema.bindings.exprType(for: receiverExpr) {
            // Member-property callable invocation: `receiver.prop(args)` where
            // `prop` is a function-typed member property (KUU-482/BUG-250).
            // The property symbol is not a local value, so the local-value arm
            // below cannot resolve it — read `receiver.prop` through the
            // ordinary member-read path, then invoke the function value
            // through the runtime kk_function_invoke* ABI.
            if sema.symbols.symbol(localSym)?.kind == .property,
               let invokeCallee = runtimeCallableInvokeCallee(
                   callableValueCallBinding: callableBinding,
                   sema: sema,
                   interner: interner
               )
            {
                let loweredReceiverID = driver.lowerExpr(
                    receiverExpr,
                    shared: shared,
                    emit: &instructions
                )
                if let functionValue = lowerStoredMemberPropertyReadValue(
                    propertySymbol: localSym,
                    receiverExpr: receiverExpr,
                    loweredReceiverID: loweredReceiverID,
                    resultType: callableBinding.functionType,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions.instructions
                ) {
                    let loweredArgIDs = args.map { argument in
                        driver.lowerExpr(argument.expr, shared: shared, emit: &instructions)
                    }
                    var invokeArgs = normalizedCallableValueArguments(
                        providedArguments: loweredArgIDs,
                        callableValueCallBinding: callableBinding,
                        sema: sema
                    )
                    if fnType.receiver != nil {
                        // `val action: R.() -> T` invoked as `receiver.action(args)`:
                        // the call-site receiver is the lambda's dispatch receiver,
                        // passed right after the function value (mirroring the
                        // local-value arm below).
                        invokeArgs.insert(loweredReceiverID, at: 0)
                    }
                    let boundType = sema.bindings.exprTypes[exprID] ?? fnType.returnType
                    let result = arena.appendTemporary(type: boundType)
                    instructions.append(.call(
                        symbol: localSym,
                        callee: invokeCallee,
                        arguments: [functionValue] + invokeArgs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    return result
                }
            }
            let maybeReceiverFnType: (FunctionType, Bool)
            if fnType.receiver != nil {
                maybeReceiverFnType = (fnType, fnType.params.count == args.count)
            } else if !fnType.params.isEmpty && args.count == fnType.params.count - 1 {
                let syntheticReceiverType = fnType.params[0]
                let syntheticFunction = FunctionType(
                    receiver: syntheticReceiverType,
                    params: Array(fnType.params.dropFirst()),
                    returnType: fnType.returnType,
                    isSuspend: fnType.isSuspend,
                    nullability: fnType.nullability
                )
                maybeReceiverFnType = (syntheticFunction, true)
            } else {
                maybeReceiverFnType = (FunctionType(
                    params: fnType.params,
                    returnType: fnType.returnType,
                    isSuspend: fnType.isSuspend,
                    nullability: fnType.nullability
                ), false)
            }
            if maybeReceiverFnType.1,
               let receiverType = maybeReceiverFnType.0.receiver,
               sema.types.isSubtype(
                   sema.types.makeNonNullable(receiverExprType),
                   receiverType
               )
            {
                let effectiveFnType = maybeReceiverFnType.0
                let boundType = sema.bindings.exprTypes[exprID] ?? effectiveFnType.returnType
                let loweredReceiver = driver.lowerExpr(receiverExpr, shared: shared, emit: &instructions)
                let loweredArgIDs = args.map { argument in
                    driver.lowerExpr(argument.expr, shared: shared, emit: &instructions)
                }
                let result = arena.appendTemporary(type: boundType)
                if let localExprID = driver.ctx.localValue(for: localSym),
                   let info = driver.ctx.callableValueInfo(for: localExprID)
                {
                    var allArgs = info.captureArguments
                    allArgs.append(loweredReceiver)
                    allArgs.append(contentsOf: loweredArgIDs)
                    instructions.append(.call(
                        symbol: info.symbol,
                        callee: info.callee,
                        arguments: allArgs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else if let localExprID = driver.ctx.localValue(for: localSym),
                          let invokeCallee = runtimeCallableInvokeCallee(
                              callableValueCallBinding: callableBinding,
                              sema: sema,
                              interner: interner
                          )
                {
                    let allArgs = [localExprID, loweredReceiver] + loweredArgIDs
                    instructions.append(.call(
                        symbol: localSym,
                        callee: invokeCallee,
                        arguments: allArgs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else {
                    let allArgs = [loweredReceiver] + loweredArgIDs
                    instructions.append(.call(
                        symbol: localSym,
                        callee: calleeName,
                        arguments: allArgs,
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                return result
            }
        }

        // Explicit `invoke` sugar on a function-typed value:
        // `f.invoke(args)` / `prop.invoke(args)` (KUU-644). Sema binds a
        // CallableValueCallBinding with `target == nil`, so the lowered
        // receiver expression itself is the function object to invoke.
        if let callableBinding = sema.bindings.callableValueCalls[exprID],
           callableBinding.target == nil,
           case .functionType = sema.types.kind(of: callableBinding.functionType),
           let invokeCallee = runtimeCallableInvokeCallee(
               callableValueCallBinding: callableBinding,
               sema: sema,
               interner: interner
           )
        {
            let functionValue = driver.lowerExpr(receiverExpr, shared: shared, emit: &instructions)
            let loweredArgIDs = args.map { argument in
                driver.lowerExpr(argument.expr, shared: shared, emit: &instructions)
            }
            let invokeArgs = normalizedCallableValueArguments(
                providedArguments: loweredArgIDs,
                callableValueCallBinding: callableBinding,
                sema: sema
            )
            let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
            let result = arena.appendTemporary(type: boundType)
            instructions.append(.call(
                symbol: nil,
                callee: invokeCallee,
                arguments: [functionValue] + invokeArgs,
                result: result,
                canThrow: false,
                thrownResult: nil
            ))
            return result
        }

        let effectiveCalleeName = if sema.bindings.isInvokeOperatorCall(exprID) {
            KnownCompilerNames(interner: interner).invoke
        } else {
            calleeName
        }
        if let typeQualifiedConstructorResult = tryLowerTypeQualifiedConstructorCall(
            exprID,
            calleeName: effectiveCalleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions.instructions
        ) { return typeQualifiedConstructorResult }
        if let objProp = tryLowerObjectMemberPropertyRead(
            exprID, receiverExpr: receiverExpr, args: args, ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions.instructions
        ) { return objProp }
        if let fqnQualifiedValue = tryLowerFQNQualifiedValue(
            exprID,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions.instructions
        ) { return fqnQualifiedValue }
        if let fqnTopLevelResult = tryLowerFQNTopLevelResolvedCall(
            exprID,
            calleeName: effectiveCalleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions.instructions
        ) { return fqnTopLevelResult }
        return lowerMemberLikeCallExpr(
            exprID,
            receiverExpr: receiverExpr,
            calleeName: effectiveCalleeName,
            args: args,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            requireNonNullableReceiverForConstFold: false,
            prependReceiverForUnresolvedCollectionCall: true,
            instructions: &instructions.instructions
        )
    }

}
