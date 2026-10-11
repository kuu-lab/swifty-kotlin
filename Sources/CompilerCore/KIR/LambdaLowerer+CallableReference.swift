extension LambdaLowerer {
    /// Lowers a SAM-converted callable reference (`Comparator<Int>(::myCompare)`)
    /// into a wrapper object implementing the functional interface.  A thunk with
    /// the lambda calling convention `(captures..., params...) -> R` is generated
    /// so the shared SAM wrapper synthesis can delegate to the referenced callable.
    private func lowerCallableRefSamWrapperValue(
        _ exprID: ExprID,
        targetSymbol: SymbolID,
        targetName: InternedString?,
        captureArguments: [KIRExprID],
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

        let samMethodParamTypes = samFunctionType.params
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
        let valueParams: [KIRParameter] = samMethodParamTypes.enumerated().map { index, type in
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
        if sema.bindings.implicitReceiverMemberNames[exprID] != nil,
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
                canThrow: false,
                thrownResult: nil,
                dispatch: dispatch
            ))
        } else {
            body.append(.call(
                symbol: targetSymbol,
                callee: callee,
                arguments: callArguments,
                result: callResult,
                canThrow: false,
                thrownResult: nil
            ))
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

        return lowerSamWrapperValue(
            exprID,
            interfaceType: interfaceType,
            lambdaSymbol: thunkSymbol,
            lambdaName: thunkName,
            lambdaReturnType: returnType,
            captureBindings: captureBindings,
            samMethodParamTypes: samMethodParamTypes,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
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
        let targetSymbol = resolveCallableRefTargetSymbol(
            exprID: exprID,
            receiverExpr: receiverExpr,
            memberName: memberName,
            sema: sema
        )
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
           targetSymbol.flatMap({ sema.symbols.symbol($0)?.kind }) != .constructor
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
        //
        // Substituted *here*, after the capture decisions above and before the
        // three call-target branches: those decisions consult
        // `parentSymbol(for:)` on the property symbol, which the synthetic
        // accessor symbol does not carry.
        var callTargetSymbol = targetSymbol
        var callTargetName: InternedString?
        if sema.bindings.callableRefKind(for: exprID) == .propertyRef,
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
        // A reference to an interface / open / abstract member function must
        // dispatch virtually; the declaring symbol alone is only a stub.
        if sema.bindings.callableRefKind(for: exprID) == .functionRef,
           let targetSymbol,
           let thunk = virtualFunctionReferenceThunk(
               targetSymbol: targetSymbol,
               receiverStaticType: isUnbound ? nil : receiverExpr.flatMap { sema.bindings.exprTypes[$0] },
               sema: sema,
               arena: arena,
               interner: interner
           )
        {
            callTargetSymbol = thunk.symbol
            callTargetName = thunk.name
        }

        // BUG-048: A callable reference in SAM-conversion position must become an
        // object implementing the functional interface (with an itable entry), the
        // same way a SAM-converted lambda literal does.  Lowering it as a bare
        // callable value makes interface dispatch on the result fail at runtime.
        if sema.bindings.isSamConversion(exprID),
           let callTargetSymbol,
           let samValue = lowerCallableRefSamWrapperValue(
               exprID,
               targetSymbol: callTargetSymbol,
               targetName: callTargetName,
               captureArguments: captureArguments,
               sema: sema,
               arena: arena,
               interner: interner,
               instructions: &instructions
           )
        {
            return samValue
        }

        // REFL-003: When a callable ref is used as a collection HOF argument
        // (e.g. `list.map(::double)`), we must generate a wrapper thunk with the
        // HOF ABI: (closureRaw, value, outThrown) -> result.  The target function
        // itself uses a plain ABI (value) -> result, so we cannot pass its
        // pointer directly to the runtime HOF implementation.
        let needsHOFWrapper = sema.bindings.isCollectionHOFLambdaExpr(exprID)

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
        if let callTargetSymbol, isConstructorTarget {
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
            let wrapperParams = (closureParam.map { [$0] } ?? []) + valueParams

            var body: [KIRInstruction] = [.beginBlock]
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

            let constructedValue = driver.callLowerer.lowerResolvedCallBody(
                exprID,
                args: [],
                loweredArgIDs: callArgExprs,
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
                instructions: &body
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
                thrownResult: nil,
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
        } else if let callTargetSymbol, needsHOFWrapper {
            // Generate a HOF-ABI wrapper that delegates to the target function.
            callableSymbol = driver.ctx.syntheticLambdaSymbol(for: exprID)
            callableName = syntheticLambdaName(for: exprID, interner: interner)

            let targetName = callTargetName
                ?? callableTargetName(for: callTargetSymbol, sema: sema, interner: interner)
            let functionType = boundType.flatMap { typeID -> FunctionType? in
                guard case let .functionType(ft) = sema.types.kind(of: typeID) else { return nil }
                return ft
            }
            let valueParamTypes = functionType?.params ?? []
            let returnType = functionType?.returnType ?? sema.types.anyType

            // Build wrapper params: (closureRaw, value0, ..., valueN)
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
            let wrapperParams = [closureParam] + valueParams

            // Build wrapper body: call the target function with the value params,
            // then return its result.
            var body: [KIRInstruction] = [.beginBlock]
            var callArgExprs: [KIRExprID] = []
            // If the callable ref has a bound receiver, pass capture args first.
            for _ in captureArguments {
                let captureRef = arena.appendExpr(
                    .symbolRef(closureParam.symbol),
                    type: closureParam.type
                )
                body.append(.constValue(result: captureRef, value: .symbolRef(closureParam.symbol)))
                callArgExprs.append(captureRef)
            }
            for valueParam in valueParams {
                let paramExpr = arena.appendExpr(.symbolRef(valueParam.symbol), type: valueParam.type)
                body.append(.constValue(result: paramExpr, value: .symbolRef(valueParam.symbol)))
                let normalizedParamExpr = normalizeHOFPrimitiveParameter(
                    paramExpr,
                    type: valueParam.type,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &body,
                    isRawCallbackParameter: true
                )
                callArgExprs.append(normalizedParamExpr)
            }
            let callResult = arena.appendTemporary(type: returnType
            )
            body.append(.call(
                symbol: callTargetSymbol,
                callee: targetName,
                arguments: callArgExprs,
                result: callResult,
                canThrow: false,
                thrownResult: nil
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
        if needsHOFWrapper {
            if sema.bindings.callableRefKind(for: exprID) == .functionRef,
               case let .functionType(functionType) = sema.types.kind(of: callableType)
            {
                emitRawFunctionArityTag(
                    callableExpr, functionType: functionType, sema: sema,
                    arena: arena, interner: interner, instructions: &instructions
                )
            }
            return callableExpr
        }

        // Bound references need per-value storage: the same target pointer can
        // also represent an unbound reference with a different arity. Boxing
        // preserves the receiver when the value escapes the KIR callable table.
        let callableValue: KIRExprID
        if !captureArguments.isEmpty,
           case let .functionType(functionType) = sema.types.kind(of: callableType),
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

    // MARK: - REFL-003: Callable reference type identity

    /// Emits a runtime tagging call that annotates a callable reference value
    /// with KFunction or KProperty type identity. Returns a new KIR expression
    /// representing the tagged value.  The caller must use the returned
    /// expression (and register it for callable-value resolution) so that the
    /// tagged value propagates through the program.
    func emitCallableRefTypeTag(
        callableExpr: KIRExprID,
        callableType: TypeID,
        refKind: CallableRefKind,
        memberName: InternedString,
        targetSymbol: SymbolID? = nil,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        // Compute arity and isSuspend from the function type.
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

        // Emit the name string literal.
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

        // Emit the arity literal.
        let arityExpr = arena.appendExpr(.intLiteral(arity), type: sema.types.intType)
        instructions.append(.constValue(result: arityExpr, value: .intLiteral(arity)))

        // Choose the tagging callee based on callable reference kind.
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

        // Emit the tagging call.
        let taggedExpr = arena.appendTemporary(type: callableType
        )
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(tagCallee),
            arguments: tagArguments,
            result: taggedExpr,
            canThrow: false,
            thrownResult: nil
        ))
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
}
