
// MARK: - Pre-interned runtime names for delegate rewriting

private struct DelegateRuntimeNames {
    let getValueName: InternedString
    let setValueName: InternedString
    let lazyGetValue: InternedString
    let observableGetValue: InternedString
    let vetoableGetValue: InternedString
    let notNullGetValue: InternedString
    let observableSetValue: InternedString
    let vetoableSetValue: InternedString
    let notNullSetValue: InternedString

    init(interner: StringInterner) {
        getValueName = interner.intern("getValue")
        setValueName = interner.intern("setValue")
        lazyGetValue = interner.intern("kk_lazy_get_value")
        observableGetValue = interner.intern("kk_observable_get_value")
        vetoableGetValue = interner.intern("kk_vetoable_get_value")
        notNullGetValue = interner.intern("kk_notNull_get_value")
        observableSetValue = interner.intern("kk_observable_set_value")
        vetoableSetValue = interner.intern("kk_vetoable_set_value")
        notNullSetValue = interner.intern("kk_notNull_set_value")
    }
}

extension KIRLoweringDriver {
    func postProcessTopLevelInitializersAndDelegates(
        ast: ASTModule,
        sema: SemaModule,
        compilationCtx: CompilationContext,
        arena: KIRArena,
        allTopLevelInitInstructions: KIRLoweringEmitContext,
        delegateStorageSymbolByPropertySymbol: [SymbolID: SymbolID]
    ) {
        guard !allTopLevelInitInstructions.isEmpty || !delegateStorageSymbolByPropertySymbol.isEmpty else { return }

        let interner = compilationCtx.interner
        let mainName = interner.intern("main")

        let delegateKindByPropertySymbol = buildDelegateKindMap(ast: ast, sema: sema, interner: interner)
        let names = DelegateRuntimeNames(interner: interner)

        arena.transformFunctions { function in
            var updated = function

            if function.name == mainName, !allTopLevelInitInstructions.isEmpty {
                updated.replaceBody(injectTopLevelInits(
                    body: function.body, inits: allTopLevelInitInstructions
                ))
            }

            if !delegateStorageSymbolByPropertySymbol.isEmpty {
                updated.replaceBody(rewriteDelegateAccesses(
                    body: updated.body, arena: arena, sema: sema,
                    storageMap: delegateStorageSymbolByPropertySymbol,
                    kindMap: delegateKindByPropertySymbol, names: names, interner: interner
                ))
            }

            return updated
        }
    }

    // MARK: - Top-Level Init Injection

    private func injectTopLevelInits(
        body: [KIRInstruction],
        inits: KIRLoweringEmitContext
    ) -> [KIRInstruction] {
        let offset = topLevelInitLabelOffset(body: body, inits: inits.instructions)
        var shiftedInits = inits
        if offset > 0 {
            shiftedInits.instructions = inits.instructions.map { shiftLabels(in: $0, by: offset) }
        }

        var newBody: KIRLoweringEmitContext = []
        if let first = body.first, case .beginBlock = first {
            newBody.append(first)
            newBody.append(contentsOf: shiftedInits)
            newBody.append(contentsOf: body.dropFirst())
        } else {
            newBody.append(contentsOf: shiftedInits)
            newBody.append(contentsOf: body)
        }
        return newBody.instructions
    }

    private func topLevelInitLabelOffset(body: [KIRInstruction], inits: [KIRInstruction]) -> Int32 {
        let bodyLabels = body.compactMap(labelID)
        let initLabels = inits.compactMap(labelID)
        guard let minInit = initLabels.min(), let maxBody = bodyLabels.max() else { return 0 }
        return max(maxBody + 1 - minInit, 0)
    }

    private func labelID(in instruction: KIRInstruction) -> Int32? {
        switch instruction {
        case let .label(id): return id
        case let .jump(target): return target
        case let .jumpIfEqual(_, _, target): return target
        case let .jumpIfNotNull(_, target): return target
        default: return nil
        }
    }

