extension KIRLoweringDriver {
    func emitKPropertyStubCreate(
        propertySymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        isLocal: Bool = false,
        delegateValue: KIRExprID? = nil,
        ast: ASTModule? = nil,
        emit body: inout KIRLoweringEmitContext
    ) -> KIRExprID {
        let propertyName = sema.symbols.symbol(propertySymbol)?.name ?? interner.intern("")
        let propertyType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.anyType
        let propertyNameExprID = arena.appendExpr(
            .stringLiteral(propertyName),
            type: sema.types.stringType
        )
        body.append(.constValue(result: propertyNameExprID, value: .stringLiteral(propertyName)))
        let returnTypeSig = interner.intern(
            sema.types.displayName(of: propertyType, symbols: sema.symbols, interner: interner)
        )
        let returnTypeExprID = arena.appendExpr(
            .stringLiteral(returnTypeSig),
            type: sema.types.stringType
        )
        body.append(.constValue(result: returnTypeExprID, value: .stringLiteral(returnTypeSig)))
        let qualifiedName = sema.symbols.symbol(propertySymbol)?.fqName
            .map(interner.resolve)
            .joined(separator: ".") ?? interner.resolve(propertyName)
        let receiverTypeSig = sema.symbols.extensionPropertyReceiverType(for: propertySymbol)
            .map { sema.types.displayName(of: $0, symbols: sema.symbols, interner: interner) } ?? ""
        let ownerKind = sema.symbols.parentSymbol(for: propertySymbol)
            .flatMap { sema.symbols.symbol($0)?.kind }
        let hasReceiver = sema.symbols.extensionPropertyReceiverType(for: propertySymbol) != nil
            || ownerKind.map { [.class, .interface, .object, .enumClass, .annotationClass].contains($0) } == true
        let isMutable = sema.symbols.symbol(propertySymbol)?.flags.contains(.mutable) == true
        let identity = interner.intern(
            "delegate-property:\(qualifiedName):id=\(propertySymbol.rawValue):receiver=\(receiverTypeSig):return=\(interner.resolve(returnTypeSig)):arity=\(hasReceiver ? 1 : 0):mutable=\(isMutable)"
        )
        let identityExprID = arena.appendExpr(
            .stringLiteral(identity),
            type: sema.types.stringType
        )
        body.append(.constValue(result: identityExprID, value: .stringLiteral(identity)))
        let stubCalleeName: String
        var stubArguments = [propertyNameExprID, returnTypeExprID, identityExprID]
        if isLocal {
            let isMutableFlag: Int64 = isMutable ? 1 : 0
            let isMutableExprID = arena.appendExpr(
                .intLiteral(isMutableFlag),
                type: sema.types.intType
            )
            body.append(.constValue(result: isMutableExprID, value: .intLiteral(isMutableFlag)))
            stubArguments.append(isMutableExprID)
            stubCalleeName = "__kk_kproperty_stub_create_local"
        } else {
            if let wrapperValue = lambdaLowerer.lowerDelegatedPropertyStubWrapper(
                propertySymbol: propertySymbol,
                propertyName: propertyName,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &body.instructions
            ) {
                return wrapperValue
            }
            let arityExprID = arena.appendExpr(.intLiteral(hasReceiver ? 1 : 0), type: sema.types.intType)
            body.append(.constValue(result: arityExprID, value: .intLiteral(hasReceiver ? 1 : 0)))
            let isMutableExprID = arena.appendExpr(.intLiteral(isMutable ? 1 : 0), type: sema.types.intType)
            body.append(.constValue(result: isMutableExprID, value: .intLiteral(isMutable ? 1 : 0)))
            let returnTypeKTypeRaw = lowerKTypeExpr(
                for: propertyType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &body.instructions
            )
            stubArguments.append(contentsOf: [returnTypeKTypeRaw, arityExprID, isMutableExprID])
            stubCalleeName = "__kk_kproperty_stub_create_cached_typed"
        }
        let kPropertyExprID = arena.appendTemporary(type: sema.types.anyType
        )
        body.append(
            .call(callee: interner.intern(stubCalleeName), arguments: stubArguments, result: kPropertyExprID, canThrow: false)
        )
        if !isLocal {
            lambdaLowerer.emitFunctionDescription(
                value: kPropertyExprID,
                description: lambdaLowerer.propertyReferenceDescription(
                    memberName: propertyName,
                    propertySymbol: propertySymbol,
                    isMutable: isMutable,
                    returnType: propertyType,
                    sema: sema,
                    interner: interner
                ),
                identity: false,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &body.instructions
            )
        }
        // The stub object is cached per property identity while member
        // delegates differ per instance, so the delegate handle is pointed at
        // it right before each call rather than baked into creation.
        if let delegateValue, !isLocal {
            let setDelegateResult = arena.appendTemporary(type: sema.types.intType
            )
            body.append(.call(
                callee: interner.intern("__kk_kproperty_stub_set_delegate"),
                arguments: [kPropertyExprID, delegateValue],
                result: setDelegateResult,
                canThrow: false
            ))
        }
        return kPropertyExprID
    }

