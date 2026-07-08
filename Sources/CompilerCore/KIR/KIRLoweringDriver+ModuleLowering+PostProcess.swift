
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
        var newBody: KIRLoweringEmitContext = []
        if let first = body.first, case .beginBlock = first {
            newBody.append(first)
            newBody.append(contentsOf: inits)
            newBody.append(contentsOf: body.dropFirst())
        } else {
            newBody.append(contentsOf: inits)
            newBody.append(contentsOf: body)
        }
        return newBody.instructions
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
    func lowerDelegateLambdaBody(
        delegateBody: FunctionBody?,
        propertySymbol: SymbolID,
        paramCount: Int,
        shared: KIRLoweringSharedContext,
        emit instructions: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let lambdaSymbol = ctx.allocateSyntheticGeneratedSymbol()
        let lambdaName = interner.intern("kk_delegate_lambda_\(propertySymbol.rawValue)")

        var params: [KIRParameter] = []
        for i in 0 ..< paramCount {
            let paramSymbol = SymbolID(
                rawValue: -(propertySymbol.rawValue + Int32(i + 1) * 1000 + 50000)
            )
            params.append(KIRParameter(symbol: paramSymbol, type: sema.types.anyType))
        }

        var lambdaBody: KIRLoweringEmitContext = [.beginBlock]
        for param in params {
            let paramExpr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            lambdaBody.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            ctx.setLocalValue(paramExpr, for: param.symbol)
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

        let lambdaRefExpr = arena.appendExpr(.symbolRef(lambdaSymbol), type: sema.types.anyType)
        instructions.append(.constValue(result: lambdaRefExpr, value: .symbolRef(lambdaSymbol)))
        return lambdaRefExpr
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
