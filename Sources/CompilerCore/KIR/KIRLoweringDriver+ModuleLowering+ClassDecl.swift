
import RuntimeABI

extension KIRLoweringDriver {
    func lowerTopLevelClassDecl(
        _ classDecl: ClassDecl,
        symbol: SymbolID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext
    ) -> [KIRDeclID] {
        let sema = shared.sema
        let arena = shared.arena

        var declIDs: [KIRDeclID] = []
        var allNestedObjects = classDecl.nestedObjects
        if let companionDeclID = classDecl.companionObject {
            allNestedObjects.append(companionDeclID)
        }

        // BUG-274: synthesize the companion's initializer -- which registers
        // its lazy "ensure initialized" entry -- *before* lowering this
        // class's own member function bodies below. Those bodies can
        // reference the companion (`Companion.member`, or a bare `member`
        // treated as implicit companion access) and need the registry entry
        // already populated for the lazy-init guard to actually fire;
        // lowering member functions first left the registry empty for
        // their own enclosing companion.
        declIDs.append(contentsOf: synthesizeCompanionInitializerIfNeeded(
            companionDeclID: classDecl.companionObject,
            ownerSymbol: symbol,
            shared: shared
        ))

        let (directMembers, memberDecls) = memberLowerer.lowerMemberDecls(
            memberFunctions: classDecl.memberFunctions,
            memberProperties: classDecl.memberProperties,
            nestedClasses: classDecl.nestedClasses,
            nestedObjects: allNestedObjects,
            shared: shared,
            compilationCtx: compilationCtx
        )
        var allDecls = memberDecls
        if sema.symbols.symbol(symbol)?.kind == .enumClass {
            allDecls.append(contentsOf: memberLowerer.lowerEnumEntryBodyMembers(
                classDecl: classDecl,
                shared: shared,
                compilationCtx: compilationCtx
            ))
        }
        var finalDirectMembers = directMembers
        let forwardingDeclIDs = synthesizeClassDelegationForwardingMethods(
            classSymbol: symbol,
            shared: shared,
            compilationCtx: compilationCtx
        )
        finalDirectMembers.append(contentsOf: forwardingDeclIDs)
        let forwardingPropertyDeclIDs = synthesizeClassDelegationForwardingPropertyAccessors(
            classSymbol: symbol,
            shared: shared,
            compilationCtx: compilationCtx
        )
        finalDirectMembers.append(contentsOf: forwardingPropertyDeclIDs)
        let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: finalDirectMembers)))
        declIDs.append(kirID)
        declIDs.append(contentsOf: allDecls)
        declIDs.append(contentsOf: forwardingDeclIDs)
        declIDs.append(contentsOf: forwardingPropertyDeclIDs)
        declIDs.append(contentsOf: synthesizeConstructorReflectionInitializer(
            classDecl: classDecl,
            ownerSymbol: symbol,
            shared: shared
        ))

        let ctorFQName = (sema.symbols.symbol(symbol)?.fqName ?? []) + [shared.interner.intern("<init>")]
        let ctorSymbols = sema.symbols.lookupAll(
            fqName: ctorFQName
        )
        for ctorSymbol in ctorSymbols {
            declIDs.append(contentsOf: lowerConstructor(
                ctorSymbol: ctorSymbol,
                ctorFQName: ctorFQName,
                classDecl: classDecl,
                ownerSymbol: symbol,
                shared: shared
            ))
        }

        // MemberLowerer has already emitted nested constructors recursively.
        // Add the reflection initializers and enum helpers here only once.
        lowerNestedClassConstructors(
            nestedClasses: classDecl.nestedClasses,
            shared: shared,
            compilationCtx: compilationCtx,
            declIDs: &declIDs
        )

        declIDs.append(contentsOf: synthesizeEnumConstructorPropertyHelperFunctions(
            classDecl: classDecl,
            ownerSymbol: symbol,
            shared: shared,
            compilationCtx: compilationCtx
        ))

        return declIDs
    }

    private func lowerNestedClassConstructors(
        nestedClasses: [DeclID],
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext,
        declIDs: inout [KIRDeclID]
    ) {
        let ast = shared.ast
        let sema = shared.sema
        for declID in nestedClasses {
            guard let decl = ast.arena.decl(declID),
                  let nestedSymbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            switch decl {
            case let .classDecl(nestedClass):
                declIDs.append(contentsOf: synthesizeConstructorReflectionInitializer(
                    classDecl: nestedClass,
                    ownerSymbol: nestedSymbol,
                    shared: shared
                ))
                lowerNestedClassConstructors(
                    nestedClasses: nestedClass.nestedClasses,
                    shared: shared,
                    compilationCtx: compilationCtx,
                    declIDs: &declIDs
                )

                declIDs.append(contentsOf: synthesizeEnumConstructorPropertyHelperFunctions(
                    classDecl: nestedClass,
                    ownerSymbol: nestedSymbol,
                    shared: shared,
                    compilationCtx: compilationCtx
                ))
            default:
                break
            }
        }
    }

    func synthesizeClassDelegationForwardingMethods(
        classSymbol: SymbolID,
        shared: KIRLoweringSharedContext,
        compilationCtx _: CompilationContext?
    ) -> [KIRDeclID] {
        let sema = shared.sema
        let arena = shared.arena
        var declIDs: [KIRDeclID] = []
        let intType = sema.types.intType
        // Enum values are ordinal-backed, so a delegated supertype on an enum
        // class stores its delegate in per-entry side storage read through the
        // $enumConstructorProperty$ helper rather than an object field. An
        // enum with no entries never gets that storage; its (unreachable)
        // forwarders keep the ordinary field path.
        let usesEnumEntryStorage = sema.symbols.symbol(classSymbol)?.kind == .enumClass
            && sema.symbols.children(of: classSymbol).contains { childID in
                sema.symbols.symbol(childID).map {
                    sema.symbols.enumOwnerSymbol(for: $0) == classSymbol
                } ?? false
            }

        for forwardingSymbol in sema.symbols.classDelegationForwardingMethodSymbols(forClass: classSymbol) {
            guard let info = sema.symbols.classDelegationForwardingMethodInfo(for: forwardingSymbol),
                  let signature = sema.symbols.functionSignature(for: forwardingSymbol),
                  let interfaceMethodSym = sema.symbols.symbol(info.interfaceMethodSymbol)
            else {
                continue
            }
            let calleeName = interfaceMethodSym.name
            let dispatchTargets = classDelegationDispatchTargets(
                interfaceSymbol: info.interfaceSymbol,
                interfaceMethodSymbol: info.interfaceMethodSymbol,
                sema: sema,
                interner: shared.interner
            )
            let fallbackMethodSymbol = classDelegationDefaultMethodSymbol(
                interfaceMethodSymbol: info.interfaceMethodSymbol,
                sema: sema
            ) ?? {
                // Runtime collection boxes such as `listOf(...)` carry the
                // interface type ID but are not concrete Kotlin classes in
                // `dispatchTargets`. Abstract collection members that have a
                // runtime ABI link must use that bridge as the delegation
                // fallback instead of reaching `kk_abort_unreachable`.
                guard let linkName = sema.symbols.externalLinkName(for: info.interfaceMethodSymbol),
                      !linkName.isEmpty
                else {
                    return nil
                }
                return info.interfaceMethodSymbol
            }()
            ctx.resetScopeForFunction()
            ctx.beginCallableLoweringScope()
            ctx.setCurrentFunctionSymbol(forwardingSymbol)

            var params: [KIRParameter] = []
            var dispatchReceiverExprID: KIRExprID?
            // A member extension has the class instance and extension value as separate receivers.
            if sema.symbols.memberExtensionOwnerSymbol(for: info.interfaceMethodSymbol) != nil,
               let ownerInfo = sema.symbols.symbol(classSymbol)
            {
                let ownerTypeArgs = signature.typeParameterSymbols
                    .prefix(signature.classTypeParameterCount)
                    .map { TypeArg.invariant(sema.types.make(.typeParam(TypeParamType(
                        symbol: $0, nullability: .nonNull
                    )))) }
                let dispatchReceiverType = sema.types.make(.classType(ClassType(
                    classSymbol: classSymbol, args: ownerTypeArgs, nullability: .nonNull
                )))
                let dispatchReceiverSymbol = SyntheticSymbolScheme.receiverParameterSymbol(for: classSymbol)
                params.append(KIRParameter(symbol: dispatchReceiverSymbol, type: dispatchReceiverType))
                let receiverExpr = arena.appendExpr(.symbolRef(dispatchReceiverSymbol), type: dispatchReceiverType)
                ctx.setLocalValue(receiverExpr, for: dispatchReceiverSymbol)
                ctx.setLocalValue(receiverExpr, for: classSymbol)
                ctx.setLocalDeclaredType(dispatchReceiverType, for: classSymbol)
                ctx.setQualifiedThisReceiver(receiverExpr, for: ownerInfo.name)
                ctx.setCapturedOuterReceiver(receiverExpr, for: classSymbol)
                dispatchReceiverExprID = receiverExpr
            }
            if let receiverType = signature.receiverType {
                let receiverSymbol = callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: forwardingSymbol)
                params.append(KIRParameter(symbol: receiverSymbol, type: receiverType))
                ctx.setImplicitReceiver(
                    symbol: receiverSymbol,
                    exprID: arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
                )
            }
            params.append(contentsOf: zip(signature.valueParameterSymbols, signature.parameterTypes).map { pair in
                KIRParameter(symbol: pair.0, type: pair.1)
            })

            var body: KIRLoweringEmitContext = [.beginBlock]
            if let receiverBinding = ctx.activeImplicitReceiver() {
                body.append(.constValue(result: receiverBinding.exprID, value: .symbolRef(receiverBinding.symbol)))
            }

            let delegateResultID = arena.appendTemporary(type: shared.sema.symbols.propertyType(for: info.fieldSymbol) ?? shared.sema.types.anyType
            )
            let delegateReceiverExprID = dispatchReceiverExprID ?? ctx.activeImplicitReceiverExprID()!
            if usesEnumEntryStorage,
               let fieldName = sema.symbols.symbol(info.fieldSymbol)?.name
            {
                body.append(.call(
                    callee: EnumPropertyHelperNames.placeholder(
                        prefix: EnumPropertyHelperNames.getterPrefix,
                        ownerSymbol: classSymbol,
                        propertyName: fieldName,
                        interner: shared.interner
                    ),
                    arguments: [delegateReceiverExprID],
                    result: delegateResultID,
                    canThrow: false,
                    isSuperCall: false
                ))
            } else {
                let offset = shared.sema.symbols.nominalLayout(for: classSymbol)?.fieldOffsets[info.fieldSymbol] ?? 0
                let offsetExpr = arena.appendExpr(.intLiteral(Int64(offset)), type: shared.sema.types.intType)
                body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(offset))))
                body.append(.call(
                    callee: shared.interner.intern("kk_array_get"),
                    arguments: [delegateReceiverExprID, offsetExpr],
                    result: delegateResultID,
                    canThrow: true,
                    isSuperCall: false
                ))
            }

            var callArgExprs: [KIRExprID] = []
            if sema.symbols.memberExtensionOwnerSymbol(for: info.interfaceMethodSymbol) != nil,
               let receiverBinding = ctx.activeImplicitReceiver()
            {
                callArgExprs.append(arena.appendExpr(
                    .symbolRef(receiverBinding.symbol),
                    type: signature.receiverType ?? sema.types.anyType
                ))
            }
            for (paramSym, paramType) in zip(signature.valueParameterSymbols, signature.parameterTypes) {
                callArgExprs.append(arena.appendExpr(.symbolRef(paramSym), type: paramType))
            }

            let delegateTypeIDExpr = arena.appendTemporary(type: intType
            )
            emitNonThrowingCall(
                callee: shared.interner.intern("kk_object_type_id"),
                arg: delegateResultID,
                result: delegateTypeIDExpr,
                into: &body.instructions
            )

            let branchLabels = dispatchTargets.map { _ in ctx.makeLoopLabel() }
            let fallbackLabel = ctx.makeLoopLabel()
            let endLabel = ctx.makeLoopLabel()
            var resultExprID: KIRExprID?
            if signature.returnType != sema.types.unitType {
                let resultExpr = arena.appendExpr(
                    delegationDefaultValue(for: signature.returnType, sema: sema),
                    type: signature.returnType
                )
                resultExprID = resultExpr
            }

            for (target, label) in zip(dispatchTargets, branchLabels) {
                let typeIDExpr = arena.appendExpr(.intLiteral(target.typeID), type: intType)
                body.append(.constValue(result: typeIDExpr, value: .intLiteral(target.typeID)))
                body.append(.jumpIfEqual(lhs: delegateTypeIDExpr, rhs: typeIDExpr, target: label))
            }
            body.append(.jump(fallbackLabel))

            for (target, label) in zip(dispatchTargets, branchLabels) {
                body.append(.label(label))
                let targetCalleeName: InternedString = if let externalLinkName = sema.symbols.externalLinkName(for: target.methodSymbol),
                                                          !externalLinkName.isEmpty
                {
                    shared.interner.intern(externalLinkName)
                } else {
                    sema.symbols.symbol(target.methodSymbol)?.name ?? calleeName
                }
                body.append(.call(
                    symbol: target.methodSymbol,
                    callee: targetCalleeName,
                    arguments: [delegateResultID] + callArgExprs,
                    result: resultExprID,
                    canThrow: false,
                    isSuperCall: false
                ))
                body.append(.jump(endLabel))
            }

            body.append(.label(fallbackLabel))
            let hasRuntimeBridge = [info.interfaceMethodSymbol, fallbackMethodSymbol].compactMap { $0 }.contains {
                sema.symbols.externalLinkName(for: $0).map { RuntimeABISpec.byName[$0] != nil } == true
            }
            if let methodSlot = sema.symbols.nominalLayout(for: info.interfaceSymbol)?.vtableSlots[info.interfaceMethodSymbol],
               !hasRuntimeBridge
            {
                // An implementation defined by a library consumer is absent
                // from the known targets. Dispatch through its interface table
                // before considering an ordinary interface default body.
                let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                    symbol: info.interfaceSymbol, sema: sema, interner: shared.interner
                )
                body.append(.virtualCall(
                    symbol: info.interfaceMethodSymbol,
                    callee: calleeName,
                    receiver: delegateResultID,
                    arguments: callArgExprs,
                    result: resultExprID,
                    canThrow: false,
                    dispatch: .itableDynamic(interfaceTypeID: interfaceTypeID, methodSlot: methodSlot)
                ))
            } else if let fallbackMethodSymbol {
                let fallbackCalleeName: InternedString = if let externalLinkName = sema.symbols.externalLinkName(for: fallbackMethodSymbol),
                                                            !externalLinkName.isEmpty
                {
                    shared.interner.intern(externalLinkName)
                } else {
                    sema.symbols.symbol(fallbackMethodSymbol)?.name ?? calleeName
                }
                body.append(.call(
                    symbol: fallbackMethodSymbol,
                    callee: fallbackCalleeName,
                    arguments: [delegateResultID] + callArgExprs,
                    result: resultExprID,
                    canThrow: false,
                    isSuperCall: false
                ))
            } else {
                body.append(.call(
                    callee: shared.interner.intern("kk_abort_unreachable"),
                    arguments: [],
                    result: nil,
                    canThrow: false,
                    isSuperCall: false
                ))
            }
            body.append(.jump(endLabel))
            body.append(.label(endLabel))

            if let resultExprID {
                body.append(.returnValue(resultExprID))
            } else {
                body.append(.returnUnit)
            }
            body.append(.endBlock)

            let kirFunc = KIRFunction(
                symbol: forwardingSymbol,
                name: calleeName,
                params: params,
                returnType: signature.returnType,
                body: body,
                isSuspend: signature.isSuspend,
                isInline: false,
                sourceRange: nil
            )
            let funcDeclID = arena.appendDecl(.function(kirFunc))
            declIDs.append(funcDeclID)
        }

        ctx.clearImplicitReceiver()
        return declIDs
    }

    /// Synthesizes getter/setter accessor bodies for delegated interface
    /// properties (Inheritance.swift's `synthesizeForwardingProperty`
    /// registered the Sema-side property symbol; this mirrors
    /// `synthesizeClassDelegationForwardingMethods` for the accessor
    /// functions). Each body reads the delegate out of its field, switches on
    /// the delegate's runtime type the same way a forwarded method call does,
    /// and calls the matching concrete implementer's own getter/setter
    /// accessor — never the interface's null-returning abstract stub.
    func synthesizeClassDelegationForwardingPropertyAccessors(
        classSymbol: SymbolID,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext?
    ) -> [KIRDeclID] {
        let sema = shared.sema
        var declIDs: [KIRDeclID] = []

        for forwardingSymbol in sema.symbols.classDelegationForwardingPropertySymbols(forClass: classSymbol) {
            guard let info = sema.symbols.classDelegationForwardingPropertyInfo(for: forwardingSymbol),
                  let forwardingInfo = sema.symbols.symbol(forwardingSymbol)
            else {
                continue
            }

            declIDs.append(contentsOf: synthesizeDelegationPropertyAccessorBody(
                accessorKind: .getter,
                classSymbol: classSymbol,
                forwardingSymbol: forwardingSymbol,
                info: info,
                shared: shared,
                compilationCtx: compilationCtx
            ))

            if forwardingInfo.flags.contains(.mutable) {
                declIDs.append(contentsOf: synthesizeDelegationPropertyAccessorBody(
                    accessorKind: .setter,
                    classSymbol: classSymbol,
                    forwardingSymbol: forwardingSymbol,
                    info: info,
                    shared: shared,
                    compilationCtx: compilationCtx
                ))
            }
        }

        return declIDs
    }

    private func synthesizeDelegationPropertyAccessorBody(
        accessorKind: PropertyAccessorKind,
        classSymbol: SymbolID,
        forwardingSymbol: SymbolID,
        info: (interfaceSymbol: SymbolID, interfacePropertySymbol: SymbolID, fieldSymbol: SymbolID),
        shared: KIRLoweringSharedContext,
        compilationCtx _: CompilationContext?
    ) -> [KIRDeclID] {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let intType = sema.types.intType

        guard let ownerSym = sema.symbols.symbol(classSymbol) else { return [] }
        let propType = sema.symbols.propertyType(for: forwardingSymbol) ?? sema.types.anyType
        let ownerType = sema.types.make(.classType(ClassType(
            classSymbol: ownerSym.id, args: [], nullability: .nonNull
        )))
        let accessorFunctionSymbol: SymbolID = switch accessorKind {
        case .getter:
            SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: forwardingSymbol)
        case .setter:
            SyntheticSymbolScheme.propertySetterAccessorSymbol(for: forwardingSymbol)
        }
        let accessorName = interner.intern(accessorKind == .getter ? "get" : "set")
        let returnType = accessorKind == .getter ? propType : sema.types.unitType

        ctx.resetScopeForFunction()
        ctx.beginCallableLoweringScope()
        ctx.setCurrentFunctionSymbol(accessorFunctionSymbol)

        let receiverSymbol = callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: forwardingSymbol)
        var params: [KIRParameter] = [KIRParameter(symbol: receiverSymbol, type: ownerType)]
        ctx.setImplicitReceiver(
            symbol: receiverSymbol,
            exprID: arena.appendExpr(.symbolRef(receiverSymbol), type: ownerType)
        )

        var valueExprID: KIRExprID?
        var body: KIRLoweringEmitContext = [.beginBlock]
        if let receiverBinding = ctx.activeImplicitReceiver() {
            body.append(.constValue(result: receiverBinding.exprID, value: .symbolRef(receiverBinding.symbol)))
        }
        if accessorKind == .setter {
            let valueParamSymbol = SyntheticSymbolScheme.setterValueParameterSymbol(for: forwardingSymbol)
            params.append(KIRParameter(symbol: valueParamSymbol, type: propType))
            let ve = arena.appendExpr(.symbolRef(valueParamSymbol), type: propType)
            body.append(.constValue(result: ve, value: .symbolRef(valueParamSymbol)))
            valueExprID = ve
        }

        // Enum values are ordinal-backed: their delegate handles live in
        // per-entry side storage read through the $enumConstructorProperty$
        // helper (see synthesizeClassDelegationForwardingMethods).
        let usesEnumEntryStorage = ownerSym.kind == .enumClass
            && sema.symbols.children(of: classSymbol).contains { childID in
                sema.symbols.symbol(childID).map {
                    sema.symbols.enumOwnerSymbol(for: $0) == classSymbol
                } ?? false
            }

        let delegateResultID = arena.appendTemporary(
            type: sema.symbols.propertyType(for: info.fieldSymbol) ?? sema.types.anyType
        )
        if usesEnumEntryStorage,
           let fieldName = sema.symbols.symbol(info.fieldSymbol)?.name
        {
            body.append(.call(
                callee: EnumPropertyHelperNames.placeholder(
                    prefix: EnumPropertyHelperNames.getterPrefix,
                    ownerSymbol: classSymbol,
                    propertyName: fieldName,
                    interner: interner
                ),
                arguments: [ctx.activeImplicitReceiverExprID()!],
                result: delegateResultID,
                canThrow: false,
                isSuperCall: false
            ))
        } else {
            let offset = sema.symbols.nominalLayout(for: classSymbol)?.fieldOffsets[info.fieldSymbol] ?? 0
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(offset)), type: intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(offset))))
            body.append(.call(
                callee: interner.intern("kk_array_get"),
                arguments: [ctx.activeImplicitReceiverExprID()!, offsetExpr],
                result: delegateResultID,
                canThrow: true,
                isSuperCall: false
            ))
        }

        let delegateTypeIDExpr = arena.appendTemporary(type: intType)
        emitNonThrowingCall(
            callee: interner.intern("kk_object_type_id"),
            arg: delegateResultID,
            result: delegateTypeIDExpr,
            into: &body.instructions
        )

        let dispatchTargets = classDelegationPropertyAccessorDispatchTargets(
            interfaceSymbol: info.interfaceSymbol,
            interfacePropertySymbol: info.interfacePropertySymbol,
            accessorKind: accessorKind,
            sema: sema,
            interner: interner
        )
        let fallbackAccessorSymbol = classDelegationDefaultPropertyAccessorSymbol(
            interfacePropertySymbol: info.interfacePropertySymbol,
            accessorKind: accessorKind,
            sema: sema
        )

        let branchLabels = dispatchTargets.map { _ in ctx.makeLoopLabel() }
        let fallbackLabel = ctx.makeLoopLabel()
        let endLabel = ctx.makeLoopLabel()

        var resultExprID: KIRExprID?
        if returnType != sema.types.unitType {
            resultExprID = arena.appendExpr(
                delegationDefaultValue(for: returnType, sema: sema),
                type: returnType
            )
        }

        for (target, label) in zip(dispatchTargets, branchLabels) {
            let typeIDExpr = arena.appendExpr(.intLiteral(target.typeID), type: intType)
            body.append(.constValue(result: typeIDExpr, value: .intLiteral(target.typeID)))
            body.append(.jumpIfEqual(lhs: delegateTypeIDExpr, rhs: typeIDExpr, target: label))
        }
        body.append(.jump(fallbackLabel))

        let callArgs: [KIRExprID] = valueExprID.map { [delegateResultID, $0] } ?? [delegateResultID]
        for (target, label) in zip(dispatchTargets, branchLabels) {
            body.append(.label(label))
            let targetCallee = sema.symbols.externalLinkName(for: target.accessorSymbol)
                .map { interner.intern($0) } ?? accessorName
            body.append(.call(
                symbol: target.accessorSymbol,
                callee: targetCallee,
                arguments: callArgs,
                result: resultExprID,
                canThrow: false,
                isSuperCall: false
            ))
            body.append(.jump(endLabel))
        }

        body.append(.label(fallbackLabel))
        if accessorKind == .getter,
           let externalLinkName = sema.symbols.externalLinkName(for: info.interfacePropertySymbol),
           !externalLinkName.isEmpty
        {
            // BUG-240: runtime-bridged interface properties (e.g. Map's
            // keys/values/entries → kk_map_*) have no concrete accessor to
            // dispatch to; call the runtime bridge on the delegate directly.
            body.append(.call(
                callee: interner.intern(externalLinkName),
                arguments: callArgs,
                result: resultExprID,
                canThrow: false,
                isSuperCall: false
            ))
        } else if let fallbackAccessorSymbol,
                  let link = sema.symbols.externalLinkName(for: fallbackAccessorSymbol),
                  RuntimeABISpec.byName[link] != nil
        {
            // Imported runtime bridges may live on the accessor rather than
            // the property. Keep them ahead of the ordinary default getter.
            body.append(.call(
                symbol: fallbackAccessorSymbol,
                callee: accessorName,
                arguments: callArgs,
                result: resultExprID,
                canThrow: false,
                isSuperCall: false
            ))
        } else if accessorKind == .getter,
                  let methodSlot = kirInterfacePropertyGetterSlot(
                      interfaceProperty: info.interfacePropertySymbol,
                      interfaceSymbol: info.interfaceSymbol,
                      sema: sema,
                      interner: interner
                  )
        {
            // A delegate whose runtime type is not among the compile-time
            // known subtypes (imported or externally-provided implementations)
            // still reaches its getter through the itable slot. This must take
            // precedence over calling an interface default getter directly:
            // the downstream type may override that default.
            let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                symbol: info.interfaceSymbol,
                sema: sema,
                interner: interner
            )
            body.append(.virtualCall(
                symbol: SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: info.interfacePropertySymbol),
                callee: accessorName,
                receiver: delegateResultID,
                arguments: [],
                result: resultExprID,
                canThrow: false,
                dispatch: .itableDynamic(
                    interfaceTypeID: interfaceTypeID,
                    methodSlot: methodSlot
                )
            ))
        } else if let fallbackAccessorSymbol {
            body.append(.call(
                symbol: fallbackAccessorSymbol,
                callee: accessorName,
                arguments: callArgs,
                result: resultExprID,
                canThrow: false,
                isSuperCall: false
            ))
        } else {
            body.append(.call(callee: interner.intern("kk_abort_unreachable"), arguments: [], result: nil, canThrow: false, isSuperCall: false))
        }
        body.append(.jump(endLabel))
        body.append(.label(endLabel))

        if let resultExprID {
            body.append(.returnValue(resultExprID))
        } else {
            body.append(.returnUnit)
        }
        body.append(.endBlock)

        let kirFunc = KIRFunction(
            symbol: accessorFunctionSymbol,
            name: accessorName,
            params: params,
            returnType: returnType,
            body: body,
            isSuspend: false,
            isInline: false,
            sourceRange: nil
        )
        let funcDeclID = arena.appendDecl(.function(kirFunc))
        ctx.clearImplicitReceiver()
        return [funcDeclID]
    }

    private struct ClassDelegationPropertyAccessorDispatchTarget {
        let typeID: Int64
        let accessorSymbol: SymbolID
    }

    private func classDelegationPropertyAccessorDispatchTargets(
        interfaceSymbol: SymbolID,
        interfacePropertySymbol: SymbolID,
        accessorKind: PropertyAccessorKind,
        sema: SemaModule,
        interner: StringInterner
    ) -> [ClassDelegationPropertyAccessorDispatchTarget] {
        var targets: [ClassDelegationPropertyAccessorDispatchTarget] = []
        var queue = sema.symbols.directSubtypes(of: interfaceSymbol)
        var visited: Set<SymbolID> = []

        while !queue.isEmpty {
            let candidate = queue.removeFirst()
            guard visited.insert(candidate).inserted,
                  let candidateSymbol = sema.symbols.symbol(candidate)
            else {
                continue
            }
            queue.append(contentsOf: sema.symbols.directSubtypes(of: candidate))

            guard candidateSymbol.kind == .class || candidateSymbol.kind == .object || candidateSymbol.kind == .enumClass,
                  !candidateSymbol.flags.contains(.abstractType),
                  let accessorSymbol = resolveClassDelegationDispatchPropertyAccessor(
                      interfacePropertySymbol: interfacePropertySymbol,
                      accessorKind: accessorKind,
                      concreteTypeSymbol: candidate,
                      sema: sema
                  )
            else {
                continue
            }

            targets.append(ClassDelegationPropertyAccessorDispatchTarget(
                typeID: RuntimeTypeCheckToken.stableNominalTypeID(
                    symbol: candidate,
                    sema: sema,
                    interner: interner
                ),
                accessorSymbol: accessorSymbol
            ))
        }

        return targets.sorted { lhs, rhs in
            lhs.typeID < rhs.typeID
        }
    }

    private func resolveClassDelegationDispatchPropertyAccessor(
        interfacePropertySymbol: SymbolID,
        accessorKind: PropertyAccessorKind,
        concreteTypeSymbol: SymbolID,
        sema: SemaModule
    ) -> SymbolID? {
        guard let interfaceProperty = sema.symbols.symbol(interfacePropertySymbol) else {
            return nil
        }

        var fallbackMatch: SymbolID?
        var queue: [SymbolID] = [concreteTypeSymbol]
        var visited: Set<SymbolID> = []
        while !queue.isEmpty {
            let owner = queue.removeFirst()
            guard visited.insert(owner).inserted,
                  let ownerSymbol = sema.symbols.symbol(owner)
            else {
                continue
            }

            let fqName = ownerSymbol.fqName + [interfaceProperty.name]
            for candidate in sema.symbols.lookupAll(fqName: fqName) {
                guard sema.symbols.parentSymbolIfKnown(for: candidate) == owner,
                      let propSymbol = sema.symbols.symbol(candidate),
                      propSymbol.kind == .property,
                      isClassDelegationDispatchMember(propSymbol, sema: sema)
                else {
                    continue
                }

                if propSymbol.flags.contains(.overrideMember) {
                    return classDelegationPropertyAccessorSymbol(for: candidate, kind: accessorKind, sema: sema)
                }
                if fallbackMatch == nil {
                    fallbackMatch = candidate
                }
            }

            queue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
        }

        if let fallbackMatch {
            return classDelegationPropertyAccessorSymbol(for: fallbackMatch, kind: accessorKind, sema: sema)
        }
        return classDelegationDefaultPropertyAccessorSymbol(
            interfacePropertySymbol: interfacePropertySymbol, accessorKind: accessorKind, sema: sema
        )
    }

    private func classDelegationPropertyAccessorSymbol(
        for propertySymbol: SymbolID,
        kind: PropertyAccessorKind,
        sema: SemaModule
    ) -> SymbolID {
        // Source-declared runtime properties have no emitted getter body.
        // Preserve their ABI link when selecting a concrete delegation target,
        // just as imported accessors and the interface fallback already do.
        if kind == .getter,
           let link = sema.symbols.externalLinkName(for: propertySymbol),
           RuntimeABISpec.byName[link] != nil
        {
            return propertySymbol
        }
        return switch kind {
        case .getter:
            sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
                ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
        case .setter:
            sema.symbols.extensionPropertySetterAccessor(for: propertySymbol)
                ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySymbol)
        }
    }

    private func classDelegationDefaultPropertyAccessorSymbol(
        interfacePropertySymbol: SymbolID,
        accessorKind: PropertyAccessorKind,
        sema: SemaModule
    ) -> SymbolID? {
        let accessorSymbol = classDelegationPropertyAccessorSymbol(
            for: interfacePropertySymbol, kind: accessorKind, sema: sema
        )
        // Imported runtime-backed properties keep the bridge on their accessor,
        // even when the interface property itself is abstract.
        if let link = sema.symbols.externalLinkName(for: accessorSymbol),
           RuntimeABISpec.byName[link] != nil {
            return accessorSymbol
        }
        guard let interfaceProperty = sema.symbols.symbol(interfacePropertySymbol),
              !interfaceProperty.flags.contains(.abstractType),
              // A runtime-bridged property's synthetic accessor has no
              // emitted body — resolve it through the bridge instead.
              (sema.symbols.externalLinkName(for: interfacePropertySymbol) ?? "").isEmpty
        else {
            return nil
        }
        return accessorSymbol
    }

    private struct ClassDelegationDispatchTarget {
        let typeID: Int64
        let methodSymbol: SymbolID
    }

    private func classDelegationDispatchTargets(
        interfaceSymbol: SymbolID,
        interfaceMethodSymbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [ClassDelegationDispatchTarget] {
        var targets: [ClassDelegationDispatchTarget] = []
        var queue = sema.symbols.directSubtypes(of: interfaceSymbol)
        var visited: Set<SymbolID> = []

        while !queue.isEmpty {
            let candidate = queue.removeFirst()
            guard visited.insert(candidate).inserted,
                  let candidateSymbol = sema.symbols.symbol(candidate)
            else {
                continue
            }
            queue.append(contentsOf: sema.symbols.directSubtypes(of: candidate))

            guard candidateSymbol.kind == .class || candidateSymbol.kind == .object || candidateSymbol.kind == .enumClass,
                  !candidateSymbol.flags.contains(.abstractType),
                  let methodSymbol = resolveClassDelegationDispatchMethod(
                      interfaceMethodSymbol: interfaceMethodSymbol,
                      concreteTypeSymbol: candidate,
                      sema: sema
                  )
            else {
                continue
            }

            targets.append(ClassDelegationDispatchTarget(
                typeID: RuntimeTypeCheckToken.stableNominalTypeID(
                    symbol: candidate,
                    sema: sema,
                    interner: interner
                ),
                methodSymbol: methodSymbol
            ))
        }

        return targets.sorted { lhs, rhs in
            lhs.typeID < rhs.typeID
        }
    }

    private func resolveClassDelegationDispatchMethod(
        interfaceMethodSymbol: SymbolID,
        concreteTypeSymbol: SymbolID,
        sema: SemaModule
    ) -> SymbolID? {
        guard let interfaceMethod = sema.symbols.symbol(interfaceMethodSymbol),
              let interfaceSignature = sema.symbols.functionSignature(for: interfaceMethodSymbol)
        else {
            return nil
        }

        var fallbackMatch: SymbolID?
        var queue: [SymbolID] = [concreteTypeSymbol]
        var visited: Set<SymbolID> = []
        while !queue.isEmpty {
            let owner = queue.removeFirst()
            guard visited.insert(owner).inserted,
                  let ownerSymbol = sema.symbols.symbol(owner)
            else {
                continue
            }

            let fqName = ownerSymbol.fqName + [interfaceMethod.name]
            for candidate in sema.symbols.lookupAll(fqName: fqName) {
                guard sema.symbols.parentSymbolIfKnown(for: candidate) == owner,
                      let methodSymbol = sema.symbols.symbol(candidate),
                      isClassDelegationDispatchMember(methodSymbol, sema: sema),
                      !methodSymbol.flags.contains(.abstractType),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.receiverType != nil,
                      signature.isSuspend == interfaceSignature.isSuspend,
                      signature.typeParameterSymbols.count - signature.classTypeParameterCount
                          == interfaceSignature.typeParameterSymbols.count - interfaceSignature.classTypeParameterCount
                else {
                    continue
                }
                guard kirMethodSignatureMatches(
                    source: interfaceSignature, target: signature,
                    sourceOwner: sema.symbols.parentSymbol(for: interfaceMethodSymbol),
                    targetOwner: owner, instanceOwner: concreteTypeSymbol,
                    sourceIsMemberExtension: sema.symbols.memberExtensionOwnerSymbol(for: interfaceMethodSymbol) != nil,
                    targetIsMemberExtension: sema.symbols.memberExtensionOwnerSymbol(for: candidate) != nil,
                    types: sema.types
                ) else {
                    continue
                }

                // Inherited class implementations take precedence over
                // interface defaults, even when declared without `override`.
                if ownerSymbol.kind != .interface || methodSymbol.flags.contains(.overrideMember) {
                    return candidate
                }
                if fallbackMatch == nil {
                    fallbackMatch = candidate
                }
            }

            let supertypes = sema.symbols.directSupertypes(for: owner)
            queue.insert(contentsOf: supertypes.filter { sema.symbols.symbol($0)?.kind != .interface }, at: 0)
            queue.append(contentsOf: supertypes.filter { sema.symbols.symbol($0)?.kind == .interface })
        }

        if let fallbackMatch {
            return fallbackMatch
        }
        return classDelegationDefaultMethodSymbol(interfaceMethodSymbol: interfaceMethodSymbol, sema: sema)
    }

    private func isClassDelegationDispatchMember(_ member: SemanticSymbol, sema: SemaModule) -> Bool {
        // Local source members and real delegation forwarders are executable
        // implementations even though both carry the synthetic flag.
        !member.flags.contains(.synthetic)
            || sema.bindings.declSymbols.values.contains(member.id)
            || sema.symbols.classDelegationForwardingMethodInfo(for: member.id) != nil
            || sema.symbols.classDelegationForwardingPropertyInfo(for: member.id) != nil
    }

    private func classDelegationDefaultMethodSymbol(
        interfaceMethodSymbol: SymbolID,
        sema: SemaModule
    ) -> SymbolID? {
        guard let interfaceMethod = sema.symbols.symbol(interfaceMethodSymbol),
              !interfaceMethod.flags.contains(.abstractType)
        else {
            return nil
        }
        return interfaceMethodSymbol
    }

    func delegationDefaultValue(for type: TypeID, sema: SemaModule) -> KIRExprKind {
        switch sema.types.kind(of: type) {
        case .unit:
            .unit
        case .primitive(.boolean, _):
            .boolLiteral(false)
        case .primitive(.float, _):
            .floatLiteral(0)
        case .primitive(.double, _):
            .doubleLiteral(0)
        case .primitive, .nothing:
            .intLiteral(0)
        case .nullableUnit, .platformUnit, .stringStruct, .classType, .functionType, .typeParam, .any, .intersection, .kClassType:
            .null
        case .error:
            .intLiteral(0)
        }
    }

    func emitDelegationCall(
        delegation: ConstructorDelegationCall,
        ctorFQName: [InternedString],
        ownerSymbol: SymbolID,
        ctorSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let delegationTarget: [InternedString]
        switch delegation.kind {
        case .this:
            delegationTarget = ctorFQName
        case .super_:
            let supertypes = sema.symbols.directSupertypes(for: ownerSymbol)
            let classSupertypes = supertypes.filter {
                let kind = sema.symbols.symbol($0)?.kind
                return kind == .class || kind == .enumClass
            }
            if let superclass = classSupertypes.first {
                let superFQ = sema.symbols.symbol(superclass)?.fqName ?? []
                delegationTarget = superFQ + [shared.interner.intern("<init>")]
            } else {
                delegationTarget = []
            }
        }
        guard !delegationTarget.isEmpty else { return }
        var loweredArgs: [KIRExprID] = []
        if case .super_ = delegation.kind,
           let receiver = ctx.activeImplicitReceiverExprID()
        {
            loweredArgs = lowerSuperConstructorArguments(
                delegation.args,
                ctorSymbol: ctorSymbol,
                ownerSymbol: ownerSymbol,
                receiver: receiver,
                shared: shared,
                body: &body
            )
        } else {
            for arg in delegation.args {
                loweredArgs.append(lowerExpr(arg.expr, shared: shared, emit: &body))
            }
        }
        let delegationResultID = arena.appendTemporary(type: sema.types.unitType
        )
        // A class can have several constructors sharing the same `<init>` FQ
        // name, so a plain FQ-name lookup can't tell which overload the
        // delegation call means, and can even resolve back to the
        // constructor currently being lowered (infinite self-recursion).
        // Prefer the overload Sema already picked; only fall back to the
        // naive lookup (still excluding self) if that binding is missing.
        let resolvedSymbol = sema.bindings.constructorDelegationTarget(for: ctorSymbol)
            ?? sema.symbols.lookupAll(fqName: delegationTarget).first(where: { $0 != ctorSymbol })
        if let resolvedSymbol,
           sema.symbols.symbol(resolvedSymbol)?.flags.contains(.synthetic) == true,
           sema.symbols.parentSymbol(for: resolvedSymbol) == sema.types.anyClassSymbol
        {
            // Any's compiler-provided constructor is allocation-only.
            return
        }
        if let resolvedSymbol,
           let receiver = ctx.activeImplicitReceiverExprID(),
           let superclassSymbol = sema.symbols.parentSymbol(for: resolvedSymbol),
           let throwableSymbol = sema.symbols.lookup(fqName: [
               shared.interner.intern("kotlin"), shared.interner.intern("Throwable"),
           ]),
           sema.types.isNominalSubtypeSymbol(superclassSymbol, of: throwableSymbol),
           isRuntimeThrowableSuperConstructor(resolvedSymbol, sema: sema)
        {
            // Runtime-backed Throwable factories return a separate box for
            // both `this(...)` and `super(...)`; copy its state onto `this`.
            emitRuntimeThrowableSuperInitialization(
                superCtorSymbol: resolvedSymbol,
                superclassSymbol: superclassSymbol,
                receiver: receiver,
                loweredArgs: loweredArgs,
                spreadFlags: delegation.args.map(\.isSpread),
                argumentLabels: delegation.args.map(\.label),
                callBinding: sema.bindings.constructorDelegationCallBinding(for: ctorSymbol),
                shared: shared,
                body: &body
            )
            return
        }
        emitDelegatedConstructorCall(
            target: resolvedSymbol,
            receiver: ctx.activeImplicitReceiverExprID(),
            loweredArgs: loweredArgs,
            spreadFlags: delegation.args.map(\.isSpread),
            argumentLabels: delegation.args.map(\.label),
            callBinding: sema.bindings.constructorDelegationCallBinding(for: ctorSymbol),
            sourceArgExprs: delegation.args.map(\.expr),
            result: delegationResultID,
            shared: shared,
            body: &body
        )
    }

    func emitDelegatedConstructorCall(
        target: SymbolID?,
        receiver: KIRExprID?,
        loweredArgs: [KIRExprID],
        spreadFlags: [Bool],
        argumentLabels: [InternedString?] = [],
        callBinding: CallBinding?,
        sourceArgExprs: [ExprID],
        result: KIRExprID,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let sema = shared.sema
        let arena = shared.arena
        var argIDs: [KIRExprID] = []
        if let receiver {
            argIDs.append(receiver)
        }
        // KUU-2955: delegating to an inner-class `<init>` (`class FooC :
        // A.AB` inside an `A` member/extension) must populate the inherited
        // `$outer` slot with the enclosing `A` instance before the super
        // constructor runs — inherited member bodies read through it. The
        // object under construction may itself be a non-inner local class,
        // so the instance is resolved from its own `$outer` chain or, as a
        // fallback, from a captured receiver field.
        if let receiver,
           let target,
           let superclassSymbol = sema.symbols.parentSymbol(for: target),
           sema.symbols.symbol(superclassSymbol)?.flags.contains(.innerClass) == true,
           let declaredOuterSymbol = sema.symbols.parentSymbol(for: superclassSymbol),
           let outerFieldSymbol = sema.symbols.outerInstanceFieldSymbol(for: superclassSymbol),
           let constructedOwner = ctx.currentFunctionSymbol.flatMap({ sema.symbols.parentSymbol(for: $0) }),
           let outerOffset = sema.symbols.nominalLayout(for: constructedOwner)?.fieldOffsets[outerFieldSymbol],
           let outerValue = innerSuperOuterInstance(
               declaredOuterSymbol: declaredOuterSymbol,
               ownerSymbol: constructedOwner,
               receiver: receiver,
               sema: sema,
               arena: arena,
               interner: shared.interner,
               body: &body
           )
        {
            let offsetExpr = arena.appendExpr(.intLiteral(Int64(outerOffset)), type: sema.types.intType)
            body.append(.constValue(result: offsetExpr, value: .intLiteral(Int64(outerOffset))))
            let storeResult = arena.appendTemporary(type: sema.types.anyType)
            body.append(.call(
                callee: shared.interner.intern("kk_array_set"),
                arguments: [receiver, offsetExpr, outerValue],
                result: storeResult,
                canThrow: true
            ))
        }
        var defaultMaskWords: [Int64] = [0]
        if let target, let callBinding, callBinding.chosenCallee == target {
            let normalized = callSupportLowerer.normalizedCallArguments(
                providedArguments: loweredArgs,
                callBinding: callBinding,
                chosenCallee: target,
                spreadFlags: spreadFlags,
                argumentLabels: argumentLabels,
                shared: shared,
                emit: &body
            )
            argIDs.append(contentsOf: normalized.arguments)
            defaultMaskWords = normalized.defaultMaskWords
        } else {
            argIDs.append(contentsOf: loweredArgs)
        }
        callLowerer.materializeSourceBackedFunctionValueArguments(
            chosenCallee: target,
            sourceArgExprs: sourceArgExprs,
            sema: sema,
            arena: arena,
            interner: shared.interner,
            instructions: &body.instructions,
            arguments: &argIDs,
            valueArgOffsetOverride: receiver == nil ? 0 : 1,
            parameterMapping: callBinding?.chosenCallee == target ? callBinding?.parameterMapping : nil
        )
        if defaultMaskWords.contains(where: { $0 != 0 }),
           let target,
           sema.symbols.externalLinkName(for: target)?.isEmpty ?? true,
           let ownerName = sema.symbols.parentSymbol(for: target).flatMap({ sema.symbols.symbol($0)?.name })
        {
            callLowerer.appendDefaultMaskArguments(
                defaultMaskWords,
                sema: sema,
                arena: arena,
                instructions: &body.instructions,
                arguments: &argIDs
            )
            body.append(.call(
                symbol: callSupportLowerer.defaultStubSymbol(for: target),
                callee: shared.interner.intern(shared.interner.resolve(ownerName) + "$default"),
                arguments: argIDs,
                result: result,
                canThrow: false
            ))
            return
        }
        // Runtime-backed collection copy constructors (`ArrayList(elements)`,
        // `LinkedHashSet(elements)`, `TreeSet(elements)` /
        // `TreeSet(sortedSet)`, `HashMap(original)` /
        // `LinkedHashMap(original)`) are rewritten by
        // CollectionLiteralLoweringPass into factories that allocate and
        // return a fresh box. As a constructor delegation target that result
        // is discarded, so the subclass receiver keeps the empty box it was
        // allocated as and silently drops the copied elements. Populate
        // `receiver` in place with the same bridge the member `addAll` /
        // `putAll` calls lower to instead.
        if argIDs.count == 2,
           let target,
           let populateCallee = collectionCopyConstructorPopulateCallee(
               for: target,
               sema: sema,
               interner: shared.interner
           )
        {
            body.append(.call(callee: populateCallee, arguments: argIDs, result: result, canThrow: false))
            return
        }
        body.append(.call(symbol: target, callee: shared.interner.intern("<init>"), arguments: argIDs, result: result, canThrow: false))
    }

    /// Resolves the enclosing `declaredOuterSymbol` instance for an
    /// inner-class super-constructor delegation (KUU-2955). `receiver` is
    /// the object under construction: it may itself reach the outer
    /// instance through its own `$outer` chain (`inner class D :
    /// InnerBase`), or — when it is a non-inner local class (`class FooC :
    /// A.AB` inside an `A` member/extension) — the instance arrives through
    /// one of its captured receiver fields.
    private func innerSuperOuterInstance(
        declaredOuterSymbol: SymbolID,
        ownerSymbol: SymbolID,
        receiver: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        body: inout KIRLoweringEmitContext
    ) -> KIRExprID? {
        if let outerValue = resolveOuterChainValue(
            from: receiver,
            to: declaredOuterSymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body.instructions
        ) {
            return outerValue
        }
        let outerOwnerArgs = sema.types.nominalTypeParameterSymbols(for: declaredOuterSymbol).map {
            TypeArg.invariant(sema.types.make(.typeParam(TypeParamType(symbol: $0))))
        }
        let outerType = sema.types.make(.classType(ClassType(
            classSymbol: declaredOuterSymbol, args: outerOwnerArgs, nullability: .nonNull
        )))
        for capturedSymbol in sema.bindings.objectLiteralCaptureSymbols(for: ownerSymbol) {
            guard let capturedValue = ctx.localValue(for: capturedSymbol) else {
                continue
            }
            let capturedType = sema.bindings.capturedLocalType(for: capturedSymbol)
                ?? arena.exprType(capturedValue)
            guard let capturedType,
                  sema.types.isSubtype(sema.types.makeNonNullable(capturedType), outerType)
            else {
                continue
            }
            return capturedValue
        }
        return nil
    }

    private func collectionCopyConstructorPopulateCallee(
        for target: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> InternedString? {
        guard sema.symbols.symbol(target)?.kind == .constructor,
              let parent = sema.symbols.parentSymbol(for: target),
              let parentFQName = sema.symbols.symbol(parent)?.fqName.map(interner.resolve),
              let signature = sema.symbols.functionSignature(for: target),
              signature.parameterTypes.count == 1,
              let parameterFQName = resolveClassTypeSymbol(signature.parameterTypes[0], sema: sema)?
                  .symbol.fqName.map(interner.resolve)
        else { return nil }
        switch (parentFQName, parameterFQName) {
        case (["kotlin", "collections", "ArrayList"], ["kotlin", "collections", "Collection"]):
            return interner.intern("__kk_mutable_list_addAll")
        case (["kotlin", "collections", "LinkedHashSet"], ["kotlin", "collections", "Collection"]),
             (["java", "util", "TreeSet"], ["kotlin", "collections", "Collection"]),
             (["java", "util", "TreeSet"], ["kotlin", "collections", "SortedSet"]):
            return interner.intern("__kk_mutable_set_addAll")
        case (["kotlin", "collections", "HashMap"], ["kotlin", "collections", "Map"]),
             (["kotlin", "collections", "LinkedHashMap"], ["kotlin", "collections", "Map"]):
            return interner.intern("__kk_mutable_map_putAll")
        default:
            return nil
        }
    }
}