    private func shiftLabels(in instruction: KIRInstruction, by offset: Int32) -> KIRInstruction {
        switch instruction {
        case let .label(id): return .label(id + offset)
        case let .jump(target): return .jump(target + offset)
        case let .jumpIfEqual(lhs, rhs, target):
            return .jumpIfEqual(lhs: lhs, rhs: rhs, target: target + offset)
        case let .jumpIfNotNull(value, target):
            return .jumpIfNotNull(value: value, target: target + offset)
        default: return instruction
        }
    }

    // MARK: - Delegate Kind Map

    private func buildDelegateKindMap(
        ast: ASTModule, sema: SemaModule, interner: StringInterner
    ) -> [SymbolID: StdlibDelegateKind] {
        var map: [SymbolID: StdlibDelegateKind] = [:]

        func collect(from declID: DeclID) {
            guard let decl = ast.arena.decl(declID) else { return }
            switch decl {
            case let .propertyDecl(prop):
                guard let sym = sema.bindings.declSymbols[declID],
                      prop.delegateExpression != nil
                else { return }
                map[sym] = StdlibDelegateKind.detect(
                    delegateExpr: prop.delegateExpression,
                    ast: ast,
                    interner: interner
                )
            case let .classDecl(classDecl):
                for memberProperty in classDecl.memberProperties {
                    collect(from: memberProperty)
                }
                for nestedClass in classDecl.nestedClasses {
                    collect(from: nestedClass)
                }
                for nestedObject in classDecl.nestedObjects {
                    collect(from: nestedObject)
                }
            case let .objectDecl(objectDecl):
                for memberProperty in objectDecl.memberProperties {
                    collect(from: memberProperty)
                }
                for nestedClass in objectDecl.nestedClasses {
                    collect(from: nestedClass)
                }
                for nestedObject in objectDecl.nestedObjects {
                    collect(from: nestedObject)
                }
            case let .interfaceDecl(interfaceDecl):
                for memberProperty in interfaceDecl.memberProperties {
                    collect(from: memberProperty)
                }
                for nestedClass in interfaceDecl.nestedClasses {
                    collect(from: nestedClass)
                }
                for nestedObject in interfaceDecl.nestedObjects {
                    collect(from: nestedObject)
                }
            default:
                return
            }
        }

        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                collect(from: declID)
            }
        }
        return map
    }

    // MARK: - Delegate Access Rewriting

    private func rewriteDelegateAccesses(
        body: [KIRInstruction],
        arena: KIRArena,
        sema: SemaModule,
        storageMap: [SymbolID: SymbolID],
        kindMap: [SymbolID: StdlibDelegateKind],
        names: DelegateRuntimeNames,
        interner: StringInterner
    ) -> [KIRInstruction] {
        var fullStorageMap = storageMap
        for symbol in sema.symbols.allSymbols() where symbol.kind == .property {
            if let storageSymbol = sema.symbols.delegateStorageSymbol(for: symbol.id) {
                fullStorageMap[symbol.id] = storageSymbol
            }
        }
        var propertyByStorageSymbol: [SymbolID: SymbolID] = [:]
        for (propertySymbol, storageSymbol) in fullStorageMap {
            propertyByStorageSymbol[storageSymbol] = propertySymbol
        }
        // Pass 1: collect copy targets to distinguish getter vs setter paths.
        var copyTargetExprs: Set<KIRExprID> = []
        for instruction in body {
            if case let .copy(_, toExpr) = instruction { copyTargetExprs.insert(toExpr) }
        }

        // Pass 2: rewrite instructions.
        var targets: [KIRExprID: SymbolID] = [:]
        var result: KIRLoweringEmitContext = []
        result.reserveCapacity(body.count)

        for instruction in body {
            if case let .call(symbol, callee, arguments, callResult, _, _, _, _) = instruction,
               let storageSymbol = symbol,
               let propertySymbol = propertyByStorageSymbol[storageSymbol],
               callee == names.getValueName || callee == names.setValueName
            {
                if kindMap[propertySymbol] == .custom {
                    result.append(instruction)
                    continue
                }
                if callee == names.getValueName {
                    emitGetValue(
                        result: callResult ?? arena.appendTemporary(type: sema.types.anyType),
                        storageSym: storageSymbol,
                        propSym: propertySymbol,
                        kindMap: kindMap,
                        names: names,
                        arena: arena,
                        sema: sema,
                        body: &result
                    )
                } else {
                    let valueExpr = arguments.last ?? arena.appendExpr(.unit, type: sema.types.anyType)
                    emitSetValue(
                        fromExpr: valueExpr,
                        storageSym: storageSymbol,
                        kind: kindMap[propertySymbol],
                        names: names,
                        arena: arena,
                        sema: sema,
                        body: &result
                    )
                }
                continue
            }

            if case let .loadGlobal(res, sym) = instruction,
               let storageSym = fullStorageMap[sym]
            {
                if kindMap[sym] == .custom {
                    result.append(
                        .call(
                            symbol: SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: sym),
                            callee: interner.intern("get"),
                            arguments: [],
                            result: res,
                            canThrow: false,
                            thrownResult: nil
                        )
                    )
                    continue
                }
                emitGetValue(
                    result: res, storageSym: storageSym, propSym: sym,
                    kindMap: kindMap, names: names,
                    arena: arena, sema: sema, body: &result
                )
                continue
            }

            if case let .constValue(res, value) = instruction,
               case let .symbolRef(sym) = value,
               let storageSym = fullStorageMap[sym]
            {
                if kindMap[sym] == .custom {
                    if copyTargetExprs.contains(res) {
                        targets[res] = sym
                        result.append(instruction)
                    } else {
                        result.append(
                            .call(
                                symbol: SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: sym),
                                callee: interner.intern("get"),
                                arguments: [],
                                result: res,
                                canThrow: false,
                                thrownResult: nil
                            )
                        )
                    }
                    continue
                }
                if copyTargetExprs.contains(res) {
                    targets[res] = sym
                    result.append(instruction)
                } else {
                    emitGetValue(
                        result: res, storageSym: storageSym, propSym: sym,
                        kindMap: kindMap, names: names,
                        arena: arena, sema: sema, body: &result
                    )
                }
                continue
            }

            if case let .copy(fromExpr, toExpr) = instruction,
               let propSym = targets.removeValue(forKey: toExpr),
               let storageSym = fullStorageMap[propSym]
            {
                if kindMap[propSym] == .custom {
                    result.append(
                        .call(
                            symbol: SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propSym),
                            callee: interner.intern("set"),
                            arguments: [fromExpr],
                            result: nil,
                            canThrow: false,
                            thrownResult: nil
                        )
                    )
                    continue
                }
                if kindMap[propSym] == .lazy {
                    result.append(instruction)
                    continue
                }
                emitSetValue(
                    fromExpr: fromExpr, storageSym: storageSym,
                    kind: kindMap[propSym],
                    names: names, arena: arena, sema: sema, body: &result
                )
                continue
            }

            result.append(instruction)
        }
        return result.instructions
    }

    private func emitGetValue(
        result: KIRExprID, storageSym: SymbolID, propSym: SymbolID,
        kindMap: [SymbolID: StdlibDelegateKind], names: DelegateRuntimeNames,
        arena: KIRArena, sema: SemaModule, body: inout KIRLoweringEmitContext
    ) {
        let handle = arena.appendTemporary(type: sema.types.anyType
        )
        body.append(.loadGlobal(result: handle, symbol: storageSym))
        let name: InternedString = switch kindMap[propSym] {
        case .lazy: names.lazyGetValue
        case .observable: names.observableGetValue
        case .vetoable: names.vetoableGetValue
        case .notNull: names.notNullGetValue
        case .custom:
            preconditionFailure(
                "'.custom' delegate property access must be redirected to the property's " +
                    "own accessor symbol by rewriteDelegateAccesses before reaching emitGetValue"
            )
        case nil:
            preconditionFailure("delegate kind must be resolved by buildDelegateKindMap before reaching emitGetValue")
        }
        body.append(.call(
            symbol: nil,
            callee: name,
            arguments: [handle],
            result: result, canThrow: false, thrownResult: nil
        ))
    }

    private func emitSetValue(
        fromExpr: KIRExprID, storageSym: SymbolID, kind: StdlibDelegateKind?,
        names: DelegateRuntimeNames,
        arena: KIRArena, sema: SemaModule, body: inout KIRLoweringEmitContext
    ) {
        let handle = arena.appendTemporary(type: sema.types.anyType
        )
        body.append(.loadGlobal(result: handle, symbol: storageSym))
        let name: InternedString = switch kind {
        case .observable: names.observableSetValue
        case .vetoable: names.vetoableSetValue
        case .notNull: names.notNullSetValue
        case .lazy: preconditionFailure("lazy delegate setValue is not supported")
        case .custom:
            preconditionFailure(
                "'.custom' delegate property access must be redirected to the property's " +
                    "own accessor symbol by rewriteDelegateAccesses before reaching emitSetValue"
            )
        case nil:
            preconditionFailure("delegate kind must be resolved by buildDelegateKindMap before reaching emitSetValue")
        }
        let setResult = arena.appendTemporary(type: sema.types.anyType
        )
        body.append(.call(
            symbol: nil,
            callee: name,
            arguments: [handle, fromExpr],
            result: setResult, canThrow: false, thrownResult: nil
        ))
    }
}

