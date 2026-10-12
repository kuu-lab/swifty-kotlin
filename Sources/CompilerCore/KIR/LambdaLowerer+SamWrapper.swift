extension LambdaLowerer {
    func lowerSamWrapperValue(
        _ exprID: ExprID,
        interfaceType: ClassType,
        lambdaSymbol: SymbolID,
        lambdaName: InternedString,
        lambdaReturnType: TypeID,
        captureBindings: [(capturedSymbol: SymbolID, param: KIRParameter, valueExpr: KIRExprID, declaredType: TypeID)],
        samMethodParamTypes: [TypeID],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let interfaceSymbol = interfaceType.classSymbol
        guard let interfaceInfo = sema.symbols.symbol(interfaceSymbol),
              interfaceInfo.kind == .interface,
              interfaceInfo.flags.contains(.funInterface),
              let samMethod = samMethodSymbolAndSignature(for: interfaceSymbol, sema: sema)
        else {
            return nil
        }

        let wrapperName = interner.intern("kk_sam_wrapper_\(exprID.rawValue)")
        let wrapperFQName = [wrapperName]
        let wrapperSymbol = sema.symbols.define(
            kind: .class,
            name: wrapperName,
            fqName: wrapperFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        sema.symbols.setDirectSupertypes([interfaceSymbol], for: wrapperSymbol)
        sema.types.setNominalDirectSupertypes([interfaceSymbol], for: wrapperSymbol)
        sema.symbols.setSupertypeTypeArgs(interfaceType.args, for: wrapperSymbol, supertype: interfaceSymbol)
        sema.types.setNominalSupertypeTypeArgs(interfaceType.args, for: wrapperSymbol, supertype: interfaceSymbol)

        let wrapperType = sema.types.make(.classType(ClassType(
            classSymbol: wrapperSymbol,
            args: [],
            nullability: .nonNull
        )))

        var fieldOffsets: [SymbolID: Int] = [:]
        var nextFieldOffset = 2
        let captureFieldSymbols = captureBindings.enumerated().map { index, capture in
            let fieldName = interner.intern("$sam_capture_\(index)")
            let fieldSymbol = sema.symbols.define(
                kind: .field,
                name: fieldName,
                fqName: wrapperFQName + [fieldName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            sema.symbols.setParentSymbol(wrapperSymbol, for: fieldSymbol)
            sema.symbols.setPropertyType(capture.param.type, for: fieldSymbol)
            fieldOffsets[fieldSymbol] = nextFieldOffset
            nextFieldOffset += 1
            return fieldSymbol
        }

        let methodName = samMethod.info.name
        let methodSymbol = sema.symbols.define(
            kind: .function,
            name: methodName,
            fqName: wrapperFQName + [methodName],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        sema.symbols.setParentSymbol(wrapperSymbol, for: methodSymbol)

        let methodParamSymbols: [SymbolID] = samMethodParamTypes.enumerated().map { index, type in
            let paramName = interner.intern("$p\(index)")
            let paramSymbol = sema.symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: wrapperFQName + [methodName, paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            sema.symbols.setPropertyType(type, for: paramSymbol)
            return paramSymbol
        }
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: wrapperType,
                parameterTypes: samMethodParamTypes,
                returnType: lambdaReturnType,
                isSuspend: samMethod.signature.isSuspend,
                valueParameterSymbols: methodParamSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: methodParamSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: methodParamSymbols.count),
                typeParameterSymbols: []
            ),
            for: methodSymbol
        )
        sema.symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 2,
                instanceFieldCount: captureFieldSymbols.count,
                instanceSizeWords: max(2 + captureFieldSymbols.count, 1),
                fieldOffsets: fieldOffsets,
                vtableSlots: [methodSymbol: 0, samMethod.symbol: 0],
                itableSlots: [interfaceSymbol: 0],
                vtableSize: 1,
                superClass: nil
            ),
            for: wrapperSymbol
        )

        let nominalDeclID = arena.appendDecl(.nominalType(KIRNominalType(symbol: wrapperSymbol)))
        driver.ctx.appendGeneratedCallableDecl(nominalDeclID)

        let scopeSnapshot = driver.ctx.saveScope()
        driver.ctx.resetScopeForFunction()
        driver.ctx.beginCallableLoweringScope()
        driver.ctx.setCurrentFunctionSymbol(methodSymbol)

        let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: methodSymbol)
        let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: wrapperType)
        driver.ctx.setImplicitReceiver(symbol: receiverSymbol, exprID: receiverExpr)

        let methodParams = [KIRParameter(symbol: receiverSymbol, type: wrapperType)]
            + zip(methodParamSymbols, samMethodParamTypes).map { KIRParameter(symbol: $0.0, type: $0.1) }
        var methodBody: [KIRInstruction] = [.beginBlock]
        methodBody.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSymbol)))

        var loadedCaptureExprs: [KIRExprID] = []
        for (index, fieldSymbol) in captureFieldSymbols.enumerated() {
            guard let fieldOffset = fieldOffsets[fieldSymbol] else {
                continue
            }
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            methodBody.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let captureType = captureBindings[index].param.type
            let loadedExpr = arena.appendTemporary(type: captureType)
            methodBody.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_get_inbounds"),
                arguments: [receiverExpr, offsetExpr],
                result: loadedExpr,
                canThrow: false,
                thrownResult: nil
            ))
            loadedCaptureExprs.append(loadedExpr)
        }

        let loweredMethodParamExprs = zip(methodParamSymbols, samMethodParamTypes).map { symbol, type in
            let expr = arena.appendExpr(.symbolRef(symbol), type: type)
            methodBody.append(.constValue(result: expr, value: .symbolRef(symbol)))
            return expr
        }

        let callResult = arena.appendTemporary(type: lambdaReturnType)
        methodBody.append(.call(
            symbol: lambdaSymbol,
            callee: lambdaName,
            arguments: loadedCaptureExprs + loweredMethodParamExprs,
            result: callResult,
            canThrow: true,
            thrownResult: nil
        ))
        if lambdaReturnType == sema.types.unitType {
            methodBody.append(.returnUnit)
        } else {
            methodBody.append(.returnValue(callResult))
        }
        methodBody.append(.endBlock)

        let methodDeclID = arena.appendDecl(.function(KIRFunction(
            symbol: methodSymbol,
            name: methodName,
            params: methodParams,
            returnType: lambdaReturnType,
            body: methodBody,
            isSuspend: samMethod.signature.isSuspend,
            isInline: false
        )))
        driver.ctx.appendGeneratedCallableDecl(methodDeclID)
        driver.ctx.restoreScope(scopeSnapshot)

        let slotCount = Int64(max(2 + captureFieldSymbols.count, 1))
        let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: sema.types.intType)
        instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
        let classIDValue = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: wrapperSymbol,
            sema: sema,
            interner: interner
        )
        let classIDExpr = arena.appendExpr(.intLiteral(classIDValue), type: sema.types.intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))
        let wrapperValue = arena.appendTemporary(type: sema.types.make(.classType(ClassType(
                classSymbol: interfaceSymbol,
                args: interfaceType.args,
                nullability: .nonNull
            )))
        )
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: wrapperValue,
            canThrow: false,
            thrownResult: nil
        ))

        let childTypeExpr = arena.appendExpr(.intLiteral(classIDValue), type: sema.types.intType)
        instructions.append(.constValue(result: childTypeExpr, value: .intLiteral(classIDValue)))
        let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: interfaceSymbol,
            sema: sema,
            interner: interner
        )
        let interfaceTypeExpr = arena.appendExpr(.intLiteral(interfaceTypeID), type: sema.types.intType)
        instructions.append(.constValue(result: interfaceTypeExpr, value: .intLiteral(interfaceTypeID)))
        let registerResult = arena.appendTemporary(type: sema.types.intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_type_register_iface"),
            arguments: [childTypeExpr, interfaceTypeExpr],
            result: registerResult,
            canThrow: false,
            thrownResult: nil
        ))
        // BUG-224: `wrapperSymbol` is a KIR-synthetic identity with no Sema
        // supertype entry of its own, so the edge above must stay explicit —
        // but `interfaceSymbol` (the SAM/fun interface being implemented) is
        // a real declared nominal, and if it itself extends another
        // interface that edge needs registering too, or a comparison through
        // that further ancestor would never reach this wrapper.
        appendTypeAncestryRegistrations(
            rootSymbol: interfaceSymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        let ifaceSlot = Int64(sema.symbols.nominalLayout(for: wrapperSymbol)?.itableSlots[interfaceSymbol] ?? 0)
        let methodSlot = Int64(sema.symbols.nominalLayout(for: interfaceSymbol)?.vtableSlots[samMethod.symbol] ?? 0)
        let ifaceSlotExpr = arena.appendExpr(.intLiteral(ifaceSlot), type: sema.types.intType)
        instructions.append(.constValue(result: ifaceSlotExpr, value: .intLiteral(ifaceSlot)))
        let registerIfaceResult = arena.appendTemporary(type: sema.types.intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_register_itable_iface"),
            arguments: [wrapperValue, interfaceTypeExpr, ifaceSlotExpr],
            result: registerIfaceResult,
            canThrow: false,
            thrownResult: nil
        ))
        let methodSlotExpr = arena.appendExpr(.intLiteral(methodSlot), type: sema.types.intType)
        instructions.append(.constValue(result: methodSlotExpr, value: .intLiteral(methodSlot)))
        let registeredMethodSymbol = itableBridgeSymbolForMethod(
            interfaceMethod: samMethod.symbol,
            implementation: methodSymbol,
            nominalSymbol: wrapperSymbol,
            driver: driver,
            arena: arena,
            sema: sema,
            interner: interner
        )
        let methodFnExpr = arena.appendExpr(.symbolRef(registeredMethodSymbol), type: sema.types.intType)
        instructions.append(.constValue(result: methodFnExpr, value: .symbolRef(registeredMethodSymbol)))
        let registerMethodResult = arena.appendTemporary(type: sema.types.intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_register_itable_method"),
            arguments: [wrapperValue, ifaceSlotExpr, methodSlotExpr, methodFnExpr],
            result: registerMethodResult,
            canThrow: false,
            thrownResult: nil
        ))

        // Expose the SAM wrapper as an invokable comparator value so stdlib
        // comparison lowering can call `compare` directly when needed.
        driver.ctx.registerCallableValue(
            wrapperValue,
            symbol: methodSymbol,
            callee: methodName,
            captureArguments: [wrapperValue],
            hasClosureParam: false
        )

        for (index, capture) in captureBindings.enumerated() {
            guard index < captureFieldSymbols.count,
                  let fieldOffset = fieldOffsets[captureFieldSymbols[index]]
            else {
                continue
            }
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            instructions.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let unusedResult = arena.appendTemporary(type: sema.types.anyType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [wrapperValue, offsetExpr, capture.valueExpr],
                result: unusedResult,
                canThrow: true,
                thrownResult: nil
            ))
        }

        _ = samMethodParamTypes
        return wrapperValue
    }

    private func samMethodSymbolAndSignature(
        for interfaceSymbol: SymbolID,
        sema: SemaModule
    ) -> (symbol: SymbolID, info: SemanticSymbol, signature: FunctionSignature)? {
        guard let interfaceInfo = sema.symbols.symbol(interfaceSymbol),
              interfaceInfo.kind == .interface,
              interfaceInfo.flags.contains(.funInterface)
        else {
            return nil
        }
        let abstractMethods = sema.symbols.children(ofFQName: interfaceInfo.fqName).compactMap { childID -> (SymbolID, SemanticSymbol, FunctionSignature)? in
            guard let childInfo = sema.symbols.symbol(childID),
                  childInfo.kind == .function,
                  childInfo.flags.contains(.abstractType),
                  let signature = sema.symbols.functionSignature(for: childID)
            else {
                return nil
            }
            return (childID, childInfo, signature)
        }
        guard abstractMethods.count == 1 else {
            return nil
        }
        return abstractMethods[0]
    }
}
