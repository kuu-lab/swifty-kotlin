
final class MemberLowerer {
    unowned let driver: KIRLoweringDriver

    init(driver: KIRLoweringDriver) {
        self.driver = driver
    }

    private func synthesizeNestedCompanionInitializers(
        _ declIDs: [DeclID],
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        var initializers: [KIRDeclID] = []
        for declID in declIDs {
            guard let decl = shared.ast.arena.decl(declID),
                  let symbol = shared.sema.bindings.declSymbols[declID]
            else { continue }
            let companionDeclID: DeclID?
            var nestedDecls: [DeclID]
            switch decl {
            case let .classDecl(nested):
                companionDeclID = nested.companionObject
                nestedDecls = nested.nestedClasses + nested.nestedObjects
            case let .interfaceDecl(nested):
                companionDeclID = nested.companionObject
                nestedDecls = nested.nestedClasses + nested.nestedObjects
            case let .objectDecl(nested):
                companionDeclID = nil
                nestedDecls = nested.nestedClasses + nested.nestedObjects
            default: continue
            }
            if let companionDeclID { nestedDecls.append(companionDeclID) }
            initializers.append(contentsOf: synthesizeNestedCompanionInitializers(nestedDecls, shared: shared))
            guard let companionDeclID,
                  let companionSymbol = shared.sema.bindings.declSymbols[companionDeclID],
                  driver.ctx.objectLazyInit(for: companionSymbol) == nil
            else { continue }
            initializers.append(contentsOf: driver.synthesizeCompanionInitializerIfNeeded(
                companionDeclID: companionDeclID, ownerSymbol: symbol, shared: shared
            ))
        }
        return initializers
    }

    private func synthesizeNestedObjectInitializers(
        _ declIDs: [DeclID],
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        var initializers: [KIRDeclID] = []
        for declID in declIDs {
            guard let decl = shared.ast.arena.decl(declID) else { continue }

            var nestedDecls: [DeclID]
            switch decl {
            case let .classDecl(nested):
                nestedDecls = nested.nestedClasses + nested.nestedObjects
                if let companionDeclID = nested.companionObject {
                    nestedDecls.append(companionDeclID)
                }
            case let .interfaceDecl(nested):
                nestedDecls = nested.nestedClasses + nested.nestedObjects
                if let companionDeclID = nested.companionObject {
                    nestedDecls.append(companionDeclID)
                }
            case let .objectDecl(nested):
                nestedDecls = nested.nestedClasses + nested.nestedObjects
            default:
                continue
            }
            initializers.append(contentsOf: synthesizeNestedObjectInitializers(
                nestedDecls, shared: shared
            ))

            guard case let .objectDecl(objectDecl) = decl,
                  !objectDecl.modifiers.contains(.companion),
                  let objectSymbol = shared.sema.bindings.declSymbols[declID],
                  !driver.ctx.hasObjectInitializer(for: objectSymbol)
            else {
                continue
            }

            let objectType = shared.sema.types.make(.classType(ClassType(
                classSymbol: objectSymbol, args: [], nullability: .nonNull
            )))
            initializers.append(shared.arena.appendDecl(.global(KIRGlobal(
                symbol: objectSymbol, type: objectType
            ))))
            initializers.append(contentsOf: driver.synthesizeObjectInitializer(
                objectDecl,
                objectSymbol: objectSymbol,
                shared: shared
            ))
        }
        return initializers
    }

