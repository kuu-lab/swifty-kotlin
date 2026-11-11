import RuntimeABI

extension KIRLoweringDriver {
    /// Synthesizes KIR bodies for `@Serializable` classes:
    ///   - `Companion.serializer()` returning a real `$serializer` instance
    ///   - `$serializer.<init>()`
    ///   - `$serializer.descriptor` (`ClassSerialDescriptorBuilder` + `SerialDescriptorImpl`)
    ///   - `$serializer.serialize(encoder, value)`
    ///   - `$serializer.deserialize(decoder)`
    func synthesizeSerializationMembers(
        classDecl: ClassDecl,
        classSymbol: SymbolID,
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        guard let info = shared.sema.serializationClasses[classSymbol] else { return [] }
        var extraDecls: [KIRDeclID] = []
        let arena = shared.arena
        let sema = shared.sema
        let interner = shared.interner

        var companionMemberDecls: [KIRDeclID] = []

        // 1. Companion serializer() method
        if let serializerSym = info.companionSerializerMethod,
           arena.function(for: serializerSym) == nil,
           let signature = sema.symbols.functionSignature(for: serializerSym)
        {
            let receiverType = signature.receiverType ?? sema.types.anyType
            var params: [KIRParameter] = [
                KIRParameter(symbol: info.companionObjectSymbol ?? classSymbol, type: receiverType),
            ]
            for (idx, paramType) in signature.parameterTypes.enumerated() {
                let paramSym = signature.valueParameterSymbols.indices.contains(idx)
                    ? signature.valueParameterSymbols[idx]
                    : classSymbol
                params.append(KIRParameter(symbol: paramSym, type: paramType))
            }

            var body: [KIRInstruction] = []
            if let genClass = info.generatedSerializerClass,
               let genCtor = info.serializerConstructor
            {
                let instanceExpr = emitAllocatePluginNominalInstance(
                    ownerSymbol: genClass,
                    resultType: signature.returnType,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &body
                )
                let ctorRes = arena.appendTemporary(type: signature.returnType)
                body.append(.call(
                    symbol: genCtor,
                    callee: interner.intern("<init>"),
                    arguments: [instanceExpr],
                    result: ctorRes,
                    canThrow: false
                ))
                body.append(.returnValue(instanceExpr))
            } else {
                let dummyResult = arena.appendExpr(.null, type: signature.returnType)
                body.append(.constValue(result: dummyResult, value: .null))
                body.append(.returnValue(dummyResult))
            }

            let kirFunc = KIRFunction(
                symbol: serializerSym,
                name: interner.intern("serializer"),
                params: params,
                returnType: signature.returnType,
                body: body,
                isSuspend: false,
                isInline: false
            )
            let declID = arena.appendDecl(.function(kirFunc))
            companionMemberDecls.append(declID)
            extraDecls.append(declID)
        }

        // If KotlinxSerializationPlugin synthesized a Companion not present in AST,
        // emit its KIRGlobal + KIRNominalType so Companion.serializer() resolves at link time.
        if let compID = info.companionObjectSymbol, classDecl.companionObject == nil {
            let compType = sema.types.make(.classType(ClassType(
                classSymbol: compID,
                args: [],
                nullability: .nonNull
            )))
            extraDecls.append(arena.appendDecl(.global(KIRGlobal(symbol: compID, type: compType))))
            extraDecls.append(arena.appendDecl(.nominalType(KIRNominalType(
                symbol: compID,
                memberDecls: companionMemberDecls
            ))))
            extraDecls.append(emitPluginSingletonInitializer(
                objectSymbol: compID,
                objectType: compType,
                shared: shared
            ))
        }

        // 2. $serializer nested class & its members
        if let genClass = info.generatedSerializerClass {
            var genMembers: [KIRDeclID] = []

            if let ctorSym = info.serializerConstructor,
               arena.function(for: ctorSym) == nil,
               let sig = sema.symbols.functionSignature(for: ctorSym)
            {
                let genType = sig.receiverType ?? sema.types.anyType
                let selfParam = makePluginSyntheticParam(
                    ownerFQName: sema.symbols.symbol(ctorSym)?.fqName ?? [],
                    shared: shared
                )
                let selfRef = arena.appendExpr(.symbolRef(selfParam), type: genType)
                let kirFunc = KIRFunction(
                    symbol: ctorSym,
                    name: interner.intern("<init>"),
                    params: [KIRParameter(symbol: selfParam, type: genType)],
                    returnType: sig.returnType,
                    body: [
                        .constValue(result: selfRef, value: .symbolRef(selfParam)),
                        .returnValue(selfRef),
                    ],
                    isSuspend: false,
                    isInline: false
                )
                extraDecls.append(arena.appendDecl(.function(kirFunc)))
            }

            if let descGetter = info.descriptorGetter,
               arena.function(for: descGetter) == nil,
               let sig = sema.symbols.functionSignature(for: descGetter),
               let declID = emitSerializerDescriptorGetter(
                   getterSymbol: descGetter,
                   targetClass: classSymbol,
                   properties: info.serializableProperties,
                   signature: sig,
                   shared: shared
               )
            {
                genMembers.append(declID)
                extraDecls.append(declID)
            }

            if let serializeSym = info.serializeMethod,
               arena.function(for: serializeSym) == nil,
               let sig = sema.symbols.functionSignature(for: serializeSym),
               let declID = emitSerializerSerializeMethod(
                   methodSymbol: serializeSym,
                   targetClass: classSymbol,
                   descriptorGetter: info.descriptorGetter,
                   properties: info.serializableProperties,
                   signature: sig,
                   shared: shared
               )
            {
                genMembers.append(declID)
                extraDecls.append(declID)
            }

            if let deserializeSym = info.deserializeMethod,
               arena.function(for: deserializeSym) == nil,
               let sig = sema.symbols.functionSignature(for: deserializeSym),
               let declID = emitSerializerDeserializeMethod(
                   methodSymbol: deserializeSym,
                   targetClass: classSymbol,
                   descriptorGetter: info.descriptorGetter,
                   properties: info.serializableProperties,
                   signature: sig,
                   shared: shared
               )
            {
                genMembers.append(declID)
                extraDecls.append(declID)
            }

            extraDecls.append(arena.appendDecl(.nominalType(KIRNominalType(
                symbol: genClass,
                memberDecls: genMembers
            ))))
        }

        return extraDecls
    }

