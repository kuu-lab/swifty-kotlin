/// `typeOf<T>()` lowering plus KClass / annotation metadata
/// registration emit-time helpers.
///
/// Split out from `CallLowerer.swift`.
extension CallLowerer {
    /// Lowers `typeOf<T>()` calls to `kk_typeof(typeToken, nameHint, argsRaw, isNullable)`.
    /// Returns nil if the expression is not a typeOf call.
    func lowerTypeOfCallExpr(
        _ exprID: ExprID,
        calleeExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.stdlibSpecialCallKind(for: exprID) == .typeOf else {
            return nil
        }

        let knownNames = KnownCompilerNames(interner: interner)
        guard let callee = ast.arena.expr(calleeExpr) else {
            return nil
        }
        switch callee {
        case let .nameRef(name, _):
            guard name == knownNames.typeOf else { return nil }
        case let .memberCall(_, member, _, _, _):
            // Fully-qualified `kotlin.reflect.typeOf<T>()` (KSP-1323).
            guard member == knownNames.typeOf else { return nil }
        default:
            return nil
        }

        // Resolve the type argument from the call binding.
        let callBinding = sema.bindings.callBindings[exprID]
        let typeArg: TypeID
        if let binding = callBinding,
           !binding.substitutedTypeArguments.isEmpty
        {
            typeArg = binding.substitutedTypeArguments[0]
        } else {
            // Fallback: typeOf<T>() with no resolved type argument defaults to Any.
            typeArg = sema.types.anyType
        }

        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.stringType

        func makeTypeTokenExpr(for type: TypeID) -> KIRExprID {
            if case let .typeParam(typeParam) = sema.types.kind(of: type) {
                let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParam.symbol)
                if let captured = driver.ctx.localValue(for: tokenSymbol) { return captured }
                let tokenExpr = arena.appendExpr(.symbolRef(tokenSymbol), type: intType)
                instructions.append(.constValue(result: tokenExpr, value: .symbolRef(tokenSymbol)))
                return tokenExpr
            }
            let encoded = RuntimeTypeCheckToken.encode(type: type, sema: sema, interner: interner)
            let tokenExpr = arena.appendExpr(.intLiteral(encoded), type: intType)
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encoded)))
            return tokenExpr
        }

        func makeNameHintExpr(for type: TypeID) -> KIRExprID {
            if let name = RuntimeTypeCheckToken.qualifiedName(of: type, sema: sema, interner: interner) {
                let internedName = interner.intern(name)
                let nameHintExpr = arena.appendExpr(.stringLiteral(internedName), type: stringType)
                instructions.append(.constValue(result: nameHintExpr, value: .stringLiteral(internedName)))
                return nameHintExpr
            }
            let nameHintExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: nameHintExpr, value: .intLiteral(0)))
            return nameHintExpr
        }

        func makeNullabilityExpr(for type: TypeID) -> KIRExprID {
            // A rigid T can represent String? even when the occurrence is T,
            // so its hidden token, rather than syntax alone, carries the flag.
            if case let .typeParam(parameter) = sema.types.kind(of: type),
               parameter.nullability != .nullable,
               sema.symbols.symbol(parameter.symbol)?.flags.contains(.reifiedTypeParameter) == true {
                let token = makeTypeTokenExpr(for: type)
                let mask = arena.appendExpr(.intLiteral(RuntimeTypeCheckToken.nullableFlag), type: intType)
                instructions.append(.constValue(result: mask, value: .intLiteral(RuntimeTypeCheckToken.nullableFlag)))
                let nullable = arena.appendTemporary(type: intType)
                instructions.append(.call(
                    symbol: nil, callee: interner.intern("kk_bitwise_and"), arguments: [token, mask],
                    result: nullable, canThrow: false, thrownResult: nil
                ))
                return nullable
            }
            let isNullable: Int64 = {
                switch sema.types.kind(of: type) {
                case .nullableUnit:
                    return 1
                case let .primitive(_, nullability):
                    return nullability == .nullable ? 1 : 0
                case let .classType(ct):
                    return ct.nullability == .nullable ? 1 : 0
                case let .typeParam(tp):
                    return tp.nullability == .nullable ? 1 : 0
                case let .kClassType(kc):
                    return kc.nullability == .nullable ? 1 : 0
                case let .any(nullability):
                    return nullability == .nullable ? 1 : 0
                case let .nothing(nullability):
                    return nullability == .nullable ? 1 : 0
                case let .stringStruct(nullability):
                    return nullability == .nullable ? 1 : 0
                case let .functionType(functionType):
                    return functionType.nullability == .nullable ? 1 : 0
                default:
                    return 0
                }
            }()
            let isNullableExpr = arena.appendExpr(.intLiteral(isNullable), type: intType)
            instructions.append(.constValue(result: isNullableExpr, value: .intLiteral(isNullable)))
            return isNullableExpr
        }

        func lowerKTypeExpr(for type: TypeID) -> KIRExprID {
            func lowerKTypeProjectionExpr(_ argument: TypeArg) -> KIRExprID {
                let varianceOrdinal: Int64
                let typeRawExpr: KIRExprID
                switch argument {
                case .star:
                    varianceOrdinal = -1
                    typeRawExpr = arena.appendExpr(.intLiteral(0), type: intType)
                    instructions.append(.constValue(result: typeRawExpr, value: .intLiteral(0)))
                case let .invariant(argumentType):
                    varianceOrdinal = 2
                    typeRawExpr = lowerKTypeExpr(for: argumentType)
                case let .out(argumentType):
                    varianceOrdinal = 1
                    typeRawExpr = lowerKTypeExpr(for: argumentType)
                case let .in(argumentType):
                    varianceOrdinal = 0
                    typeRawExpr = lowerKTypeExpr(for: argumentType)
                }
                let varianceExpr = arena.appendExpr(.intLiteral(varianceOrdinal), type: intType)
                instructions.append(.constValue(result: varianceExpr, value: .intLiteral(varianceOrdinal)))
                let projectionExpr = arena.appendTemporary(type: sema.types.anyType)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("__kk_ktypeprojection_create"),
                    arguments: [typeRawExpr, varianceExpr],
                    result: projectionExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                return projectionExpr
            }

            // A nullable KType has the same classifier as its non-null counterpart.
            let tokenExpr = makeTypeTokenExpr(for: sema.types.makeNonNullable(type))
            emitClassLiteralMetadataRegistration(
                classRefTargetType: sema.types.makeNonNullable(type), typeTokenExpr: tokenExpr,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
            let nameHintExpr = makeNameHintExpr(for: type)
            let typeArguments: [TypeArg]
            switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
            case let .classType(classType):
                typeArguments = classType.args
            case let .kClassType(kClassType):
                typeArguments = [.invariant(kClassType.argument)]
            case let .functionType(functionType):
                // KUU-1084: KType.arguments for a function type is the
                // parameter types followed by the return type (Kotlin
                // FunctionN order: context receivers, extension receiver,
                // value parameters, return type).
                var argumentTypes = functionType.contextReceivers
                if let receiver = functionType.receiver {
                    argumentTypes.append(receiver)
                }
                argumentTypes.append(contentsOf: functionType.params)
                argumentTypes.append(functionType.returnType)
                typeArguments = argumentTypes.map { .invariant($0) }
            default:
                typeArguments = []
            }

            let argsListExpr: KIRExprID
            if typeArguments.isEmpty {
                argsListExpr = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: argsListExpr, value: .intLiteral(0)))
            } else {
                let countExpr = arena.appendExpr(.intLiteral(Int64(typeArguments.count)), type: intType)
                instructions.append(.constValue(result: countExpr, value: .intLiteral(Int64(typeArguments.count))))
                let arrayExpr = arena.appendTemporary(type: sema.types.anyType)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_new"),
                    arguments: [countExpr],
                    result: arrayExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
                for (index, argument) in typeArguments.enumerated() {
                    let projectionExpr = lowerKTypeProjectionExpr(argument)
                    let indexExpr = arena.appendExpr(.intLiteral(Int64(index)), type: intType)
                    instructions.append(.constValue(result: indexExpr, value: .intLiteral(Int64(index))))
                    let setResult = arena.appendTemporary(type: sema.types.anyType)
                    instructions.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_set"),
                        arguments: [arrayExpr, indexExpr, projectionExpr],
                        result: setResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
                argsListExpr = arena.appendTemporary(type: sema.types.anyType)
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("__kk_list_of"),
                    arguments: [arrayExpr, countExpr],
                    result: argsListExpr,
                    canThrow: false,
                    thrownResult: nil
                ))
            }

            let isNullableExpr = makeNullabilityExpr(for: type)
            let ktypeExpr = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_typeof"),
                arguments: [tokenExpr, nameHintExpr, argsListExpr, isNullableExpr],
                result: ktypeExpr,
                canThrow: false,
                thrownResult: nil
            ))
            return ktypeExpr
        }

        let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        let lowered = lowerKTypeExpr(for: typeArg)
        let result = arena.appendTemporary(type: resultType)
        instructions.append(.copy(from: lowered, to: result))
        return result
    }

    // MARK: - REFL-005: KClass Metadata Registration for Constructor Calls

    /// Emits a `__kk_kclass_register_metadata` call so that `KClass` reflection
    /// queries (`.members`, `.constructors`, etc.) return correct data.
    /// This mirrors `ObjectLiteralLowerer.registerKClassMetadata` but is used
    /// for regular class constructor invocations.
    func emitKClassMetadataRegistration(
        objectSymbol: SymbolID,
        typeID: Int64,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        guard let symbol = sema.symbols.symbol(objectSymbol) else { return }

        let intType = sema.types.intType

        let typeToken = RuntimeTypeCheckToken.encode(
            base: RuntimeTypeCheckToken.nominalBase,
            nullable: false,
            payload: typeID
        )
        let typeTokenExpr = arena.appendExpr(.intLiteral(typeToken), type: intType)
        instructions.append(.constValue(result: typeTokenExpr, value: .intLiteral(typeToken)))

        let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
        let fqNameInterned = interner.intern(fqName)
        let fqNameExpr = arena.appendExpr(.stringLiteral(fqNameInterned), type: intType)
        instructions.append(.constValue(result: fqNameExpr, value: .stringLiteral(fqNameInterned)))

        let simpleName = interner.resolve(symbol.name)
        let simpleNameInterned = interner.intern(simpleName)
        let simpleNameExpr = arena.appendExpr(.stringLiteral(simpleNameInterned), type: intType)
        instructions.append(.constValue(result: simpleNameExpr, value: .stringLiteral(simpleNameInterned)))

        let supertypeNameExpr: KIRExprID
        if let joined = kclassSupertypeDisplayNamesJoined(
            for: objectSymbol, sema: sema, interner: interner
        ) {
            let superInterned = interner.intern(joined)
            supertypeNameExpr = arena.appendExpr(.stringLiteral(superInterned), type: intType)
            instructions.append(.constValue(result: supertypeNameExpr, value: .stringLiteral(superInterned)))
        } else {
            supertypeNameExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: supertypeNameExpr, value: .intLiteral(0)))
        }

        var flags: Int64 = 0
        if symbol.flags.contains(.dataType) { flags |= 1 << 0 }
        if symbol.flags.contains(.sealedType) { flags |= 1 << 1 }
        if symbol.flags.contains(.valueType) { flags |= 1 << 2 }
        if symbol.kind == .interface { flags |= 1 << 3 }
        if symbol.kind == .object { flags |= 1 << 4 }
        if symbol.kind == .enumClass { flags |= 1 << 5 }
        if symbol.kind == .annotationClass { flags |= 1 << 6 }
        // Reflection reports Kotlin modality, not the internal inheritance flags.
        let isSealed = symbol.flags.contains(.sealedType)
        let isAbstract = !isSealed && (symbol.kind == .interface || symbol.kind == .annotationClass || symbol.flags.contains(.abstractType))
        if isAbstract { flags |= 1 << 7 }
        if !isSealed && !isAbstract && !symbol.flags.contains(.openType) { flags |= 1 << 8 }
        if !isSealed && !isAbstract && symbol.flags.contains(.openType) { flags |= 1 << 9 }
        // STDLIB-REFLECT-067: bits 10-12 for inner / companion / funInterface
        if symbol.flags.contains(.innerClass) { flags |= 1 << 10 }
        if symbol.flags.contains(.funInterface) { flags |= 1 << 12 }
        if symbol.kind == .object {
            let parentFQName = Array(symbol.fqName.dropLast())
            if let parentSymbol = sema.symbols.lookup(fqName: parentFQName),
               sema.symbols.companionObjectSymbol(for: parentSymbol) == objectSymbol {
                flags |= 1 << 11
            }
        }
        let flagsExpr = arena.appendExpr(.intLiteral(flags), type: intType)
        instructions.append(.constValue(result: flagsExpr, value: .intLiteral(flags)))

        let fieldCount: Int64
        if let layout = sema.symbols.nominalLayout(for: objectSymbol) {
            fieldCount = Int64(layout.instanceFieldCount)
        } else {
            fieldCount = -1
        }
        let fieldCountExpr = arena.appendExpr(.intLiteral(fieldCount), type: intType)
        instructions.append(.constValue(result: fieldCountExpr, value: .intLiteral(fieldCount)))

        let memberCount: Int64
        if let layout = sema.symbols.nominalLayout(for: objectSymbol) {
            memberCount = Int64(layout.instanceFieldCount + layout.vtableSize)
        } else {
            memberCount = -1
        }
        let memberCountExpr = arena.appendExpr(.intLiteral(memberCount), type: intType)
        instructions.append(.constValue(result: memberCountExpr, value: .intLiteral(memberCount)))

        let constructorCount = Int64(sema.symbols.children(ofFQName: symbol.fqName).filter { child in
            sema.symbols.symbol(child)?.kind == .constructor
        }.count)
        let constructorCountExpr = arena.appendExpr(.intLiteral(constructorCount), type: intType)
        instructions.append(.constValue(result: constructorCountExpr, value: .intLiteral(constructorCount)))

        let registerResult = arena.appendTemporary(type: intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("__kk_kclass_register_metadata"),
            arguments: [typeTokenExpr, fqNameExpr, simpleNameExpr, supertypeNameExpr, flagsExpr, fieldCountExpr, memberCountExpr, constructorCountExpr],
            result: registerResult,
            canThrow: false,
            thrownResult: nil
        ))
        emitKClassDisplayNameRegistration(
            symbol: objectSymbol, typeTokenExpr: typeTokenExpr,
            sema: sema, arena: arena, interner: interner, instructions: &instructions
        )
        emitKClassCompanionAndNestedRegistration(
            classSymbol: objectSymbol, typeTokenExpr: typeTokenExpr,
            sema: sema, arena: arena, interner: interner, instructions: &instructions
        )

        // STDLIB-REFLECT-065: Register annotations for this type.
        emitKClassAnnotationRegistration(
            objectSymbol: objectSymbol,
            typeTokenExpr: typeTokenExpr,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        // KUU-1448: construction also makes this class reachable through
        // `KType.classifier`/`__kk_kclass_of` handles, so its ancestors need
        // metadata too. Seeded with `objectSymbol` so a sealed ancestor's
        // subclass walk cannot re-emit this registration.
        var visitedClassSymbols: Set<SymbolID> = [objectSymbol]
        emitTransitiveSupertypeKClassMetadataRegistrations(
            for: objectSymbol,
            visitedClassSymbols: &visitedClassSymbols,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }
}