    func lowerMemberDecls(
        memberFunctions: [DeclID],
        memberProperties: [DeclID],
        nestedClasses: [DeclID],
        nestedObjects: [DeclID],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        compilationCtx: CompilationContext? = nil,
        isInterfaceContext: Bool = false
    ) -> (directMembers: [KIRDeclID], allDecls: [KIRDeclID]) {
        var directMembers: [KIRDeclID] = []
        var allDecls: [KIRDeclID] = []

        let shared = KIRLoweringSharedContext(
            ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers
        )
        let nestedDecls = nestedClasses + nestedObjects
        allDecls.append(contentsOf: synthesizeNestedCompanionInitializers(
            nestedDecls, shared: shared
        ))
        allDecls.append(contentsOf: synthesizeNestedObjectInitializers(
            nestedDecls, shared: shared
        ))

        for declID in memberFunctions {
            lowerSingleMemberFunction(
                declID: declID, ast: ast, sema: sema, arena: arena,
                interner: interner, propertyConstantInitializers: propertyConstantInitializers,
                directMembers: &directMembers, allDecls: &allDecls
            )
        }

        for declID in memberProperties {
            guard let decl = ast.arena.decl(declID),
                  case let .propertyDecl(propertyDecl) = decl,
                  let symbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            let propType = sema.symbols.propertyType(for: symbol) ?? sema.types.anyType

            // Delegate properties (`val x: T by expr`) also have no backing storage
            // for the property symbol itself — all access is routed through the
            // delegate storage symbol (e.g. `$delegate_x`) which gets its own
            // KIRGlobal below.  Emitting a second KIRGlobal for the property symbol
            // with type `propType` (e.g. `stringStruct`) would cause the code
            // generator to write a wide stringStruct aggregate into an i64-sized
            // slot, corrupting adjacent globals (including the delegate storage).
            let hasExplicitBackingField = propertyDecl.explicitBackingField != nil
            let isAbstractProperty = sema.symbols.symbol(symbol)?.flags.contains(.abstractType) == true
            let isGetterOnlyComputed = propertyDecl.getter != nil
                && propertyDecl.setter == nil
                && propertyDecl.initializer == nil
                && propertyDecl.delegateExpression == nil
                && !hasExplicitBackingField
            let isDelegateProperty = propertyDecl.delegateExpression != nil

            if !isInterfaceContext, !isAbstractProperty, !isGetterOnlyComputed, !isDelegateProperty {
                let kirID = arena.appendDecl(.global(KIRGlobal(symbol: symbol, type: propType)))
                directMembers.append(kirID)
                allDecls.append(kirID)
            }

            if !isInterfaceContext, let backingFieldSymbol = sema.symbols.backingFieldSymbol(for: symbol) {
                let backingFieldType = sema.symbols.propertyType(for: backingFieldSymbol) ?? propType
                let backingFieldKirID = arena.appendDecl(
                    .global(KIRGlobal(symbol: backingFieldSymbol, type: backingFieldType))
                )
                allDecls.append(backingFieldKirID)
            }

            if let getter = propertyDecl.getter, getter.body != .unit {
                lowerAccessorBody(
                    accessorBody: getter.body,
                    propertySymbol: symbol,
                    propertyType: propType,
                    accessorKind: .getter,
                    setterParamName: nil,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    allDecls: &allDecls
                )
            }

            if let setter = propertyDecl.setter, setter.body != .unit {
                lowerAccessorBody(
                    accessorBody: setter.body,
                    propertySymbol: symbol,
                    propertyType: propType,
                    accessorKind: .setter,
                    setterParamName: setter.parameterName,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    allDecls: &allDecls
                )
            }

            // BUG-227: the same field-reading getter is also exactly what a
            // *class* vtable slot needs behind it, so every property that
            // ever needs virtual dispatch — not just `override` members, but
            // also the open stored-property root of the chain — gets one here too.
            // A `final` property never needs one: LayoutSynthesis never gives
            // it a vtable slot, so no call site ever looks for this accessor.
            let hasCustomGetterBody = (propertyDecl.getter?.body).map { $0 != .unit } ?? false
            let hasCustomSetterBody = (propertyDecl.setter?.body).map { $0 != .unit } ?? false
            let hasDelegate = propertyDecl.delegateExpression != nil
            let propFlags = sema.symbols.symbol(symbol)?.flags
            let needsVirtualAccessor = propFlags.map {
                $0.contains(.overrideMember) || $0.contains(.openType) || $0.contains(.abstractType)
            } ?? false
            let inheritedInterfaceAccessors = if let ownerSymbol = sema.symbols.parentSymbol(for: symbol) {
                kirStoredPropertyInheritedInterfaceAccessors(
                    propertySymbol: symbol,
                    ownerSymbol: ownerSymbol,
                    sema: sema
                )
            } else {
                (getter: false, setter: false)
            }
            if !hasCustomGetterBody, !hasDelegate,
               let ownerSymbol = sema.symbols.parentSymbol(for: symbol)
            {
                let isExternalLinked = sema.symbols.externalLinkName(for: symbol).map { !$0.isEmpty } ?? false
                if isInterfaceContext, !isExternalLinked {
                    synthesizeInterfacePropertyGetterStub(
                        propertySymbol: symbol,
                        ownerSymbol: ownerSymbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        allDecls: &allDecls
                    )
                } else if !isInterfaceContext, needsVirtualAccessor || inheritedInterfaceAccessors.getter {
                    synthesizeStoredPropertyGetterAccessor(
                        propertySymbol: symbol,
                        ownerSymbol: ownerSymbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        allDecls: &allDecls
                    )
                }
            }
            if !hasCustomSetterBody, !hasDelegate,
               propFlags?.contains(.mutable) == true,
               let ownerSymbol = sema.symbols.parentSymbol(for: symbol)
            {
                let isExternalLinked = sema.symbols.externalLinkName(for: symbol).map { !$0.isEmpty } ?? false
                if isInterfaceContext, !isExternalLinked {
                    synthesizeInterfacePropertySetterStub(
                        propertySymbol: symbol,
                        ownerSymbol: ownerSymbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        allDecls: &allDecls
                    )
                } else if !isInterfaceContext, needsVirtualAccessor || inheritedInterfaceAccessors.setter {
                    synthesizeStoredPropertySetterAccessor(
                        propertySymbol: symbol,
                        ownerSymbol: ownerSymbol,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        allDecls: &allDecls
                    )
                }
            }

            if !isInterfaceContext, propertyDecl.delegateExpression != nil {
                let delegateStorageSymbol: SymbolID
                if let existingStorage = sema.symbols.delegateStorageSymbol(for: symbol) {
                    delegateStorageSymbol = existingStorage
                } else {
                    let extensionSuffix = sema.symbols.hasExtensionPropertyReceiver(symbol)
                        ? "_extension_\(symbol.rawValue)"
                        : ""
                    let delegateStorageName = interner.intern(
                        "$delegate_\(interner.resolve(propertyDecl.name))\(extensionSuffix)"
                    )
                    let delegateStorageFQName = (sema.symbols.symbol(symbol)?.fqName.dropLast() ?? []) + [delegateStorageName]
                    delegateStorageSymbol = sema.symbols.define(
                        kind: .field,
                        name: delegateStorageName,
                        fqName: Array(delegateStorageFQName),
                        declSite: propertyDecl.range,
                        visibility: .private,
                        flags: []
                    )
                    sema.symbols.setDelegateStorageSymbol(delegateStorageSymbol, for: symbol)
                }
                let delegateType = sema.types.anyType
                let delegateKirID = arena.appendDecl(
                    .global(KIRGlobal(symbol: delegateStorageSymbol, type: delegateType))
                )
                allDecls.append(delegateKirID)

                lowerDelegateAccessor(
                    propertySymbol: symbol,
                    propertyType: propType,
                    delegateStorageSymbol: delegateStorageSymbol,
                    accessorKind: .getter,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    allDecls: &allDecls
                )

                if propertyDecl.isVar {
                    lowerDelegateAccessor(
                        propertySymbol: symbol,
                        propertyType: propType,
                        delegateStorageSymbol: delegateStorageSymbol,
                        accessorKind: .setter,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        allDecls: &allDecls
                    )
                }
            }
        }

        for declID in nestedClasses {
            guard let decl = ast.arena.decl(declID),
                  let symbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            switch decl {
            case let .classDecl(nested):
                var nestedAllObjects = nested.nestedObjects
                if let companionDeclID = nested.companionObject {
                    nestedAllObjects.append(companionDeclID)
                }
                let (nestedDirect, nestedAll) = lowerMemberDecls(
                    memberFunctions: nested.memberFunctions,
                    memberProperties: nested.memberProperties,
                    nestedClasses: nested.nestedClasses,
                    nestedObjects: nestedAllObjects,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    compilationCtx: compilationCtx
                )
                var nestedAllDecls = nestedAll
                if sema.symbols.symbol(symbol)?.kind == .enumClass {
                    nestedAllDecls.append(contentsOf: lowerEnumEntryBodyMembers(
                        classDecl: nested,
                        shared: KIRLoweringSharedContext(
                            ast: ast,
                            sema: sema,
                            arena: arena,
                            interner: interner,
                            propertyConstantInitializers: propertyConstantInitializers
                        ),
                        compilationCtx: compilationCtx
                    ))
                }
                let shared = KIRLoweringSharedContext(
                    ast: ast, sema: sema, arena: arena, interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers
                )
                let forwardingDecls = driver.synthesizeClassDelegationForwardingMethods(
                    classSymbol: symbol, shared: shared, compilationCtx: compilationCtx
                ) + driver.synthesizeClassDelegationForwardingPropertyAccessors(
                    classSymbol: symbol, shared: shared, compilationCtx: compilationCtx
                )
                let kirID = arena.appendDecl(.nominalType(KIRNominalType(
                    symbol: symbol, memberDecls: nestedDirect + forwardingDecls
                )))
                directMembers.append(kirID)
                allDecls.append(kirID)
                allDecls.append(contentsOf: nestedAllDecls)
                allDecls.append(contentsOf: forwardingDecls)

                let ctorFQName = (sema.symbols.symbol(symbol)?.fqName ?? []) + [interner.intern("<init>")]
                let ctorSymbols = sema.symbols.lookupAll(fqName: ctorFQName)
                for ctorSymbol in ctorSymbols {
                    let ctorDecls = driver.lowerConstructor(
                        ctorSymbol: ctorSymbol,
                        ctorFQName: ctorFQName,
                        classDecl: nested,
                        ownerSymbol: symbol,
                        shared: shared
                    )
                    allDecls.append(contentsOf: ctorDecls)
                }
            case let .interfaceDecl(nestedInterface):
                var nestedInterfaceAllObjects = nestedInterface.nestedObjects
                if let companionDeclID = nestedInterface.companionObject {
                    nestedInterfaceAllObjects.append(companionDeclID)
                }
                let (nestedDirect, nestedAll) = lowerMemberDecls(
                    memberFunctions: nestedInterface.memberFunctions,
                    memberProperties: nestedInterface.memberProperties,
                    nestedClasses: nestedInterface.nestedClasses,
                    nestedObjects: nestedInterfaceAllObjects,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    compilationCtx: compilationCtx,
                    isInterfaceContext: true
                )
                let kirID = arena.appendDecl(.nominalType(KIRNominalType(symbol: symbol, memberDecls: nestedDirect)))
                directMembers.append(kirID)
                allDecls.append(kirID)
                allDecls.append(contentsOf: nestedAll)
            default:
                continue
            }
        }

        for declID in nestedObjects {
            guard let decl = ast.arena.decl(declID),
                  case let .objectDecl(nested) = decl,
                  let symbol = sema.bindings.declSymbols[declID]
            else {
                continue
            }
            let (nestedDirect, nestedAll) = lowerMemberDecls(
                memberFunctions: nested.memberFunctions,
                memberProperties: nested.memberProperties,
                nestedClasses: nested.nestedClasses,
                nestedObjects: nested.nestedObjects,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                compilationCtx: compilationCtx
            )
            let shared = KIRLoweringSharedContext(
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers
            )
            let forwardingDecls = driver.synthesizeClassDelegationForwardingMethods(
                classSymbol: symbol, shared: shared, compilationCtx: compilationCtx
            ) + driver.synthesizeClassDelegationForwardingPropertyAccessors(
                classSymbol: symbol, shared: shared, compilationCtx: compilationCtx
            )
            let kirID = arena.appendDecl(.nominalType(KIRNominalType(
                symbol: symbol, memberDecls: nestedDirect + forwardingDecls
            )))
            directMembers.append(kirID)
            allDecls.append(kirID)
            allDecls.append(contentsOf: nestedAll)
            allDecls.append(contentsOf: forwardingDecls)

        }

        return (directMembers, allDecls)
    }

