import RuntimeABI

extension KIRLoweringDriver {
    /// Synthesizes KIR bodies for `@Parcelize` classes:
    ///   - `describeContents(): Int`
    ///   - `writeToParcel(dest: Parcel, flags: Int): Unit` (reading/writing fields)
    ///   - `CREATOR.createFromParcel(parcel: Parcel): T` & `CREATOR.newArray(size: Int): Array<T?>`
    func synthesizeParcelizeMembers(
        classDecl _: ClassDecl,
        classSymbol: SymbolID,
        shared: KIRLoweringSharedContext
    ) -> (classMemberDecls: [KIRDeclID], moduleExtraDecls: [KIRDeclID]) {
        guard let info = shared.sema.parcelizeClasses[classSymbol] else {
            return ([], [])
        }
        let arena = shared.arena
        let sema = shared.sema
        let interner = shared.interner
        var classMemberDecls: [KIRDeclID] = []
        var moduleExtraDecls: [KIRDeclID] = []

        // 1. describeContents(): Int -> returns 0
        if let describeContentsSymbol = info.describeContentsMethod,
           arena.function(for: describeContentsSymbol) == nil,
           let signature = sema.symbols.functionSignature(for: describeContentsSymbol)
        {
            var body: [KIRInstruction] = []
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            body.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            body.append(.returnValue(zeroExpr))

            let receiverType = signature.receiverType ?? sema.types.anyType
            let kirFunc = KIRFunction(
                symbol: describeContentsSymbol,
                name: interner.intern("describeContents"),
                params: [KIRParameter(symbol: classSymbol, type: receiverType)],
                returnType: sema.types.intType,
                body: body,
                isSuspend: false,
                isInline: false
            )
            classMemberDecls.append(arena.appendDecl(.function(kirFunc)))
        }

        // 2. writeToParcel(dest: Parcel, flags: Int): Unit
        if let writeToParcelSymbol = info.writeToParcelMethod,
           arena.function(for: writeToParcelSymbol) == nil,
           let signature = sema.symbols.functionSignature(for: writeToParcelSymbol)
        {
            let receiverType = signature.receiverType ?? sema.types.anyType
            let selfParam = makePluginSyntheticParam(
                ownerFQName: sema.symbols.symbol(writeToParcelSymbol)?.fqName ?? [],
                shared: shared
            )
            let destParam = signature.valueParameterSymbols.first ?? makePluginSyntheticParam(
                ownerFQName: sema.symbols.symbol(writeToParcelSymbol)?.fqName ?? [],
                paramName: "dest",
                shared: shared
            )
            let flagsParam = signature.valueParameterSymbols.count > 1
                ? signature.valueParameterSymbols[1]
                : makePluginSyntheticParam(
                    ownerFQName: sema.symbols.symbol(writeToParcelSymbol)?.fqName ?? [],
                    paramName: "flags",
                    shared: shared
                )
            let destType = signature.parameterTypes.first ?? sema.types.anyType
            let flagsType = signature.parameterTypes.count > 1 ? signature.parameterTypes[1] : sema.types.intType

            let selfRef = arena.appendExpr(.symbolRef(selfParam), type: receiverType)
            let destRef = arena.appendExpr(.symbolRef(destParam), type: destType)
            let flagsRef = arena.appendExpr(.symbolRef(flagsParam), type: flagsType)

            var body: [KIRInstruction] = [
                .constValue(result: selfRef, value: .symbolRef(selfParam)),
                .constValue(result: destRef, value: .symbolRef(destParam)),
                .constValue(result: flagsRef, value: .symbolRef(flagsParam)),
            ]

            if let parcelSymbol = info.parcelSymbol {
                for propID in info.properties {
                    guard let offset = resolvePluginPropertyOffset(
                        ownerClass: classSymbol,
                        propertySymbol: propID,
                        sema: sema
                    ) else { continue }
                    let propType = sema.symbols.propertyType(for: propID) ?? sema.types.anyType
                    let offsetExpr = arena.appendExpr(.intLiteral(Int64(offset)), type: sema.types.intType)
                    body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(offset))))
                    let fieldVal = arena.appendTemporary(type: propType)
                    body.append(.call(
                        callee: interner.intern("kk_array_get_inbounds"),
                        arguments: [selfRef, offsetExpr],
                        result: fieldVal,
                        canThrow: false
                    ))
                    emitParcelWriteField(
                        destRef: destRef,
                        parcelSymbol: parcelSymbol,
                        flagsRef: flagsRef,
                        value: fieldVal,
                        valueType: propType,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &body
                    )
                }
            }

            body.append(.returnUnit)

            let kirFunc = KIRFunction(
                symbol: writeToParcelSymbol,
                name: interner.intern("writeToParcel"),
                params: [
                    KIRParameter(symbol: selfParam, type: receiverType),
                    KIRParameter(symbol: destParam, type: destType),
                    KIRParameter(symbol: flagsParam, type: flagsType),
                ],
                returnType: sema.types.unitType,
                body: body,
                isSuspend: false,
                isInline: false
            )
            classMemberDecls.append(arena.appendDecl(.function(kirFunc)))
        }

        // 3. CREATOR object (`createFromParcel` and `newArray`)
        if let creatorObjSym = info.creatorObjectSymbol {
            var creatorMemberDecls: [KIRDeclID] = []

            if let createSym = info.createFromParcelMethod,
               arena.function(for: createSym) == nil,
               let sig = sema.symbols.functionSignature(for: createSym)
            {
                let creatorType = sig.receiverType ?? sema.types.anyType
                let selfParam = makePluginSyntheticParam(
                    ownerFQName: sema.symbols.symbol(createSym)?.fqName ?? [],
                    shared: shared
                )
                let parcelParam = sig.valueParameterSymbols.first ?? makePluginSyntheticParam(
                    ownerFQName: sema.symbols.symbol(createSym)?.fqName ?? [],
                    paramName: "parcel",
                    shared: shared
                )
                let parcelType = sig.parameterTypes.first ?? sema.types.anyType
                let parcelRef = arena.appendExpr(.symbolRef(parcelParam), type: parcelType)

                var body: [KIRInstruction] = [
                    .constValue(result: parcelRef, value: .symbolRef(parcelParam)),
                ]
                let targetObj = emitAllocatePluginNominalInstance(
                    ownerSymbol: classSymbol,
                    resultType: sig.returnType,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &body
                )

                if let parcelSymbol = info.parcelSymbol {
                    for propID in info.properties {
                        guard let offset = resolvePluginPropertyOffset(
                            ownerClass: classSymbol,
                            propertySymbol: propID,
                            sema: sema
                        ) else { continue }
                        let propType = sema.symbols.propertyType(for: propID) ?? sema.types.anyType
                        if let readVal = emitParcelReadField(
                            parcelRef: parcelRef,
                            parcelSymbol: parcelSymbol,
                            targetType: propType,
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &body
                        ) {
                            let offsetExpr = arena.appendExpr(.intLiteral(Int64(offset)), type: sema.types.intType)
                            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(offset))))
                            let setRes = arena.appendTemporary(type: sema.types.anyType)
                            body.append(.call(
                                callee: interner.intern("kk_array_set"),
                                arguments: [targetObj, offsetExpr, readVal],
                                result: setRes,
                                canThrow: false
                            ))
                        }
                    }
                }
                body.append(.returnValue(targetObj))

                let kirFunc = KIRFunction(
                    symbol: createSym,
                    name: interner.intern("createFromParcel"),
                    params: [
                        KIRParameter(symbol: selfParam, type: creatorType),
                        KIRParameter(symbol: parcelParam, type: parcelType),
                    ],
                    returnType: sig.returnType,
                    body: body,
                    isSuspend: false,
                    isInline: false
                )
                let declID = arena.appendDecl(.function(kirFunc))
                creatorMemberDecls.append(declID)
                moduleExtraDecls.append(declID)
            }

            if let newArraySym = info.newArrayMethod,
               arena.function(for: newArraySym) == nil,
               let sig = sema.symbols.functionSignature(for: newArraySym)
            {
                let creatorType = sig.receiverType ?? sema.types.anyType
                let selfParam = makePluginSyntheticParam(
                    ownerFQName: sema.symbols.symbol(newArraySym)?.fqName ?? [],
                    shared: shared
                )
                let sizeParam = sig.valueParameterSymbols.first ?? makePluginSyntheticParam(
                    ownerFQName: sema.symbols.symbol(newArraySym)?.fqName ?? [],
                    paramName: "size",
                    shared: shared
                )
                let sizeRef = arena.appendExpr(.symbolRef(sizeParam), type: sema.types.intType)
                let arrayExpr = arena.appendTemporary(type: sig.returnType)
                let body: [KIRInstruction] = [
                    .constValue(result: sizeRef, value: .symbolRef(sizeParam)),
                    .call(
                        callee: interner.intern("kk_array_new"),
                        arguments: [sizeRef],
                        result: arrayExpr,
                        canThrow: false
                    ),
                    .returnValue(arrayExpr),
                ]
                let kirFunc = KIRFunction(
                    symbol: newArraySym,
                    name: interner.intern("newArray"),
                    params: [
                        KIRParameter(symbol: selfParam, type: creatorType),
                        KIRParameter(symbol: sizeParam, type: sema.types.intType),
                    ],
                    returnType: sig.returnType,
                    body: body,
                    isSuspend: false,
                    isInline: false
                )
                let declID = arena.appendDecl(.function(kirFunc))
                creatorMemberDecls.append(declID)
                moduleExtraDecls.append(declID)
            }

            let creatorType = sema.types.make(.classType(ClassType(
                classSymbol: creatorObjSym,
                args: [],
                nullability: .nonNull
            )))
            moduleExtraDecls.append(arena.appendDecl(.global(KIRGlobal(symbol: creatorObjSym, type: creatorType))))
            moduleExtraDecls.append(arena.appendDecl(.nominalType(KIRNominalType(
                symbol: creatorObjSym,
                memberDecls: creatorMemberDecls
            ))))
            moduleExtraDecls.append(emitPluginSingletonInitializer(
                objectSymbol: creatorObjSym,
                objectType: creatorType,
                shared: shared
            ))
        }

        return (classMemberDecls, moduleExtraDecls)
    }

    private func emitParcelWriteField(
        destRef: KIRExprID,
        parcelSymbol: SymbolID,
        flagsRef: KIRExprID,
        value: KIRExprID,
        valueType: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        let nonNullType = sema.types.makeNonNullable(valueType)
        if nonNullType == sema.types.stringType {
            if let fn = findPluginMethodSymbol(on: parcelSymbol, named: "writeString", arity: 1, sema: sema, interner: interner) {
                _ = emitPluginMemberCall(
                    receiver: destRef, receiverNominalSymbol: parcelSymbol,
                    methodSymbol: fn, arguments: [value], returnType: sema.types.unitType,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
            }
            return
        }
        switch sema.types.kind(of: nonNullType) {
        case .primitive(.int, _), .primitive(.char, _), .primitive(.short, _):
            if let fn = findPluginMethodSymbol(on: parcelSymbol, named: "writeInt", arity: 1, sema: sema, interner: interner) {
                _ = emitPluginMemberCall(
                    receiver: destRef, receiverNominalSymbol: parcelSymbol,
                    methodSymbol: fn, arguments: [value], returnType: sema.types.unitType,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
            }
        case .primitive(.long, _):
            if let fn = findPluginMethodSymbol(on: parcelSymbol, named: "writeLong", arity: 1, sema: sema, interner: interner) {
                _ = emitPluginMemberCall(
                    receiver: destRef, receiverNominalSymbol: parcelSymbol,
                    methodSymbol: fn, arguments: [value], returnType: sema.types.unitType,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
            }
        case .primitive(.float, _):
            if let fn = findPluginMethodSymbol(on: parcelSymbol, named: "writeFloat", arity: 1, sema: sema, interner: interner) {
                _ = emitPluginMemberCall(
                    receiver: destRef, receiverNominalSymbol: parcelSymbol,
                    methodSymbol: fn, arguments: [value], returnType: sema.types.unitType,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
            }
        case .primitive(.double, _):
            if let fn = findPluginMethodSymbol(on: parcelSymbol, named: "writeDouble", arity: 1, sema: sema, interner: interner) {
                _ = emitPluginMemberCall(
                    receiver: destRef, receiverNominalSymbol: parcelSymbol,
                    methodSymbol: fn, arguments: [value], returnType: sema.types.unitType,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
            }
        case .primitive(.boolean, _):
            if let fn = findPluginMethodSymbol(on: parcelSymbol, named: "writeInt", arity: 1, sema: sema, interner: interner) {
                _ = emitPluginMemberCall(
                    receiver: destRef, receiverNominalSymbol: parcelSymbol,
                    methodSymbol: fn, arguments: [value], returnType: sema.types.unitType,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
            }
        default:
            if let fn = findPluginMethodSymbol(on: parcelSymbol, named: "writeParcelable", arity: 2, sema: sema, interner: interner) {
                _ = emitPluginMemberCall(
                    receiver: destRef, receiverNominalSymbol: parcelSymbol,
                    methodSymbol: fn, arguments: [value, flagsRef], returnType: sema.types.unitType,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
            } else if let fn = findPluginMethodSymbol(on: parcelSymbol, named: "writeValue", arity: 1, sema: sema, interner: interner) {
                _ = emitPluginMemberCall(
                    receiver: destRef, receiverNominalSymbol: parcelSymbol,
                    methodSymbol: fn, arguments: [value], returnType: sema.types.unitType,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
            }
        }
    }

    private func emitParcelReadField(
        parcelRef: KIRExprID,
        parcelSymbol: SymbolID,
        targetType: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let nonNullTarget = sema.types.makeNonNullable(targetType)
        if nonNullTarget == sema.types.stringType {
            guard let fn = findPluginMethodSymbol(on: parcelSymbol, named: "readString", arity: 0, sema: sema, interner: interner) else {
                return nil
            }
            return emitPluginMemberCall(
                receiver: parcelRef, receiverNominalSymbol: parcelSymbol,
                methodSymbol: fn, arguments: [], returnType: targetType,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
        }
        switch sema.types.kind(of: nonNullTarget) {
        case .primitive(.int, _), .primitive(.char, _), .primitive(.short, _), .primitive(.boolean, _):
            guard let fn = findPluginMethodSymbol(on: parcelSymbol, named: "readInt", arity: 0, sema: sema, interner: interner) else {
                return nil
            }
            return emitPluginMemberCall(
                receiver: parcelRef, receiverNominalSymbol: parcelSymbol,
                methodSymbol: fn, arguments: [], returnType: targetType,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
        case .primitive(.long, _):
            guard let fn = findPluginMethodSymbol(on: parcelSymbol, named: "readLong", arity: 0, sema: sema, interner: interner) else {
                return nil
            }
            return emitPluginMemberCall(
                receiver: parcelRef, receiverNominalSymbol: parcelSymbol,
                methodSymbol: fn, arguments: [], returnType: targetType,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
        case .primitive(.float, _):
            guard let fn = findPluginMethodSymbol(on: parcelSymbol, named: "readFloat", arity: 0, sema: sema, interner: interner) else {
                return nil
            }
            return emitPluginMemberCall(
                receiver: parcelRef, receiverNominalSymbol: parcelSymbol,
                methodSymbol: fn, arguments: [], returnType: targetType,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
        case .primitive(.double, _):
            guard let fn = findPluginMethodSymbol(on: parcelSymbol, named: "readDouble", arity: 0, sema: sema, interner: interner) else {
                return nil
            }
            return emitPluginMemberCall(
                receiver: parcelRef, receiverNominalSymbol: parcelSymbol,
                methodSymbol: fn, arguments: [], returnType: targetType,
                sema: sema, arena: arena, interner: interner, instructions: &instructions
            )
        default:
            if let fn = findPluginMethodSymbol(on: parcelSymbol, named: "readParcelable", arity: 1, sema: sema, interner: interner) {
                let nullLoader = arena.appendExpr(.null, type: sema.types.nullableAnyType)
                instructions.append(.constValue(result: nullLoader, value: .null))
                return emitPluginMemberCall(
                    receiver: parcelRef, receiverNominalSymbol: parcelSymbol,
                    methodSymbol: fn, arguments: [nullLoader], returnType: targetType,
                    sema: sema, arena: arena, interner: interner, instructions: &instructions
                )
            }
            return nil
        }
    }
}
