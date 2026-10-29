
extension MemberLowerer {
    func lowerMemberDecls(
        memberFunctions: [DeclID],
        memberProperties: [DeclID],
        nestedClasses: [DeclID],
        nestedObjects: [DeclID],
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext? = nil,
        isInterfaceContext: Bool = false
    ) -> (directMembers: [KIRDeclID], allDecls: [KIRDeclID]) {
        lowerMemberDecls(
            memberFunctions: memberFunctions,
            memberProperties: memberProperties,
            nestedClasses: nestedClasses,
            nestedObjects: nestedObjects,
            ast: shared.ast,
            sema: shared.sema,
            arena: shared.arena,
            interner: shared.interner,
            propertyConstantInitializers: shared.propertyConstantInitializers,
            compilationCtx: compilationCtx,
            isInterfaceContext: isInterfaceContext
        )
    }

    func lowerDelegateAccessor(
        propertySymbol: SymbolID,
        propertyType: TypeID,
        delegateStorageSymbol: SymbolID,
        accessorKind: PropertyAccessorKind,
        shared: KIRLoweringSharedContext,
        allDecls: inout [KIRDeclID]
    ) {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner

        // See the matching note in MemberLowerer.lowerSingleMemberFunction
        // (KSP-CAP-001): this can run nested inside an enclosing function's
        // lowering (a delegated property on an object literal), so the reset
        // below must not discard that caller's scope.
        let scopeSnapshot = driver.ctx.saveScope()
        defer { driver.ctx.restoreScope(scopeSnapshot) }
        driver.ctx.resetScopeForFunction()
        driver.ctx.beginCallableLoweringScope()

        let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol)
        let extensionReceiverType = sema.symbols.extensionPropertyReceiverType(for: propertySymbol)
        let semanticAccessorSymbol = accessorKind == .getter
            ? sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
            : sema.symbols.extensionPropertySetterAccessor(for: propertySymbol)
        let semanticSignature = semanticAccessorSymbol.flatMap {
            sema.symbols.functionSignature(for: $0)
        }
        var params: [KIRParameter] = []
        var dispatchReceiverBinding: (symbol: SymbolID, exprID: KIRExprID)?