    // MARK: - $serializer Member Emitters

    private func emitSerializerDescriptorGetter(
        getterSymbol: SymbolID,
        targetClass: SymbolID,
        properties: [SerializationPropertyInfo],
        signature: FunctionSignature,
        shared: KIRLoweringSharedContext
    ) -> KIRDeclID? {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let genType = signature.receiverType ?? sema.types.anyType
        let selfParam = makePluginSyntheticParam(
            ownerFQName: sema.symbols.symbol(getterSymbol)?.fqName ?? [],
            shared: shared
        )
        let selfRef = arena.appendExpr(.symbolRef(selfParam), type: genType)
        let targetFQName = sema.symbols.symbol(targetClass)?
            .fqName.map { interner.resolve($0) }.joined(separator: ".") ?? "Unknown"

        var body: [KIRInstruction] = [
            .constValue(result: selfRef, value: .symbolRef(selfParam)),
        ]

        let builderFQ = ["kotlinx", "serialization", "descriptors", "ClassSerialDescriptorBuilder"].map { interner.intern($0) }
        let descImplFQ = ["kotlinx", "serialization", "descriptors", "SerialDescriptorImpl"].map { interner.intern($0) }
        let structClassFQ = ["kotlinx", "serialization", "descriptors", "StructureKind", "CLASS"].map { interner.intern($0) }
        let primDescFQ = ["kotlinx", "serialization", "internal", "PrimitiveSerialDescriptor"].map { interner.intern($0) }

        if let builderClass = sema.symbols.lookup(fqName: builderFQ),
           let builderCtor = lookupInitConstructor(on: builderClass, arity: 1, sema: sema, interner: interner),
           let elementMethod = findPluginMethodSymbol(on: builderClass, named: "element", arity: 4, sema: sema, interner: interner),
           let descImplClass = sema.symbols.lookup(fqName: descImplFQ),
           let descImplCtor = lookupInitConstructor(on: descImplClass, arity: 5, sema: sema, interner: interner),
           let structKindClass = sema.symbols.lookup(fqName: structClassFQ)
        {
            let serialNameExpr = arena.appendExpr(.stringLiteral(interner.intern(targetFQName)), type: sema.types.stringType)
            body.append(.constValue(result: serialNameExpr, value: .stringLiteral(interner.intern(targetFQName))))

            let builderType = sema.types.make(.classType(ClassType(classSymbol: builderClass, args: [], nullability: .nonNull)))
            let builderObj = emitAllocatePluginNominalInstance(
                ownerSymbol: builderClass,
                resultType: builderType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &body
            )
            let builderCtorRes = arena.appendTemporary(type: builderType)
            body.append(.call(
                symbol: builderCtor,
                callee: interner.intern("<init>"),
                arguments: [builderObj, serialNameExpr],
                result: builderCtorRes,
                canThrow: false
            ))

            let emptyListExpr = emitEmptyListCall(sema: sema, arena: arena, interner: interner, instructions: &body)
            let falseExpr = arena.appendExpr(.boolLiteral(false), type: sema.types.booleanType)
            body.append(.constValue(result: falseExpr, value: .boolLiteral(false)))

            let primDescClass = sema.symbols.lookup(fqName: primDescFQ)
            let primDescCtor = primDescClass.flatMap { lookupInitConstructor(on: $0, arity: 2, sema: sema, interner: interner) }

            for propInfo in properties {
                let propType = sema.symbols.propertyType(for: propInfo.symbol) ?? sema.types.anyType
                let elemNameExpr = arena.appendExpr(.stringLiteral(interner.intern(propInfo.serialName)), type: sema.types.stringType)
                body.append(.constValue(result: elemNameExpr, value: .stringLiteral(interner.intern(propInfo.serialName))))

                let elemDescExpr: KIRExprID
                if let primDescClass,
                   let primDescCtor,
                   let primKindObj = resolvePrimitiveKindObject(for: propType, sema: sema, interner: interner)
                {
                    let primDescType = sema.types.make(.classType(ClassType(classSymbol: primDescClass, args: [], nullability: .nonNull)))
                    let primObj = emitAllocatePluginNominalInstance(
                        ownerSymbol: primDescClass,
                        resultType: primDescType,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &body
                    )
                    let kindType = sema.types.make(.classType(ClassType(classSymbol: primKindObj, args: [], nullability: .nonNull)))
                    let kindExpr = emitLoadPluginSingletonObject(
                        objectSymbol: primKindObj,
                        resultType: kindType,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &body
                    )
                    let primSerialExpr = arena.appendExpr(.stringLiteral(interner.intern(propInfo.serialName)), type: sema.types.stringType)
                    body.append(.constValue(result: primSerialExpr, value: .stringLiteral(interner.intern(propInfo.serialName))))
                    let ctorRes = arena.appendTemporary(type: primDescType)
                    body.append(.call(
                        symbol: primDescCtor,
                        callee: interner.intern("<init>"),
                        arguments: [primObj, primSerialExpr, kindExpr],
                        result: ctorRes,
                        canThrow: false
                    ))
                    elemDescExpr = primObj
                } else {
                    let nilDesc = arena.appendExpr(.null, type: signature.returnType)
                    body.append(.constValue(result: nilDesc, value: .null))
                    elemDescExpr = nilDesc
                }

                _ = emitPluginMemberCall(
                    receiver: builderObj,
                    receiverNominalSymbol: builderClass,
                    methodSymbol: elementMethod,
                    arguments: [elemNameExpr, elemDescExpr, emptyListExpr, falseExpr],
                    returnType: sema.types.unitType,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &body
                )
            }

            let structKindType = sema.types.make(.classType(ClassType(classSymbol: structKindClass, args: [], nullability: .nonNull)))
            let structKindExpr = emitLoadPluginSingletonObject(
                objectSymbol: structKindClass,
                resultType: structKindType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &body
            )
            let countExpr = arena.appendExpr(.intLiteral(Int64(properties.count)), type: sema.types.intType)
            body.append(.constValue(result: countExpr, value: .intLiteral(Int64(properties.count))))

            let descImplObj = emitAllocatePluginNominalInstance(
                ownerSymbol: descImplClass,
                resultType: signature.returnType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &body
            )
            let descCtorRes = arena.appendTemporary(type: signature.returnType)
            body.append(.call(
                symbol: descImplCtor,
                callee: interner.intern("<init>"),
                arguments: [descImplObj, serialNameExpr, structKindExpr, countExpr, emptyListExpr, builderObj],
                result: descCtorRes,
                canThrow: false
            ))
            body.append(.returnValue(descImplObj))
        } else {
            let nullDesc = arena.appendExpr(.null, type: signature.returnType)
            body.append(.constValue(result: nullDesc, value: .null))
            body.append(.returnValue(nullDesc))
        }

        let kirFunc = KIRFunction(
            symbol: getterSymbol,
            name: interner.intern("<get-descriptor>"),
            params: [KIRParameter(symbol: selfParam, type: genType)],
            returnType: signature.returnType,
            body: body,
            isSuspend: false,
            isInline: false
        )
        return arena.appendDecl(.function(kirFunc))
    }