extension KIRLoweringDriver {
    /// Creates a lambda function from the delegate body.
    ///
    /// DEBT-KIR-008: when this runs for a class member's `by lazy { ... }`
    /// initializer (`paramCount == 0`), the body may reference the enclosing
    /// instance (`label` implicitly reading `this.label`). The generated
    /// function is invoked later through `kk_lazy_create`'s stored function
    /// pointer, which cannot simply gain an extra KIR parameter — the caller
    /// (`RuntimeLazyBox.evaluateInitializer`) always invokes it through
    /// `kk_function_invoke_0`. That runtime entry point already dispatches
    /// between a raw thunk pointer and a boxed `Function0` closure value (see
    /// its doc comment), so a captured receiver is threaded in by materializing
    /// a closure object instead, mirroring
    /// `LambdaLowerer.materializeEscapingCallableValue`'s `(closureRaw) -> T`
    /// adapter pattern.
    ///
    /// Observable/vetoable callbacks use the same representation through
    /// `kk_function_invoke_3`: a non-capturing callback remains a raw thunk,
    /// while a member callback is a boxed Function3 carrying the receiver.
    func lowerDelegateLambdaBody(
        delegateBody: FunctionBody?,
        delegateBodyParams: [InternedString] = [],
        valueType: TypeID? = nil,
        propertySymbol: SymbolID,
        paramCount: Int,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let outerReceiver = ctx.activeImplicitReceiver()

        let scopeSnapshot = ctx.saveScope()
        defer { ctx.restoreScope(scopeSnapshot) }
        ctx.resetScopeForFunction()

        let lambdaSymbol = ctx.allocateSyntheticGeneratedSymbol()
        let lambdaName = interner.intern("kk_delegate_lambda_\(propertySymbol.rawValue)")

        var numberedParams: [KIRParameter] = []
        for i in 0 ..< paramCount {
            let paramSymbol = SyntheticSymbolScheme.delegateLambdaParameterSymbol(
                for: propertySymbol,
                at: i
            )
            // `(property, oldValue, newValue)`: only the two value parameters
            // carry the property's type; typing them keeps operations on them
            // (comparisons, string templates) from treating the raw value as an
            // untyped object handle.
            let paramType = i == 0 ? sema.types.anyType : (valueType ?? sema.types.anyType)
            numberedParams.append(KIRParameter(symbol: paramSymbol, type: paramType))
        }
        let receiverParam: KIRParameter? = outerReceiver.map { receiver in
            KIRParameter(
                symbol: ctx.allocateSyntheticGeneratedSymbol(),
                type: arena.exprType(receiver.exprID) ?? sema.types.anyType
            )
        }
        let params = (receiverParam.map { [$0] } ?? []) + numberedParams

        var lambdaBody: KIRLoweringEmitContext = [.beginBlock]
        if let receiverParam {
            let receiverExpr = arena.appendExpr(.symbolRef(receiverParam.symbol), type: receiverParam.type)
            lambdaBody.append(.constValue(result: receiverExpr, value: .symbolRef(receiverParam.symbol)))
            ctx.setImplicitReceiver(symbol: receiverParam.symbol, exprID: receiverExpr)
        }
        let underscore = interner.intern("_")
        // Names the callback lambda declared for its parameters
        // (`{ property, old, new -> ... }`) must resolve to the synthetic
        // parameters below while the body is lowered, then be restored so they
        // do not leak into the enclosing function's name scope.
        var savedParamBindings: [(name: InternedString, symbol: SymbolID?)] = []
        for (index, param) in numberedParams.enumerated() {
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            lambdaBody.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            ctx.setLocalValue(paramExpr, for: param.symbol)
            guard index < delegateBodyParams.count else { continue }
            let name = delegateBodyParams[index]
            guard name != underscore else { continue }
            savedParamBindings.append((name, ctx.lambdaParamSymbol(named: name)))
            ctx.registerLambdaParam(symbol: param.symbol, forName: name)
        }
        defer {
            for binding in savedParamBindings {
                ctx.restoreLambdaParam(symbol: binding.symbol, forName: binding.name)
            }
        }

        switch delegateBody {
        case let .block(exprIDs, _):
            var lastValue: KIRExprID?
            for exprID in exprIDs {
                lastValue = lowerExpr(exprID, shared: shared, emit: &lambdaBody)
            }
            if let lastValue {
                lambdaBody.append(.returnValue(lastValue))
            } else {
                lambdaBody.append(.returnUnit)
            }
        case let .expr(exprID, _):
            let value = lowerExpr(exprID, shared: shared, emit: &lambdaBody)
            lambdaBody.append(.returnValue(value))
        case .unit, nil:
            lambdaBody.append(.returnUnit)
        }
        lambdaBody.append(.endBlock)

        let lambdaDecl = arena.appendDecl(.function(KIRFunction(
            symbol: lambdaSymbol, name: lambdaName, params: params,
            returnType: sema.types.anyType, body: lambdaBody,
            isSuspend: false, isInline: false
        )))
        ctx.appendGeneratedCallableDecl(lambdaDecl)

        guard let outerReceiver else {
            let lambdaRefExpr = arena.appendExpr(.symbolRef(lambdaSymbol), type: sema.types.anyType)
            instructions.append(.constValue(result: lambdaRefExpr, value: .symbolRef(lambdaSymbol)))
            return lambdaRefExpr
        }
        return materializeCapturingDelegateLambda(
            innerLambdaSymbol: lambdaSymbol,
            innerLambdaName: lambdaName,
            receiverExpr: outerReceiver.exprID,
            valueParamTypes: numberedParams.map(\.type),
            returnType: sema.types.anyType,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    /// Wraps `innerLambdaSymbol` into a boxed function value carrying
    /// `receiverExpr` as captured state. The adapter receives the closure
    /// object followed by the delegate callback's regular arguments, reloads
    /// the receiver, and calls the inner function with both.
    private func materializeCapturingDelegateLambda(
        innerLambdaSymbol: SymbolID,
        innerLambdaName: InternedString,
        receiverExpr: KIRExprID,
        valueParamTypes: [TypeID],
        returnType: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let adapterSymbol = ctx.allocateSyntheticGeneratedSymbol()
        let adapterName = interner.intern("kk_delegate_lambda_adapter_\(adapterSymbol.rawValue)")
        let closureParam = KIRParameter(symbol: ctx.allocateSyntheticGeneratedSymbol(), type: sema.types.intType)
        let valueParams = valueParamTypes.map { type in
            KIRParameter(symbol: ctx.allocateSyntheticGeneratedSymbol(), type: type)
        }
        let captureOffset = Int64(2)

        var body: KIRLoweringEmitContext = [.beginBlock]
        let closureExpr = arena.appendExpr(.symbolRef(closureParam.symbol), type: closureParam.type)
        body.append(.constValue(result: closureExpr, value: .symbolRef(closureParam.symbol)))
        let valueExprs = valueParams.map { param in
            let expr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: expr, value: .symbolRef(param.symbol)))
            return expr
        }

        let receiverType = arena.exprType(receiverExpr) ?? sema.types.anyType
        let loadOffsetExpr = arena.appendExpr(.intLiteral(captureOffset), type: sema.types.intType)
        body.append(.constValue(result: loadOffsetExpr, value: .intLiteral(captureOffset)))
        let loadedReceiver = arena.appendTemporary(type: receiverType)
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_get_inbounds"),
            arguments: [closureExpr, loadOffsetExpr],
            result: loadedReceiver,
            canThrow: false,
            thrownResult: nil
        ))

        let callResult = arena.appendTemporary(type: returnType)
        body.append(.call(
            symbol: innerLambdaSymbol,
            callee: innerLambdaName,
            arguments: [loadedReceiver] + valueExprs,
            result: callResult,
            canThrow: false,
            thrownResult: nil
        ))
        body.append(.returnValue(callResult))
        body.append(.endBlock)

        let adapterDecl = arena.appendDecl(.function(KIRFunction(
            symbol: adapterSymbol, name: adapterName, params: [closureParam] + valueParams,
            returnType: returnType, body: body, isSuspend: false, isInline: false
        )))
        ctx.appendGeneratedCallableDecl(adapterDecl)

        let slotCountExpr = arena.appendExpr(.intLiteral(3), type: sema.types.intType)
        instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(3)))
        let classIDExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(0)))
        let closureObj = arena.appendTemporary(type: sema.types.intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: closureObj,
            canThrow: false,
            thrownResult: nil
        ))
        let storeOffsetExpr = arena.appendExpr(.intLiteral(captureOffset), type: sema.types.intType)
        instructions.append(.constValue(result: storeOffsetExpr, value: .intLiteral(captureOffset)))
        let setResult = arena.appendTemporary(type: sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [closureObj, storeOffsetExpr, receiverExpr],
            result: setResult,
            canThrow: true,
            thrownResult: nil
        ))

        let adapterExpr = arena.appendExpr(.symbolRef(adapterSymbol), type: sema.types.intType)
        instructions.append(.constValue(result: adapterExpr, value: .symbolRef(adapterSymbol)))
        let materializedExpr = arena.appendTemporary(type: sema.types.anyType)
        let createCallee: InternedString = switch valueParams.count {
        case 0: interner.intern("kk_function_create_0")
        case 1: interner.intern("kk_function_create_1")
        case 2: interner.intern("kk_function_create_2")
        case 3: interner.intern("kk_function_create_3")
        default: preconditionFailure("Unsupported delegate callback arity: \(valueParams.count)")
        }
        instructions.append(.call(
            symbol: nil,
            callee: createCallee,
            arguments: [adapterExpr, closureObj],
            result: materializedExpr,
            canThrow: false,
            thrownResult: nil
        ))
        return materializedExpr
    }

    /// Lowers the initial value argument from a delegate expression.
    func lowerDelegateInitialValue(
        delegateExpr: ExprID?,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena
        guard let exprID = delegateExpr,
              let expr = ast.arena.expr(exprID)
        else {
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.anyType)
            instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            return zeroExpr
        }

        switch expr {
        case let .call(_, _, args, _):
            if let firstArg = args.first {
                return lowerExpr(firstArg.expr, shared: shared, emit: &instructions)
            }
        case let .memberCall(_, _, _, args, _):
            if let firstArg = args.first {
                return lowerExpr(firstArg.expr, shared: shared, emit: &instructions)
            }
        default: break
        }

        return lowerExpr(exprID, shared: shared, emit: &instructions)
    }
}