    func emitProvideDelegateInit(
        delegateObjExpr: KIRExprID,
        symbol: SymbolID,
        delegateStorageSymbol: SymbolID,
        delegateType _: TypeID,
        shared: KIRLoweringSharedContext,
        emit initInstructions: inout KIRLoweringEmitContext
    ) {
        let arena = shared.arena
        let sema = shared.sema
        let interner = shared.interner
        guard let provideDelegateSymbol = sema.symbols.delegateProvideDelegateSymbol(for: symbol) else {
            emitSimpleDelegateInit(
                delegateObjExpr: delegateObjExpr,
                delegateStorageSymbol: delegateStorageSymbol,
                shared: shared,
                emit: &initInstructions
            )
            return
        }

        initInstructions.append(.storeGlobal(value: delegateObjExpr, symbol: delegateStorageSymbol))

        let thisRefExprID = arena.appendExpr(.null, type: sema.types.nullableAnyType)
        initInstructions.append(.constValue(result: thisRefExprID, value: .null))

        let kPropertyExprID = emitKPropertyStubCreate(
            propertySymbol: symbol,
            sema: sema,
            arena: arena,
            interner: interner,
            delegateValue: delegateObjExpr,
            ast: shared.ast,
            emit: &initInstructions
        )

        let provideDelegateName = interner.intern("provideDelegate")
        // The stored result must keep the provideDelegate return type's ABI
        // representation: when the effective delegate type is a primitive
        // (e.g. `Long` from `Double.provideDelegate`), getValue/setValue
        // receiver code — including inlined bodies — reads the storage as a
        // raw scalar, so boxing it as `Any` would corrupt the receiver value.
        let provideDelegateResult = arena.appendTemporary(
            type: sema.symbols.functionSignature(for: provideDelegateSymbol)?.returnType
                ?? sema.types.anyType
        )
        initInstructions.append(memberLowerer.dispatchedDelegateMemberCall(
            symbol: provideDelegateSymbol,
            callee: provideDelegateName,
            receiver: delegateObjExpr,
            extraArguments: [thisRefExprID, kPropertyExprID],
            result: provideDelegateResult,
            sema: sema,
            interner: interner
        ))

        initInstructions.append(.storeGlobal(value: provideDelegateResult, symbol: delegateStorageSymbol))
    }

    func emitSimpleDelegateInit(
        delegateObjExpr: KIRExprID,
        delegateStorageSymbol: SymbolID,
        shared _: KIRLoweringSharedContext,
        emit initInstructions: inout KIRLoweringEmitContext
    ) {
        initInstructions.append(.storeGlobal(value: delegateObjExpr, symbol: delegateStorageSymbol))
    }
}
