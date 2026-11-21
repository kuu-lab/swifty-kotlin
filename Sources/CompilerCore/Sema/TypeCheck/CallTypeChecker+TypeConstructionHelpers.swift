extension CallTypeChecker {
    func makeSyntheticListType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        guard let listSymbol = symbols.lookupNominal(fqName: listFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    func makeSyntheticIterableType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let iterableFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]
        guard let iterableSymbol = symbols.lookupNominal(fqName: iterableFQName) else {
            // Fall back to Any rather than List<Char> to avoid granting
            // list-only members (e.g. get()) to the iterable result type.
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: iterableSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    func makeSyntheticArrayType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let arrayFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("Array"),
        ]
        guard let arraySymbol = symbols.lookupNominal(fqName: arrayFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    func makeSyntheticPrimitiveArrayType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        arrayName: String
    ) -> TypeID {
        let arrayFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern(arrayName),
        ]
        guard let arraySymbol = symbols.lookupNominal(fqName: arrayFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    func makeSyntheticSequenceType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let sequenceFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("sequences"),
            interner.intern("Sequence"),
        ]
        guard let sequenceSymbol = symbols.lookupNominal(fqName: sequenceFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    func inferSyntheticMapKeyValueTypes(
        from argTypes: [TypeID],
        ctx: TypeInferenceContext
    ) -> (keyType: TypeID, valueType: TypeID)? {
        let sema = ctx.sema
        let interner = ctx.interner
        let pairFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("Pair"),
        ]
        guard let pairSymbol = sema.symbols.lookupNominal(fqName: pairFQName) else {
            return nil
        }

        var keyTypes: [TypeID] = []
        var valueTypes: [TypeID] = []
        for type in argTypes {
            guard case let .classType(classType) = sema.types.kind(of: type),
                  classType.classSymbol == pairSymbol,
                  classType.args.count == 2
            else {
                return nil
            }
            func projected(_ arg: TypeArg) -> TypeID {
                switch arg {
                case let .invariant(t), let .out(t), let .in(t):
                    return t
                case .star:
                    return sema.types.anyType
                }
            }
            keyTypes.append(projected(classType.args[0]))
            valueTypes.append(projected(classType.args[1]))
        }

        guard !keyTypes.isEmpty, !valueTypes.isEmpty else {
            return nil
        }
        return (sema.types.lub(keyTypes), sema.types.lub(valueTypes))
    }

    func inferMapTypeArgumentsFromConstructorArgument(
        from argTypes: [TypeID],
        ctx: TypeInferenceContext
    ) -> (keyType: TypeID, valueType: TypeID)? {
        guard argTypes.count == 1,
              case let .classType(argumentClass) = ctx.sema.types.kind(of: argTypes[0])
        else {
            return nil
        }
        let interner = ctx.interner
        let mapSymbol = ctx.sema.symbols.lookupNominal(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Map"),
        ])
        guard let mapSymbol,
              let mapArgs = ctx.sema.types.liftedNominalSupertypeArgs(
                  from: argumentClass.classSymbol,
                  childArgs: argumentClass.args,
                  to: mapSymbol
              ),
              mapArgs.count == 2
        else {
            return nil
        }

        func projected(_ arg: TypeArg) -> TypeID {
            switch arg {
            case let .invariant(type), let .in(type), let .out(type):
                return type
            case .star:
                return ctx.sema.types.anyType
            }
        }
        return (projected(mapArgs[0]), projected(mapArgs[1]))
    }

    func makeSyntheticMutableListType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let mutableListFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableList"),
        ]
        guard let mutableListSymbol = symbols.lookupNominal(fqName: mutableListFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: mutableListSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    func makeSyntheticListConstructorType(
        name: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let fqName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern(name),
        ]
        guard let classSymbol = symbols.lookupNominal(fqName: fqName),
              symbols.symbol(classSymbol)?.kind == .class
        else {
            return makeSyntheticMutableListType(
                symbols: symbols,
                types: types,
                interner: interner,
                elementType: elementType
            )
        }
        return types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    func makeSyntheticSetType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let setFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Set"),
        ]
        guard let setSymbol = symbols.lookupNominal(fqName: setFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: setSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    func makeSyntheticMutableSetType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let mutableSetFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableSet"),
        ]
        guard let mutableSetSymbol = symbols.lookupNominal(fqName: mutableSetFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: mutableSetSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    func makeSyntheticHashSetType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let hashSetFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("HashSet"),
        ]
        guard let hashSetSymbol = symbols.lookupNominal(fqName: hashSetFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: hashSetSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    func makeSyntheticLinkedHashSetType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let linkedHashSetFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("LinkedHashSet"),
        ]
        guard let linkedHashSetSymbol = symbols.lookupNominal(fqName: linkedHashSetFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: linkedHashSetSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    func makeSyntheticMapType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        keyType: TypeID,
        valueType: TypeID
    ) -> TypeID {
        let mapFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Map"),
        ]
        guard let mapSymbol = symbols.lookupNominal(fqName: mapFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.invariant(keyType), .out(valueType)],
            nullability: .nonNull
        )))
    }

    func makeSyntheticMutableMapType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        keyType: TypeID,
        valueType: TypeID
    ) -> TypeID {
        let mapFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableMap"),
        ]
        guard let mapSymbol = symbols.lookupNominal(fqName: mapFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.invariant(keyType), .invariant(valueType)],
            nullability: .nonNull
        )))
    }

    func makeSourceBackedHashMapType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        keyType: TypeID,
        valueType: TypeID
    ) -> TypeID {
        let hashMapFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("HashMap"),
        ]
        guard let hashMapSymbol = symbols.lookupNominal(fqName: hashMapFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: hashMapSymbol,
            args: [.invariant(keyType), .invariant(valueType)],
            nullability: .nonNull
        )))
    }

    func makeSourceBackedLinkedHashMapType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        keyType: TypeID,
        valueType: TypeID
    ) -> TypeID {
        let linkedHashMapFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("LinkedHashMap"),
        ]
        guard let linkedHashMapSymbol = symbols.lookupNominal(fqName: linkedHashMapFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: linkedHashMapSymbol,
            args: [.invariant(keyType), .invariant(valueType)],
            nullability: .nonNull
        )))
    }

    func applyContractEffects(
        id: ExprID,
        chosen: SymbolID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) {
        applyContractCallsInPlaceEffects(id: id, chosen: chosen, args: args, ctx: ctx, locals: &locals)
        let sema = ctx.sema
        let implications = sema.symbols.contractImplicationEffects(for: chosen)
        if !implications.isEmpty {
            if implications.contains(where: { $0.returnCondition == .normally }) {
                let state = ctx.dataFlow.applyContractImplications(
                    id, result: .normally, base: ctx.flowState.includingMembers(from: locals),
                    locals: locals,
                    ast: ctx.ast, sema: sema, interner: ctx.interner, scope: ctx.scope
                )
                driver.exprChecker.applyFlowStateToLocals(state, locals: &locals, sema: sema)
            }
            return
        }
        guard let signature = sema.symbols.functionSignature(for: chosen) else {
            return
        }
        let parameterIndex: Int
        if let effect = sema.symbols.contractNonNullEffect(for: chosen),
           effect.appliesOnAnyReturn,
           let index = signature.valueParameterSymbols.firstIndex(of: effect.parameterSymbol),
           index < args.count,
           index < signature.parameterTypes.count
        {
            parameterIndex = index
        } else if let effect = sema.symbols.contractConditionEffect(for: chosen),
                  effect.returnsValue == nil,
                  effect.conditionParameterIndex < args.count,
                  effect.conditionParameterIndex < signature.parameterTypes.count
        {
            parameterIndex = effect.conditionParameterIndex
        } else {
            return
        }
        guard let argumentIndex = sema.bindings.callBinding(for: id)?.parameterMapping.first(where: { $0.value == parameterIndex })?.key,
              args.indices.contains(argumentIndex) else { return }
        let conditionExpr = args[argumentIndex].expr
        let narrowedState: DataFlowState
        if signature.parameterTypes[parameterIndex] == sema.types.booleanType {
            let branch = ctx.dataFlow.branchOnCondition(
                conditionExpr,
                base: ctx.flowState.includingMembers(from: locals),
                locals: locals,
                ast: ctx.ast,
                sema: sema,
                interner: ctx.interner,
                scope: ctx.scope
            )
            narrowedState = branch.trueState
        } else {
            narrowedState = ctx.dataFlow.narrowNonNull(
                conditionExpr,
                base: ctx.flowState.includingMembers(from: locals),
                locals: locals,
                ast: ctx.ast,
                sema: sema,
                interner: ctx.interner
            )
        }
        driver.exprChecker.applyFlowStateToLocals(
            narrowedState,
            locals: &locals,
            sema: sema
        )
    }

    private func applyContractCallsInPlaceEffects(
        id: ExprID,
        chosen: SymbolID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) {
        // A safe call (`?.`) skips the whole call -- lambda included -- when
        // the receiver is null, so callsInPlace cannot guarantee that the
        // lambda ran; kotlinc rejects definite assignment through it as well.
        if case .safeMemberCall = ctx.ast.arena.expr(id) {
            return
        }
        let sema = ctx.sema
        let effects = sema.symbols.contractCallsInPlaceEffects(for: chosen)
        guard !effects.isEmpty,
              let signature = sema.symbols.functionSignature(for: chosen)
        else {
            return
        }
        for effect in effects {
            guard effect.kind == .exactlyOnce || effect.kind == .atLeastOnce,
                  let parameterIndex = signature.valueParameterSymbols.firstIndex(of: effect.parameterSymbol),
                  let argumentIndex = sema.bindings.callBinding(for: id)?.parameterMapping.first(where: { $0.value == parameterIndex })?.key,
                  args.indices.contains(argumentIndex)
            else {
                continue
            }
            let initializedSymbols = Set(
                sema.bindings.contractCallsInPlaceInitializedSymbols(for: args[argumentIndex].expr)
            )
            guard !initializedSymbols.isEmpty else { continue }
            for (name, local) in locals where !local.isInitialized && initializedSymbols.contains(local.symbol) {
                locals[name] = (local.type, local.symbol, local.isMutable, true)
            }
        }
    }
}
