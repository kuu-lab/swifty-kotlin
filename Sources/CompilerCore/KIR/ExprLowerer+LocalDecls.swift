extension ExprLowerer {
    func lowerLocalFunDecl(
        name localFunName: InternedString,
        valueParams localFunValueParams: [ValueParamDecl],
        body localFunBody: FunctionBody,
        isTailrec: Bool,
        exprID: ExprID,
        boundType: TypeID?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        if let symbol = sema.bindings.identifierSymbols[exprID] {
            let sig = sema.symbols.functionSignature(for: symbol)
            let funType: TypeID = if let sig {
                sema.types.make(.functionType(FunctionType(
                    contextReceivers: sig.contextParameterTypes,
                    receiver: sig.receiverType,
                    params: sig.parameterTypes,
                    returnType: sig.returnType,
                    isSuspend: sig.isSuspend,
                    nullability: .nonNull
                )))
            } else {
                boundType ?? sema.types.anyType
            }
            let funRef = arena.appendExpr(.symbolRef(symbol), type: funType)
            instructions.append(.constValue(result: funRef, value: .symbolRef(symbol)))
            driver.ctx.setLocalValue(funRef, for: symbol)

            let localFunCalleeName = driver.lambdaLowerer.callableTargetName(for: symbol, sema: sema, interner: interner)
            if isTailrec { driver.ctx.markTailrecFunction(symbol) }

            let localFunValueParamList: [KIRParameter]
            let localFunContextParamList = sig.map { signature in
                zip(signature.contextParameterSymbols, signature.contextParameterTypes).map { symbol, type in
                    KIRParameter(symbol: symbol, type: type)
                }
            } ?? []
            let localFunReceiverParam = sig?.receiverType.map {
                KIRParameter(symbol: SyntheticSymbolScheme.receiverParameterSymbol(for: symbol), type: $0)
            }
            let localFunReturnType: TypeID
            if let sig {
                localFunValueParamList = zip(sig.valueParameterSymbols, sig.parameterTypes).map { pair in
                    // Sema records the body type for packed vararg parameters;
                    // the signature still carries their individual element type.
                    KIRParameter(
                        symbol: pair.0,
                        type: sema.symbols.propertyType(for: pair.0) ?? pair.1
                    )
                }
                localFunReturnType = sig.returnType
            } else {
                localFunValueParamList = localFunValueParams.indices.map { index in
                    KIRParameter(
                        symbol: driver.lambdaLowerer.syntheticLambdaParamSymbol(lambdaExprID: exprID, paramIndex: index),
                        type: sema.types.anyType
                    )
                }
                localFunReturnType = sema.types.unitType
            }

            var captureBodyExprIDs: [ExprID] = []
            switch localFunBody {
            case let .block(bodyExprIDs, _):
                captureBodyExprIDs = bodyExprIDs
            case let .expr(bodyExprID, _):
                captureBodyExprIDs = [bodyExprID]
            case .unit:
                break
            }
            // Default expressions are evaluated in the lifted function's lexical scope too.
            captureBodyExprIDs.append(contentsOf: localFunValueParams.compactMap(\.defaultValue))

            var referencedSymbols: [SymbolID] = []
            var seenSymbols: Set<SymbolID> = []
            for bodyExprID in captureBodyExprIDs {
                driver.lambdaLowerer.collectBoundIdentifierSymbols(
                    in: bodyExprID,
                    ast: ast,
                    sema: sema,
                    referenced: &referencedSymbols,
                    seen: &seenSymbols
                )
            }
            let localFunParamSymbols = Set(
                ((localFunReceiverParam.map { [$0] } ?? []) + localFunContextParamList + localFunValueParamList)
                    .map(\.symbol)
            )
            var captureSymbols = referencedSymbols.filter { sym in
                if localFunParamSymbols.contains(sym) { return false }
                if sym == symbol { return false }
                if driver.ctx.localDelegateStorage(for: sym) != nil { return true }
                if sym == driver.ctx.activeImplicitReceiverSymbol(),
                   driver.ctx.activeImplicitReceiverExprID() != nil { return true }
                guard let referencedSymbol = sema.symbols.symbol(sym),
                      referencedSymbol.kind == .local
                        || referencedSymbol.kind == .valueParameter
                        || referencedSymbol.flags.contains(.localFunction)
                else {
                    return false
                }
                return driver.ctx.localValue(for: sym) != nil
            }

            // Explicit this/super and implicit member accesses do not
            // collect the receiver in collectBoundIdentifierSymbols, so check separately —
            // mirrors the post-filter in lexicalCaptureSymbolsForLambda.
            if localFunReceiverParam == nil,
               let receiverSymbol = driver.ctx.activeImplicitReceiverSymbol(),
               driver.ctx.activeImplicitReceiverExprID() != nil,
               !captureSymbols.contains(receiverSymbol)
            {
                let needsReceiver = captureBodyExprIDs.contains { bodyExprID in
                    driver.lambdaLowerer.containsImplicitReceiverReference(in: bodyExprID, ast: ast)
                        || driver.lambdaLowerer.containsImplicitReceiverMemberAccess(
                            in: bodyExprID, ast: ast, sema: sema,
                            excludingLocalExtensionBodies: true
                        )
                }
                if needsReceiver {
                    captureSymbols.append(receiverSymbol)
                }
            }

            // Transitive capture: if a captured symbol is a callable with
            // its own captures, also capture those dependencies so call
            // sites inside the body can forward correct capture arguments.
            // Build a deterministic reverse map (KIRExprID → SymbolID) from
            // current local bindings so we avoid nondeterministic Dictionary
            // iteration with first(where:).
            var exprIDToSymbol: [KIRExprID: SymbolID] = [:]
            for (sym, expr) in driver.ctx.allLocalValues() {
                exprIDToSymbol[expr] = sym
            }
            var transitiveChanged = true
            while transitiveChanged {
                transitiveChanged = false
                for sym in captureSymbols {
                    guard let outerExpr = driver.ctx.localValue(for: sym),
                          let callableInfo = driver.ctx.callableValueInfo(for: outerExpr)
                    else {
                        continue
                    }
                    for captureArg in callableInfo.captureArguments {
                        var transitiveSym: SymbolID?
                        if let found = exprIDToSymbol[captureArg] {
                            transitiveSym = found
                        } else if case let .symbolRef(argSym) = arena.expr(captureArg) {
                            transitiveSym = argSym
                        } else if captureArg == driver.ctx.activeImplicitReceiverExprID() {
                            transitiveSym = driver.ctx.activeImplicitReceiverSymbol()
                        }
                        if let transitiveSym, !captureSymbols.contains(transitiveSym) {
                            captureSymbols.append(transitiveSym)
                            transitiveChanged = true
                        }
                    }
                }
            }

            var captureBindings: [(capturedSymbol: SymbolID, param: KIRParameter, valueExpr: KIRExprID, declaredType: TypeID)] = []
            captureBindings.reserveCapacity(captureSymbols.count)
            for (index, capturedSymbol) in captureSymbols.enumerated() {
                let declaredType = driver.ctx.localDeclaredType(for: capturedSymbol)
                    ?? driver.ctx.localValue(for: capturedSymbol).flatMap { arena.exprType($0) }
                    ?? driver.lambdaLowerer.typeForSymbolReference(capturedSymbol, sema: sema)
                if let semanticSymbol = sema.symbols.symbol(capturedSymbol),
                   semanticSymbol.kind == .local,
                   semanticSymbol.flags.contains(.mutable)
                {
                    _ = ensureMutableCaptureCell(
                        for: capturedSymbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                }
                guard let captureValue = driver.lambdaLowerer.captureValueExpr(
                    for: capturedSymbol,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                ) else {
                    continue
                }
                let captureType = arena.exprType(captureValue) ?? driver.lambdaLowerer.typeForSymbolReference(capturedSymbol, sema: sema)
                let captureParamSymbol = driver.lambdaLowerer.syntheticLambdaCaptureParamSymbol(
                    lambdaExprID: exprID,
                    captureIndex: index
                )
                let captureParam = KIRParameter(symbol: captureParamSymbol, type: captureType)
                captureBindings.append((
                    capturedSymbol: capturedSymbol,
                    param: captureParam,
                    valueExpr: captureValue,
                    declaredType: declaredType
                ))
            }

            driver.ctx.registerCallableValue(
                funRef,
                symbol: symbol,
                callee: localFunCalleeName,
                captureArguments: captureBindings.map(\.valueExpr)
            )
            let hasNonLocalLoopJump = sema.bindings.loopJumpLambdaPaths.values.contains {
                $0.contains(exprID)
            }
            if hasNonLocalLoopJump, !captureBindings.isEmpty {
                arena.registerLambdaCaptureArgs(
                    symbol,
                    captureArgs: captureBindings.map(\.valueExpr)
                )
            }

            let scopeSnapshot = driver.ctx.saveScope()
            let boxedCaptureSymbols = Set(
                captureBindings.compactMap { binding in
                    driver.ctx.isMutableCaptureBoxed(binding.capturedSymbol) ? binding.capturedSymbol : nil
                }
            )
            let savedReceiverSymbol = scopeSnapshot.currentImplicitReceiverSymbol
            defer { driver.ctx.restoreScope(scopeSnapshot) }
            driver.ctx.resetScopeForFunction()
            driver.ctx.currentLambdaAllowsNonLocalBreakContinue = hasNonLocalLoopJump
            if hasNonLocalLoopJump {
                driver.ctx.enclosingLoopControlStack = scopeSnapshot.enclosingLoopControlStack
                    + scopeSnapshot.loopControlStack
                driver.ctx.nextLoopLabel = max(scopeSnapshot.nextLoopLabel, 10000)
            }

            var localFunBodyInstructions: [KIRInstruction] = [.beginBlock]

            for capture in captureBindings {
                let captureExpr = arena.appendExpr(.symbolRef(capture.param.symbol), type: capture.param.type)
                localFunBodyInstructions.append(.constValue(result: captureExpr, value: .symbolRef(capture.param.symbol)))
                if sema.symbols.delegateGetValueSymbol(for: capture.capturedSymbol) != nil {
                    driver.ctx.setLocalDelegateStorage(captureExpr, for: capture.capturedSymbol)
                } else if boxedCaptureSymbols.contains(capture.capturedSymbol) {
                    driver.ctx.setMutableCaptureCell(captureExpr, for: capture.capturedSymbol)
                } else {
                    driver.ctx.setLocalValue(captureExpr, for: capture.capturedSymbol)
                }
                driver.ctx.setLocalDeclaredType(capture.declaredType, for: capture.capturedSymbol)
                if capture.capturedSymbol == savedReceiverSymbol {
                    driver.ctx.setImplicitReceiver(symbol: capture.param.symbol, exprID: captureExpr)
                }
            }

            for param in localFunValueParamList {
                let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
                localFunBodyInstructions.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
                driver.ctx.setLocalValue(paramExpr, for: param.symbol)
            }
            var localContextReceiverValues: [KIRLoweringContext.ContextReceiverValue] = []
            for param in localFunContextParamList {
                let contextExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
                localFunBodyInstructions.append(.constValue(result: contextExpr, value: .symbolRef(param.symbol)))
                driver.ctx.setLocalDeclaredType(param.type, for: param.symbol)
                driver.ctx.setLocalValue(contextExpr, for: param.symbol)
                localContextReceiverValues.append(
                    KIRLoweringContext.ContextReceiverValue(type: param.type, exprID: contextExpr)
                )
            }
            if let param = localFunReceiverParam {
                let receiverExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
                localFunBodyInstructions.append(.constValue(result: receiverExpr, value: .symbolRef(param.symbol)))
                driver.ctx.setLocalValue(receiverExpr, for: param.symbol)
                driver.ctx.setImplicitReceiver(symbol: param.symbol, exprID: receiverExpr)
            }

            // Propagate callable value info for captured callables so that
            // calls inside the body find correct capture arguments.
            // Build a direct outer-expr → body-expr mapping from capture
            // bindings. This works for any expression kind (symbolRef,
            // intLiteral, etc.) without needing reverse lookups.
            var outerExprToBodyExpr: [KIRExprID: KIRExprID] = [:]
            for capture in captureBindings {
                if let bodyExpr = driver.ctx.localValue(for: capture.capturedSymbol) {
                    outerExprToBodyExpr[capture.valueExpr] = bodyExpr
                }
            }
            for capture in captureBindings {
                if let outerCallableInfo = driver.ctx.callableValueInfo(for: capture.valueExpr),
                   let bodyCallableExpr = driver.ctx.localValue(for: capture.capturedSymbol)
                {
                    var remappedArgs: [KIRExprID] = []
                    var mappingFailed = false
                    for argExpr in outerCallableInfo.captureArguments {
                        if let bodyArgExpr = outerExprToBodyExpr[argExpr] {
                            remappedArgs.append(bodyArgExpr)
                        } else if case let .symbolRef(argSym) = arena.expr(argExpr),
                                  let bodyArgExpr = driver.ctx.localValue(for: argSym)
                        {
                            remappedArgs.append(bodyArgExpr)
                        } else {
                            assertionFailure("BuildKIRPhase: failed to remap capture argument for local function body")
                            mappingFailed = true
                            break
                        }
                    }
                    if !mappingFailed {
                        driver.ctx.registerCallableValue(
                            bodyCallableExpr,
                            symbol: outerCallableInfo.symbol,
                            callee: outerCallableInfo.callee,
                            captureArguments: remappedArgs
                        )
                    }
                }
            }

            // Re-register the local function symbol inside its own body
            // so that recursive calls resolve correctly with capture arguments.
            // Inside the body, capture arguments reference the capture *parameters*
            // (not the outer values) since we're in the body's scope.
            let bodyFunRef = arena.appendExpr(.symbolRef(symbol), type: funType)
            localFunBodyInstructions.append(.constValue(result: bodyFunRef, value: .symbolRef(symbol)))
            driver.ctx.setLocalValue(bodyFunRef, for: symbol)
            let recursiveCaptureArguments: [KIRExprID] = captureBindings.map { binding in
                guard let value = driver.ctx.localValue(for: binding.capturedSymbol)
                    ?? driver.ctx.localDelegateStorage(for: binding.capturedSymbol)
                else {
                    preconditionFailure("BuildKIRPhase: missing capture binding for recursive local function '\(symbol)'")
                }
                return value
            }
            driver.ctx.registerCallableValue(
                bodyFunRef,
                symbol: symbol,
                callee: localFunCalleeName,
                captureArguments: recursiveCaptureArguments
            )

            driver.ctx.withContextReceiverValues(localContextReceiverValues) {
            switch localFunBody {
            case let .block(bodyExprIDs, _):
                var lastValue: KIRExprID?
                var terminatedByReturn = false
                for bodyExprID in bodyExprIDs {
                    if let bodyExpr = ast.arena.expr(bodyExprID),
                       case let .returnExpr(value, _, _) = bodyExpr
                    {
                        if let value {
                            let lowered = lowerExpr(
                                value,
                                ast: ast,
                                sema: sema,
                                arena: arena,
                                interner: interner,
                                propertyConstantInitializers: propertyConstantInitializers,
                                instructions: &localFunBodyInstructions
                            )
                            localFunBodyInstructions.append(.returnValue(lowered))
                        } else {
                            localFunBodyInstructions.append(.returnUnit)
                        }
                        terminatedByReturn = true
                        break
                    }
                    if let bodyExpr = ast.arena.expr(bodyExprID),
                       case .throwExpr = bodyExpr
                    {
                        _ = lowerExpr(
                            bodyExprID,
                            ast: ast,
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            propertyConstantInitializers: propertyConstantInitializers,
                            instructions: &localFunBodyInstructions
                        )
                        terminatedByReturn = true
                        break
                    }
                    lastValue = lowerExpr(
                        bodyExprID,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &localFunBodyInstructions
                    )
                    if let lastValue, driver.controlFlowLowerer.isTerminatedExpr(lastValue, arena: arena, sema: sema) {
                        terminatedByReturn = true
                        break
                    }
                }
                if !terminatedByReturn {
                    if let lastValue {
                        localFunBodyInstructions.append(.returnValue(lastValue))
                    } else {
                        localFunBodyInstructions.append(.returnUnit)
                    }
                }
            case let .expr(bodyExprID, _):
                let value = lowerExpr(
                    bodyExprID,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &localFunBodyInstructions
                )
                localFunBodyInstructions.append(.returnValue(value))
            case .unit:
                localFunBodyInstructions.append(.returnUnit)
            }
            }
            localFunBodyInstructions.append(.endBlock)

            let isTailrec = ast.arena.isLocalTailrecFunction(exprID)
            if isTailrec { driver.ctx.markTailrecFunction(symbol) }
            let localFunDeclID = arena.appendDecl(
                .function(
                    KIRFunction(
                        symbol: symbol,
                        name: localFunName,
                        params: captureBindings.map(\.param) + (localFunReceiverParam.map { [$0] } ?? [])
                            + localFunContextParamList + localFunValueParamList,
                        returnType: localFunReturnType,
                        body: localFunBodyInstructions,
                        isSuspend: sig?.isSuspend ?? false,
                        isInline: hasNonLocalLoopJump,
                        isInlineOnly: hasNonLocalLoopJump,
                        isTailrec: isTailrec
                    )
                )
            )
            driver.ctx.appendGeneratedCallableDecl(localFunDeclID)

            // Call sites route an omitted-argument call through `<name>$default`;
            // top-level/member functions get that stub from module lowering, but
            // a local function is only reachable from here.
            let localFunDefaults = localFunValueParams.map(\.defaultValue)
            if let sig, localFunDefaults.contains(where: { $0 != nil }) {
                let stubID = driver.callSupportLowerer.generateDefaultStubFunction(
                    originalSymbol: symbol,
                    originalName: localFunName,
                    signature: sig,
                    defaultExpressions: localFunDefaults,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    captures: captureBindings.map { binding in
                        DefaultStubCapture(
                            capturedSymbol: binding.capturedSymbol,
                            param: binding.param,
                            isBoxedMutable: boxedCaptureSymbols.contains(binding.capturedSymbol)
                        )
                    }
                )
                driver.ctx.appendGeneratedCallableDecl(stubID)
            }
        }
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    func lowerLocalDecl(
        isMutable: Bool,
        initializer: ExprID?,
        isDelegated: Bool,
        exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        if let initializer {
            let initializerID = lowerExpr(
                initializer,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let symbol = sema.bindings.identifierSymbols[exprID] {
                // Local delegated declaration (custom and, since KSP-491, the
                // stdlib factories lazy/Delegates.observable/vetoable/notNull
                // alike -- they all resolve getValue/setValue through the same
                // operator convention now). `initializer`'s own AST shape here
                // (unlike a member/top-level PropertyDecl's `delegateExpression`)
                // already includes any trailing lambda as a normal call
                // argument, so `lowerExpr` above already invoked the real
                // factory correctly.
                let isCustomDelegateDecl = isDelegated
                    && sema.symbols.delegateGetValueSymbol(for: symbol) != nil
                if isCustomDelegateDecl {
                    // Local delegate declaration (custom, and since KSP-491 the
                    // stdlib factories lazy/Delegates.observable/vetoable/notNull
                    // alike): binds `x`'s storage to the delegate *instance*
                    // (`Prop()`/`LazyImpl(...)`/...), not its value -- unlike a
                    // plain local, `x`'s getValue runs at each *read* site (see
                    // below), not here, which is what keeps `val x by lazy { ... }`'s
                    // initializer deferred until `x` is first read (BUG-014 /
                    // KSP-CAP-007's fix for the read side predates this; this
                    // declaration-site half only resolves the delegate object).
                    //
                    // provideDelegate (BUG-146): when the delegate exposes a
                    // `provideDelegate` operator, the *effective* delegate is
                    // its return value, mirroring member/top-level lowering in
                    // KIRLoweringDriver+ProvideDelegate.swift. Call
                    // `Factory().provideDelegate(null, KProperty("x"))` first and
                    // resolve getValue/setValue against that result (Sema already
                    // recorded getValue/setValue for the effective delegate type
                    // via DeclTypeChecker.typeCheckDelegate).
                    let effectiveDelegateID = lowerLocalProvideDelegateIfNeeded(
                        symbol: symbol,
                        rawDelegateID: initializerID,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    driver.ctx.setLocalDelegateStorage(effectiveDelegateID, for: symbol)
                    let propertyType = sema.symbols.propertyType(for: symbol)
                        ?? arena.exprType(effectiveDelegateID)
                        ?? sema.types.anyType
                    driver.ctx.setLocalDeclaredType(propertyType, for: symbol)
                } else {
                    let initializerType = arena.exprType(initializerID)
                    // Prefer the symbol's Sema-recorded declared type over the
                    // initializer's own type: an explicit widening annotation
                    // (e.g. `val x: Any = 42L`) records `Any` on the symbol while
                    // the literal's own arena type stays `Long`. Falling back to
                    // the initializer's type here would silently drop the
                    // widening, leaving the local aliased to an unboxed literal
                    // register.
                    let declaredType = (isDelegated ? nil : sema.symbols.propertyType(for: symbol))
                        ?? initializerType
                        ?? driver.lambdaLowerer.typeForSymbolReference(symbol, sema: sema)
                    driver.ctx.setLocalDeclaredType(declaredType, for: symbol)
                    // Nullable Unit also needs its declared slot type: a null
                    // initializer must not leave storage typed as Nothing? after
                    // later writes of the raw Unit value.
                    // Reference-like declared locals need a slot typed to the
                    // declaration rather than an alias to the initializer. This
                    // keeps later assignments (e.g. String -> Int in Any) in the
                    // same erased storage and lets ABILoweringPass apply the
                    // correct boxing at each copy. Nullable primitives whose
                    // raw payload can collide with the null sentinel need the
                    // same treatment: aliasing a raw `Long` initializer would
                    // leave sentinel-equal bits in the `Long?` slot, which
                    // every null check then reads as `null` (KUU-854).
                    let declaredTypeIsReferenceLike: Bool = switch sema.types.kind(of: declaredType) {
                    // String has its own aggregate kind instead of `.classType`.
                    // It still needs declared-type storage when a nullable local
                    // starts as `null`, so later assignments update the local slot.
                    case .nullableUnit, .platformUnit, .any, .classType, .functionType, .stringStruct, .typeParam:
                        true
                    default:
                        false
                    }
                    let declaredTypeIsNullablePrimitive: Bool = {
                        // Every nullable primitive slot must hold a box
                        // handle (or the null sentinel), never the raw
                        // scalar: `===` on `P?` operands is JVM reference
                        // equality on the boxed value, which only works
                        // when the slot representation is the box
                        // (KUU-1385). Sentinel-colliding kinds (Long?,
                        // ULong?, Double?, Float?) needed this already;
                        // the remaining kinds join them now.
                        guard case let .primitive(_, nullability) = sema.types.kind(of: declaredType) else {
                            return false
                        }
                        return nullability != .nonNull
                    }()
                    // A mutable local initialized directly from a bare symbol
                    // reference (an enum entry or object singleton, e.g. `var d:
                    // Direction = Direction.NORTH`) must not alias its storage to
                    // that exact expression. `arena.expr` never changes once
                    // recorded, so a later reassignment (`d = Direction.SOUTH`)
                    // only patches the runtime bits in place via `.copy` — any
                    // fold that pattern-matches the storage's static `.symbolRef`
                    // shape (e.g. enum `.name`/`.ordinal` constant-folding in
                    // tryLowerEnumEntryPropertyRead) would keep resolving to the
                    // *initial* entry forever, regardless of the reassignment.
                    let initializerIsBareSymbolRef: Bool = {
                        if case .symbolRef = arena.expr(initializerID) { return true }
                        return false
                    }()
                    let requiresFreshSlotForMutableAlias = isMutable
                        && declaredTypeIsReferenceLike
                        && initializerIsBareSymbolRef
                    if !isDelegated,
                       declaredTypeIsReferenceLike || declaredTypeIsNullablePrimitive,
                       (initializerType != nil && initializerType != declaredType)
                       || requiresFreshSlotForMutableAlias
                    {
                        let localSlot = arena.appendTemporary(type: declaredType)
                        instructions.append(.copy(from: initializerID, to: localSlot))
                        driver.ctx.setLocalValue(localSlot, for: symbol)
                        if let callableInfo = driver.ctx.callableValueInfo(for: initializerID) {
                            driver.ctx.callableValueInfoByExprID[localSlot] = callableInfo
                        }
                    } else if !isDelegated, isBareVariableRead(initializer, ast: ast) {
                        // `val a = b` must snapshot `b`'s current value. Binding the
                        // new local directly to the initializer register would alias
                        // the two, so a later in-place update of `b` (`b += 1`, which
                        // copies into the same register) would retroactively change
                        // `a` as well.
                        let localSlot = arena.appendTemporary(type: declaredType)
                        instructions.append(.copy(from: initializerID, to: localSlot))
                        driver.ctx.setLocalValue(localSlot, for: symbol)
                        if let callableInfo = driver.ctx.callableValueInfo(for: initializerID) {
                            driver.ctx.callableValueInfoByExprID[localSlot] = callableInfo
                        }
                    } else {
                        driver.ctx.setLocalValue(initializerID, for: symbol)
                    }
                    if isMutable, !isDelegated, isCapturedByLambda(symbol, sema: sema) {
                        // The cell must dominate every possible capture.
                        // Allocating it at the first lowered lambda leaves
                        // sibling branches using an uninitialized cell.
                        _ = ensureMutableCaptureCell(
                            for: symbol,
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &instructions
                        )
                    }
                }
            }
        } else if let symbol = sema.bindings.identifierSymbols[exprID] {
            let declaredType = driver.lambdaLowerer.typeForSymbolReference(symbol, sema: sema)
            driver.ctx.setLocalDeclaredType(declaredType, for: symbol)
            // No initializer (e.g. `lateinit var f: (Int) -> Int`): a
            // lambda capturing `f` before its first real assignment --
            // a self-referential closure such as `f = { ... f(...) ... }`
            // -- needs `f`'s mutable-capture cell to already exist so it
            // can capture a reference to it, but `ensureMutableCaptureCell`
            // requires a current value to seed the cell with. Seed a
            // transient null placeholder for that case only (mutable,
            // reference-like, and actually captured), mirroring how a
            // lateinit *property*'s backing storage is seeded with `.null`
            // in lowerPropertyInitializer. Scoped this narrowly because a
            // primitive local's `.null` representation is a distinct
            // sentinel (see `declaredTypeIsReferenceLike` above), not a
            // plain null constant. Other uninitialized mutable locals retain
            // their existing first-assignment and capture-cell paths;
            // immutable locals receive a shared slot below so branch
            // assignments survive joins.
            let declaredTypeIsReferenceLike: Bool = switch sema.types.kind(of: declaredType) {
            case .any, .classType, .functionType, .typeParam:
                true
            default:
                false
            }
            if !isMutable, !isDelegated {
                // A definitely-assigned `val` may be written in mutually
                // exclusive branches. Keep one stable slot so each branch
                // stores to the same target and reads after the join observe
                // the value from the branch that ran. Sema remains responsible
                // for rejecting reads before the first assignment.
                let localSlot = arena.appendTemporary(type: declaredType)
                driver.ctx.setLocalValue(localSlot, for: symbol)
                if sema.bindings.isContractCallsInPlaceInitializedSymbol(symbol),
                   isCapturedByLambda(symbol, sema: sema)
                {
                    // Sema approved deferred initialization inside a callback.
                    // Allocate its shared cell before capture without reading an
                    // undefined slot; Sema prevents observing the seed value.
                    let seed = deferredLocalCaptureCellSeedValue(
                        for: declaredType, sema: sema, arena: arena, instructions: &instructions
                    )
                    instructions.append(.copy(from: seed, to: localSlot))
                    emitMutableCaptureCellInitialization(
                        driver: driver, symbol: symbol, currentValue: localSlot,
                        sema: sema, arena: arena, interner: interner, instructions: &instructions
                    )
                }
            }
            if sema.symbols.symbol(symbol)?.flags.contains(.lateinitProperty) == true {
                // Store the raw null sentinel. Creating a closure captures
                // the shared cell without reading/checking its contents.
                let sentinel = arena.appendExpr(.null, type: declaredType)
                instructions.append(.constValue(result: sentinel, value: .null))
                let storage = arena.appendTemporary(type: declaredType)
                instructions.append(.copy(from: sentinel, to: storage))
                driver.ctx.setLocalValue(storage, for: symbol)
                if isMutable, isCapturedByLambda(symbol, sema: sema) {
                    _ = ensureMutableCaptureCell(
                        for: symbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                }
            } else if isMutable, declaredTypeIsReferenceLike, isCapturedByLambda(symbol, sema: sema) {
                let placeholder = arena.appendExpr(.null, type: declaredType)
                instructions.append(.constValue(result: placeholder, value: .null))
                driver.ctx.setLocalValue(placeholder, for: symbol)
                _ = ensureMutableCaptureCell(
                    for: symbol,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
            }
        }
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    func lowerDestructuringDecl(
        names: [InternedString?],
        initializer: ExprID,
        exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let rhsID = lowerExpr(
            initializer, ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers, instructions: &instructions
        )
        let rhsType = sema.bindings.exprTypes[initializer] ?? sema.types.anyType
        let nonNullRhsType = sema.types.makeNonNullable(rhsType)
        for (index, name) in names.enumerated() {
            if let propertyBinding = sema.bindings.destructuringProperty(for: exprID, index: index) {
                let propertyResult = driver.callLowerer.lowerDestructuringPropertyRead(
                    propertyBinding,
                    receiverExpr: initializer,
                    receiverType: nonNullRhsType,
                    loweredReceiverID: rhsID,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                if let name {
                    let symbols = sema.symbols.lookupAll(fqName: [
                        interner.intern("__destructuring_\(exprID.rawValue)"),
                        name,
                    ])
                    if let symbol = symbols.first {
                        driver.ctx.setLocalValue(propertyResult, for: symbol)
                    }
                }
                continue
            }
            guard let name else {
                continue
            }
            let componentIndex = index + 1
            let componentName = interner.intern("component\(componentIndex)")

            let memberCandidates = TypeCheckHelpers().collectMemberFunctionCandidates(
                named: componentName,
                receiverType: nonNullRhsType,
                sema: sema,
                interner: interner
            )
            // Sema's chosen callee wins: `componentN` is an overloaded name across
            // Pair/Triple, user extensions and bundled stdlib extensions, so the
            // symbol has to travel to codegen instead of being re-resolved by name.
            let chosenCallee = sema.bindings.destructuringComponentCallee(
                for: exprID,
                index: index
            ) ?? memberCandidates.first
            let calleeName: InternedString = if let chosenCallee,
                                                let linkName = sema.symbols.externalLinkName(for: chosenCallee),
                                                !linkName.isEmpty
            {
                interner.intern(linkName)
            } else {
                componentName
            }

            // Look up the symbol defined by Sema for this variable first,
            // so we can use its per-component type (not the expression-level Unit type)
            let candidates = sema.symbols.lookupAll(fqName: [
                interner.intern("__destructuring_\(exprID.rawValue)"),
                name,
            ])
            let componentType = candidates.first.flatMap { sema.symbols.propertyType(for: $0) } ?? sema.types.anyType
            let componentResult = arena.appendTemporary(type: componentType)
            let calleeSymbol: SymbolID? = chosenCallee.flatMap { callee in
                sema.symbols.isSourceBackedSymbol(callee) ? callee : nil
            }
            driver.callLowerer.emitDestructuringComponentCall(
                candidate: chosenCallee,
                symbol: calleeSymbol,
                callee: calleeName,
                receiverExpr: initializer,
                receiverID: rhsID,
                result: componentResult,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )

            if let symbol = candidates.first {
                driver.ctx.setLocalValue(componentResult, for: symbol)
            }
        }
        let unit = arena.appendExpr(.unit, type: sema.types.unitType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }
}