    private func emitSerializerSerializeMethod(
        methodSymbol: SymbolID,
        targetClass: SymbolID,
        descriptorGetter: SymbolID?,
        properties: [SerializationPropertyInfo],
        signature: FunctionSignature,
        shared: KIRLoweringSharedContext
    ) -> KIRDeclID? {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let genType = signature.receiverType ?? sema.types.anyType
        let encoderType = signature.parameterTypes.first ?? sema.types.anyType
        let valueType = signature.parameterTypes.count > 1 ? signature.parameterTypes[1] : sema.types.anyType

        let selfParam = makePluginSyntheticParam(ownerFQName: sema.symbols.symbol(methodSymbol)?.fqName ?? [], shared: shared)
        let encParam = signature.valueParameterSymbols.first ?? makePluginSyntheticParam(
            ownerFQName: sema.symbols.symbol(methodSymbol)?.fqName ?? [],
            paramName: "encoder",
            shared: shared
        )
        let valParam = signature.valueParameterSymbols.count > 1
            ? signature.valueParameterSymbols[1]
            : makePluginSyntheticParam(
                ownerFQName: sema.symbols.symbol(methodSymbol)?.fqName ?? [],
                paramName: "value",
                shared: shared
            )

        let selfRef = arena.appendExpr(.symbolRef(selfParam), type: genType)
        let encRef = arena.appendExpr(.symbolRef(encParam), type: encoderType)
        let valRef = arena.appendExpr(.symbolRef(valParam), type: valueType)

        var body: [KIRInstruction] = [
            .constValue(result: selfRef, value: .symbolRef(selfParam)),
            .constValue(result: encRef, value: .symbolRef(encParam)),
            .constValue(result: valRef, value: .symbolRef(valParam)),
        ]

        let encoderSym = sema.symbols.lookup(fqName: ["kotlinx", "serialization", "encoding", "Encoder"].map { interner.intern($0) })
        let compositeSym = sema.symbols.lookup(fqName: ["kotlinx", "serialization", "encoding", "CompositeEncoder"].map { interner.intern($0) })

        if let descriptorGetter,
           let encoderSym,
           let compositeSym,
           let beginStructureSym = findPluginMethodSymbol(on: encoderSym, named: "beginStructure", arity: 1, sema: sema, interner: interner),
           let endStructureSym = findPluginMethodSymbol(on: compositeSym, named: "endStructure", arity: 1, sema: sema, interner: interner)
        {
            let descType = sema.symbols.functionSignature(for: descriptorGetter)?.returnType ?? sema.types.anyType
            let descExpr = arena.appendTemporary(type: descType)
            body.append(.call(
                symbol: descriptorGetter,
                callee: interner.intern("<get-descriptor>"),
                arguments: [selfRef],
                result: descExpr,
                canThrow: false
            ))

            let compositeType = sema.types.make(.classType(ClassType(classSymbol: compositeSym, args: [], nullability: .nonNull)))
            if let compositeExpr = emitPluginMemberCall(
                receiver: encRef,
                receiverNominalSymbol: encoderSym,
                methodSymbol: beginStructureSym,
                arguments: [descExpr],
                returnType: compositeType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &body
            ) {
                for (index, propInfo) in properties.enumerated() {
                    guard let offset = resolvePluginPropertyOffset(
                        ownerClass: targetClass,
                        propertySymbol: propInfo.symbol,
                        sema: sema
                    ) else { continue }
                    let propType = sema.symbols.propertyType(for: propInfo.symbol) ?? sema.types.anyType
                    let offsetExpr = arena.appendExpr(.intLiteral(Int64(offset)), type: sema.types.intType)
                    body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(offset))))
                    let fieldVal = arena.appendTemporary(type: propType)
                    body.append(.call(
                        callee: interner.intern("kk_array_get_inbounds"),
                        arguments: [valRef, offsetExpr],
                        result: fieldVal,
                        canThrow: false
                    ))
                    let indexExpr = arena.appendExpr(.intLiteral(Int64(index)), type: sema.types.intType)
                    body.append(.constValue(result: indexExpr, value: .intLiteral(Int64(index))))
                    if let encodeMethodName = compositeEncodeMethodName(for: propType, sema: sema),
                       let encodeMethod = findPluginMethodSymbol(on: compositeSym, named: encodeMethodName, arity: 3, sema: sema, interner: interner)
                    {
                        _ = emitPluginMemberCall(
                            receiver: compositeExpr,
                            receiverNominalSymbol: compositeSym,
                            methodSymbol: encodeMethod,
                            arguments: [descExpr, indexExpr, fieldVal],
                            returnType: sema.types.unitType,
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            instructions: &body
                        )
                    }
                }

