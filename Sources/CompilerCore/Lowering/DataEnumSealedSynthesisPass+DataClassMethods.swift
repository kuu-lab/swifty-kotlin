// swiftlint:disable file_length

extension DataEnumSealedSynthesisPass {
    func appendSyntheticDataCopyIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        module: KIRModule,
        sema: SemaModule,
        existingSymbol: SymbolID?,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner,
        diagnostics: DiagnosticEngine
    ) {
        guard owner.kind == .class || owner.kind == .enumClass || owner.kind == .object,
              let functionSymbol = existingSymbol
        else {
            return
        }
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let selfParamName = interner.intern("$self")
        let fqName = owner.fqName + [name]
        let selfParamSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: selfParamName,
            fqName: fqName + [selfParamName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let selfParam = KIRParameter(symbol: selfParamSymbol, type: receiverType)

        // Prefer the declared constructor symbol by FQName to stay aligned with
        // the lowered constructor body that codegen will emit.
        let initName = interner.intern("<init>")
        let ctorFQName = owner.fqName + [initName]
        let ctorSymbol = sema.symbols.lookupAll(fqName: ctorFQName).first { symbolID in
            sema.symbols.symbol(symbolID)?.kind == .constructor
        }

        // Guard: if no constructor is found, emit a simple self-returning copy()
        // to avoid generating an invalid .call instruction with nil symbol.
        guard let resolvedCtorSymbol = ctorSymbol,
              let ctorSignature = sema.symbols.functionSignature(for: resolvedCtorSymbol)
        else {
            let ownerName = interner.resolve(owner.name)
            diagnostics.warning(
                "KSWIFTK-DATA-0001",
                "data class '\(ownerName)' has no primary constructor; copy() returns self unchanged",
                range: owner.declSite
            )
            let resultExpr = module.arena.appendTemporary(type: receiverType
            )
            let body: [KIRInstruction] = [
                .constValue(result: resultExpr, value: .symbolRef(selfParamSymbol)),
                .returnValue(resultExpr),
            ]
            let signature = FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: receiverType,
                isSuspend: false
            )
            appendSyntheticFunctionWithSymbol(
                functionSymbol: functionSymbol,
                name: name,
                module: module,
                sema: sema,
                signature: signature,
                params: [selfParam],
                body: body
            )
            return
        }

        // The constructor signature stores symbols in valueParameterSymbols and
        // types in parameterTypes. When a receiver type is prepended to
        // parameterTypes (but not to valueParameterSymbols), we strip the leading
        // receiver entry from parameterTypes so that both arrays align 1-to-1.
        // We check both the locally-constructed receiverType and the signature's
        // own receiverType so that generic data classes (whose receiver type
        // may carry type arguments) are handled correctly.
        let ctorParamSymbols = ctorSignature.valueParameterSymbols
        var ctorParamTypes = ctorSignature.parameterTypes
        if ctorParamTypes.count > ctorParamSymbols.count,
           ctorParamTypes.first == receiverType || ctorParamTypes.first == ctorSignature.receiverType {
            ctorParamTypes.removeFirst()
        }

        let pairCount = min(ctorParamSymbols.count, ctorParamTypes.count)
        if ctorParamSymbols.count != ctorParamTypes.count {
            let ownerName = interner.resolve(owner.name)
            diagnostics.warning(
                "KSWIFTK-DATA-0002",
                "data class '\(ownerName)' constructor signature mismatch: \(ctorParamSymbols.count) parameter symbols vs \(ctorParamTypes.count) parameter types; copy() uses first \(pairCount)",
                range: owner.declSite
            )
        }
        let propertyParams: [(symbol: SymbolID, type: TypeID)] = (0..<pairCount).map { i in
            (ctorParamSymbols[i], ctorParamTypes[i])
        }

        // Each copy parameter mirrors the corresponding constructor parameter name
        // (e.g. name, age) so diagnostics and dumps reflect Kotlin's copy(name=..., age=...).
        var allParams: [KIRParameter] = [selfParam]
        var allParamSymbols: [SymbolID] = [selfParamSymbol]
        var allParamTypes: [TypeID] = [receiverType]
        var allParamHasDefault: [Bool] = [false]
        var allParamIsVararg: [Bool] = [false]
        var copyParamSymbols: [SymbolID] = []

        for (ctorSym, paramType) in propertyParams {
            let ctorParamName = sema.symbols.symbol(ctorSym)?.name ?? interner.intern("$copy_\(allParams.count)")
            let paramSymbol = sema.symbols.define(
                kind: .valueParameter,
                name: ctorParamName,
                fqName: fqName + [ctorParamName],
                declSite: owner.declSite,
                visibility: .private,
                flags: [.synthetic]
            )
            allParams.append(KIRParameter(symbol: paramSymbol, type: paramType))
            allParamSymbols.append(paramSymbol)
            allParamTypes.append(paramType)
            allParamHasDefault.append(true)
            allParamIsVararg.append(false)
            copyParamSymbols.append(paramSymbol)
        }

        var body: [KIRInstruction] = []
        let intType = sema.types.intType

        var ctorArgExprs: [KIRExprID] = []
        for (index, paramSymbol) in copyParamSymbols.enumerated() {
            let paramType = propertyParams[index].type
            let paramExpr = module.arena.appendTemporary(type: paramType
            )
            body.append(.constValue(result: paramExpr, value: .symbolRef(paramSymbol)))
            ctorArgExprs.append(paramExpr)
        }

        let slotCount = Int64(max(sema.symbols.nominalLayout(for: owner.id)?.instanceSizeWords ?? 1, 1))
        let slotCountExpr = module.arena.appendExpr(.intLiteral(slotCount), type: intType)
        body.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
        let classIDValue = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: owner.id,
            sema: sema,
            interner: interner
        )
        let classIDExpr = module.arena.appendExpr(.intLiteral(classIDValue), type: intType)
        body.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))
        let allocatedObjectExpr = module.arena.appendTemporary(type: receiverType
        )
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: allocatedObjectExpr,
            canThrow: false,
            thrownResult: nil
        ))

        // A local data class restores enclosing captures from its instance
        // fields inside <init>. Preserve those fields before running the new
        // instance's initializers; body properties themselves are reinitialized.
        let capturedSymbols = sema.bindings.objectLiteralCaptureSymbols(for: owner.id)
        if !capturedSymbols.isEmpty {
            let selfRef = module.arena.appendExpr(.symbolRef(selfParamSymbol), type: receiverType)
            body.append(.constValue(result: selfRef, value: .symbolRef(selfParamSymbol)))
            let layout = sema.symbols.nominalLayout(for: owner.id)
            for capturedSymbol in capturedSymbols {
                guard let offset = layout?.fieldOffsets[capturedSymbol] else { continue }
                let offsetExpr = module.arena.appendExpr(.intLiteral(Int64(offset)), type: intType)
                body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(offset))))
                let captureSymbol = sema.symbols.symbol(capturedSymbol)
                let isMutableLocal = captureSymbol?.kind == .local
                    && captureSymbol?.flags.contains(.mutable) == true
                let captureType = isMutableLocal ? sema.types.anyType
                    : (sema.bindings.capturedLocalType(for: capturedSymbol)
                        ?? sema.symbols.propertyType(for: capturedSymbol) ?? sema.types.anyType)
                let value = module.arena.appendTemporary(type: captureType)
                body.append(.call(
                    symbol: nil, callee: interner.intern("kk_array_get_inbounds"),
                    arguments: [selfRef, offsetExpr], result: value,
                    canThrow: false, thrownResult: nil
                ))
                let stored = module.arena.appendTemporary(type: sema.types.unitType)
                body.append(.call(
                    symbol: nil, callee: interner.intern("kk_array_set"),
                    arguments: [allocatedObjectExpr, offsetExpr, value], result: stored,
                    canThrow: false, thrownResult: nil
                ))
            }
        }

        let resultExpr = module.arena.appendTemporary(type: receiverType
        )
        body.append(.call(
            symbol: resolvedCtorSymbol,
            callee: initName,
            arguments: [allocatedObjectExpr] + ctorArgExprs,
            result: resultExpr,
            canThrow: false,
            thrownResult: nil
        ))
        body.append(.returnValue(resultExpr))

        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: propertyParams.map(\.type),
            returnType: receiverType,
            isSuspend: false,
            valueParameterSymbols: copyParamSymbols,
            valueParameterHasDefaultValues: Array(repeating: true, count: copyParamSymbols.count),
            valueParameterIsVararg: Array(repeating: false, count: copyParamSymbols.count)
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: functionSymbol,
            name: name,
            module: module,
            sema: sema,
            signature: signature,
            params: allParams,
            body: body
        )
        appendSyntheticDataCopyDefaultStubIfNeeded(
            functionSymbol: functionSymbol,
            name: name,
            owner: owner,
            receiverType: receiverType,
            propertyParams: propertyParams,
            module: module,
            sema: sema,
            interner: interner
        )
    }

    func appendSyntheticDataCopyDefaultStubIfNeeded(
        functionSymbol: SymbolID,
        name: InternedString,
        owner: SemanticSymbol,
        receiverType: TypeID,
        propertyParams: [(symbol: SymbolID, type: TypeID)],
        module: KIRModule,
        sema: SemaModule,
        interner: StringInterner
    ) {
        let intType = sema.types.intType
        let maskType = sema.types.longType
        let fqName = owner.fqName + [name]
        let selfParamName = interner.intern("$self")
        let selfParamSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: selfParamName,
            fqName: fqName + [interner.intern("$default")] + [selfParamName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        var params: [KIRParameter] = [KIRParameter(symbol: selfParamSymbol, type: receiverType)]
        var valueParamSymbols: [SymbolID] = []
        for (index, propertyParam) in propertyParams.enumerated() {
            let paramName = sema.symbols.symbol(propertyParam.symbol)?.name ?? interner.intern("$copy_\(index)")
            let paramSymbol = sema.symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: fqName + [interner.intern("$default")] + [paramName],
                declSite: owner.declSite,
                visibility: .private,
                flags: [.synthetic]
            )
            params.append(KIRParameter(symbol: paramSymbol, type: propertyParam.type))
            valueParamSymbols.append(paramSymbol)
        }
        let maskWordCount = DefaultArgumentMask(parameterCount: propertyParams.count).stubWords.count
        let maskSymbols = [SyntheticSymbolScheme.defaultMaskSymbol(for: functionSymbol)]
            + (1 ..< maskWordCount).map { wordIndex in
                let maskName = interner.intern("$mask_\(wordIndex)")
                return sema.symbols.define(
                    kind: .valueParameter,
                    name: maskName,
                    fqName: fqName + [interner.intern("$default"), maskName],
                    declSite: owner.declSite,
                    visibility: .private,
                    flags: [.synthetic]
                )
            }
        params.append(contentsOf: maskSymbols.map { KIRParameter(symbol: $0, type: maskType) })

        let defaultStubName = interner.intern("\(interner.resolve(name))$default")
        let defaultStubSymbol = SyntheticSymbolScheme.defaultStubSymbol(for: functionSymbol)
        let selfRef = module.arena.appendExpr(.symbolRef(selfParamSymbol), type: receiverType)
        let maskRefs = maskSymbols.map { module.arena.appendExpr(.symbolRef($0), type: maskType) }
        var body: [KIRInstruction] = [
            .constValue(result: selfRef, value: .symbolRef(selfParamSymbol)),
        ]
        for (symbol, ref) in zip(maskSymbols, maskRefs) {
            body.append(.constValue(result: ref, value: .symbolRef(symbol)))
        }

        let layout = sema.symbols.nominalLayout(for: owner.id)
        let propertySymbols = primaryConstructorPropertySymbols(owner: owner, sema: sema)
        var resolvedArgs: [KIRExprID] = []

        for (index, propertyParam) in propertyParams.enumerated() {
            let providedExpr = module.arena.appendExpr(.symbolRef(valueParamSymbols[index]), type: propertyParam.type)
            body.append(.constValue(result: providedExpr, value: .symbolRef(valueParamSymbols[index])))

            let bitValue = Int64(1) << (index % DefaultArgumentMask.bitsPerWord)
            let bitExpr = module.arena.appendExpr(.intLiteral(bitValue), type: maskType)
            body.append(.constValue(result: bitExpr, value: .intLiteral(bitValue)))

            let maskedExpr = module.arena.appendTemporary(type: maskType
            )
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_bitwise_and"),
                arguments: [maskRefs[index / DefaultArgumentMask.bitsPerWord], bitExpr],
                result: maskedExpr,
                canThrow: false,
                thrownResult: nil
            ))

            let zeroExpr = module.arena.appendExpr(.intLiteral(0), type: maskType)
            body.append(.constValue(result: zeroExpr, value: .intLiteral(0)))

            let resolvedExpr = module.arena.appendTemporary(type: propertyParam.type
            )
            let useProvidedLabel = Int32(20000 + index * 2)
            let afterLabel = Int32(20001 + index * 2)
            body.append(.jumpIfEqual(lhs: maskedExpr, rhs: zeroExpr, target: useProvidedLabel))

            if let layout,
               index < propertySymbols.count,
               let propertySymbol = propertySymbols[index]
            {
                let backingField = sema.symbols.backingFieldSymbol(for: propertySymbol.id) ?? propertySymbol.id
                if let fieldOffset = layout.fieldOffsets[backingField] ?? layout.fieldOffsets[propertySymbol.id] {
                    let offsetExpr = module.arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: intType)
                    body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                    body.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_get_inbounds"),
                        arguments: [selfRef, offsetExpr],
                        result: resolvedExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else {
                    body.append(.copy(from: providedExpr, to: resolvedExpr))
                }
            } else {
                body.append(.copy(from: providedExpr, to: resolvedExpr))
            }

            body.append(.jump(afterLabel))
            body.append(.label(useProvidedLabel))
            body.append(.copy(from: providedExpr, to: resolvedExpr))
            body.append(.label(afterLabel))
            resolvedArgs.append(resolvedExpr)
        }

        let resultExpr = module.arena.appendTemporary(type: receiverType
        )
        body.append(.call(
            symbol: functionSymbol,
            callee: name,
            arguments: [selfRef] + resolvedArgs,
            result: resultExpr,
            canThrow: false,
            thrownResult: nil
        ))
        body.append(.returnValue(resultExpr))

        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: propertyParams.map(\.type) + Array(repeating: maskType, count: maskSymbols.count),
            returnType: receiverType,
            isSuspend: false,
            valueParameterSymbols: valueParamSymbols + maskSymbols,
            valueParameterHasDefaultValues: Array(repeating: false, count: propertyParams.count + maskSymbols.count),
            valueParameterIsVararg: Array(repeating: false, count: propertyParams.count + maskSymbols.count)
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: defaultStubSymbol,
            name: defaultStubName,
            module: module,
            sema: sema,
            signature: signature,
            params: params,
            body: body
        )
    }

    func appendSyntheticDataObjectHashCodeIfNeeded(
        owner: SemanticSymbol,
        objectName: InternedString,
        existingSymbol: SymbolID?,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .object, let functionSymbol = existingSymbol else {
            return
        }
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let hashCodeName = interner.intern("hashCode")
        let parameterName = interner.intern("$self")
        let fqName = owner.fqName + [hashCodeName]
        let parameterSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: fqName + [parameterName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let parameter = KIRParameter(symbol: parameterSymbol, type: receiverType)

        var hashCode: Int32 = 0
        for codeUnit in interner.resolve(objectName).utf16 {
            hashCode = 31 &* hashCode &+ Int32(codeUnit)
        }
        let resultExpr = module.arena.appendTemporary(type: intType)
        let body: [KIRInstruction] = [
            .constValue(result: resultExpr, value: .intLiteral(Int64(hashCode))),
            .returnValue(resultExpr),
        ]
        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [],
            returnType: intType,
            isSuspend: false,
            valueParameterSymbols: [],
            valueParameterHasDefaultValues: [],
            valueParameterIsVararg: [],
            typeParameterSymbols: []
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: functionSymbol,
            name: hashCodeName,
            module: module,
            sema: sema,
            signature: signature,
            params: [parameter],
            body: body
        )
    }

    /// Uses existingSymbol when provided (from Sema) so call resolution matches the KIR function.
    func appendSyntheticDataObjectToStringIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        objectName: InternedString,
        existingSymbol: SymbolID?,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .object, let functionSymbol = existingSymbol else {
            return
        }
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let stringType = sema.types.stringType
        let parameterName = interner.intern("$self")
        let fqName = owner.fqName + [name]
        let parameterSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: fqName + [parameterName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let parameter = KIRParameter(symbol: parameterSymbol, type: receiverType)
        let resultExpr = module.arena.appendTemporary(type: stringType
        )
        let body: [KIRInstruction] = [
            .constValue(result: resultExpr, value: .stringLiteral(objectName)),
            .returnValue(resultExpr),
        ]
        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [],
            returnType: stringType,
            isSuspend: false,
            valueParameterSymbols: [],
            valueParameterHasDefaultValues: [],
            valueParameterIsVararg: [],
            typeParameterSymbols: []
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: functionSymbol,
            name: name,
            module: module,
            sema: sema,
            signature: signature,
            params: [parameter],
            body: body
        )
    }

    func appendSyntheticDataObjectEqualsIfNeeded(
        owner: SemanticSymbol,
        existingSymbol: SymbolID?,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .object, let functionSymbol = existingSymbol else {
            return
        }
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let nullableAnyType = sema.types.nullableAnyType
        let equalsName = interner.intern("equals")
        let paramName = interner.intern("other")
        let fqName = owner.fqName + [equalsName]
        let paramSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: paramName,
            fqName: fqName + [paramName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let receiverParam = KIRParameter(
            symbol: sema.symbols.define(
                kind: .valueParameter,
                name: interner.intern("$self"),
                fqName: fqName + [interner.intern("$self")],
                declSite: owner.declSite,
                visibility: .private,
                flags: [.synthetic]
            ),
            type: receiverType
        )
        let otherParam = KIRParameter(symbol: paramSymbol, type: nullableAnyType)
        let receiverRef = module.arena.appendExpr(.symbolRef(receiverParam.symbol), type: receiverType)
        let otherRef = module.arena.appendExpr(.symbolRef(paramSymbol), type: nullableAnyType)
        let resultExpr = module.arena.appendTemporary(type: boolType
        )
        let body: [KIRInstruction] = [
            .constValue(result: receiverRef, value: .symbolRef(receiverParam.symbol)),
            .constValue(result: otherRef, value: .symbolRef(paramSymbol)),
            .call(
                symbol: nil,
                callee: interner.intern("kk_op_eq"),
                arguments: [receiverRef, otherRef],
                result: resultExpr,
                canThrow: false,
                thrownResult: nil
            ),
            .returnValue(resultExpr),
        ]
        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [nullableAnyType],
            returnType: boolType,
            isSuspend: false,
            valueParameterSymbols: [paramSymbol],
            valueParameterHasDefaultValues: [false],
            valueParameterIsVararg: [false],
            typeParameterSymbols: []
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: functionSymbol,
            name: equalsName,
            module: module,
            sema: sema,
            signature: signature,
            params: [receiverParam, otherParam],
            body: body
        )
    }

    func appendSyntheticDataClassHashCodeIfNeeded(
        owner: SemanticSymbol,
        existingSymbol: SymbolID?,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .class || owner.kind == .annotationClass, let functionSymbol = existingSymbol else {
            return
        }
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let hashCodeName = interner.intern("hashCode")
        let fqName = owner.fqName + [hashCodeName]

        let receiverParamSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: interner.intern("$self"),
            fqName: fqName + [interner.intern("$self")],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let receiverParam = KIRParameter(symbol: receiverParamSymbol, type: receiverType)

        // Kotlin's synthesized hashCode uses only primary-constructor properties, in declaration order.
        let propertySymbols = dataClassPropertySymbols(owner: owner, symbols: sema.symbols)

        var body: [KIRInstruction] = []

        let receiverRef = module.arena.appendExpr(.symbolRef(receiverParamSymbol), type: receiverType)
        body.append(.constValue(result: receiverRef, value: .symbolRef(receiverParamSymbol)))

        let hashCodeCallee = interner.intern("kk_any_hashCode")
        let mulCallee = interner.intern("kk_op_mul")
        let addCallee = interner.intern("kk_op_add")

        if propertySymbols.isEmpty {
            let zeroExpr = module.arena.appendTemporary(type: intType
            )
            body.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            body.append(.returnValue(zeroExpr))
        } else {
            var resultExpr: KIRExprID!
            for (index, propSym) in propertySymbols.enumerated() {
                let fieldOffsetValue: Int64
                if let layout = sema.symbols.nominalLayout(for: owner.id),
                   let offset = layout.fieldOffsets[propSym.id] {
                    fieldOffsetValue = Int64(offset)
                } else {
                    fieldOffsetValue = Int64(index)
                }

                let fieldOffsetExpr = module.arena.appendTemporary(type: intType
                )
                body.append(.constValue(result: fieldOffsetExpr, value: .intLiteral(fieldOffsetValue)))

                // Read the stored field first (matching appendSyntheticDataClassEqualsIfNeeded /
                // synthesizeDataClassComponentN). Passing `receiverRef` itself straight to
                // kk_any_hashCode — as this used to do — hashed the *receiver's own pointer*
                // on every iteration (kk_any_hashCode only reads its `tag` arg for non-pointer
                // values), so every property contributed the same identity-based hash and
                // equal-by-content instances ended up with different hashCode()s.
                let propType = sema.symbols.propertyType(for: propSym.id) ?? sema.types.anyType
                let fieldValueExpr = module.arena.appendTemporary(type: propType
                )
                body.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_get_inbounds"),
                    arguments: [receiverRef, fieldOffsetExpr],
                    result: fieldValueExpr,
                    canThrow: false,
                    thrownResult: nil
                ))

                let propHashExpr = module.arena.appendTemporary(type: intType
                )
                if owner.kind == .annotationClass, isAnnotationArrayType(propType, sema: sema, interner: interner) {
                    body.append(.call(
                        symbol: nil, callee: interner.intern("__kk_array_contentDeepHashCode"),
                        arguments: [fieldValueExpr], result: propHashExpr,
                        canThrow: false, thrownResult: nil
                    ))
                } else if let arrayHashSymbol = dataClassArrayContentHashSymbol(
                    for: propType, sema: sema, interner: interner
                ) {
                    let callee = sema.symbols.externalLinkNameIfKnown(for: arrayHashSymbol)
                        .map(interner.intern) ?? interner.intern("contentHashCode")
                    body.append(.call(
                        symbol: arrayHashSymbol,
                        callee: callee,
                        arguments: [fieldValueExpr],
                        result: propHashExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else {
                    let tagValue = computeAnyFallbackTag(for: propType, sema: sema)
                    let tagExpr = module.arena.appendTemporary(type: intType)
                    body.append(.constValue(result: tagExpr, value: .intLiteral(tagValue)))
                    let hashValue: KIRExprID
                    if owner.kind == .annotationClass {
                        let canonicalValue = annotationCanonicalMemberValue(
                            fieldValueExpr, type: propType, module: module, sema: sema,
                            interner: interner, body: &body
                        )
                        hashValue = boxSentinelProneHashCodeReceiver(
                            canonicalValue, sourceType: propType, sema: sema,
                            interner: interner, arena: module.arena, into: &body
                        )
                    } else {
                        // Full-width primitive payloads (notably Double -0.0)
                        // can equal the null sentinel. Preserve their non-null
                        // value before entering generic runtime hash dispatch.
                        hashValue = boxSentinelProneHashCodeReceiver(
                            fieldValueExpr, sourceType: propType, sema: sema,
                            interner: interner, arena: module.arena, into: &body
                        )
                    }
                    body.append(.call(
                        symbol: nil,
                        callee: hashCodeCallee,
                        arguments: [hashValue, tagExpr],
                        result: propHashExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }

                if owner.kind == .annotationClass {
                    var nameHash: Int32 = 0
                    for unit in interner.resolve(propSym.name).utf16 {
                        nameHash = 31 &* nameHash &+ Int32(unit)
                    }
                    let nameExpr = module.arena.appendTemporary(type: intType)
                    body.append(.constValue(result: nameExpr, value: .intLiteral(Int64(127 &* nameHash))))
                    let memberHash = module.arena.appendTemporary(type: intType)
                    body.append(.call(
                        symbol: nil, callee: interner.intern("kk_bitwise_xor"),
                        arguments: [nameExpr, propHashExpr], result: memberHash,
                        canThrow: false, thrownResult: nil
                    ))
                    if index == 0 {
                        resultExpr = memberHash
                    } else {
                        let sum = module.arena.appendTemporary(type: intType)
                        body.append(.call(
                            symbol: nil, callee: addCallee, arguments: [resultExpr, memberHash],
                            result: sum, canThrow: false, thrownResult: nil
                        ))
                        resultExpr = sum
                    }
                } else if index == 0 {
                    resultExpr = propHashExpr
                } else {
                    let thirtyOneExpr = module.arena.appendTemporary(type: intType
                    )
                    body.append(.constValue(result: thirtyOneExpr, value: .intLiteral(31)))

                    let mulExpr = module.arena.appendTemporary(type: intType
                    )
                    body.append(.call(
                        symbol: nil,
                        callee: mulCallee,
                        arguments: [thirtyOneExpr, resultExpr],
                        result: mulExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))

                    let addExpr = module.arena.appendTemporary(type: intType
                    )
                    body.append(.call(
                        symbol: nil,
                        callee: addCallee,
                        arguments: [mulExpr, propHashExpr],
                        result: addExpr,
                        canThrow: false,
                        thrownResult: nil
                    ))

                    resultExpr = addExpr
                }
            }
            if owner.kind == .annotationClass {
                // Member sums wrap in Kotlin's signed 32-bit Int domain.
                let normalized = module.arena.appendTemporary(type: intType)
                body.append(.call(
                    symbol: nil, callee: interner.intern("kk_long_to_int"),
                    arguments: [resultExpr!], result: normalized, canThrow: false, thrownResult: nil
                ))
                resultExpr = normalized
            }
            body.append(.returnValue(resultExpr))
        }

        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [],
            returnType: intType,
            isSuspend: false,
            valueParameterSymbols: [],
            valueParameterHasDefaultValues: [],
            valueParameterIsVararg: [],
            typeParameterSymbols: []
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: functionSymbol,
            name: hashCodeName,
            module: module,
            sema: sema,
            signature: signature,
            params: [receiverParam],
            body: body
        )
    }

    private func dataClassArrayContentHashSymbol(
        for type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        guard let (arrayType, arraySymbol) = resolveClassTypeSymbol(
            sema.types.makeNonNullable(type), sema: sema
        ),
            arraySymbol.fqName == [interner.intern("kotlin"), arraySymbol.name],
            KnownCompilerNames(interner: interner).isArrayLikeName(arraySymbol.name)
        else {
            return nil
        }
        let fqName = [interner.intern("kotlin"), interner.intern("collections"), interner.intern("contentHashCode")]
        return sema.symbols.lookupAll(fqName: fqName).first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.isEmpty,
                  let receiverType = signature.receiverType,
                  let (receiverClass, _) = resolveClassTypeSymbol(
                      sema.types.makeNonNullable(receiverType), sema: sema
                  )
            else {
                return false
            }
            return receiverClass.classSymbol == arrayType.classSymbol
        }
    }

    private func dataClassArrayContentToStringSymbol(
        for type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        guard let (arrayType, arraySymbol) = resolveClassTypeSymbol(
            sema.types.makeNonNullable(type), sema: sema
        ),
            arraySymbol.fqName == [interner.intern("kotlin"), arraySymbol.name],
            KnownCompilerNames(interner: interner).isArrayLikeName(arraySymbol.name)
        else {
            return nil
        }
        let fqName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("contentToString"),
        ]
        return sema.symbols.lookupAll(fqName: fqName).first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.isEmpty,
                  let receiverType = signature.receiverType,
                  let (receiverClass, _) = resolveClassTypeSymbol(
                      sema.types.makeNonNullable(receiverType), sema: sema
                  )
            else {
                return false
            }
            return receiverClass.classSymbol == arrayType.classSymbol
        }
    }

    /// Output format: "ClassName(prop1=val1, prop2=val2)"
    func appendSyntheticDataClassToStringIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        properties: [SemanticSymbol],
        existingSymbol: SymbolID?,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .class || owner.kind == .annotationClass, let functionSymbol = existingSymbol else {
            return
        }
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let stringType = sema.types.stringType
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let builderType = sema.types.anyType
        let layout = sema.symbols.nominalLayout(for: owner.id)
        let fqName = owner.fqName + [name]
        let parameterName = interner.intern("$self")
        let parameterSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: fqName + [parameterName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let parameter = KIRParameter(symbol: parameterSymbol, type: receiverType)

        var body: [KIRInstruction] = []
        // Freshly synthesized function body, so label numbers only need to be
        // unique within it — safe to start from 0 (mirrors the equals()
        // synthesis below).
        var nextLabel: Int32 = 0
        func allocateLabel() -> Int32 {
            defer { nextLabel += 1 }
            return nextLabel
        }

        // A data class always owns the generated toString() representation,
        // including when it extends another class. The inherited class name
        // must not leak into the data-class output (for example, A(n=5), not
        // Sn=5).
        let className = owner.kind == .annotationClass
            ? "@" + owner.fqName.map(interner.resolve).joined(separator: ".")
            : interner.resolve(owner.name)
        let prefixStr = interner.intern("\(className)(")
        let prefixExpr = module.arena.appendTemporary(type: stringType
        )
        body.append(.constValue(result: prefixExpr, value: .stringLiteral(prefixStr)))
        let builderExpr = module.arena.appendTemporary(type: builderType
        )
        body.append(.call(
            symbol: nil,
            callee: interner.intern("__kk_string_builder_new_from_string_flat"),
            arguments: [prefixExpr],
            result: builderExpr,
            canThrow: false,
            thrownResult: nil
        ))

        for (index, property) in properties.enumerated() {
            let propName = interner.resolve(property.name)
            let labelStr: String = index == 0 ? "\(propName)=" : ", \(propName)="
            let labelInterned = interner.intern(labelStr)
            let labelExpr = module.arena.appendTemporary(type: stringType
            )
            body.append(.constValue(result: labelExpr, value: .stringLiteral(labelInterned)))

            body.append(.call(
                symbol: nil,
                callee: interner.intern("__kk_string_builder_append_obj"),
                arguments: [builderExpr, labelExpr],
                result: builderExpr,
                canThrow: false,
                thrownResult: nil
            ))

            // Read the constructor-backed field directly so data-class synthesis
            // does not depend on separate property accessor emission.
            let receiverRef = module.arena.appendExpr(.symbolRef(parameterSymbol), type: receiverType)
            body.append(.constValue(result: receiverRef, value: .symbolRef(parameterSymbol)))

            let propType = sema.symbols.propertyType(for: property.id) ?? sema.types.anyType
            let propValue = module.arena.appendTemporary(type: propType
            )
            let backingField = sema.symbols.backingFieldSymbol(for: property.id) ?? property.id
            if sema.symbols.effectiveValueClassUnderlyingType(for: owner.id) != nil {
                // This body is synthesized after ValueClassUnboxingPass, so read
                // the underlying field from the raw receiver without a heap load.
                body.append(.copy(from: receiverRef, to: propValue))
            } else if let layout,
               let fieldOffset = layout.fieldOffsets[backingField] ?? layout.fieldOffsets[property.id]
            {
                let offsetExpr = module.arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: intType)
                body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                body.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_array_get_inbounds"),
                    arguments: [receiverRef, offsetExpr],
                    result: propValue,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else {
                body.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_abort_unreachable"),
                    arguments: [],
                    result: propValue,
                    canThrow: false,
                    thrownResult: nil
                ))
            }

            let propStr = module.arena.appendTemporary(type: stringType
            )
            let propIsNullable = sema.types.makeNonNullable(propType) != propType

            // A statically enum-typed property is stored as its bare ordinal
            // and a statically class-typed property (including a value class)
            // is stored as a heap pointer or raw unboxed primitive — neither
            // representation is recoverable by the generic kk_any_to_string
            // tag path below. Prefer the enum ordinal-to-name helper, then the
            // property type's own toString(), before falling back to the tag
            // path, mirroring CallLowerer.emitAnyToStringWithNullGuard (shared
            // via resolveEnumOrdinalToNameCallee/resolveClassOwnToStringCallee
            // since this pass runs standalone, with no KIRLoweringDriver to
            // construct a CallLowerer).
            if owner.kind == .annotationClass, isAnnotationArrayType(propType, sema: sema, interner: interner) {
                body.append(.call(
                    symbol: nil, callee: interner.intern("__kk_array_contentDeepToString"),
                    arguments: [propValue], result: propStr, canThrow: false, thrownResult: nil
                ))
            } else if let arrayToStringSymbol = dataClassArrayContentToStringSymbol(
                for: propType, sema: sema, interner: interner
            ) {
                let callee = sema.symbols.externalLinkNameIfKnown(for: arrayToStringSymbol)
                    .map(interner.intern) ?? interner.intern("contentToString")
                body.append(.call(
                    symbol: arrayToStringSymbol,
                    callee: callee,
                    arguments: [propValue],
                    result: propStr,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else if let nameHelper = resolveEnumOrdinalToNameCallee(for: propType, sema: sema, interner: interner) {
                body.append(.call(
                    symbol: nameHelper.symbol,
                    callee: nameHelper.callee,
                    arguments: [propValue],
                    result: propStr,
                    canThrow: false,
                    thrownResult: nil
                ))
            } else if let classToString = resolveClassOwnToStringCallee(for: propType, sema: sema, interner: interner) {
                // KUU-3110: `toString` dispatch must go through the
                // `kotlin.Any.toString` vtable slot — the runtime member
                // registered there forwards to the object's own toString —
                // to reach the most-derived override. Looking the slot up by
                // the resolved symbol instead would find orphan slots
                // (synthesized data-class members and interface members are
                // stored under their own key but are never registered as
                // virtual slots). Types whose layout carries no Any slot —
                // interfaces under source-injected stdlib — fall back to
                // `kk_any_to_string`, which resolves the object's per-object
                // toString the same way.
                let toStringVtableSlot: Int? = {
                    guard let (_, classSymbol) = resolveClassTypeSymbol(propType, sema: sema),
                          let layout = sema.symbols.nominalLayout(for: classSymbol.id)
                    else { return nil }
                    return layout.vtableSlots.first(where: { key, _ in
                        sema.symbols.symbol(key).map {
                            isSyntheticAnyToStringSymbol($0, interner: interner)
                        } ?? false
                    })?.value
                }()
                let toStringTagExpr: KIRExprID? = toStringVtableSlot == nil
                    ? module.arena.appendTemporary(type: intType)
                    : nil
                if let toStringTagExpr {
                    body.append(.constValue(
                        result: toStringTagExpr,
                        value: .intLiteral(computeAnyFallbackTag(for: propType, sema: sema))
                    ))
                }
                let toStringCall = { (result: KIRExprID) -> KIRInstruction in
                    if let toStringVtableSlot {
                        return .virtualCall(
                            symbol: classToString.symbol,
                            callee: classToString.callee,
                            receiver: propValue,
                            arguments: [],
                            result: result,
                            canThrow: false,
                            thrownResult: nil,
                            dispatch: .vtable(slot: toStringVtableSlot)
                        )
                    }
                    if let toStringTagExpr {
                        return .call(
                            symbol: nil,
                            callee: interner.intern("kk_any_to_string"),
                            arguments: [propValue, toStringTagExpr],
                            result: result,
                            canThrow: false,
                            thrownResult: nil
                        )
                    }
                    return .call(
                        symbol: classToString.symbol,
                        callee: classToString.callee,
                        arguments: [propValue],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    )
                }
                if propIsNullable {
                    let nonNullLabel = allocateLabel()
                    let endLabel = allocateLabel()
                    let nullStr = interner.intern("null")
                    let nullStrExpr = module.arena.appendTemporary(type: stringType)
                    body.append(.constValue(result: nullStrExpr, value: .stringLiteral(nullStr)))
                    body.append(.jumpIfNotNull(value: propValue, target: nonNullLabel))
                    body.append(.copy(from: nullStrExpr, to: propStr))
                    body.append(.jump(endLabel))
                    body.append(.label(nonNullLabel))
                    let innerPropStr = module.arena.appendTemporary(type: stringType)
                    body.append(toStringCall(innerPropStr))
                    body.append(.copy(from: innerPropStr, to: propStr))
                    body.append(.label(endLabel))
                } else {
                    body.append(toStringCall(propStr))
                }
            } else {
                // Convert to string via kk_any_to_string using the same tag convention
                // as Any.toString lowering.
                let anyTag = computeAnyFallbackTag(for: propType, sema: sema)
                let tagExpr = module.arena.appendTemporary(type: intType
                )
                body.append(.constValue(result: tagExpr, value: .intLiteral(anyTag)))

                // Nullable Float?/Double?/ULong? properties need an explicit null
                // guard before kk_any_to_string: tags 5/6/7 are decoded before the
                // null-sentinel check (their in-range values can share Int.min's
                // bit pattern), so an actually-null property would otherwise
                // render as -0.0/a large ULong instead of "null" (see
                // CallLowerer.emitAnyToStringWithNullGuard for the full rationale).
                if propIsNullable, anyTag == 5 || anyTag == 6 || anyTag == 7 {
                    let nonNullLabel = allocateLabel()
                    let endLabel = allocateLabel()
                    let nullStr = interner.intern("null")
                    let nullStrExpr = module.arena.appendTemporary(type: stringType)
                    body.append(.constValue(result: nullStrExpr, value: .stringLiteral(nullStr)))
                    body.append(.jumpIfNotNull(value: propValue, target: nonNullLabel))
                    body.append(.copy(from: nullStrExpr, to: propStr))
                    body.append(.jump(endLabel))
                    body.append(.label(nonNullLabel))
                    let innerPropStr = module.arena.appendTemporary(type: stringType)
                    body.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_any_to_string"),
                        arguments: [propValue, tagExpr],
                        result: innerPropStr,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    body.append(.copy(from: innerPropStr, to: propStr))
                    body.append(.label(endLabel))
                } else {
                    body.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_any_to_string"),
                        arguments: [propValue, tagExpr],
                        result: propStr,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }
            }

            body.append(.call(
                symbol: nil,
                callee: interner.intern("__kk_string_builder_append_obj"),
                arguments: [builderExpr, propStr],
                result: builderExpr,
                canThrow: false,
                thrownResult: nil
            ))
        }

        let suffixStr = interner.intern(")")
        let suffixExpr = module.arena.appendTemporary(type: stringType
        )
        body.append(.constValue(result: suffixExpr, value: .stringLiteral(suffixStr)))

        body.append(.call(
            symbol: nil,
            callee: interner.intern("__kk_string_builder_append_obj"),
            arguments: [builderExpr, suffixExpr],
            result: builderExpr,
            canThrow: false,
            thrownResult: nil
        ))

        let resultExpr = module.arena.appendTemporary(type: stringType
        )
        body.append(.call(
            symbol: nil,
            callee: interner.intern("__kk_string_builder_toString"),
            arguments: [builderExpr],
            result: resultExpr,
            canThrow: false,
            thrownResult: nil
        ))
        body.append(.returnValue(resultExpr))

        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [],
            returnType: stringType,
            isSuspend: false,
            valueParameterSymbols: [],
            valueParameterHasDefaultValues: [],
            valueParameterIsVararg: [],
            typeParameterSymbols: []
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: functionSymbol,
            name: name,
            module: module,
            sema: sema,
            signature: signature,
            params: [parameter],
            body: body
        )
    }

    func appendSyntheticDataClassEqualsIfNeeded(
        owner: SemanticSymbol,
        properties: [SemanticSymbol],
        existingSymbol: SymbolID?,
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard owner.kind == .class || owner.kind == .annotationClass, let functionSymbol = existingSymbol else {
            return
        }
        if existingFunctionSymbols.contains(functionSymbol) {
            return
        }

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let nullableAnyType = sema.types.nullableAnyType
        let layout = sema.symbols.nominalLayout(for: owner.id)
        let equalsName = interner.intern("equals")
        let paramName = interner.intern("other")
        let fqName = owner.fqName + [equalsName]
        let paramSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: paramName,
            fqName: fqName + [paramName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let receiverParam = KIRParameter(
            symbol: sema.symbols.define(
                kind: .valueParameter,
                name: interner.intern("$self"),
                fqName: fqName + [interner.intern("$self")],
                declSite: owner.declSite,
                visibility: .private,
                flags: [.synthetic]
            ),
            type: receiverType
        )
        let otherParam = KIRParameter(symbol: paramSymbol, type: nullableAnyType)

        var body: [KIRInstruction] = []
        var nextLabel: Int32 = 0
        func allocateLabel() -> Int32 {
            defer { nextLabel += 1 }
            return nextLabel
        }

        if properties.isEmpty, owner.kind != .annotationClass {
            let receiverRef = module.arena.appendExpr(.symbolRef(receiverParam.symbol), type: receiverType)
            let otherRef = module.arena.appendExpr(.symbolRef(paramSymbol), type: nullableAnyType)
            let resultExpr = module.arena.appendTemporary(type: boolType
            )
            body.append(.constValue(result: receiverRef, value: .symbolRef(receiverParam.symbol)))
            body.append(.constValue(result: otherRef, value: .symbolRef(paramSymbol)))

            // With no value properties, equality falls back to reference equality.
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_eq"),
                arguments: [receiverRef, otherRef],
                result: resultExpr,
                canThrow: false,
                thrownResult: nil
            ))
            body.append(.returnValue(resultExpr))
        } else {
            let intType = sema.types.intType
            let falseExpr = module.arena.appendExpr(.boolLiteral(false), type: boolType)
            body.append(.constValue(result: falseExpr, value: .boolLiteral(false)))

            let typeTokenValue = RuntimeTypeCheckToken.encode(type: receiverType, sema: sema, interner: interner)
            let typeTokenExpr = module.arena.appendExpr(.intLiteral(typeTokenValue), type: intType)
            body.append(.constValue(result: typeTokenExpr, value: .intLiteral(typeTokenValue)))

            let otherAnyRef = module.arena.appendExpr(.symbolRef(paramSymbol), type: nullableAnyType)
            body.append(.constValue(result: otherAnyRef, value: .symbolRef(paramSymbol)))

            let isSameTypeExpr = module.arena.appendTemporary(type: boolType
            )
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_is"),
                arguments: [otherAnyRef, typeTokenExpr],
                result: isSameTypeExpr,
                canThrow: false,
                thrownResult: nil
            ))

            let returnFalseLabel = allocateLabel()
            body.append(.jumpIfEqual(lhs: isSameTypeExpr, rhs: falseExpr, target: returnFalseLabel))

            let otherTypedRef = module.arena.appendTemporary(type: receiverType
            )
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_safe_cast"),
                arguments: [otherAnyRef, typeTokenExpr],
                result: otherTypedRef,
                canThrow: false,
                thrownResult: nil
            ))

            for property in properties {
                let propType = sema.symbols.propertyType(for: property.id) ?? sema.types.anyType
                let backingField = sema.symbols.backingFieldSymbol(for: property.id) ?? property.id
                let fieldOffset = layout.flatMap { $0.fieldOffsets[backingField] ?? $0.fieldOffsets[property.id] }

                let selfRef = module.arena.appendExpr(.symbolRef(receiverParam.symbol), type: receiverType)
                body.append(.constValue(result: selfRef, value: .symbolRef(receiverParam.symbol)))
                let selfProp = module.arena.appendTemporary(type: propType
                )

                let otherProp = module.arena.appendTemporary(type: propType
                )
                if let fieldOffset {
                    let offsetExpr = module.arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: intType)
                    body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
                    body.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_get_inbounds"),
                        arguments: [selfRef, offsetExpr],
                        result: selfProp,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    body.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_array_get_inbounds"),
                        arguments: [otherTypedRef, offsetExpr],
                        result: otherProp,
                        canThrow: false,
                        thrownResult: nil
                    ))
                } else {
                    body.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_abort_unreachable"),
                        arguments: [],
                        result: selfProp,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    body.append(.call(
                        symbol: nil,
                        callee: interner.intern("kk_abort_unreachable"),
                        arguments: [],
                        result: otherProp,
                        canThrow: false,
                        thrownResult: nil
                    ))
                }

                let cmpResult = module.arena.appendTemporary(type: boolType
                )
                // Use structural equality for reference types (String, class instances, etc.)
                // to match Kotlin data class equals() semantics. Primitive types can use
                // pointer/value equality via kk_op_eq.
                let eqCallee: String = if owner.kind == .annotationClass,
                    isAnnotationArrayType(propType, sema: sema, interner: interner)
                {
                    "__kk_array_contentDeepEquals"
                } else {
                    switch sema.types.kind(of: sema.types.makeNonNullable(propType)) {
                    case .stringStruct, .classType, .any:
                        "kk_structural_eq"
                    case .primitive:
                        // KUU-3109: data class equals uses Double.equals/
                        // Float.equals semantics — NaN equals NaN regardless of
                        // payload while -0.0 differs from +0.0 — not the raw
                        // bit-pattern equality kk_op_eq applies. Nullable
                        // Float?/Double? stay on the existing path (KUU-3108).
                        switch sema.types.kind(of: propType) {
                        case .primitive(.double, .nonNull):
                            "kk_double_equals"
                        case .primitive(.float, .nonNull):
                            "kk_float_equals"
                        default:
                            "kk_op_eq"
                        }
                    default:
                        "kk_structural_eq"
                    }
                }
                let lhsValue = owner.kind == .annotationClass
                    ? annotationCanonicalMemberValue(
                        selfProp, type: propType, module: module, sema: sema,
                        interner: interner, body: &body
                    ) : selfProp
                let rhsValue = owner.kind == .annotationClass
                    ? annotationCanonicalMemberValue(
                        otherProp, type: propType, module: module, sema: sema,
                        interner: interner, body: &body
                    ) : otherProp
                // The deep-array bridge returns a boxed Boolean. This synthetic call
                // has no Sema signature from which ABILowering can infer that contract.
                let callResult = eqCallee == "__kk_array_contentDeepEquals"
                    ? module.arena.appendTemporary(type: sema.types.anyType) : cmpResult
                body.append(.call(
                    symbol: nil,
                    callee: interner.intern(eqCallee),
                    arguments: [lhsValue, rhsValue],
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ))
                if callResult != cmpResult {
                    body.append(.call(
                        symbol: nil, callee: interner.intern("kk_unbox_bool"),
                        arguments: [callResult], result: cmpResult,
                        canThrow: false, thrownResult: nil
                    ))
                }

                body.append(.jumpIfEqual(lhs: cmpResult, rhs: falseExpr, target: returnFalseLabel))
            }

            let trueResult = module.arena.appendExpr(
                .boolLiteral(true),
                type: boolType
            )
            body.append(.constValue(result: trueResult, value: .boolLiteral(true)))
            body.append(.returnValue(trueResult))

            body.append(.label(returnFalseLabel))
            let falseResult = module.arena.appendExpr(
                .boolLiteral(false),
                type: boolType
            )
            body.append(.constValue(result: falseResult, value: .boolLiteral(false)))
            body.append(.returnValue(falseResult))
        }

        let signature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [nullableAnyType],
            returnType: boolType,
            isSuspend: false,
            valueParameterSymbols: [paramSymbol],
            valueParameterHasDefaultValues: [false],
            valueParameterIsVararg: [false],
            typeParameterSymbols: []
        )
        appendSyntheticFunctionWithSymbol(
            functionSymbol: functionSymbol,
            name: equalsName,
            module: module,
            sema: sema,
            signature: signature,
            params: [receiverParam, otherParam],
            body: body
        )
    }

}