    func lowerEnumEntryBodyMembers(
        classDecl: ClassDecl,
        shared: KIRLoweringSharedContext,
        compilationCtx: CompilationContext?
    ) -> [KIRDeclID] {
        var declIDs: [KIRDeclID] = []
        for entry in classDecl.enumEntries {
            let accessorProperties = entry.memberProperties.filter { declID in
                guard case let .propertyDecl(property)? = shared.ast.arena.decl(declID) else { return false }
                return property.getter.map { $0.body != .unit } == true
                    || property.setter.map { $0.body != .unit } == true
            }
            guard !entry.memberFunctions.isEmpty || !accessorProperties.isEmpty || !entry.nestedClasses.isEmpty else {
                continue
            }
            declIDs.append(contentsOf: lowerMemberDecls(
                memberFunctions: entry.memberFunctions,
                memberProperties: accessorProperties,
                nestedClasses: entry.nestedClasses,
                nestedObjects: [],
                shared: shared,
                compilationCtx: compilationCtx
            ).allDecls)
        }
        return declIDs
    }

    private func lowerSingleMemberFunction(
        declID: DeclID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        directMembers: inout [KIRDeclID],
        allDecls: inout [KIRDeclID]
    ) {
        guard let decl = ast.arena.decl(declID),
              case let .funDecl(function) = decl,
              let symbol = sema.bindings.declSymbols[declID]
        else { return }
        // Functions with an external link name are bridged to a runtime
        // function; call sites are redirected via the external link name
        // (see CallLowerer), so the source body is never executed. Do NOT
        // emit a KIRFunction declaration for them at all: NativeEmitter
        // unconditionally registers every emitted KIRFunction in
        // `internalFunctions[symbol]`, and call-site codegen prefers that
        // internal definition over the redirected external callee name.
        // Emitting even a stub body here would shadow the real runtime
        // function and cause calls to silently invoke the stub instead.
        if let externalLink = sema.symbols.externalLinkName(for: symbol), !externalLink.isEmpty {
            return
        }
        if function.modifiers.contains(.external), function.body == .unit {
            return
        }
        // restore is harmless -- there is no enclosing function lowering in
        // progress. But an object literal's member functions are lowered
        // *from inside* whichever function's expression lowering constructs
        // it (`ObjectLiteralLowerer.lowerObjectLiteralMemberFunctions`), so
        // without save/restore here, this reset previously wiped that
        // enclosing function's own locals (parameters, prior `val`/`var`
        // declarations) for the remainder of its lowering. Save/restore
        // (mirroring `LambdaLowerer`'s per-closure scope handling) makes
        // this a no-op for the ordinary top-level case while fixing the
        // nested case.
        let scopeSnapshot = driver.ctx.saveScope()
        defer { driver.ctx.restoreScope(scopeSnapshot) }
        driver.ctx.resetScopeForFunction()
        driver.ctx.beginCallableLoweringScope()
        driver.ctx.setCurrentFunctionSymbol(symbol)

        let signature = sema.symbols.functionSignature(for: symbol)
        var params: [KIRParameter] = []
        if let signature {
            if let receiverType = signature.receiverType {
                if function.receiverType != nil,
                   let ownerSymbol = sema.symbols.parentSymbol(for: symbol),
                   let ownerInfo = sema.symbols.symbol(ownerSymbol),
                   [.class, .interface, .enumClass, .object].contains(ownerInfo.kind)
                {
                    let ownerArgs: [TypeArg] = signature.typeParameterSymbols
                        .prefix(signature.classTypeParameterCount)
                        .map { .invariant(sema.types.make(.typeParam(TypeParamType(symbol: $0, nullability: .nonNull)))) }
                    let dispatchReceiverType = sema.types.make(.classType(ClassType(
                        classSymbol: ownerSymbol, args: ownerArgs, nullability: .nonNull
                    )))
                    let dispatchReceiverSymbol = SyntheticSymbolScheme.receiverParameterSymbol(for: ownerSymbol)
                    params.append(KIRParameter(symbol: dispatchReceiverSymbol, type: dispatchReceiverType))
                    let dispatchReceiverExpr = arena.appendExpr(.symbolRef(dispatchReceiverSymbol), type: dispatchReceiverType)
                    driver.ctx.setLocalValue(dispatchReceiverExpr, for: dispatchReceiverSymbol)
                    driver.ctx.setLocalValue(dispatchReceiverExpr, for: ownerSymbol)
                    driver.ctx.setLocalDeclaredType(dispatchReceiverType, for: ownerSymbol)
                    driver.ctx.setQualifiedThisReceiver(dispatchReceiverExpr, for: ownerInfo.name)
                    driver.ctx.setCapturedOuterReceiver(dispatchReceiverExpr, for: ownerSymbol)
                }
                let receiverSymbol = driver.callSupportLowerer.syntheticReceiverParameterSymbol(functionSymbol: symbol)
                params.append(KIRParameter(symbol: receiverSymbol, type: receiverType))
                driver.ctx.setLocalDeclaredType(receiverType, for: receiverSymbol)
                driver.ctx.setImplicitReceiver(
                    symbol: receiverSymbol,
                    exprID: arena.appendExpr(.symbolRef(receiverSymbol), type: receiverType)
                )
                if function.receiverType == nil,
                   let owner = sema.symbols.parentSymbol(for: symbol),
                   let receiver = driver.ctx.activeImplicitReceiverExprID()
                {
                    driver.ctx.setCapturedOuterReceiver(receiver, for: owner)
                    driver.ctx.setLocalValue(receiver, for: owner)
                    driver.ctx.setLocalDeclaredType(receiverType, for: owner)
                }
            }
            for (contextSymbol, contextType) in zip(
                signature.contextParameterSymbols,
                signature.contextParameterTypes
            ) {
                params.append(KIRParameter(symbol: contextSymbol, type: contextType))
            }
            let isVararg = OverloadResolver.normalizeFlags(signature.valueParameterIsVararg, count: signature.parameterTypes.count)
            for (index, (paramSymbol, paramType)) in zip(signature.valueParameterSymbols, signature.parameterTypes).enumerated() {
                let effectiveType: TypeID
                if index < isVararg.count, isVararg[index] {
                    let listFQName: [InternedString] = [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern("List"),
                    ]
                    if let listSymbol = sema.symbols.lookupNominal(fqName: listFQName) {
                        effectiveType = sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.invariant(paramType)],
                            nullability: .nonNull
                        )))
                    } else {
                        effectiveType = paramType
                    }
                } else {
                    effectiveType = paramType
                }
                params.append(KIRParameter(symbol: paramSymbol, type: effectiveType))
            }
        }
        if function.isInline, let signature, !signature.reifiedTypeParameterIndices.isEmpty {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            for index in signature.reifiedTypeParameterIndices.sorted() {
                guard index < signature.typeParameterSymbols.count else { continue }
                let typeParamSymbol = signature.typeParameterSymbols[index]
                let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParamSymbol)
                params.append(KIRParameter(symbol: tokenSymbol, type: intType))
                params.append(KIRParameter(
                    symbol: SyntheticSymbolScheme.reifiedKTypeSymbol(for: typeParamSymbol), type: intType
                ))
            }
        }
        let returnType = signature?.returnType ?? sema.types.unitType
        var body: [KIRInstruction] = [.beginBlock]
        bindFunctionParameterLocals(params: params, body: &body, arena: arena)
        driver.objectLiteralLowerer.restoreObjectLiteralCaptures(
            forMemberFunction: symbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body
        )
        let contextValues = signature.map { signature in
            zip(signature.contextParameterSymbols, signature.contextParameterTypes).map { symbol, type in
                KIRLoweringContext.ContextReceiverValue(
                    type: type,
                    exprID: arena.appendExpr(.symbolRef(symbol), type: type)
                )
            }
        } ?? []
        driver.ctx.withContextReceiverValues(contextValues) {
            switch function.body {
        case let .block(exprIDs, _):
            var terminatedByReturn = false
            for exprID in exprIDs {
                if let expr = ast.arena.expr(exprID), case let .returnExpr(value, _, _) = expr {
                    if let value {
                        let lowered = driver.lowerExpr(value, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &body)
                        body.append(.returnValue(lowered))
                    } else {
                        body.append(.returnUnit)
                    }
                    terminatedByReturn = true
                    break
                }
                let lowered = driver.lowerExpr(exprID, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &body)
                if driver.controlFlowLowerer.isTerminatedExpr(lowered, arena: arena, sema: sema) {
                    terminatedByReturn = true
                    break
                }
            }
            if !terminatedByReturn {
                body.append(.returnUnit)
            }
        case let .expr(exprID, _):
            let value = driver.lowerExpr(exprID, ast: ast, sema: sema, arena: arena, interner: interner, propertyConstantInitializers: propertyConstantInitializers, instructions: &body)
            body.append(.returnValue(value))
        case .unit:
            body.append(.returnUnit)
            }
        }
        body.append(.endBlock)
        let kirID = arena.appendDecl(.function(KIRFunction(
            symbol: symbol, name: function.name, params: params, returnType: returnType,
            body: body, isSuspend: function.isSuspend, isInline: function.isInline, isTailrec: function.isTailrec
        )))
        directMembers.append(kirID)
        allDecls.append(kirID)
        if let defaults = driver.ctx.defaultArguments(for: symbol), let sig = signature {
            let stubID = driver.callSupportLowerer.generateDefaultStubFunction(
                originalSymbol: symbol, originalName: function.name, signature: sig,
                defaultExpressions: defaults, ast: ast, sema: sema, arena: arena,
                interner: interner, propertyConstantInitializers: propertyConstantInitializers
            )
            allDecls.append(stubID)
        }
        allDecls.append(contentsOf: driver.ctx.drainGeneratedCallableDecls())
        driver.ctx.clearImplicitReceiver()
        driver.ctx.setCurrentFunctionSymbol(nil)
    }

    func lowerDelegateAccessor(
        propertySymbol: SymbolID,
        propertyType: TypeID,
        delegateStorageSymbol: SymbolID,
        accessorKind: PropertyAccessorKind,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        allDecls: inout [KIRDeclID]
    ) {
        let shared = KIRLoweringSharedContext(
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: [:]
        )
        lowerDelegateAccessor(
            propertySymbol: propertySymbol,
            propertyType: propertyType,
            delegateStorageSymbol: delegateStorageSymbol,
            accessorKind: accessorKind,
            shared: shared,
            allDecls: &allDecls
        )
    }

    func lowerAccessorBody(
        accessorBody: FunctionBody,
        propertySymbol: SymbolID,
        propertyType: TypeID,
        accessorKind: PropertyAccessorKind,
        setterParamName: InternedString?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        allDecls: inout [KIRDeclID]
    ) {
        let shared = KIRLoweringSharedContext(
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers
        )
        lowerAccessorBody(
            accessorBody: accessorBody,
            propertySymbol: propertySymbol,
            propertyType: propertyType,
            accessorKind: accessorKind,
            setterParamName: setterParamName,
            shared: shared,
            allDecls: &allDecls
        )
    }

    private func bindFunctionParameterLocals(
        params: [KIRParameter],
        body: inout [KIRInstruction],
        arena: KIRArena
    ) {
        if let receiverBinding = driver.ctx.activeImplicitReceiver() {
            body.append(.constValue(result: receiverBinding.exprID, value: .symbolRef(receiverBinding.symbol)))
            driver.ctx.setLocalValue(receiverBinding.exprID, for: receiverBinding.symbol)
        }

        for param in params where param.symbol != driver.ctx.activeImplicitReceiverSymbol() {
            let paramExpr = driver.ctx.localValue(for: param.symbol)
                ?? arena.appendExpr(.symbolRef(param.symbol), type: param.type)
            body.append(.constValue(result: paramExpr, value: .symbolRef(param.symbol)))
            driver.ctx.setLocalValue(paramExpr, for: param.symbol)
        }
    }
}
