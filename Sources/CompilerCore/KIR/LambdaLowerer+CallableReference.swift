extension LambdaLowerer {
    private func lowerCallableReferenceAdapter(
        _ exprID: ExprID,
        targetSymbol: SymbolID,
        targetName: InternedString?,
        binding: CallBinding,
        isUnbound: Bool,
        captureArguments: [KIRExprID],
        localCaptureCount: Int,
        needsHOFWrapper: Bool,
        memberName: InternedString,
        functionType: FunctionType,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> (symbol: SymbolID, name: InternedString) {
        let callableSymbol = driver.ctx.syntheticLambdaSymbol(for: exprID)
        let callableName = syntheticLambdaName(for: exprID, interner: interner)
        let inputTypes = (functionType.receiver.map { [$0] } ?? []) + functionType.params
        let closureParam = needsHOFWrapper ? KIRParameter(
            symbol: syntheticLambdaClosureParamSymbol(lambdaExprID: exprID),
            type: sema.types.intType
        ) : nil
        let captureParams: [KIRParameter] = captureArguments.enumerated().map { index, capture in
            KIRParameter(
                symbol: syntheticLambdaCaptureParamSymbol(lambdaExprID: exprID, captureIndex: index),
                type: arena.exprType(capture) ?? sema.types.anyType
            )
        }
        let valueParams = inputTypes.enumerated().map { index, type in
            KIRParameter(
                symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                type: type
            )
        }
        let wrapperParams = (closureParam.map { [$0] } ?? captureParams) + valueParams
        var body: [KIRInstruction] = [.beginBlock]
        let captureRefs: [KIRExprID]
        if needsHOFWrapper, let closureParam {
            let closureRef = arena.appendExpr(.symbolRef(closureParam.symbol), type: closureParam.type)
            body.append(.constValue(result: closureRef, value: .symbolRef(closureParam.symbol)))
            captureRefs = driver.callLowerer.appendCallableCaptureLoads(
                callableInfo: KIRCallableValueInfo(
                    symbol: callableSymbol,
                    callee: callableName,
                    captureArguments: captureArguments,
                    hasClosureParam: false
                ),
                closureExpr: closureRef,
                sema: sema,
                arena: arena,
                interner: interner,
                body: &body
            )
        } else {
            captureRefs = captureParams.map { parameter -> KIRExprID in
                let reference = arena.appendExpr(.symbolRef(parameter.symbol), type: parameter.type)
                body.append(.constValue(result: reference, value: .symbolRef(parameter.symbol)))
                return reference
            }
        }
        let valueRefs = valueParams.map { parameter -> KIRExprID in
            let reference = arena.appendExpr(.symbolRef(parameter.symbol), type: parameter.type)
            body.append(.constValue(result: reference, value: .symbolRef(parameter.symbol)))
            return reference
        }

        let signature = sema.symbols.functionSignature(for: targetSymbol)
        let hasCallableReceiver = signature?.receiverType != nil
        let receiverInputCount = isUnbound && hasCallableReceiver ? 1 : 0
        let receiverOverride: KIRExprID? = if receiverInputCount == 1 {
            valueRefs.first
        } else if hasCallableReceiver && !isUnbound && captureRefs.indices.contains(localCaptureCount) {
            captureRefs[localCaptureCount]
        } else {
            nil
        }
        let isInnerConstructor = sema.symbols.symbol(targetSymbol)?.kind == .constructor
            && sema.symbols.parentSymbol(for: targetSymbol)
                .flatMap { sema.symbols.symbol($0) }?.flags.contains(.innerClass) == true
        let constructorOuterReceiver: KIRExprID? = if isInnerConstructor && isUnbound {
            valueRefs.first
        } else if sema.symbols.symbol(targetSymbol)?.kind == .constructor,
                  captureRefs.indices.contains(localCaptureCount)
        {
            captureRefs[localCaptureCount]
        } else {
            nil
        }
        var valueArguments = Array(valueRefs.dropFirst(receiverInputCount))
        let callBinding = binding
        let typeVariables = sema.types.makeTypeVarBySymbol(signature?.typeParameterSymbols ?? [])
        var typeSubstitution: [TypeVarID: TypeID] = [:]
        if let signature {
            for (index, symbol) in signature.typeParameterSymbols.enumerated()
                where index < binding.substitutedTypeArguments.count
            {
                guard let variable = typeVariables[symbol] else { continue }
                typeSubstitution[variable] = binding.substitutedTypeArguments[index]
            }
        }
        if let signature {
            for (argumentIndex, parameterIndex) in callBinding.parameterMapping {
                guard valueArguments.indices.contains(argumentIndex),
                      signature.parameterTypes.indices.contains(parameterIndex),
                      let sourceType = arena.exprType(valueArguments[argumentIndex])
                else {
                    continue
                }
                let parameterType = sema.types.substituteTypeParameters(
                    in: signature.parameterTypes[parameterIndex],
                    substitution: typeSubstitution,
                    typeVarBySymbol: typeVariables
                )
                switch sema.types.kind(of: sema.types.makeNonNullable(parameterType)) {
                case .any, .typeParam:
                    // A contextual function type may pass a primitive (such as
                    // Char from CharArray.fold) to an erased target parameter
                    // (such as String.plus(Any?)). Keep its boxed type identity
                    // across the generated callable-reference adapter.
                    valueArguments[argumentIndex] = boxValueForAnySlot(
                        valueArguments[argumentIndex],
                        sourceType: sourceType,
                        types: sema.types,
                        symbols: sema.symbols,
                        interner: interner,
                        arena: arena,
                        resultType: parameterType,
                        sema: sema,
                        cache: driver.ctx.nominalDispatchCache,
                        into: &body
                    )
                default:
                    continue
                }
            }
        }
        let varargFlags: [Bool] = valueArguments.enumerated().map { argumentIndex, argument in
            guard let parameterIndex = callBinding.parameterMapping[argumentIndex],
                  let signature,
                  signature.valueParameterIsVararg.indices.contains(parameterIndex),
                  signature.valueParameterIsVararg[parameterIndex]
            else {
                return false
            }
            let elementType = sema.types.substituteTypeParameters(
                in: signature.parameterTypes[parameterIndex],
                substitution: typeSubstitution,
                typeVarBySymbol: typeVariables
            )
            let packedType = primitiveVarargArrayType(
                elementType: signature.parameterTypes[parameterIndex], sema: sema, interner: interner
            ) ?? referenceVarargArrayType(
                elementType: elementType, sema: sema, interner: interner
            )
            guard let packedType, let argumentType = arena.exprType(argument) else { return false }
            return sema.types.isSubtype(
                sema.types.makeNonNullable(argumentType), sema.types.makeNonNullable(packedType)
            )
        }
        let callArguments = valueArguments.enumerated().map { index, _ in
            CallArgument(isSpread: varargFlags[index], expr: exprID)
        }
        let declaredReturnType = signature.map {
            sema.types.substituteTypeParameters(
                in: $0.returnType, substitution: typeSubstitution, typeVarBySymbol: typeVariables
            )
        } ?? functionType.returnType
        let callResultType = functionType.returnType == sema.types.unitType
            ? declaredReturnType
            : functionType.returnType
        let contextCaptureStart = max(captureRefs.count - binding.boundContextParameterTypes.count, 0)
        let contextReceiverValues: [KIRLoweringContext.ContextReceiverValue] = binding.boundContextParameterTypes
            .enumerated().compactMap { index, type in
                guard captureRefs.indices.contains(contextCaptureStart + index) else { return nil }
                return KIRLoweringContext.ContextReceiverValue(
                    type: type,
                    exprID: captureRefs[contextCaptureStart + index]
                )
            }
        let callResult = driver.ctx.withContextReceiverValues(contextReceiverValues) {
            driver.callLowerer.lowerResolvedCallBody(
                exprID,
                args: callArguments,
                loweredArgIDs: valueArguments,
                chosen: targetSymbol,
                callBinding: callBinding,
                callableValueCallBinding: nil,
                loweredCallable: nil,
                loweredCalleeExprID: nil,
                sourceCalleeName: memberName,
                boundType: callResultType,
                knownNames: KnownCompilerNames(interner: interner),
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &body,
                sourceArgExprsOverride: [],
                explicitReceiverOverride: receiverOverride,
                outerReceiverOverride: constructorOuterReceiver,
                localFunctionCaptureArguments: Array(captureRefs.prefix(localCaptureCount))
            )
        }
        switch sema.types.kind(of: functionType.returnType) {
        case .unit, .nothing(.nonNull), .nothing(.nullable):
            body.append(.returnUnit)
        default:
            body.append(.returnValue(callResult))
        }
        body.append(.endBlock)
        driver.ctx.appendGeneratedCallableDecl(arena.appendDecl(.function(KIRFunction(
            symbol: callableSymbol,
            name: callableName,
            params: wrapperParams,
            returnType: functionType.returnType,
            body: body,
            isSuspend: functionType.isSuspend,
            isInline: false
        ))))
        return (callableSymbol, callableName)
    }

    /// A thunk with the lambda calling convention `(captures..., params...) -> R`
    /// is generated so the shared SAM wrapper synthesis can delegate to the
    /// referenced callable.
    private func lowerCallableRefSamWrapperValue(
        _ exprID: ExprID,
        targetSymbol: SymbolID,
        targetName: InternedString?,
        captureArguments: [KIRExprID],
        isReifiedThunk: Bool = false,
        identityTargetSymbol: SymbolID? = nil,
        callableType: TypeID? = nil,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard let interfaceTypeID = sema.bindings.samInterfaceType(for: exprID),
              case let .classType(interfaceType) = sema.types.kind(of: interfaceTypeID),
              let samFunctionTypeID = sema.bindings.samUnderlyingFunctionType(for: exprID),
              case let .functionType(samFunctionType) = sema.types.kind(of: samFunctionTypeID)
        else {
            return nil
        }

        let samMethodReceiverType = samFunctionType.receiver
        let samMethodParamTypes = samFunctionType.params
        let samMethodInputTypes = (samMethodReceiverType.map { [$0] } ?? []) + samMethodParamTypes
        let returnType = samFunctionType.returnType

        let thunkName = interner.intern("kk_sam_ref_thunk_\(exprID.rawValue)")
        let thunkSymbol = sema.symbols.define(
            kind: .function,
            name: thunkName,
            fqName: [thunkName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )

        let captureParams: [KIRParameter] = captureArguments.enumerated().map { index, captureExpr in
            KIRParameter(
                symbol: syntheticLambdaCaptureParamSymbol(lambdaExprID: exprID, captureIndex: index),
                type: arena.exprType(captureExpr) ?? sema.types.anyType
            )
        }
        let valueParams: [KIRParameter] = samMethodInputTypes.enumerated().map { index, type in
            KIRParameter(
                symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                type: type
            )
        }

        var body: [KIRInstruction] = [.beginBlock]
        var callArguments: [KIRExprID] = []
        for param in captureParams + valueParams {
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            callArguments.append(paramExpr)
        }
        let callResult = arena.appendTemporary(type: returnType)
        let callee = targetName ?? callableTargetName(for: targetSymbol, sema: sema, interner: interner)
        if !isReifiedThunk, sema.bindings.implicitReceiverMemberNames[exprID] != nil,
           let receiver = callArguments.first,
           let receiverType = captureParams.first?.type,
           let dispatch = driver.callLowerer.resolveVirtualDispatch(
               callee: targetSymbol,
               receiverTypeID: receiverType,
               sema: sema,
               interner: interner
           )
        {
            body.append(.virtualCall(
                symbol: targetSymbol,
                callee: callee,
                receiver: receiver,
                arguments: Array(callArguments.dropFirst()),
                result: callResult,
                canThrow: isReifiedThunk,
                dispatch: dispatch
            ))
        } else {
            body.append(.call(symbol: targetSymbol, callee: callee, arguments: callArguments, result: callResult, canThrow: isReifiedThunk))
        }
        switch sema.types.kind(of: returnType) {
        case .unit, .nothing(.nonNull), .nothing(.nullable):
            body.append(.returnUnit)
        default:
            body.append(.returnValue(callResult))
        }
        body.append(.endBlock)

        let thunkDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: thunkSymbol,
                    name: thunkName,
                    params: captureParams + valueParams,
                    returnType: returnType,
                    body: body,
                    isSuspend: samFunctionType.isSuspend,
                    isInline: false
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(thunkDecl)

        let captureBindings = zip(captureParams, captureArguments).map { param, valueExpr in
            (capturedSymbol: param.symbol, param: param, valueExpr: valueExpr, declaredType: param.type)
        }

        guard let samValue = lowerSamWrapperValue(
            exprID,
            interfaceType: interfaceType,
            lambdaSymbol: thunkSymbol,
            lambdaName: thunkName,
            lambdaReturnType: returnType,
            captureBindings: captureBindings,
            samMethodReceiverType: samMethodReceiverType,
            samMethodParamTypes: samMethodParamTypes,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        ) else {
            return nil
        }
        emitSamAdapterIdentity(
            callableExpr: samValue,
            exprID: exprID,
            interfaceType: interfaceType,
            identityTargetSymbol: identityTargetSymbol,
            captures: captureArguments,
            callableType: callableType,
            samFunctionType: samFunctionType,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        return samValue
    }

    /// JVM `fun interface` SAM wrappers built from callable references also
    /// implement `kotlin.jvm.internal.FunctionAdapter`: their synthesized
    /// equals/hashCode delegate to the stored function reference, and equals
    /// additionally requires `other instanceof <that interface>` (KUU-2940).
    /// Record the referenced target and bound captures on the wrapper so the
    /// erased `==`/`!=` and `hashCode()` runtime paths compare the delegate
    /// rather than wrapper object identity.
    private func emitSamAdapterIdentity(
        callableExpr: KIRExprID,
        exprID: ExprID,
        interfaceType: ClassType,
        identityTargetSymbol: SymbolID?,
        captures: [KIRExprID],
        callableType: TypeID?,
        samFunctionType: FunctionType,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        // Mirror emitCallableRefTypeTag's identity target: a function ref
        // keys on the referenced symbol itself (not the per-site SAM thunk
        // or adapted-reference adapter), a property ref on its getter.
        let targetSymbol: SymbolID? = switch sema.bindings.callableRefKind(for: exprID) {
        case .functionRef:
            identityTargetSymbol
        case .propertyRef:
            identityTargetSymbol.flatMap { target in
                let propertySymbol = sema.symbols.symbol(target)?.kind == .property
                    ? target
                    : sema.symbols.accessorOwnerProperty(for: target)
                return propertySymbol.flatMap {
                    sema.symbols.extensionPropertyGetterAccessor(for: $0)
                        ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: $0)
                }
            }
        case nil:
            nil
        }
        guard let targetSymbol else { return }

        let functionType = callableType.flatMap { type -> FunctionType? in
            guard case let .functionType(functionType) = sema.types.kind(of: type) else { return nil }
            return functionType
        } ?? samFunctionType
        let arity = Int64(functionType.contextReceivers.count
            + (functionType.receiver == nil ? 0 : 1) + functionType.params.count)
        // Same packing as emitCallableRefTypeTag: bit0=suspend, bit1=inline,
        // bit2=operator, bit3=infix, bit4=external.
        var flags: Int64 = functionType.isSuspend ? 1 : 0
        if let target = sema.symbols.symbol(targetSymbol) {
            if target.flags.contains(.inlineFunction) { flags |= 1 << 1 }
            if target.flags.contains(.operatorFunction) { flags |= 1 << 2 }
            if target.flags.contains(.infixFunction) { flags |= 1 << 3 }
            if sema.symbols.externalLinkName(for: targetSymbol) != nil { flags |= 1 << 4 }
        }

        let intType = sema.types.intType
        let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: interfaceType.classSymbol, sema: sema, interner: interner
        )
        let interfaceTypeExpr = arena.appendExpr(.intLiteral(interfaceTypeID), type: intType)
        instructions.append(.constValue(result: interfaceTypeExpr, value: .intLiteral(interfaceTypeID)))
        let identityTarget = arena.appendExpr(.symbolRef(targetSymbol), type: intType)
        instructions.append(.constValue(result: identityTarget, value: .symbolRef(targetSymbol)))
        let boxedCaptures = captures.map { capture in
            boxValueForAnySlot(
                capture,
                sourceType: arena.exprType(capture) ?? sema.types.anyType,
                types: sema.types,
                symbols: sema.symbols,
                interner: interner,
                arena: arena,
                requireNonNull: true,
                sema: sema,
                into: &instructions
            )
        }
        let capturesExpr: KIRExprID
        if boxedCaptures.isEmpty {
            capturesExpr = arena.appendExpr(.null, type: sema.types.nullableAnyType)
            instructions.append(.constValue(result: capturesExpr, value: .null))
        } else {
            capturesExpr = makeReflectionArgumentList(
                boxedCaptures, sema: sema, arena: arena,
                interner: interner, instructions: &instructions
            )
        }
        let arityExpr = arena.appendExpr(.intLiteral(arity), type: intType)
        instructions.append(.constValue(result: arityExpr, value: .intLiteral(arity)))
        let flagsExpr = arena.appendExpr(.intLiteral(flags), type: intType)
        instructions.append(.constValue(result: flagsExpr, value: .intLiteral(flags)))
        instructions.append(.call(
            callee: interner.intern("__kk_sam_adapter_set_identity"),
            arguments: [callableExpr, interfaceTypeExpr, identityTarget, capturesExpr, arityExpr, flagsExpr],
            result: nil,
            canThrow: false
        ))
    }

    func lowerCallableRefExpr(
        _ exprID: ExprID,
        receiverExpr: ExprID?,
        memberName: InternedString,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]

        if !sema.bindings.isSamConversion(exprID),
           let interfaceSymbol = sema.bindings.identifierSymbol(for: exprID),
           let interface = sema.symbols.symbol(interfaceSymbol),
           interface.kind == .interface,
           interface.flags.contains(.funInterface),
           let interfaceType = sema.bindings.samInterfaceType(for: exprID),
           let samFunctionTypeID = sema.bindings.samUnderlyingFunctionType(for: exprID),
           case let .functionType(samFunctionType) = sema.types.kind(of: samFunctionTypeID),
           let callable = lowerFunInterfaceConstructorCallableReference(
               exprID,
               memberName: memberName,
               interfaceSymbol: interfaceSymbol,
               interfaceType: interfaceType,
               samFunctionType: samFunctionType,
               boundType: boundType,
               ast: ast,
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            return callable
        }

        // REFL-PRIMOP: `Boolean::not` has no backing member symbol or receiver
        // value, so synthesize its intrinsic unary wrapper before symbol lookup.
        if let unaryOp = sema.bindings.primitiveUnaryOperatorCallableRef(for: exprID) {
            return lowerPrimitiveUnaryOperatorCallableRef(
                exprID,
                op: unaryOp,
                memberName: memberName,
                boundType: boundType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }

        // REFL-PRIMOP: `Int::plus`/`Int::times` (see Sema's
        // `bindPrimitiveOperatorCallableRef`) have no backing symbol and no
        // real receiver *value* (the receiver names a primitive type, not an
        // instance) -- skip straight past `resolveCallableRefTargetSymbol`
        // and the receiver-lowering/capture logic below, neither of which
        // applies here.
        if let primitiveOp = sema.bindings.primitiveOperatorCallableRef(for: exprID) {
            return lowerPrimitiveOperatorCallableRef(
                exprID,
                op: primitiveOp,
                memberName: memberName,
                boundType: boundType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }

        // `Int::toString` as `(Int) -> String` (see
        // `bindAnyToStringCallableRef`) has no target symbol either.
        if sema.bindings.isAnyToStringCallableRef(exprID) {
            return lowerAnyToStringCallableRef(
                exprID,
                memberName: memberName,
                boundType: boundType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
        let isUnbound = sema.bindings.isUnboundCallableRef(exprID)
        let callableReferenceBinding = sema.bindings.callableReferenceBinding(for: exprID)
        let isAdaptedCallableReference = callableReferenceBinding?.isCallableReferenceAdapter == true
        let targetSymbol = resolveCallableRefTargetSymbol(
            exprID: exprID,
            receiverExpr: receiverExpr,
            memberName: memberName,
            sema: sema
        )
        let isInnerConstructorTarget = targetSymbol.flatMap { target -> Bool? in
            guard sema.symbols.symbol(target)?.kind == .constructor,
                  let owner = sema.symbols.parentSymbol(for: target)
            else {
                return false
            }
            return sema.symbols.symbol(owner)?.flags.contains(.innerClass) == true
        } ?? false
        // KSP-505: a property ref whose owner is a genuine singleton
        // (`.object` — companion object or plain `object`) never captures a
        // receiver, in *either* bare or explicit-receiver form. Kotlin
        // guarantees exactly one instance for these, so
        // ensurePropertyReferenceAccessor (in
        // LambdaLowerer+PropertyReferenceLowering.swift) reads/writes a
        // single module-level global slot rather than a per-instance field —
        // there is nothing for a captured receiver to do. Capturing one
        // anyway (e.g. the explicit-receiver branch below unconditionally
        // did before this fix) mismatches that accessor's now-receiver-less
        // signature and previously crashed: for singletons that implement no
        // interface and declare no virtual dispatch, no real heap instance
        // is ever allocated, so the "receiver" being captured was frequently
        // a null placeholder in the first place.
        //
        // Deliberately excludes `.enumClass`: unlike `.object`, an enum
        // class has multiple instances (one per entry), so a property
        // declared directly in its own body is a genuine per-instance field,
        // not shared global storage — confirmed by testing (see the matching
        // note in ExprTypeChecker+NameLambdaAndCallableRefInference.swift).
        let isSingletonOwnedPropertyRef: Bool = {
            guard sema.bindings.callableRefKind(for: exprID) == .propertyRef,
                  let targetSymbol,
                  let parentSymbol = sema.symbols.parentSymbol(for: targetSymbol),
                  let parentKind = sema.symbols.symbol(parentSymbol)?.kind
            else { return false }
            return parentKind == .object
        }()
        var captureArguments: [KIRExprID] = []
        if let receiverExpr,
           !isUnbound,
           (targetSymbol.flatMap({ sema.symbols.symbol($0)?.kind }) != .constructor
               || isAdaptedCallableReference || isInnerConstructorTarget)
        {
            let loweredReceiver = driver.lowerExpr(
                receiverExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            // For unbound type references (Type::member), the receiver is
            // not captured — it becomes a parameter of the function type.
            if !isUnbound, !isSingletonOwnedPropertyRef {
                captureArguments.append(loweredReceiver)
            }
        } else if !isUnbound,
                  isInnerConstructorTarget,
                  let targetSymbol,
                  let innerClass = sema.symbols.parentSymbol(for: targetSymbol),
                  let outerClass = sema.symbols.parentSymbol(for: innerClass),
                  let outerReceiver = captureValueExpr(
                      for: outerClass,
                      sema: sema,
                      arena: arena,
                      interner: interner,
                      instructions: &instructions
                  )
        {
            // A bare `::Inner` has no syntax receiver, but its constructor
            // reference is still bound to the lexically enclosing instance.
            captureArguments.append(outerReceiver)
        } else if !isUnbound,
                  !isSingletonOwnedPropertyRef,
                  let receiverSymbol = sema.bindings.implicitReceiverOuterReceiver(for: exprID),
                  let receiverValue = captureValueExpr(
                      for: receiverSymbol,
                      sema: sema,
                      arena: arena,
                      interner: interner,
                      instructions: &instructions
                  )
        {
            captureArguments.append(receiverValue)
        } else if !isUnbound,
                  !isSingletonOwnedPropertyRef,
                  sema.bindings.callableRefKind(for: exprID) == .propertyRef,
                  let targetSymbol,
                  let parentSymbol = sema.symbols.parentSymbol(for: targetSymbol),
                  isCaptureEligibleInstanceContainerSymbol(parentSymbol, sema: sema),
                  let implicitReceiver = driver.ctx.activeImplicitReceiverExprID(),
                  implicitReceiverMatchesOwner(
                      implicitReceiver,
                      ownerSymbol: parentSymbol,
                      sema: sema,
                      arena: arena
                  )
        {
            // KSP-496: a bare `::member` reference to a member property of the
            // enclosing class is implicitly bound to `this` in Kotlin (the
            // same shape as an explicit `this::member`), so it needs the same
            // receiver capture — otherwise the generated wrapper's accessor
            // has no instance to read/write, and calling `.get()`/`.set()`
            // on it crashes (KSWIFTK-RUNTIME-0001 out-of-bounds read).
            //
            // Restricted to `.class` (see
            // isCaptureEligibleInstanceContainerSymbol; singleton owners are
            // excluded above, not here) and guarded by
            // implicitReceiverMatchesOwner: the implicit receiver at this
            // lowering point is a single "current" value (KIRLoweringContext
            // has no receiver stack), so it can be a *different*
            // receiver-scope's instance — e.g. `with(sb) { ::v }` inside a
            // member function sees `sb` (StringBuilder), not `this` (the
            // property's real owner), while it's active. When this guard
            // doesn't hold, no capture is added and the reference falls
            // through to the same (pre-existing, argument-count-mismatch)
            // crash bare `::member` already had for a receiver it can't
            // safely resolve — not memory corruption from reading a
            // wrong-typed object's fields.
            captureArguments.append(implicitReceiver)
        } else if sema.bindings.implicitReceiverMemberNames[exprID] != nil,
                  let targetSymbol,
                  let declaredReceiver = sema.symbols.functionSignature(for: targetSymbol)?.receiverType,
                  let implicitReceiver = driver.ctx.activeImplicitReceiverExprID(),
                  let activeType = arena.exprType(implicitReceiver),
                  sema.types.isSubtype(
                      sema.types.makeNonNullable(activeType),
                      sema.types.makeNonNullable(declaredReceiver)
                  )
        {
            // A bare `::member` in an extension function is a bound method
            // reference: its wrapper forwards the captured extension receiver
            // before the explicit arguments.
            captureArguments.append(implicitReceiver)
        }

        // BUG-B: a bare `::name` reference to a LOCAL function that itself
        // captures enclosing locals (e.g. an anonymous-function-expression
        // desugar capturing an outer `val`) must forward those same captures
        // as leading call arguments — the target's own compiled signature is
        // `capturedParams + declaredParams` (ExprLowerer+ControlFlowAndBlocks
        // .swift), so calling it with too few arguments crashes or reads
        // garbage. A direct call to the same function already does this
        // lookup (CallLowerer.swift); a callable reference to it must match.
        // `localValue(for:)` only ever resolves for local declarations, so
        // this is a no-op for top-level/member function targets.
        if let targetSymbol,
           let capturedInfo = driver.ctx.localValue(for: targetSymbol).flatMap({ driver.ctx.callableValueInfo(for: $0) })
        {
            captureArguments = capturedInfo.captureArguments + captureArguments
        }

        if let targetSymbol,
           let callableReferenceBinding,
           !callableReferenceBinding.boundContextParameterTypes.isEmpty,
           let signature = sema.symbols.functionSignature(for: targetSymbol)
        {
            for contextType in callableReferenceBinding.boundContextParameterTypes {
                if let contextValue = driver.callLowerer.contextArgumentValue(
                    matching: contextType,
                    callExprID: exprID,
                    signature: signature,
                    callBinding: callableReferenceBinding,
                    sema: sema,
                    arena: arena
                ) {
                    captureArguments.append(contextValue)
                }
            }
        }

        // BUG-162: KProperty0/1 references need a real object implementing the
        // bundled KProperty and Function interfaces. A raw property symbol is
        // sufficient for a direct getter call, but it has no itable entries for
        // KProperty.get/invoke/set and cannot carry the bound receiver safely.
        if sema.bindings.callableRefKind(for: exprID) == .propertyRef,
           let propertyValue = lowerPropertyReferenceWrapperValue(
               exprID,
               targetSymbol: targetSymbol,
               memberName: memberName,
               boundType: boundType,
               isUnbound: isUnbound,
               captureArguments: captureArguments,
               ast: ast,
               sema: sema,
               arena: arena,
               interner: interner,
               propertyConstantInitializers: propertyConstantInitializers,
               instructions: &instructions
           )
        {
            return propertyValue
        }

        // KSP-496: a property callable reference also reaches here whenever it
        // is consumed as a plain function value instead of a `KProperty0/1`
        // (`val f: (C) -> Int = C::v`, `list.map(C::v)`, SAM conversion) —
        // lowerPropertyReferenceWrapperValue above only builds the KProperty
        // wrapper object for the four KProperty shapes. A property symbol has
        // no emitted function behind it, so every branch below used to call a
        // symbol named after the property itself and the program failed to
        // link (`Undefined symbols: "_v"` for `class C(val v: Int)`). Call the
        // generated property-reference accessor instead.
        var callTargetSymbol = targetSymbol
        var callTargetName: InternedString?
        // A reference to an interface / open / abstract member function must
        // dispatch virtually; the declaring symbol alone is only a stub.
        if !isAdaptedCallableReference,
           sema.bindings.callableRefKind(for: exprID) == .functionRef,
           let targetSymbol,
           let thunk = virtualFunctionReferenceThunk(
               targetSymbol: targetSymbol,
               receiverStaticType: isUnbound ? nil
                   : (receiverExpr.flatMap { sema.bindings.exprTypes[$0] }
                       ?? captureArguments.first.flatMap { arena.exprType($0) }),
               sema: sema,
               arena: arena,
               interner: interner
           )
        {
            callTargetSymbol = thunk.symbol
            callTargetName = thunk.name
        }

        let reifiedFunctionType = (sema.bindings.samUnderlyingFunctionType(for: exprID) ?? boundType).flatMap { type -> FunctionType? in
            guard case let .functionType(function) = sema.types.kind(of: type) else { return nil }
            return function
        }
        let reifiedTargetSymbol = sema.bindings.callableRefKind(for: exprID) == .propertyRef
            ? callableReferenceBinding?.chosenCallee ?? targetSymbol
            : targetSymbol
        let reifiedThunk = isAdaptedCallableReference ? nil : reifiedTargetSymbol.flatMap { target in
            reifiedFunctionType.flatMap { function in
                reifiedCallableReferenceThunk(
                    exprID, targetSymbol: target, functionType: function,
                    captures: &captureArguments, sema: sema, arena: arena,
                    interner: interner, instructions: &instructions
                )
            }
        }

        // Resolve the property target after the capture decisions above:
        // those decisions consult `parentSymbol(for:)` on the property symbol,
        // which the synthetic accessor symbol does not carry.
        // Reified property getters require hidden type-token arguments. Their
        // callable thunk already forwards those tokens, so don't emit a plain
        // property getter thunk with the shorter ABI as dead invalid IR.
        if reifiedThunk == nil,
           sema.bindings.callableRefKind(for: exprID) == .propertyRef,
           let targetSymbol,
           let accessorTarget = propertyReferenceFunctionCallTarget(
               targetSymbol: targetSymbol,
               ast: ast,
               sema: sema,
               arena: arena,
               interner: interner,
               propertyConstantInitializers: propertyConstantInitializers
           )
        {
            callTargetSymbol = accessorTarget.symbol
            callTargetName = accessorTarget.name
        }

        if let reifiedThunk {
            callTargetSymbol = reifiedThunk.symbol
            callTargetName = reifiedThunk.name
        }

        // BUG-048: A callable reference in SAM-conversion position must become an
        // object implementing the functional interface (with an itable entry), the
        // same way a SAM-converted lambda literal does.  Lowering it as a bare
        // callable value makes interface dispatch on the result fail at runtime.
        if sema.bindings.isSamConversion(exprID), let callTargetSymbol {
            let samTarget: (symbol: SymbolID, name: InternedString?, isReified: Bool)
            if let callableReferenceBinding, callableReferenceBinding.isCallableReferenceAdapter,
               let functionTypeID = sema.bindings.samUnderlyingFunctionType(for: exprID),
               case let .functionType(functionType) = sema.types.kind(of: functionTypeID)
            {
                let localCaptureCount = driver.ctx.localValue(for: callTargetSymbol)
                    .flatMap { driver.ctx.callableValueInfo(for: $0)?.captureArguments.count } ?? 0
                let adapter = lowerCallableReferenceAdapter(
                    exprID,
                    targetSymbol: callTargetSymbol,
                    targetName: callTargetName,
                    binding: callableReferenceBinding,
                    isUnbound: isUnbound,
                    captureArguments: captureArguments,
                    localCaptureCount: localCaptureCount,
                    needsHOFWrapper: false,
                    memberName: memberName,
                    functionType: functionType,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                samTarget = (adapter.symbol, adapter.name, false)
            } else {
                samTarget = (callTargetSymbol, callTargetName, reifiedThunk != nil)
            }
            if let samValue = lowerCallableRefSamWrapperValue(
                exprID,
                targetSymbol: samTarget.symbol,
                targetName: samTarget.name,
                captureArguments: captureArguments,
                isReifiedThunk: samTarget.isReified,
                identityTargetSymbol: targetSymbol,
                callableType: boundType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            ) {
                return samValue
            }
        }

        // REFL-003: When a callable ref is used as a collection HOF argument
        // (e.g. `list.map(::double)`), we must generate a wrapper thunk with the
        // HOF ABI: (closureRaw, value, outThrown) -> result.  The target function
        // itself uses a plain ABI (value) -> result, so we cannot pass its
        // pointer directly to the runtime HOF implementation.
        let isCollectionHOFReference = sema.bindings.isCollectionHOFLambdaExpr(exprID)
        let needsHOFWrapper = isCollectionHOFReference && reifiedThunk == nil
        // Keep the referenced function's Kotlin ABI and adapt it through a
        // callable thunk that can use the runtime's flat String callback ABI.
        let needsTopLevelStringReturnWrapper: Bool = {
            guard driver.ctx.topLevelPropertyCallableReferenceInitializerExprID == exprID,
                  sema.bindings.callableRefKind(for: exprID) == .functionRef,
                  captureArguments.isEmpty,
                  let boundType,
                  case let .functionType(functionType) = sema.types.kind(of: boundType),
                  case .stringStruct = sema.types.kind(of: functionType.returnType)
            else {
                return false
            }
            return true
        }()
        // Imported inline bodies and local auto-inline HOFs may have no native
        // entry point. A reference must point at an emitted thunk whose call
        // can be expanded by InlineLowering, including forward declarations.
        let needsInlineWrapper: Bool = {
            guard let callTargetSymbol else { return false }
            let targetFlags = sema.symbols.symbol(callTargetSymbol)?.flags
            if targetFlags?.contains(.importedLibrary) == true && targetFlags?.contains(.inlineFunction) == true
                || sema.importedInlineFunctions.descriptors[callTargetSymbol] != nil
                || sema.importedInlineFunctions.functions[callTargetSymbol] != nil
            {
                return true
            } else if let declaration = sema.bindings.declSymbols.first(where: { $0.value == callTargetSymbol })?.key,
                      case let .funDecl(function) = ast.arena.decl(declaration),
                      !function.isInline, !function.modifiers.contains(.external),
                      sema.symbols.externalLinkName(for: callTargetSymbol) == nil,
                      let signature = sema.symbols.functionSignature(for: callTargetSymbol)
            {
                // Varargs are arrays/lists in the emitted signature, rather
                // than a single function parameter even for function elements.
                let parameterTypes = signature.receiverType.map { [$0] } ?? []
                let valueTypes = signature.parameterTypes.enumerated().compactMap { index, type in
                    index < signature.valueParameterIsVararg.count && signature.valueParameterIsVararg[index] ? nil : type
                }
                return shouldAutoInlineFunction(function, parameterTypes: parameterTypes + valueTypes, types: sema.types)
            } else {
                return false
            }
        }()

        // REFL-CTOR: a constructor reference (`::Foo`) must never call the
        // constructor's own body function directly -- that function only
        // initializes fields on an already-allocated `this` (the first
        // parameter), exactly like every other member function's receiver.
        // A literal `Foo(...)` call site gets that receiver from
        // `CallLowerer`'s constructor branch, which allocates the object with
        // `kk_object_new` and registers its itable/vtable/KClass metadata
        // *before* calling the body -- none of which a bare `.call` to the
        // target symbol would do. Route through `lowerResolvedCallBody` (the
        // same call-lowering entry point a real `Foo(...)` AST call uses) so
        // a callable reference stays byte-for-byte consistent with a direct
        // call instead of re-deriving that allocation/registration sequence
        // here.
        let isConstructorTarget = callTargetSymbol.flatMap { sema.symbols.symbol($0)?.kind } == .constructor

        let callableSymbol: SymbolID
        let callableName: InternedString
        if let callTargetSymbol,
           let callableReferenceBinding,
           callableReferenceBinding.isCallableReferenceAdapter,
           let functionType = (sema.bindings.samUnderlyingFunctionType(for: exprID) ?? boundType).flatMap({ typeID -> FunctionType? in
               guard case let .functionType(function) = sema.types.kind(of: typeID) else { return nil }
               return function
           })
        {
            let localCaptureCount = driver.ctx.localValue(for: callTargetSymbol)
                .flatMap { driver.ctx.callableValueInfo(for: $0)?.captureArguments.count } ?? 0
            let adapter = lowerCallableReferenceAdapter(
                exprID,
                targetSymbol: callTargetSymbol,
                targetName: callTargetName,
                binding: callableReferenceBinding,
                isUnbound: isUnbound,
                captureArguments: captureArguments,
                localCaptureCount: localCaptureCount,
                needsHOFWrapper: needsHOFWrapper,
                memberName: memberName,
                functionType: functionType,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            callableSymbol = adapter.symbol
            callableName = adapter.name
        } else if let callTargetSymbol, isConstructorTarget {
            callableSymbol = driver.ctx.syntheticLambdaSymbol(for: exprID)
            callableName = syntheticLambdaName(for: exprID, interner: interner)

            let functionType = boundType.flatMap { typeID -> FunctionType? in
                guard case let .functionType(ft) = sema.types.kind(of: typeID) else { return nil }
                return ft
            }
            let valueParamTypes = functionType?.params ?? []
            let returnType = functionType?.returnType ?? sema.types.anyType

            // Only collection-HOF usage (`list.map(::Foo)`) needs the
            // closureRaw ABI slot; a plain callable value (`val ctor = ::Foo`)
            // is called directly through its own symbol, exactly like the
            // no-capture fallback wrapper below.
            let closureParam = needsHOFWrapper ? KIRParameter(
                symbol: syntheticLambdaClosureParamSymbol(lambdaExprID: exprID),
                type: sema.types.intType
            ) : nil
            let valueParams: [KIRParameter] = valueParamTypes.enumerated().map { index, type in
                KIRParameter(
                    symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                    type: type
                )
            }
            let captureParams = captureArguments.enumerated().map { index, capture in
                KIRParameter(
                    symbol: syntheticLambdaCaptureParamSymbol(lambdaExprID: exprID, captureIndex: index),
                    type: arena.exprType(capture) ?? sema.types.anyType
                )
            }
            let wrapperParams = (closureParam.map { [$0] } ?? captureParams) + valueParams

            var body: [KIRInstruction] = [.beginBlock]
            let capturedValues = captureArguments.enumerated().map { index, _ -> KIRExprID in
                let parameter = closureParam ?? captureParams[index]
                let reference = arena.appendExpr(.symbolRef(parameter.symbol), type: parameter.type)
                body.append(.constValue(result: reference, value: .symbolRef(parameter.symbol)))
                return reference
            }
            var callArgExprs: [KIRExprID] = []
            for valueParam in valueParams {
                let paramExpr = arena.appendExpr(.symbolRef(valueParam.symbol), type: valueParam.type)
                body.append(.constValue(result: paramExpr, value: .symbolRef(valueParam.symbol)))
                let normalizedParamExpr = if needsHOFWrapper {
                    normalizeHOFPrimitiveParameter(
                        paramExpr,
                        type: valueParam.type,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &body,
                        isRawCallbackParameter: true
                    )
                } else {
                    paramExpr
                }
                callArgExprs.append(normalizedParamExpr)
            }

            let isInnerConstructor = isInnerConstructorTarget
            let constructorOuterReceiver: KIRExprID? = isInnerConstructor && isUnbound
                ? callArgExprs.first
                : isInnerConstructor ? capturedValues.first
                : nil
            let constructorArguments = isInnerConstructor && isUnbound
                ? Array(callArgExprs.dropFirst())
                : callArgExprs

            let constructedValue = driver.callLowerer.lowerResolvedCallBody(
                exprID,
                args: [],
                loweredArgIDs: packOrdinaryCallableVarargValues(
                    constructorArguments, targetSymbol: callTargetSymbol, parameterOffset: 0, resultType: returnType,
                    sema: sema, arena: arena, interner: interner, instructions: &body
                ),
                chosen: callTargetSymbol,
                callBinding: nil,
                callableValueCallBinding: nil,
                loweredCallable: nil,
                loweredCalleeExprID: nil,
                sourceCalleeName: memberName,
                boundType: returnType,
                knownNames: KnownCompilerNames(interner: interner),
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &body,
                outerReceiverOverride: constructorOuterReceiver
            )
            body.append(.returnValue(constructedValue))
            body.append(.endBlock)

            let wrapperDecl = arena.appendDecl(
                .function(
                    KIRFunction(
                        symbol: callableSymbol,
                        name: callableName,
                        params: wrapperParams,
                        returnType: returnType,
                        body: body,
                        isSuspend: false,
                        isInline: false
                    )
                )
            )
            driver.ctx.appendGeneratedCallableDecl(wrapperDecl)
        } else if let callTargetSymbol,
                  sema.bindings.implicitReceiverMemberNames[exprID] != nil,
                  let boundReceiver = captureArguments.first,
                  let dispatch = driver.callLowerer.resolveVirtualDispatch(
                      callee: callTargetSymbol,
                      receiverTypeID: arena.exprType(boundReceiver),
                      sema: sema,
                      interner: interner
                  )
        {
            // A bound `::member` must retain virtual dispatch. Passing the
            // interface declaration as a raw callable target would invoke it
            // directly and bypass the concrete receiver's itable entry.
            callableSymbol = driver.ctx.syntheticLambdaSymbol(for: exprID)
            callableName = syntheticLambdaName(for: exprID, interner: interner)
            let functionType = boundType.flatMap { typeID -> FunctionType? in
                guard case let .functionType(ft) = sema.types.kind(of: typeID) else { return nil }
                return ft
            }
            let returnType = functionType?.returnType ?? sema.types.anyType
            let receiverParam = KIRParameter(
                symbol: needsHOFWrapper
                    ? syntheticLambdaClosureParamSymbol(lambdaExprID: exprID)
                    : syntheticLambdaCaptureParamSymbol(lambdaExprID: exprID, captureIndex: 0),
                type: needsHOFWrapper
                    ? sema.types.intType
                    : (arena.exprType(boundReceiver) ?? sema.types.anyType)
            )
            let valueParams: [KIRParameter] = (functionType?.params ?? []).enumerated().map { index, type in
                KIRParameter(
                    symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                    type: type
                )
            }
            var body: [KIRInstruction] = [.beginBlock]
            let receiverRef = arena.appendExpr(.symbolRef(receiverParam.symbol), type: receiverParam.type)
            body.append(.constValue(result: receiverRef, value: .symbolRef(receiverParam.symbol)))
            var valueRefs: [KIRExprID] = []
            for valueParam in valueParams {
                let valueRef = arena.appendExpr(.symbolRef(valueParam.symbol), type: valueParam.type)
                body.append(.constValue(result: valueRef, value: .symbolRef(valueParam.symbol)))
                valueRefs.append(valueRef)
            }
            let callResult = arena.appendTemporary(type: returnType)
            body.append(.virtualCall(
                symbol: callTargetSymbol,
                callee: callableTargetName(for: callTargetSymbol, sema: sema, interner: interner),
                receiver: receiverRef,
                arguments: valueRefs,
                result: callResult,
                canThrow: false,
                dispatch: dispatch
            ))
            switch sema.types.kind(of: returnType) {
            case .unit, .nothing(.nonNull), .nothing(.nullable):
                body.append(.returnUnit)
            default:
                body.append(.returnValue(callResult))
            }
            body.append(.endBlock)
            let wrapperDecl = arena.appendDecl(.function(KIRFunction(
                symbol: callableSymbol,
                name: callableName,
                params: [receiverParam] + valueParams,
                returnType: returnType,
                body: body,
                isSuspend: functionType?.isSuspend ?? false,
                isInline: false
            )))
            driver.ctx.appendGeneratedCallableDecl(wrapperDecl)
        } else if let callTargetSymbol,
                  needsHOFWrapper || needsInlineWrapper || needsTopLevelStringReturnWrapper
        {
            // HOF callbacks use a closure parameter. Ordinary inline references
            // keep the Kotlin signature and pass each bound capture directly.
            callableSymbol = driver.ctx.syntheticLambdaSymbol(for: exprID)
            callableName = needsTopLevelStringReturnWrapper
                ? interner.intern("kk_top_level_string_callable_ref_\(exprID.rawValue)")
                : syntheticLambdaName(for: exprID, interner: interner)

            let targetName = callTargetName
                ?? callableTargetName(for: callTargetSymbol, sema: sema, interner: interner)
            let functionType = boundType.flatMap { typeID -> FunctionType? in
                guard case let .functionType(ft) = sema.types.kind(of: typeID) else { return nil }
                return ft
            }
            let valueParamTypes = (functionType?.receiver.map { [$0] } ?? []) + (functionType?.params ?? [])
            let returnType = functionType?.returnType ?? sema.types.anyType

            let closureParam = KIRParameter(
                symbol: syntheticLambdaClosureParamSymbol(lambdaExprID: exprID),
                type: sema.types.intType
            )
            let valueParams: [KIRParameter] = valueParamTypes.enumerated().map { index, type in
                KIRParameter(
                    symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                    type: type
                )
            }
            let captureParams = captureArguments.enumerated().map { index, capture in
                KIRParameter(
                    symbol: syntheticLambdaCaptureParamSymbol(lambdaExprID: exprID, captureIndex: index),
                    type: arena.exprType(capture) ?? sema.types.anyType
                )
            }
            let wrapperParams = (needsHOFWrapper ? [closureParam] : captureParams) + valueParams

            var body: [KIRInstruction] = [.beginBlock]
            var callArgExprs: [KIRExprID] = []
            for index in captureArguments.indices {
                let parameter = needsHOFWrapper ? closureParam : captureParams[index]
                let captureRef = arena.appendExpr(
                    .symbolRef(parameter.symbol),
                    type: parameter.type
                )
                body.append(.constValue(result: captureRef, value: .symbolRef(parameter.symbol)))
                callArgExprs.append(captureRef)
            }
            for valueParam in valueParams {
                let paramExpr = arena.appendExpr(.symbolRef(valueParam.symbol), type: valueParam.type)
                body.append(.constValue(result: paramExpr, value: .symbolRef(valueParam.symbol)))
                let normalizedParamExpr = needsHOFWrapper ? normalizeHOFPrimitiveParameter(
                    paramExpr,
                    type: valueParam.type,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &body,
                    isRawCallbackParameter: true
                ) : paramExpr
                callArgExprs.append(normalizedParamExpr)
            }
            let callResult = arena.appendTemporary(type: returnType
            )
            body.append(.call(
                symbol: callTargetSymbol,
                callee: targetName,
                arguments: packOrdinaryCallableVarargValues(
                    callArgExprs, targetSymbol: callTargetSymbol, parameterOffset: captureArguments.count, resultType: returnType,
                    sema: sema, arena: arena, interner: interner, instructions: &body
                ),
                result: callResult,
                canThrow: !needsHOFWrapper
            ))
            switch sema.types.kind(of: returnType) {
            case .unit, .nothing(.nonNull), .nothing(.nullable):
                body.append(.returnUnit)
            default:
                body.append(.returnValue(callResult))
            }
            body.append(.endBlock)

            let wrapperDecl = arena.appendDecl(
                .function(
                    KIRFunction(
                        symbol: callableSymbol,
                        name: callableName,
                        params: wrapperParams,
                        returnType: returnType,
                        body: body,
                        isSuspend: functionType?.isSuspend ?? false,
                        isInline: false
                    )
                )
            )
            driver.ctx.appendGeneratedCallableDecl(wrapperDecl)
        } else if let callTargetSymbol,
                  let signature = sema.symbols.functionSignature(for: callTargetSymbol),
                  signature.valueParameterIsVararg.contains(true),
                  !signature.isSuspend, signature.contextReceiverTypes.isEmpty,
                  signature.reifiedTypeParameterIndices.isEmpty,
                  !driver.callLowerer.kirIsRuntimeBridgedCallee(callTargetSymbol, sema: sema),
                  let boundType, case let .functionType(functionType) = sema.types.kind(of: boundType)
        {
            callableSymbol = driver.ctx.syntheticLambdaSymbol(for: exprID)
            callableName = syntheticLambdaName(for: exprID, interner: interner)
            let parameterTypes = captureArguments.map { arena.exprType($0) ?? sema.types.anyType }
                + (functionType.receiver.map { [$0] } ?? []) + functionType.params
            let parameters = parameterTypes.enumerated().map { index, type in
                KIRParameter(symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index), type: type)
            }
            var body: [KIRInstruction] = [.beginBlock]
            let refs = parameters.map { parameter -> KIRExprID in
                let ref = arena.appendExpr(.symbolRef(parameter.symbol), type: parameter.type)
                body.append(.constValue(result: ref, value: .symbolRef(parameter.symbol)))
                return ref
            }
            let arguments = packOrdinaryCallableVarargValues(
                refs, targetSymbol: callTargetSymbol,
                parameterOffset: refs.count - signature.parameterTypes.count,
                resultType: functionType.returnType,
                sema: sema, arena: arena, interner: interner, instructions: &body
            )
            let result = arena.appendTemporary(type: functionType.returnType)
            body.append(.call(symbol: callTargetSymbol,
                              callee: callTargetName ?? callableTargetName(for: callTargetSymbol, sema: sema, interner: interner),
                              arguments: arguments, result: result, canThrow: true))
            switch sema.types.kind(of: functionType.returnType) {
            case .unit, .nothing: body.append(.returnUnit)
            default: body.append(.returnValue(result))
            }
            body.append(.endBlock)
            driver.ctx.appendGeneratedCallableDecl(arena.appendDecl(.function(KIRFunction(
                symbol: callableSymbol, name: callableName, params: parameters,
                returnType: functionType.returnType, body: body,
                isSuspend: false, isInline: false
            ))))
        } else if let callTargetSymbol {
            callableSymbol = callTargetSymbol
            callableName = callTargetName
                ?? callableTargetName(for: callTargetSymbol, sema: sema, interner: interner)
        } else {
            callableSymbol = driver.ctx.syntheticLambdaSymbol(for: exprID)
            callableName = syntheticLambdaName(for: exprID, interner: interner)
            let fallbackFunctionType = boundType.flatMap { typeID -> FunctionType? in
                guard case let .functionType(functionType) = sema.types.kind(of: typeID) else {
                    return nil
                }
                return functionType
            }
            let fallbackValueParamTypes = fallbackFunctionType?.params ?? []
            let fallbackReturnType = fallbackFunctionType?.returnType ?? sema.types.anyType

            let captureParams: [KIRParameter] = captureArguments.enumerated().map { index, captureExpr in
                KIRParameter(
                    symbol: syntheticLambdaCaptureParamSymbol(lambdaExprID: exprID, captureIndex: index),
                    type: arena.exprType(captureExpr) ?? sema.types.anyType
                )
            }
            let valueParams: [KIRParameter] = fallbackValueParamTypes.enumerated().map { index, type in
                KIRParameter(
                    symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                    type: type
                )
            }
            var body: [KIRInstruction] = [.beginBlock]
            switch sema.types.kind(of: fallbackReturnType) {
            case .unit, .nothing(.nonNull), .nothing(.nullable):
                body.append(.returnUnit)
            default:
                let zero = arena.appendExpr(.intLiteral(0), type: fallbackReturnType)
                body.append(.constValue(result: zero, value: .intLiteral(0)))
                body.append(.returnValue(zero))
            }
            body.append(.endBlock)

            let fallbackDecl = arena.appendDecl(
                .function(
                    KIRFunction(
                        symbol: callableSymbol,
                        name: callableName,
                        params: captureParams + valueParams,
                        returnType: fallbackReturnType,
                        body: body,
                        isSuspend: fallbackFunctionType?.isSuspend ?? false,
                        isInline: false
                    )
                )
            )
            driver.ctx.appendGeneratedCallableDecl(fallbackDecl)
        }

        let callableType = boundType ?? typeForSymbolReference(callableSymbol, sema: sema)
        let callableExpr = arena.appendExpr(.symbolRef(callableSymbol), type: callableType)
        instructions.append(.constValue(result: callableExpr, value: .symbolRef(callableSymbol)))
        driver.ctx.registerCallableValue(
            callableExpr,
            symbol: callableSymbol,
            callee: callableName,
            captureArguments: captureArguments,
            hasClosureParam: needsHOFWrapper && callTargetSymbol != nil
        )

        // Collection HOF runtimes expect a raw function pointer plus closure payload.
        // Returning a tagged callable reference here would pass the reflection wrapper
        // object to runtime HOF entry points instead of the generated thunk symbol.
        if isCollectionHOFReference {
            if sema.bindings.callableRefKind(for: exprID) == .functionRef,
               case let .functionType(functionType) = sema.types.kind(of: callableType)
            {
                emitFunctionValueTypeTag(
                    callableExpr, functionType: functionType, sema: sema,
                    arena: arena, interner: interner, instructions: &instructions
                )
            }
            return callableExpr
        }

        // Bound references need per-value storage: the same target pointer can
        // also represent an unbound reference with a different arity. Boxing
        // preserves the receiver when the value escapes the KIR callable table.
        // Suspend references also need a box without captures: their launcher
        // thunk supplies the continuation-only entry ABI instead of calling a
        // raw Kotlin method pointer through the ordinary function ABI.
        let callableValue: KIRExprID
        if case let .functionType(functionType) = sema.types.kind(of: callableType),
           !captureArguments.isEmpty || functionType.isSuspend,
           let materialized = materializeEscapingCallableValue(
               exprID: exprID,
               lambdaSymbol: callableSymbol,
               lambdaName: callableName,
               lambdaReturnType: functionType.returnType,
               functionType: functionType,
               captureArguments: captureArguments,
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            callableValue = materialized
        } else {
            callableValue = callableExpr
        }

        // Adapted references are ordinary function values and do not expose KCallable reflection.
        if isAdaptedCallableReference {
            return callableValue
        }

        // REFL-003: Emit KFunction / KProperty type identity tag.
        // The tagging call wraps the callable value with reflection
        // metadata (name, arity, KFunction vs KProperty).  We register
        // the tagged expression with the same callable-value metadata so
        // that downstream callable-value-call lowering resolves the
        // correct target symbol and capture arguments.
        if let refKind = sema.bindings.callableRefKind(for: exprID) {
            let taggedExpr = emitCallableRefTypeTag(
                callableExpr: callableValue,
                callableType: callableType,
                refKind: refKind,
                memberName: memberName,
                targetSymbol: targetSymbol,
                identityCaptures: captureArguments,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            if case let .functionType(functionType) = sema.types.kind(of: callableType) {
                registerCallableReflection(
                    value: taggedExpr, callableSymbol: callableSymbol, callableName: callableName,
                    targetSymbol: targetSymbol,
                    parameterTypes: (functionType.receiver.map { [$0] } ?? []) + functionType.params,
                    returnType: functionType.returnType,
                    captures: captureArguments,
                    receiverCount: isUnbound && targetSymbol.flatMap { sema.symbols.functionSignature(for: $0) }?.receiverType != nil ? 1 : 0,
                    // KCallable.call's reflection bridge has no continuation
                    // parameter. Suspend references keep their suspend
                    // function-value invoke path instead of generating a
                    // non-suspend reflection thunk that cannot call the target.
                    includeInvocation: !functionType.isSuspend
                        && targetSymbol.flatMap { sema.symbols.functionSignature(for: $0) }?.reifiedTypeParameterIndices.isEmpty != false,
                    ast: ast, sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
            }
            if let callableInfo = driver.ctx.callableValueInfo(for: callableValue) {
                driver.ctx.registerCallableValue(
                    taggedExpr,
                    symbol: callableInfo.symbol,
                    callee: callableInfo.callee,
                    captureArguments: callableInfo.captureArguments,
                    hasClosureParam: callableInfo.hasClosureParam
                )
            }
            return taggedExpr
        }

        return callableValue
    }

    /// Builds the wrapper for `Type::toString` used as a `(Type) -> String`
    /// function value: its body stringifies the single parameter exactly like
    /// a literal `x.toString()` (`emitAnyToStringWithNullGuard`).
    private func lowerAnyToStringCallableRef(
        _ exprID: ExprID,
        memberName: InternedString,
        boundType: TypeID?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let needsHOFWrapper = sema.bindings.isCollectionHOFLambdaExpr(exprID)
        let callableSymbol = driver.ctx.syntheticLambdaSymbol(for: exprID)
        let callableName = syntheticLambdaName(for: exprID, interner: interner)

        let functionType = boundType.flatMap { typeID -> FunctionType? in
            guard case let .functionType(ft) = sema.types.kind(of: typeID) else { return nil }
            return ft
        }
        let operandType = functionType?.params.first ?? sema.types.anyType
        let returnType = sema.types.stringType

        let closureParam = needsHOFWrapper ? KIRParameter(
            symbol: syntheticLambdaClosureParamSymbol(lambdaExprID: exprID),
            type: sema.types.intType
        ) : nil
        let valueParam = KIRParameter(
            symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: 0),
            type: operandType
        )
        let wrapperParams = (closureParam.map { [$0] } ?? []) + [valueParam]

        var body: [KIRInstruction] = [.beginBlock]
        let paramExpr = arena.appendExpr(.symbolRef(valueParam.symbol), type: valueParam.type)
        body.append(.constValue(result: paramExpr, value: .symbolRef(valueParam.symbol)))
        let operand = needsHOFWrapper
            ? normalizeHOFPrimitiveParameter(
                paramExpr,
                type: valueParam.type,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &body,
                isRawCallbackParameter: true
            )
            : paramExpr
        let stringResult = driver.callLowerer.emitAnyToStringWithNullGuard(
            valueID: operand,
            valueType: operandType,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body
        )
        body.append(.returnValue(stringResult))
        body.append(.endBlock)

        driver.ctx.appendGeneratedCallableDecl(arena.appendDecl(.function(KIRFunction(
            symbol: callableSymbol,
            name: callableName,
            params: wrapperParams,
            returnType: returnType,
            body: body,
            isSuspend: false,
            isInline: false
        ))))

        let callableType = boundType ?? sema.types.anyType
        let callableExpr = arena.appendExpr(.symbolRef(callableSymbol), type: callableType)
        instructions.append(.constValue(result: callableExpr, value: .symbolRef(callableSymbol)))
        driver.ctx.registerCallableValue(
            callableExpr,
            symbol: callableSymbol,
            callee: callableName,
            captureArguments: []
        )
        if needsHOFWrapper {
            return callableExpr
        }
        if let refKind = sema.bindings.callableRefKind(for: exprID) {
            let taggedExpr = emitCallableRefTypeTag(
                callableExpr: callableExpr,
                callableType: callableType,
                refKind: refKind,
                memberName: memberName,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            driver.ctx.registerCallableValue(
                taggedExpr,
                symbol: callableSymbol,
                callee: callableName,
                captureArguments: []
            )
            return taggedExpr
        }
        return callableExpr
    }

    /// REFL-PRIMOP: builds the wrapper function and REFL-003 tag for a
    /// primitive-operator callable reference (`Int::plus`). Its body is the
    /// raw `KIRBinaryOp` arithmetic instruction directly -- the same one a
    /// literal `a + b` eventually lowers to for these two operators
    /// (`CallLowerer+Operators.swift`'s `lowerBinaryExpr` reaches its own
    /// bare `.binary(op:, lhs:, rhs:, result:)` fallback for `.add`/
    /// `.multiply` on every primitive numeric type, with no runtime-callee,
    /// unsigned, or overload detour in between) -- so there is no callee
    /// symbol to resolve and no receiver value to lower or capture, unlike
    /// every other shape `lowerCallableRefExpr` handles.
    private func lowerPrimitiveOperatorCallableRef(
        _ exprID: ExprID,
        op: BinaryOp,
        memberName: InternedString,
        boundType: TypeID?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let kirOp: KIRBinaryOp
        switch op {
        case .add:
            kirOp = .add
        case .multiply:
            kirOp = .multiply
        default:
            fatalError("Unreachable: Sema only records .add/.multiply primitive-operator refs")
        }

        let needsHOFWrapper = sema.bindings.isCollectionHOFLambdaExpr(exprID)
        let callableSymbol = driver.ctx.syntheticLambdaSymbol(for: exprID)
        let callableName = syntheticLambdaName(for: exprID, interner: interner)

        let functionType = boundType.flatMap { typeID -> FunctionType? in
            guard case let .functionType(ft) = sema.types.kind(of: typeID) else { return nil }
            return ft
        }
        let operandType = functionType?.params.first ?? sema.types.intType
        let returnType = functionType?.returnType ?? operandType

        let closureParam = needsHOFWrapper ? KIRParameter(
            symbol: syntheticLambdaClosureParamSymbol(lambdaExprID: exprID),
            type: sema.types.intType
        ) : nil
        let lhsParam = KIRParameter(
            symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: 0),
            type: operandType
        )
        let rhsParam = KIRParameter(
            symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: 1),
            type: operandType
        )
        let wrapperParams = (closureParam.map { [$0] } ?? []) + [lhsParam, rhsParam]

        var body: [KIRInstruction] = [.beginBlock]
        let lhsExpr = arena.appendExpr(.symbolRef(lhsParam.symbol), type: lhsParam.type)
        body.append(.constValue(result: lhsExpr, value: .symbolRef(lhsParam.symbol)))
        let rhsExpr = arena.appendExpr(.symbolRef(rhsParam.symbol), type: rhsParam.type)
        body.append(.constValue(result: rhsExpr, value: .symbolRef(rhsParam.symbol)))
        let opResult = arena.appendTemporary(type: returnType)
        body.append(.binary(op: kirOp, lhs: lhsExpr, rhs: rhsExpr, result: opResult))
        body.append(.returnValue(opResult))
        body.append(.endBlock)

        let wrapperDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: callableSymbol,
                    name: callableName,
                    params: wrapperParams,
                    returnType: returnType,
                    body: body,
                    isSuspend: false,
                    isInline: false
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(wrapperDecl)

        let callableType = boundType ?? sema.types.anyType
        let callableExpr = arena.appendExpr(.symbolRef(callableSymbol), type: callableType)
        instructions.append(.constValue(result: callableExpr, value: .symbolRef(callableSymbol)))
        driver.ctx.registerCallableValue(
            callableExpr,
            symbol: callableSymbol,
            callee: callableName,
            captureArguments: [],
            hasClosureParam: needsHOFWrapper
        )

        if needsHOFWrapper {
            return callableExpr
        }

        if let refKind = sema.bindings.callableRefKind(for: exprID) {
            let taggedExpr = emitCallableRefTypeTag(
                callableExpr: callableExpr,
                callableType: callableType,
                refKind: refKind,
                memberName: memberName,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            driver.ctx.registerCallableValue(
                taggedExpr,
                symbol: callableSymbol,
                callee: callableName,
                captureArguments: []
            )
            return taggedExpr
        }

        return callableExpr
    }

    private func lowerPrimitiveUnaryOperatorCallableRef(
        _ exprID: ExprID,
        op: UnaryOp,
        memberName: InternedString,
        boundType: TypeID?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard op == .not else {
            fatalError("Unreachable: Sema only records .not primitive-unary refs")
        }

        let needsHOFWrapper = sema.bindings.isCollectionHOFLambdaExpr(exprID)
        let callableSymbol = driver.ctx.syntheticLambdaSymbol(for: exprID)
        let callableName = syntheticLambdaName(for: exprID, interner: interner)

        let functionType = boundType.flatMap { typeID -> FunctionType? in
            guard case let .functionType(ft) = sema.types.kind(of: typeID) else { return nil }
            return ft
        }
        let operandType = functionType?.params.first ?? sema.types.booleanType
        let returnType = functionType?.returnType ?? sema.types.booleanType

        let closureParam = needsHOFWrapper ? KIRParameter(
            symbol: syntheticLambdaClosureParamSymbol(lambdaExprID: exprID),
            type: sema.types.intType
        ) : nil
        let valueParam = KIRParameter(
            symbol: syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: 0),
            type: operandType
        )
        let wrapperParams = (closureParam.map { [$0] } ?? []) + [valueParam]

        var body: [KIRInstruction] = [.beginBlock]
        let operandExpr = arena.appendExpr(.symbolRef(valueParam.symbol), type: valueParam.type)
        body.append(.constValue(result: operandExpr, value: .symbolRef(valueParam.symbol)))
        let opResult = arena.appendTemporary(type: returnType)
        body.append(.unary(op: .not, operand: operandExpr, result: opResult))
        body.append(.returnValue(opResult))
        body.append(.endBlock)

        let wrapperDecl = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: callableSymbol,
                    name: callableName,
                    params: wrapperParams,
                    returnType: returnType,
                    body: body,
                    isSuspend: false,
                    isInline: false
                )
            )
        )
        driver.ctx.appendGeneratedCallableDecl(wrapperDecl)

        let callableType = boundType ?? sema.types.anyType
        let callableExpr = arena.appendExpr(.symbolRef(callableSymbol), type: callableType)
        instructions.append(.constValue(result: callableExpr, value: .symbolRef(callableSymbol)))
        driver.ctx.registerCallableValue(
            callableExpr,
            symbol: callableSymbol,
            callee: callableName,
            captureArguments: []
        )

        if needsHOFWrapper {
            return callableExpr
        }

        if let refKind = sema.bindings.callableRefKind(for: exprID) {
            let taggedExpr = emitCallableRefTypeTag(
                callableExpr: callableExpr,
                callableType: callableType,
                refKind: refKind,
                memberName: memberName,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
            driver.ctx.registerCallableValue(
                taggedExpr,
                symbol: callableSymbol,
                callee: callableName,
                captureArguments: []
            )
            return taggedExpr
        }

        return callableExpr
    }

    /// The caller must use the returned expression (and register it for
    /// callable-value resolution) so that the tagged value propagates through
    /// the program.
    func emitCallableRefTypeTag(
        callableExpr: KIRExprID,
        callableType: TypeID,
        refKind: CallableRefKind,
        memberName: InternedString,
        targetSymbol: SymbolID? = nil,
        identityCaptures: [KIRExprID] = [],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let arity: Int64
        let isSuspendFlag: Int64
        if case let .functionType(functionType) = sema.types.kind(of: callableType) {
            arity = Int64(functionType.contextReceivers.count
                + (functionType.receiver == nil ? 0 : 1) + functionType.params.count)
            isSuspendFlag = functionType.isSuspend ? 1 : 0
        } else {
            // Property references have arity 0 (no value params, just a getter).
            arity = 0
            isSuspendFlag = 0
        }

        let nameExpr = arena.appendExpr(
            .stringLiteral(memberName),
            type: sema.types.stringType
        )
        instructions.append(.constValue(result: nameExpr, value: .stringLiteral(memberName)))

        // KCallable.returnType is represented by the same compact type-name
        // handle used by KClass reflection metadata.
        let returnType: TypeID = if case let .functionType(functionType) = sema.types.kind(of: callableType) {
            functionType.returnType
        } else {
            sema.types.anyType
        }
        let returnTypeName = interner.intern(
            sema.types.displayName(of: returnType, symbols: sema.symbols, interner: interner)
        )
        let returnTypeExpr = arena.appendExpr(
            .stringLiteral(returnTypeName),
            type: sema.types.stringType
        )
        instructions.append(.constValue(
            result: returnTypeExpr,
            value: .stringLiteral(returnTypeName)
        ))

        let arityExpr = arena.appendExpr(.intLiteral(arity), type: sema.types.intType)
        instructions.append(.constValue(result: arityExpr, value: .intLiteral(arity)))

        let tagCallee: String = switch refKind {
        case .functionRef:
            "kk_callable_ref_tag_kfunction"
        case .propertyRef:
            "kk_callable_ref_tag_kproperty"
        }

        // For function refs, emit the packed modifier flags after the
        // metadata fields: bit0=suspend, bit1=inline, bit2=operator,
        // bit3=infix, bit4=external (KUU-1357; matches RuntimeKFunctionFlags).
        var tagArguments: [KIRExprID] = [callableExpr, nameExpr, returnTypeExpr, arityExpr]
        if refKind == .functionRef {
            var flags = isSuspendFlag
            if let targetSymbol, let target = sema.symbols.symbol(targetSymbol) {
                if target.flags.contains(.inlineFunction) { flags |= 1 << 1 }
                if target.flags.contains(.operatorFunction) { flags |= 1 << 2 }
                if target.flags.contains(.infixFunction) { flags |= 1 << 3 }
                if sema.symbols.externalLinkName(for: targetSymbol) != nil { flags |= 1 << 4 }
            }
            let isSuspendExpr = arena.appendExpr(.intLiteral(flags), type: sema.types.intType)
            instructions.append(.constValue(result: isSuspendExpr, value: .intLiteral(flags)))
            tagArguments.append(isSuspendExpr)
        }

        let taggedExpr = arena.appendTemporary(type: callableType
        )
        instructions.append(.call(callee: interner.intern(tagCallee), arguments: tagArguments, result: taggedExpr, canThrow: false))
        let identityTargetSymbol: SymbolID? = {
            guard let targetSymbol else { return nil }
            switch refKind {
            case .functionRef:
                return targetSymbol
            case .propertyRef:
                let propertySymbol = sema.symbols.symbol(targetSymbol)?.kind == .property
                    ? targetSymbol
                    : sema.symbols.accessorOwnerProperty(for: targetSymbol)
                guard let propertySymbol else { return nil }
                return sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
                    ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
            }
        }()
        if let identityTargetSymbol {
            emitCallableReferenceIdentity(
                callableExpr: taggedExpr,
                targetSymbol: identityTargetSymbol,
                captures: identityCaptures,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
        if refKind == .functionRef {
            let anonymous = interner.resolve(memberName).hasPrefix("__AnonymousFunction_")
            emitFunctionDescription(
                value: taggedExpr,
                description: anonymous ? "kotlin.Function\(arity)" : functionReferenceDescription(
                    name: memberName, type: callableType, targetSymbol: targetSymbol,
                    sema: sema, interner: interner
                ),
                identity: anonymous,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
        }
        return taggedExpr
    }

    func emitCallableReferenceIdentity(
        callableExpr: KIRExprID,
        targetSymbol: SymbolID,
        captures: [KIRExprID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let identityTarget = arena.appendExpr(.symbolRef(targetSymbol), type: sema.types.intType)
        instructions.append(.constValue(result: identityTarget, value: .symbolRef(targetSymbol)))
        let boxedCaptures = captures.map { capture in
            let captureType = arena.exprType(capture) ?? sema.types.anyType
            return boxValueForAnySlot(
                capture,
                sourceType: captureType,
                types: sema.types,
                symbols: sema.symbols,
                interner: interner,
                arena: arena,
                requireNonNull: true,
                sema: sema,
                into: &instructions
            )
        }
        let identityCaptures: KIRExprID
        if boxedCaptures.isEmpty {
            identityCaptures = arena.appendExpr(.null, type: sema.types.nullableAnyType)
            instructions.append(.constValue(result: identityCaptures, value: .null))
        } else {
            identityCaptures = makeReflectionArgumentList(
                boxedCaptures,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )
        }
        instructions.append(.call(
            callee: interner.intern("__kk_callable_ref_set_identity"),
            arguments: [callableExpr, identityTarget, identityCaptures],
            result: nil,
            canThrow: false
        ))
    }
}