                _ = emitPluginMemberCall(
                    receiver: compositeExpr,
                    receiverNominalSymbol: compositeSym,
                    methodSymbol: endStructureSym,
                    arguments: [descExpr],
                    returnType: sema.types.unitType,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &body
                )
            }
        }

        body.append(.returnUnit)

        let kirFunc = KIRFunction(
            symbol: methodSymbol,
            name: interner.intern("serialize"),
            params: [
                KIRParameter(symbol: selfParam, type: genType),
                KIRParameter(symbol: encParam, type: encoderType),
                KIRParameter(symbol: valParam, type: valueType),
            ],
            returnType: sema.types.unitType,
            body: body,
            isSuspend: false,
            isInline: false
        )
        return arena.appendDecl(.function(kirFunc))
    }

    private func emitSerializerDeserializeMethod(
        methodSymbol: SymbolID,
        targetClass: SymbolID,
        descriptorGetter: SymbolID?,
        properties: [SerializationPropertyInfo],
        signature: FunctionSignature,
        shared: KIRLoweringSharedContext
    ) -> KIRDeclID? {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let genType = signature.receiverType ?? sema.types.anyType
        let decoderType = signature.parameterTypes.first ?? sema.types.anyType

        let selfParam = makePluginSyntheticParam(ownerFQName: sema.symbols.symbol(methodSymbol)?.fqName ?? [], shared: shared)
        let decParam = signature.valueParameterSymbols.first ?? makePluginSyntheticParam(
            ownerFQName: sema.symbols.symbol(methodSymbol)?.fqName ?? [],
            paramName: "decoder",
            shared: shared
        )

        let selfRef = arena.appendExpr(.symbolRef(selfParam), type: genType)
        let decRef = arena.appendExpr(.symbolRef(decParam), type: decoderType)

        var body: [KIRInstruction] = [
            .constValue(result: selfRef, value: .symbolRef(selfParam)),
            .constValue(result: decRef, value: .symbolRef(decParam)),
        ]

        let targetObj = emitAllocatePluginNominalInstance(
            ownerSymbol: targetClass,
            resultType: signature.returnType,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body
        )

        let decoderSym = sema.symbols.lookup(fqName: ["kotlinx", "serialization", "encoding", "Decoder"].map { interner.intern($0) })
        let compositeSym = sema.symbols.lookup(fqName: ["kotlinx", "serialization", "encoding", "CompositeDecoder"].map { interner.intern($0) })

        if let descriptorGetter,
           let decoderSym,
           let compositeSym,
           let beginStructureSym = findPluginMethodSymbol(on: decoderSym, named: "beginStructure", arity: 1, sema: sema, interner: interner),
           let decodeIndexSym = findPluginMethodSymbol(on: compositeSym, named: "decodeElementIndex", arity: 1, sema: sema, interner: interner),
           let endStructureSym = findPluginMethodSymbol(on: compositeSym, named: "endStructure", arity: 1, sema: sema, interner: interner)
        {
            let descType = sema.symbols.functionSignature(for: descriptorGetter)?.returnType ?? sema.types.anyType
            let descExpr = arena.appendTemporary(type: descType)
            body.append(.call(
                symbol: descriptorGetter,
                callee: interner.intern("<get-descriptor>"),
                arguments: [selfRef],
                result: descExpr,
                canThrow: false
            ))

            let compositeType = sema.types.make(.classType(ClassType(classSymbol: compositeSym, args: [], nullability: .nonNull)))
            if let compositeExpr = emitPluginMemberCall(
                receiver: decRef,
                receiverNominalSymbol: decoderSym,
                methodSymbol: beginStructureSym,
                arguments: [descExpr],
                returnType: compositeType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &body
            ) {
                let loopStartLabel = ctx.makeLoopLabel()
                let loopEndLabel = ctx.makeLoopLabel()
                let doneIdxExpr = arena.appendExpr(.intLiteral(-1), type: sema.types.intType)
                body.append(.constValue(result: doneIdxExpr, value: .intLiteral(-1)))

                body.append(.label(loopStartLabel))
                if let nextIdxExpr = emitPluginMemberCall(
                    receiver: compositeExpr,
                    receiverNominalSymbol: compositeSym,
                    methodSymbol: decodeIndexSym,
                    arguments: [descExpr],
                    returnType: sema.types.intType,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &body
                ) {
                    body.append(.jumpIfEqual(lhs: nextIdxExpr, rhs: doneIdxExpr, target: loopEndLabel))

                    let nextIterLabel = ctx.makeLoopLabel()
                    for (index, propInfo) in properties.enumerated() {
                        guard let offset = resolvePluginPropertyOffset(
                            ownerClass: targetClass,
                            propertySymbol: propInfo.symbol,
                            sema: sema
                        ) else { continue }
                        let propType = sema.symbols.propertyType(for: propInfo.symbol) ?? sema.types.anyType
                        guard let decodeMethodName = compositeDecodeMethodName(for: propType, sema: sema),
                              let decodeMethod = findPluginMethodSymbol(on: compositeSym, named: decodeMethodName, arity: 2, sema: sema, interner: interner)
                        else { continue }

                        let matchLabel = ctx.makeLoopLabel()
                        let skipLabel = ctx.makeLoopLabel()
                        let caseIdxExpr = arena.appendExpr(.intLiteral(Int64(index)), type: sema.types.intType)
                        body.append(.constValue(result: caseIdxExpr, value: .intLiteral(Int64(index))))
                        body.append(.jumpIfEqual(lhs: nextIdxExpr, rhs: caseIdxExpr, target: matchLabel))
                        body.append(.jump(skipLabel))
                        body.append(.label(matchLabel))

                        if let decodedVal = emitPluginMemberCall(
                            receiver: compositeExpr,
                            receiverNominalSymbol: compositeSym,
                            methodSymbol: decodeMethod,
                            arguments: [descExpr, caseIdxExpr],
                            returnType: propType,
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
                                arguments: [targetObj, offsetExpr, decodedVal],
                                result: setRes,
                                canThrow: false
                            ))
                        }
                        body.append(.jump(nextIterLabel))
                        body.append(.label(skipLabel))
                    }
                    body.append(.label(nextIterLabel))
                    body.append(.jump(loopStartLabel))
                    body.append(.label(loopEndLabel))
                }

                _ = emitPluginMemberCall(
                    receiver: compositeExpr,
                    receiverNominalSymbol: compositeSym,
                    methodSymbol: endStructureSym,
                    arguments: [descExpr],
                    returnType: sema.types.unitType,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &body
                )
            }
        }

        body.append(.returnValue(targetObj))

        let kirFunc = KIRFunction(
            symbol: methodSymbol,
            name: interner.intern("deserialize"),
            params: [
                KIRParameter(symbol: selfParam, type: genType),
                KIRParameter(symbol: decParam, type: decoderType),
            ],
            returnType: signature.returnType,
            body: body,
            isSuspend: false,
            isInline: false
        )
        return arena.appendDecl(.function(kirFunc))
    }

    // MARK: - Descriptor & Primitive Helpers

    private func lookupInitConstructor(
        on classSymbol: SymbolID,
        arity: Int,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        guard let info = sema.symbols.symbol(classSymbol) else { return nil }
        let initName = interner.intern("<init>")
        return sema.symbols.lookupAll(fqName: info.fqName + [initName]).first {
            sema.symbols.symbol($0)?.kind == .constructor
                && sema.symbols.parentSymbol(for: $0) == classSymbol
                && sema.symbols.functionSignature(for: $0)?.parameterTypes.count == arity
        }
    }

    private func emitEmptyListCall(
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let emptyListFQ = [interner.intern("kotlin"), interner.intern("collections"), interner.intern("emptyList")]
        if let sym = sema.symbols.lookupAll(fqName: emptyListFQ).first(where: {
            sema.symbols.symbol($0)?.kind == .function
                && sema.symbols.functionSignature(for: $0)?.parameterTypes.isEmpty == true
        }) {
            let link = sema.symbols.externalLinkName(for: sym).map { interner.intern($0) } ?? interner.intern("emptyList")
            let res = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(symbol: sym, callee: link, arguments: [], result: res, canThrow: false))
            return res
        }
        let nullList = arena.appendExpr(.null, type: sema.types.anyType)
        instructions.append(.constValue(result: nullList, value: .null))
        return nullList
    }

    private func resolvePrimitiveKindObject(
        for type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let nonNull = sema.types.makeNonNullable(type)
        let kindName: String
        if nonNull == sema.types.stringType {
            kindName = "STRING"
        } else {
            switch sema.types.kind(of: nonNull) {
            case .primitive(.boolean, _): kindName = "BOOLEAN"
            case .primitive(.byte, _): kindName = "BYTE"
            case .primitive(.char, _): kindName = "CHAR"
            case .primitive(.short, _): kindName = "SHORT"
            case .primitive(.int, _): kindName = "INT"
            case .primitive(.long, _): kindName = "LONG"
            case .primitive(.float, _): kindName = "FLOAT"
            case .primitive(.double, _): kindName = "DOUBLE"
            default: kindName = "STRING"
            }
        }
        return sema.symbols.lookup(
            fqName: ["kotlinx", "serialization", "descriptors", "PrimitiveKind", kindName].map { interner.intern($0) }
        )
    }

    private func compositeEncodeMethodName(for type: TypeID, sema: SemaModule) -> String? {
        let nonNull = sema.types.makeNonNullable(type)
        if nonNull == sema.types.stringType { return "encodeStringElement" }
        switch sema.types.kind(of: nonNull) {
        case .primitive(.boolean, _): return "encodeBooleanElement"
        case .primitive(.byte, _): return "encodeByteElement"
        case .primitive(.char, _): return "encodeCharElement"
        case .primitive(.short, _): return "encodeShortElement"
        case .primitive(.int, _): return "encodeIntElement"
        case .primitive(.long, _): return "encodeLongElement"
        case .primitive(.float, _): return "encodeFloatElement"
        case .primitive(.double, _): return "encodeDoubleElement"
        default: return nil
        }
    }

    private func compositeDecodeMethodName(for type: TypeID, sema: SemaModule) -> String? {
        let nonNull = sema.types.makeNonNullable(type)
        if nonNull == sema.types.stringType { return "decodeStringElement" }
        switch sema.types.kind(of: nonNull) {
        case .primitive(.boolean, _): return "decodeBooleanElement"
        case .primitive(.byte, _): return "decodeByteElement"
        case .primitive(.char, _): return "decodeCharElement"
        case .primitive(.short, _): return "decodeShortElement"
        case .primitive(.int, _): return "decodeIntElement"
        case .primitive(.long, _): return "decodeLongElement"
        case .primitive(.float, _): return "decodeFloatElement"
        case .primitive(.double, _): return "decodeDoubleElement"
        default: return nil
        }
    }
}