        // Member extension accessors take the dispatch receiver before the
        // extension receiver, matching ordinary extension-property accessors.
        if extensionReceiverType != nil,
           let ownerSymbol,
           let ownerInfo = sema.symbols.symbol(ownerSymbol),
           [.class, .interface, .enumClass, .object, .annotationClass].contains(ownerInfo.kind)
        {
            let ownerType = sema.types.make(
                .classType(ClassType(classSymbol: ownerSymbol, args: [], nullability: .nonNull))
            )
            let receiverSymbol = SyntheticSymbolScheme.receiverParameterSymbol(for: ownerSymbol)
            let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: ownerType)
            params.append(KIRParameter(symbol: receiverSymbol, type: ownerType))
            driver.ctx.setLocalValue(receiverExpr, for: receiverSymbol)
            driver.ctx.setLocalValue(receiverExpr, for: ownerSymbol)
            driver.ctx.setLocalDeclaredType(ownerType, for: ownerSymbol)
            driver.ctx.setQualifiedThisReceiver(receiverExpr, for: ownerInfo.name)
            driver.ctx.setCapturedOuterReceiver(receiverExpr, for: ownerSymbol)
            dispatchReceiverBinding = (receiverSymbol, receiverExpr)
        }

        if let extensionReceiverType {
            let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: propertySymbol)
            let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: extensionReceiverType)
            params.append(KIRParameter(symbol: receiverSymbol, type: extensionReceiverType))
            driver.ctx.setLocalDeclaredType(extensionReceiverType, for: receiverSymbol)
            driver.ctx.setImplicitReceiver(symbol: receiverSymbol, exprID: receiverExpr)
        } else if let ownerSymbol,
                  let ownerInfo = sema.symbols.symbol(ownerSymbol),
                  [.class, .interface, .enumClass, .object, .annotationClass].contains(ownerInfo.kind)
        {
            let ownerType = sema.types.make(
                .classType(ClassType(classSymbol: ownerSymbol, args: [], nullability: .nonNull))
            )
            let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: propertySymbol)
            let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: ownerType)
            params.append(KIRParameter(symbol: receiverSymbol, type: ownerType))
            driver.ctx.setImplicitReceiver(symbol: receiverSymbol, exprID: receiverExpr)
        }

        let returnType: TypeID
        let accessorName: InternedString
        // Sema's typeCheckDelegate resolves getValue/setValue through the ordinary
        // operator convention for every delegate kind now (lazy/observable/vetoable/
        // notNull included, since Lazy/ReadWriteProperty implementations declare
        // real getValue/setValue members) -- there is no separate "custom" path
        // anymore, just the one resolved-symbol dispatch below.
        let customGetValueSymbol = sema.symbols.delegateGetValueSymbol(for: propertySymbol)
        let customSetValueSymbol = sema.symbols.delegateSetValueSymbol(for: propertySymbol)
        // Only used for KIR dumps/LLVM instruction naming -- the actual call target
        // is `symbol: customGetValueSymbol`/`customSetValueSymbol` below.
        let getValueName = interner.intern("getValue")
        let setValueName = interner.intern("setValue")
        let getterReturnsTypeParameter = customGetValueSymbol
            .flatMap { sema.symbols.functionSignature(for: $0)?.returnType }
            .map { returnType in
                if case .typeParam = sema.types.kind(of: returnType) { return true }
                return false
            } ?? false
        let propertyTypeIsTypeParameter: Bool = if case .typeParam = sema.types.kind(of: propertyType) {
            true
        } else {
            false
        }
        let needsErasedGetterResultCast = getterReturnsTypeParameter && !propertyTypeIsTypeParameter

        var body: KIRLoweringEmitContext = [.beginBlock]
        if let dispatchReceiverBinding {
            body.append(.constValue(
                result: dispatchReceiverBinding.exprID,
                value: .symbolRef(dispatchReceiverBinding.symbol)
            ))
        }
        if let receiverBinding = driver.ctx.activeImplicitReceiver() {
            body.append(.constValue(result: receiverBinding.exprID, value: .symbolRef(receiverBinding.symbol)))
        }

        switch accessorKind {
        case .getter:
            returnType = propertyType
            accessorName = interner.intern("get")

            let delegateHandleExprID = loadDelegateHandle(
                delegateStorageSymbol: delegateStorageSymbol,
                ownerSymbol: ownerSymbol,
                receiverExprID: dispatchReceiverBinding?.exprID ?? driver.ctx.activeImplicitReceiverExprID(),
                sema: sema,
                arena: arena,
                interner: interner,
                body: &body
            )
            let resultExprID = arena.appendTemporary(
                type: needsErasedGetterResultCast ? sema.types.anyType : propertyType
            )
            let getterExtraArgs = buildCustomDelegateGetterArgs(
                propertySymbol: propertySymbol,
                sema: sema,
                arena: arena,
                interner: interner,
                body: &body
            )
            body.append(dispatchedDelegateMemberCall(
                symbol: customGetValueSymbol,
                callee: getValueName,
                receiver: delegateHandleExprID,
                extraArguments: getterExtraArgs,
                result: resultExprID,
                sema: sema,
                interner: interner
            ))
            if needsErasedGetterResultCast {
                let typeToken = RuntimeTypeCheckToken.encode(
                    type: propertyType, sema: sema, interner: interner
                )
                let typeTokenExprID = arena.appendExpr(.intLiteral(typeToken), type: sema.types.intType)
                body.append(.constValue(
                    result: typeTokenExprID,
                    value: .intLiteral(typeToken)
                ))
                let checkedResultExprID = arena.appendTemporary(type: propertyType)
                body.append(.call(
                    callee: interner.intern("kk_op_cast_erased_return"),
                    arguments: [resultExprID, typeTokenExprID],
                    result: checkedResultExprID,
                    canThrow: true
                ))
                body.append(.returnValue(checkedResultExprID))
            } else {
                body.append(.returnValue(resultExprID))
            }

        case .setter:
            returnType = sema.types.unitType
            accessorName = interner.intern("set")

            let valueParamSymbol = SyntheticSymbolScheme.setterValueParameterSymbol(for: propertySymbol)
            params.append(KIRParameter(symbol: valueParamSymbol, type: propertyType))

            let valueExprID = arena.appendExpr(.symbolRef(valueParamSymbol), type: propertyType)
            body.append(.constValue(result: valueExprID, value: .symbolRef(valueParamSymbol)))
            let delegateHandleExprID = loadDelegateHandle(
                delegateStorageSymbol: delegateStorageSymbol,
                ownerSymbol: ownerSymbol,
                receiverExprID: dispatchReceiverBinding?.exprID ?? driver.ctx.activeImplicitReceiverExprID(),
                sema: sema,
                arena: arena,
                interner: interner,
                body: &body
            )
            let resultExprID = arena.appendTemporary(type: sema.types.unitType
            )
            let setterExtraArgs = buildCustomDelegateSetterArgs(
                propertySymbol: propertySymbol,
                valueExprID: valueExprID,
                sema: sema,
                arena: arena,
                interner: interner,
                body: &body
            )
            body.append(dispatchedDelegateMemberCall(
                symbol: customSetValueSymbol,
                callee: setValueName,
                receiver: delegateHandleExprID,
                extraArguments: setterExtraArgs,
                result: resultExprID,
                sema: sema,
                interner: interner
            ))
            body.append(.returnUnit)
        }

        var typeTokenBindings: [(symbol: SymbolID, exprID: KIRExprID)] = []
        if let semanticSignature {
            for index in semanticSignature.reifiedTypeParameterIndices.sorted()
                where index < semanticSignature.typeParameterSymbols.count
            {
                let typeParameter = semanticSignature.typeParameterSymbols[index]
                let token = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParameter)
                let value = arena.appendExpr(.symbolRef(token), type: sema.types.intType)
                params.append(KIRParameter(symbol: token, type: sema.types.intType))
                driver.ctx.setLocalValue(value, for: token)
                typeTokenBindings.append((token, value))
            }
        }
        body.append(.endBlock)

        let syntheticAccessorSymbol = semanticAccessorSymbol
            ?? SyntheticSymbolScheme.propertyAccessorSymbol(for: propertySymbol, kind: accessorKind)
        var tokenInsertionIndex = body.index(after: body.startIndex)
        for (token, value) in typeTokenBindings {
            body.insert(.constValue(result: value, value: .symbolRef(token)), at: tokenInsertionIndex)
            tokenInsertionIndex = body.index(after: tokenInsertionIndex)
        }

        if sema.symbols.functionSignature(for: syntheticAccessorSymbol) == nil {
            let accessorOwnerType = extensionReceiverType ?? ownerSymbol.flatMap { owner in
                guard let ownerInfo = sema.symbols.symbol(owner),
                      [.class, .interface, .enumClass, .object, .annotationClass].contains(ownerInfo.kind)
                else { return nil }
                return sema.types.make(.classType(ClassType(
                    classSymbol: owner, args: [], nullability: .nonNull
                )))
            }
            sema.symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: accessorOwnerType,
                    parameterTypes: accessorKind == .setter ? [propertyType] : [],
                    returnType: accessorKind == .setter ? sema.types.unitType : propertyType
                ),
                for: syntheticAccessorSymbol
            )
        }

        let kirID = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: syntheticAccessorSymbol,
                    name: accessorName,
                    params: params,
                    returnType: returnType,
                    body: body,
                    isSuspend: false,
                    isInline: !(semanticSignature?.reifiedTypeParameterIndices.isEmpty ?? true)
                )
            )
        )
        allDecls.append(kirID)
        allDecls.append(contentsOf: driver.ctx.drainGeneratedCallableDecls())
        driver.ctx.clearImplicitReceiver()
    }

    /// Delegate conventions dispatch through the interface or class slot when
    /// the resolved member can be overridden. A factory may return an abstract
    /// delegate type even though the runtime object supplies the implementation.
    /// The delegate handle's static type is erased to `Any` in `$delegate_x`
    /// storage, so this always uses the dynamic (runtime type ID) itable
    /// lookup rather than a statically-known slot.
    func dispatchedDelegateMemberCall(
        symbol: SymbolID?,
        callee: InternedString,
        receiver: KIRExprID,
        extraArguments: [KIRExprID],
        result: KIRExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> KIRInstruction {
        let dispatchReceiver: KIRExprID? = if let symbol,
            let owner = sema.symbols.memberExtensionOwnerSymbol(for: symbol)
        {
            driver.ctx.localValue(for: owner) ?? driver.ctx.activeImplicitReceiverExprID()
        } else {
            nil
        }
        if let symbol,
           let parentID = sema.symbols.parentSymbol(for: symbol),
           sema.symbols.symbol(parentID)?.kind == .interface,
           let methodSlot = sema.symbols.nominalLayout(for: parentID)?.vtableSlots[symbol]
        {
            let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                symbol: parentID, sema: sema, interner: interner
            )
            return .virtualCall(
                symbol: symbol,
                callee: callee,
                receiver: dispatchReceiver ?? receiver,
                arguments: dispatchReceiver.map { _ in [receiver] + extraArguments } ?? extraArguments,
                result: result,
                canThrow: false,
                dispatch: .itableDynamic(interfaceTypeID: interfaceTypeID, methodSlot: methodSlot)
            )
        }
        if let symbol,
           let dispatch = resolveVirtualDispatchKind(
               callee: symbol, receiverTypeID: nil, sema: sema, interner: interner
           )
        {
            return .virtualCall(
                symbol: symbol,
                callee: callee,
                receiver: dispatchReceiver ?? receiver,
                arguments: dispatchReceiver.map { _ in [receiver] + extraArguments } ?? extraArguments,
                result: result,
                canThrow: false,
                dispatch: dispatch
            )
        }
        let arguments = dispatchReceiver.map { [$0, receiver] + extraArguments }
            ?? ([receiver] + extraArguments)
        let captures = symbol.flatMap { driver.ctx.localValue(for: $0) }
            .flatMap { driver.ctx.callableValueInfo(for: $0) }?.captureArguments ?? []
        return .call(symbol: symbol, callee: callee, arguments: captures + arguments, result: result, canThrow: false)
    }

    /// Class/interface instance delegates live inside the heap-allocated object,
    /// while enum delegates use a per-entry global slot because enum values are
    /// ordinal-backed. Top-level and `object`-member delegates intentionally
    /// keep a single shared instance backed by a real global.
    private func loadDelegateHandle(
        delegateStorageSymbol: SymbolID,
        ownerSymbol: SymbolID?,
        receiverExprID: KIRExprID?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let delegateType = sema.types.anyType
        if let ownerSymbol,
           sema.symbols.symbol(ownerSymbol)?.kind == .enumClass,
           let receiverExprID = driver.ctx.activeImplicitReceiverExprID(),
           let storageName = sema.symbols.symbol(delegateStorageSymbol)?.name
        {
            // Enum values are ordinal-backed, so their delegate handles live
            // in per-entry globals and are read through the enum storage helper.
            let helperName = EnumPropertyHelperNames.placeholder(
                prefix: EnumPropertyHelperNames.getterPrefix,
                ownerSymbol: ownerSymbol,
                propertyName: storageName,
                interner: interner
            )
            let result = arena.appendTemporary(type: delegateType)
            body.append(.call(callee: helperName, arguments: [receiverExprID], result: result, canThrow: false))
            return result
        }
        if let ownerSymbol,
           let ownerInfo = sema.symbols.symbol(ownerSymbol),
           ownerInfo.kind == .class || ownerInfo.kind == .interface,
           let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[delegateStorageSymbol],
           let receiverValue = receiverExprID ?? driver.ctx.activeImplicitReceiverExprID()
        {
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            let result = arena.appendTemporary(type: delegateType)
            body.append(.call(
                callee: interner.intern("kk_array_get_inbounds"),
                arguments: [receiverValue, offsetExpr],
                result: result,
                canThrow: false
            ))
            return result
        }
        let result = arena.appendTemporary(type: delegateType)
        body.append(.loadGlobal(result: result, symbol: delegateStorageSymbol))
        return result
    }

    private func buildCustomDelegateGetterArgs(
        propertySymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        body: inout KIRLoweringEmitContext
    ) -> [KIRExprID] {
        let thisRefExprID: KIRExprID
        if let receiver = driver.ctx.activeImplicitReceiverExprID() {
            thisRefExprID = receiver
        } else {
            thisRefExprID = arena.appendExpr(.null, type: sema.types.nullableAnyType)
            body.append(.constValue(result: thisRefExprID, value: .null))
        }
        let kPropertyExprID = buildKPropertyStub(
            propertySymbol: propertySymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            body: &body
        )
        return [thisRefExprID, kPropertyExprID]
    }

    private func buildCustomDelegateSetterArgs(
        propertySymbol: SymbolID,
        valueExprID: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        body: inout KIRLoweringEmitContext
    ) -> [KIRExprID] {
        buildCustomDelegateGetterArgs(
            propertySymbol: propertySymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            body: &body
        ) + [valueExprID]
    }

    /// Unlike a member delegate, whose `thisRef` is the enclosing instance, a
    /// local delegate is never bound to a receiver — `thisRef` is always `null`
    /// regardless of whether the declaration happens to sit inside a member
    /// function (where an unrelated implicit receiver for the *enclosing class*
    /// may be active).
    ///
    /// Takes a plain `[KIRInstruction]` (rather than `KIRLoweringEmitContext`,
    /// as `buildKPropertyStub` below does) because callers here are inlining
    /// into an *already-existing* function body being lowered by `ExprLowerer`,
    /// not building a standalone synthetic accessor function from scratch.
    func buildLocalDelegateAccessorArgs(
        localSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> [KIRExprID] {
        let thisRefExprID = arena.appendExpr(.null, type: sema.types.nullableAnyType)
        instructions.append(.constValue(result: thisRefExprID, value: .null))
        var body = KIRLoweringEmitContext(instructions)
        let kPropertyExprID = buildKPropertyStub(
            propertySymbol: localSymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            isLocal: true,
            body: &body
        )
        instructions = body.instructions
        return [thisRefExprID, kPropertyExprID]
    }

    private func buildKPropertyStub(
        propertySymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        isLocal: Bool = false,
        body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        driver.emitKPropertyStubCreate(
            propertySymbol: propertySymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            isLocal: isLocal,
            emit: &body
        )
    }

    /// Getter signature: `([dispatch,] receiver) -> PropertyType`
    /// Setter signature: `([dispatch,] receiver, value: PropertyType) -> Unit`
    func lowerAccessorBody(
        accessorBody: FunctionBody,
        propertySymbol: SymbolID,
        propertyType: TypeID,
        accessorKind: PropertyAccessorKind,
        setterParamName _: InternedString?,
        shared: KIRLoweringSharedContext,
        allDecls: inout [KIRDeclID]
    ) {
        let ast = shared.ast
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner

        // See the matching note in MemberLowerer.lowerSingleMemberFunction
        // (KSP-CAP-001): this can run nested inside an enclosing function's
        // lowering (a getter/setter body on an object literal property), so
        // the reset below must not discard that caller's scope.
        let scopeSnapshot = driver.ctx.saveScope()
        defer { driver.ctx.restoreScope(scopeSnapshot) }
        driver.ctx.resetScopeForFunction()
        driver.ctx.beginCallableLoweringScope()

        let semanticAccessor = accessorKind == .getter
            ? sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
            : sema.symbols.extensionPropertySetterAccessor(for: propertySymbol)
        let semanticSignature = semanticAccessor.flatMap { sema.symbols.functionSignature(for: $0) }
        let ownerSymbol = sema.symbols.parentSymbol(for: propertySymbol)
        let receiverOwnerSymbol: SymbolID? = {
            guard let ownerSymbol,
                  sema.symbols.symbol(ownerSymbol)?.kind == .field,
                  let enumOwner = sema.symbols.parentSymbol(for: ownerSymbol),
                  sema.symbols.symbol(enumOwner)?.kind == .enumClass
            else {
                return ownerSymbol
            }
            return enumOwner
        }()
        let extensionReceiverType = sema.symbols.extensionPropertyReceiverType(for: propertySymbol)
        var params: [KIRParameter] = []

        // Member extensions carry dispatch first, then extension (bare `this`).
        var dispatchReceiverBinding: (symbol: SymbolID, exprID: KIRExprID)?
        if extensionReceiverType != nil,
           let ownerSymbol,
           let ownerInfo = sema.symbols.symbol(ownerSymbol),
           [.class, .interface, .enumClass, .object].contains(ownerInfo.kind)
        {
            let ownerType = sema.types.make(.classType(ClassType(
                classSymbol: ownerSymbol, args: [], nullability: .nonNull
            )))
            let receiverSymbol = SyntheticSymbolScheme.receiverParameterSymbol(for: ownerSymbol)
            let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: ownerType)
            params.append(KIRParameter(symbol: receiverSymbol, type: ownerType))
            driver.ctx.setLocalValue(receiverExpr, for: receiverSymbol)
            driver.ctx.setLocalValue(receiverExpr, for: ownerSymbol)
            driver.ctx.setLocalDeclaredType(ownerType, for: ownerSymbol)
            driver.ctx.setQualifiedThisReceiver(receiverExpr, for: ownerInfo.name)
            driver.ctx.setCapturedOuterReceiver(receiverExpr, for: ownerSymbol)
            dispatchReceiverBinding = (receiverSymbol, receiverExpr)
        }

        if let receiverType = extensionReceiverType {
            let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: propertySymbol)
            params.append(KIRParameter(symbol: receiverSymbol, type: receiverType))
            driver.ctx.setLocalDeclaredType(receiverType, for: receiverSymbol)
            driver.ctx.setImplicitReceiver(
                symbol: receiverSymbol,
                exprID: arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
            )
        } else if let receiverOwnerSymbol,
                  let ownerSym = sema.symbols.symbol(receiverOwnerSymbol)
        {
            let ownerType = sema.types.make(
                .classType(ClassType(classSymbol: ownerSym.id, args: [], nullability: .nonNull))
            )
            let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: propertySymbol)
            params.append(KIRParameter(symbol: receiverSymbol, type: ownerType))
            let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: ownerType)
            driver.ctx.setLocalValue(receiverExpr, for: receiverOwnerSymbol)
            driver.ctx.setLocalDeclaredType(ownerType, for: receiverOwnerSymbol)
            driver.ctx.setImplicitReceiver(
                symbol: receiverSymbol,
                exprID: receiverExpr
            )
        }

        let contextParameters = zip(
            semanticSignature?.contextParameterSymbols ?? [],
            semanticSignature?.contextParameterTypes ?? []
        ).map { symbol, type in
            let parameter = KIRParameter(symbol: symbol, type: type)
            let value = arena.appendExpr(.symbolRef(symbol), type: type)
            driver.ctx.setLocalDeclaredType(type, for: symbol)
            driver.ctx.setLocalValue(value, for: symbol)
            return (parameter: parameter, value: value, type: type)
        }
        params.append(contentsOf: contextParameters.map(\.parameter))
        let contextReceiverValues = contextParameters.map { parameter in
            KIRLoweringContext.ContextReceiverValue(type: parameter.type, exprID: parameter.value)
        }

        let returnType: TypeID
        let accessorName: InternedString
        switch accessorKind {
        case .getter:
            returnType = propertyType
            accessorName = interner.intern("get")
            // Keep `field` bound to its backing-field symbol so ExprLowerer can
            // resolve it through the active receiver's instance layout.
        case .setter:
            returnType = sema.types.unitType
            accessorName = interner.intern("set")
            let valueParamSymbol = SyntheticSymbolScheme.setterValueParameterSymbol(for: propertySymbol)
            params.append(KIRParameter(symbol: valueParamSymbol, type: propertyType))
            let valueExprID = arena.appendExpr(.symbolRef(valueParamSymbol), type: propertyType)
            driver.ctx.setLocalValue(valueExprID, for: valueParamSymbol)
            // Sema binds the setter parameter name to a synthetic setter-value
            // symbol (offset -40_000) distinct from both the property symbol
            // and the backing field symbol.
            let semaSetterValueSymbol = SyntheticSymbolScheme.semaSetterValueSymbol(for: propertySymbol)
            driver.ctx.setLocalValue(valueExprID, for: semaSetterValueSymbol)
            // Keep `field` bound to its backing-field symbol so ExprLowerer can
            // resolve it through the active receiver's instance layout.
        }

        var typeTokenBindings: [(SymbolID, KIRExprID)] = []
        if let signature = semanticSignature {
            for index in signature.reifiedTypeParameterIndices.sorted() where index < signature.typeParameterSymbols.count {
                let typeParameter = signature.typeParameterSymbols[index]
                let tokens = [
                    SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParameter),
                    SyntheticSymbolScheme.reifiedArrayComponentTokenSymbol(for: typeParameter),
                ]
                for token in tokens {
                    params.append(KIRParameter(symbol: token, type: sema.types.intType))
                    let value = arena.appendExpr(.symbolRef(token), type: sema.types.intType)
                    driver.ctx.setLocalValue(value, for: token)
                    typeTokenBindings.append((token, value))
                }
            }
        }
        var body: KIRLoweringEmitContext = [.beginBlock]
        for (token, value) in typeTokenBindings { body.append(.constValue(result: value, value: .symbolRef(token))) }
        if let dispatchReceiverBinding {
            body.append(.constValue(result: dispatchReceiverBinding.exprID, value: .symbolRef(dispatchReceiverBinding.symbol)))
        }
        if let receiverBinding = driver.ctx.activeImplicitReceiver() {
            body.append(.constValue(result: receiverBinding.exprID, value: .symbolRef(receiverBinding.symbol)))
        }
        for parameter in contextParameters {
            body.append(.constValue(result: parameter.value, value: .symbolRef(parameter.parameter.symbol)))
        }
        // KSP-CAP-018: an accessor body is its own KIR function with its own
        // scope, so an outer local captured by an object literal has to be
        // read back out of the instance field it was stored into — the same
        // no-op-for-named-classes step `lowerSingleMemberFunction` already
        // performs (KSP-CAP-001). Without it the accessor body referenced a
        // symbol that had no value in this scope.
        driver.objectLiteralLowerer.restoreObjectLiteralCaptures(
            forMemberFunction: propertySymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body.instructions
        )

        driver.ctx.withContextReceiverValues(contextReceiverValues) {
        switch accessorBody {
        case let .block(exprIDs, _):
            var lastValue: KIRExprID?
            var terminatedByReturn = false
            for exprID in exprIDs {
                if let expr = ast.arena.expr(exprID),
                   case let .returnExpr(value, _, _) = expr
                {
                    if let value {
                        let lowered = driver.lowerExpr(
                            value,
                            shared: shared,
                            emit: &body
                        )
                        body.append(.returnValue(lowered))
                    } else {
                        body.append(.returnUnit)
                    }
                    terminatedByReturn = true
                    break
                }
                lastValue = driver.lowerExpr(
                    exprID,
                    shared: shared,
                    emit: &body
                )
            }
            if !terminatedByReturn {
                if accessorKind == .getter, let lastValue {
                    body.append(.returnValue(lastValue))
                } else {
                    body.append(.returnUnit)
                }
            }
        case let .expr(exprID, _):
            let value = driver.lowerExpr(
                exprID,
                shared: shared,
                emit: &body
            )
            if accessorKind == .getter {
                body.append(.returnValue(value))
            } else {
                body.append(.returnUnit)
            }
        case .unit:
            body.append(.returnUnit)
        }
        }
        body.append(.endBlock)

        let syntheticAccessorSymbol: SymbolID = switch accessorKind {
        case .getter:
            sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
                ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
        case .setter:
            sema.symbols.extensionPropertySetterAccessor(for: propertySymbol)
                ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySymbol)
        }

        // Keep the synthetic accessor's signature available to ABI lowering in
        // the same compilation. Imported library metadata already restores this
        // signature, but source-backed properties otherwise leave their accessor
        // symbol unregistered even though the KIR call carries it.
        let previousSignature = sema.symbols.functionSignature(for: syntheticAccessorSymbol)
        sema.symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: extensionReceiverType ?? receiverOwnerSymbol.flatMap { owner in
                    sema.symbols.symbol(owner).map { ownerInfo in
                        sema.types.make(.classType(ClassType(
                            classSymbol: ownerInfo.id,
                            args: [],
                            nullability: .nonNull
                        )))
                    }
                },
                contextReceiverTypes: semanticSignature?.contextReceiverTypes ?? [],
                contextParameterSymbols: semanticSignature?.contextParameterSymbols ?? [],
                contextParameterTypes: semanticSignature?.contextParameterTypes ?? [],
                parameterTypes: accessorKind == .setter ? [propertyType] : [],
                returnType: returnType,
                canThrow: true,
                typeParameterSymbols: previousSignature?.typeParameterSymbols ?? [],
                reifiedTypeParameterIndices: previousSignature?.reifiedTypeParameterIndices ?? [],
                typeParameterUpperBoundsList: previousSignature?.typeParameterUpperBoundsList ?? [],
                classTypeParameterCount: previousSignature?.classTypeParameterCount ?? 0
            ),
            for: syntheticAccessorSymbol
        )

        let kirID = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: syntheticAccessorSymbol,
                    name: accessorName,
                    params: params,
                    returnType: returnType,
                    body: body,
                    isSuspend: false,
                    isInline: !(semanticSignature?.reifiedTypeParameterIndices.isEmpty ?? true)
                )
            )
        )
        allDecls.append(kirID)
        allDecls.append(contentsOf: driver.ctx.drainGeneratedCallableDecls())
        driver.ctx.clearImplicitReceiver()
    }

    /// Concrete classes and object literals need a getter accessor for every
    /// property that overrides an interface property so its getter can be
    /// registered into the interface's itable and dispatched through an
    /// interface-typed receiver.
    func synthesizeStoredPropertyGetterAccessor(
        propertySymbol: SymbolID,
        ownerSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        allDecls: inout [KIRDeclID]
    ) {
        guard let ownerSym = sema.symbols.symbol(ownerSymbol) else { return }
        let fieldKey = sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
        // Enum values are ordinal-backed and have no instance fields: their
        // stored properties live in the per-entry storage read by the enum
        // property helper, so the getter (registered into itables for
        // interface-typed reads) forwards there.
        // Abstract enum properties have no storage of their own (entry
        // bodies implement them), so they keep no forwarding accessor.
        let isEnumOwned = ownerSym.kind == .enumClass
            && sema.symbols.symbol(propertySymbol)?.flags.contains(.abstractType) != true
        let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[fieldKey]
        guard isEnumOwned || fieldOffset != nil else {
            return
        }
        let propType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType

        let ownerType = sema.types.make(
            .classType(ClassType(classSymbol: ownerSym.id, args: [], nullability: .nonNull))
        )
        let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: propertySymbol)
        // An itable/vtable-dispatched enum receiver arrives already boxed
        // (`kk_enum_box_ordinal`); typing it as the enum would re-box the
        // box pointer as if it were an ordinal.
        let receiverKIRType = isEnumOwned ? sema.types.anyType : ownerType
        let params = [KIRParameter(symbol: receiverSymbol, type: receiverKIRType)]
        let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: receiverKIRType)
        let getterSymbol = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
        sema.symbols.setFunctionSignature(
            FunctionSignature(receiverType: ownerType, parameterTypes: [], returnType: propType),
            for: getterSymbol
        )

        var body: KIRLoweringEmitContext = [.beginBlock]
        body.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSymbol)))
        let result = arena.appendTemporary(type: propType)
        if ownerSym.kind == .object {
            // Named singleton properties use global storage, even when their
            // getters retain a receiver parameter for interface dispatch.
            body.append(.loadGlobal(result: result, symbol: fieldKey))
        } else if let fieldOffset, !isEnumOwned {
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            body.append(.call(
                callee: interner.intern("kk_array_get_inbounds"),
                arguments: [receiverExpr, offsetExpr],
                result: result,
                canThrow: false
            ))
        } else {
            body.append(.call(
                callee: EnumPropertyHelperNames.placeholder(
                    prefix: EnumPropertyHelperNames.getterPrefix,
                    ownerSymbol: ownerSymbol,
                    propertyName: sema.symbols.symbol(propertySymbol)?.name ?? interner.intern(""),
                    interner: interner
                ),
                arguments: [receiverExpr],
                result: result,
                canThrow: false
            ))
        }
        body.append(.returnValue(result))
        body.append(.endBlock)

        let kirID = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: getterSymbol,
                    name: interner.intern("get"),
                    params: params,
                    returnType: propType,
                    body: body,
                    isSuspend: false,
                    isInline: false
                )
            )
        )
        allDecls.append(kirID)
        allDecls.append(contentsOf: driver.ctx.drainGeneratedCallableDecls())
    }

    /// BUG-227: every class whose stored property ever needs virtual dispatch
    /// (the open/abstract root of an override chain, or a link further down it)
    /// needs a setter accessor so a write through a base-typed reference can
    /// dispatch to it the same way a read dispatches to the getter.
    func synthesizeStoredPropertySetterAccessor(
        propertySymbol: SymbolID,
        ownerSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        allDecls: inout [KIRDeclID]
    ) {
        guard let ownerSym = sema.symbols.symbol(ownerSymbol) else { return }
        let fieldKey = sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
        // Abstract enum properties have no storage of their own (entry
        // bodies implement them), so they keep no forwarding accessor.
        let isEnumOwned = ownerSym.kind == .enumClass
            && sema.symbols.symbol(propertySymbol)?.flags.contains(.abstractType) != true
        let fieldOffset = sema.symbols.nominalLayout(for: ownerSymbol)?.fieldOffsets[fieldKey]
        guard isEnumOwned || fieldOffset != nil else {
            return
        }
        let propType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType

        let ownerType = sema.types.make(
            .classType(ClassType(classSymbol: ownerSym.id, args: [], nullability: .nonNull))
        )
        let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: propertySymbol)
        let valueParamSymbol = SyntheticSymbolScheme.setterValueParameterSymbol(for: propertySymbol)
        let receiverKIRType = isEnumOwned ? sema.types.anyType : ownerType
        let params = [
            KIRParameter(symbol: receiverSymbol, type: receiverKIRType),
            KIRParameter(symbol: valueParamSymbol, type: propType),
        ]
        let receiverExpr = arena.appendExpr(.symbolRef(receiverSymbol), type: receiverKIRType)
        let valueExpr = arena.appendExpr(.symbolRef(valueParamSymbol), type: propType)

        var body: KIRLoweringEmitContext = [.beginBlock]
        body.append(.constValue(result: receiverExpr, value: .symbolRef(receiverSymbol)))
        body.append(.constValue(result: valueExpr, value: .symbolRef(valueParamSymbol)))
        if ownerSym.kind == .object {
            body.append(.storeGlobal(value: valueExpr, symbol: fieldKey))
        } else if let fieldOffset, !isEnumOwned {
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(fieldOffset)), type: sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(fieldOffset))))
            body.append(.call(
                callee: interner.intern("kk_array_set"),
                arguments: [receiverExpr, offsetExpr, valueExpr],
                result: nil,
                canThrow: false
            ))
        } else {
            body.append(.call(
                callee: EnumPropertyHelperNames.placeholder(
                    prefix: EnumPropertyHelperNames.setterPrefix,
                    ownerSymbol: ownerSymbol,
                    propertyName: sema.symbols.symbol(propertySymbol)?.name ?? interner.intern(""),
                    interner: interner
                ),
                arguments: [receiverExpr, valueExpr],
                result: arena.appendTemporary(type: sema.types.unitType),
                canThrow: false
            ))
        }
        body.append(.returnUnit)
        body.append(.endBlock)

        let setterSymbol = SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySymbol)
        let kirID = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: setterSymbol,
                    name: interner.intern("set"),
                    params: params,
                    returnType: sema.types.unitType,
                    body: body,
                    isSuspend: false,
                    isInline: false
                )
            )
        )
        allDecls.append(kirID)
        allDecls.append(contentsOf: driver.ctx.drainGeneratedCallableDecls())
    }

    /// The stub is never executed — interface property reads dispatch through
    /// the itable — but it gives the dispatch site a concrete internal function
    /// whose signature matches the registered implementing getters, exactly as
    /// abstract interface methods emit a unit-returning stub.
    func synthesizeInterfacePropertyGetterStub(
        propertySymbol: SymbolID,
        ownerSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        allDecls: inout [KIRDeclID]
    ) {
        guard let ownerSym = sema.symbols.symbol(ownerSymbol) else { return }
        let propType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType

        let ownerType = sema.types.make(
            .classType(ClassType(classSymbol: ownerSym.id, args: [], nullability: .nonNull))
        )
        let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: propertySymbol)
        let params = [KIRParameter(symbol: receiverSymbol, type: ownerType)]

        var body: KIRLoweringEmitContext = [.beginBlock]
        let defaultExpr = arena.appendExpr(.null, type: propType)
        body.append(.constValue(result: defaultExpr, value: .null))
        body.append(.returnValue(defaultExpr))
        body.append(.endBlock)

        let getterSymbol = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
        sema.symbols.setFunctionSignature(
            FunctionSignature(receiverType: ownerType, parameterTypes: [], returnType: propType),
            for: getterSymbol
        )
        let kirID = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: getterSymbol,
                    name: interner.intern("get"),
                    params: params,
                    returnType: propType,
                    body: body,
                    isSuspend: false,
                    isInline: false
                )
            )
        )
        allDecls.append(kirID)
        allDecls.append(contentsOf: driver.ctx.drainGeneratedCallableDecls())
    }

    /// Without this stub, an abstract interface property's setter has no
    /// registered symbol at all (its getter always gets the stub above), so
    /// anything that resolves to it — for example a `by`-delegation forwarder
    /// whose dispatch falls back to the interface's own declaration — links
    /// against an undefined name.
    func synthesizeInterfacePropertySetterStub(
        propertySymbol: SymbolID,
        ownerSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        allDecls: inout [KIRDeclID]
    ) {
        guard let ownerSym = sema.symbols.symbol(ownerSymbol) else { return }
        let propType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType

        let ownerType = sema.types.make(
            .classType(ClassType(classSymbol: ownerSym.id, args: [], nullability: .nonNull))
        )
        let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: propertySymbol)
        let valueParamSymbol = SyntheticSymbolScheme.setterValueParameterSymbol(for: propertySymbol)
        let params = [
            KIRParameter(symbol: receiverSymbol, type: ownerType),
            KIRParameter(symbol: valueParamSymbol, type: propType),
        ]

        var body: KIRLoweringEmitContext = [.beginBlock]
        body.append(.returnUnit)
        body.append(.endBlock)

        let setterSymbol = SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySymbol)
        let kirID = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: setterSymbol,
                    name: interner.intern("set"),
                    params: params,
                    returnType: sema.types.unitType,
                    body: body,
                    isSuspend: false,
                    isInline: false
                )
            )
        )
        allDecls.append(kirID)
        allDecls.append(contentsOf: driver.ctx.drainGeneratedCallableDecls())
    }
}
