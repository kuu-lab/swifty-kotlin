
extension KIRLoweringDriver {
    /// The flag gets a real symbol with a stable, unique fully-qualified
    /// name (`<owner fqName>.$initialized`) rather than reusing a raw
    /// synthetic symbol ID: `NativeEmitter.stableGlobalSlotName` falls back
    /// to a symbol-ID-derived name only when no FQ name is available, and
    /// every synthetic-lambda-range symbol ID collapses to the same
    /// `max(0, rawValue)` bucket, which would silently merge every object's
    /// flag onto one shared global.
    func makeObjectLazyInitFlag(
        for objectSymbol: SymbolID,
        declSite: SourceRange?,
        shared: KIRLoweringSharedContext
    ) -> (flagSymbol: SymbolID, globalDeclID: KIRDeclID) {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        let flagName = interner.intern("$initialized")
        let ownerFQName = sema.symbols.symbol(objectSymbol)?.fqName ?? []
        let flagSymbol = sema.symbols.define(
            kind: .field, name: flagName, fqName: ownerFQName + [flagName],
            declSite: declSite, visibility: .private, flags: [.synthetic]
        )
        let globalDeclID = arena.appendDecl(.global(KIRGlobal(symbol: flagSymbol, type: sema.types.booleanType)))
        return (flagSymbol, globalDeclID)
    }

    func emitObjectLazyInitGuardIfNeeded(
        objectSymbol: SymbolID,
        arena: KIRArena,
        sema: SemaModule,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        guard !ctx.isObjectLazyInitOmitted(for: objectSymbol) else { return }
        if sema.symbols.externalLinkNameIfKnown(for: objectSymbol) != nil {
            return
        }
        let lazyInitSymbol: SymbolID?
        let lazyInitName: InternedString
        if let lazyInit = ctx.objectLazyInit(for: objectSymbol) {
            lazyInitSymbol = lazyInit.ensureInitSymbol
            lazyInitName = lazyInit.ensureInitName
        } else if let importedLazyInit = sema.symbols.objectLazyInitializerSymbol(for: objectSymbol),
                  let importedSymbol = sema.symbols.symbol(importedLazyInit)
        {
            lazyInitSymbol = importedLazyInit
            lazyInitName = importedSymbol.name
        } else if let objectInfo = sema.symbols.symbol(objectSymbol), objectInfo.kind == .object,
                  sema.symbols.isSourceBackedSymbol(objectSymbol)
        {
            // A forward reference can precede the source object's initializer
            // registration. Resolve this guard after all declarations are lowered.
            lazyInitSymbol = ctx.deferredObjectLazyInitSymbol(for: objectSymbol)
            lazyInitName = objectInfo.name
        } else {
            guard let objectInfo = sema.symbols.symbol(objectSymbol),
                  objectInfo.kind == .object,
                  !objectInfo.flags.contains(.importedLibrary),
                  !objectInfo.flags.contains(.synthetic),
                  !objectInfo.flags.contains(.expectDeclaration)
            else { return }
            let parentSymbol = sema.symbols.parentSymbolIfKnown(for: objectSymbol)
            var ancestorSymbol = parentSymbol
            while let ancestorID = ancestorSymbol {
                switch sema.symbols.symbol(ancestorID)?.kind {
                case .class, .interface, .object, .enumClass, .annotationClass, .package:
                    ancestorSymbol = sema.symbols.parentSymbolIfKnown(for: ancestorID)
                default:
                    return
                }
            }
            let isCompanion = parentSymbol.map {
                sema.symbols.companionObjectSymbolIfKnown(for: $0) == objectSymbol
            } ?? false
            let parentIsNominal = parentSymbol.map {
                sema.symbols.symbol($0)?.kind != .package
            } ?? false
            if !isCompanion, parentIsNominal {
                let needsRuntimeInitialization = sema.symbols.directSupertypes(for: objectSymbol).contains { superSymbol in
                    let kind = sema.symbols.symbol(superSymbol)?.kind
                    if kind == .interface {
                        return true
                    }
                    return (kind == .class || kind == .enumClass)
                        && superSymbol != sema.types.anyClassSymbol
                }
                guard needsRuntimeInitialization else { return }
            }
            lazyInitSymbol = nil
            lazyInitName = interner.intern(
                isCompanion
                    ? "__companion_lazy_init_\(objectSymbol.rawValue)"
                    : "__object_lazy_init_\(objectSymbol.rawValue)"
            )
        }
        let result = arena.appendTemporary(type: sema.types.unitType)
        instructions.append(.call(symbol: lazyInitSymbol, callee: lazyInitName, arguments: [], result: result, canThrow: false))
    }

    func emitSupertypeCompanionInitCalls(
        for nominalSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        var visited: Set<SymbolID> = []
        emitSupertypeCompanionInitCalls(
            for: nominalSymbol, sema: sema, arena: arena, interner: interner,
            visited: &visited, instructions: &instructions
        )
    }

    private func emitSupertypeCompanionInitCalls(
        for nominalSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        visited: inout Set<SymbolID>,
        instructions: inout [KIRInstruction]
    ) {
        let supertypes = sema.symbols.directSupertypes(for: nominalSymbol)
        for superSymbol in supertypes {
            guard let kind = sema.symbols.symbol(superSymbol)?.kind,
                  kind == .class || kind == .enumClass,
                  superSymbol != sema.types.anyClassSymbol,
                  visited.insert(superSymbol).inserted
            else { continue }
            if let companionSymbol = sema.symbols.companionObjectSymbolIfKnown(for: superSymbol)
                ?? sema.symbols.companionBlockObjectSymbol(for: superSymbol, interner: interner)
            {
                emitObjectLazyInitGuardIfNeeded(
                    objectSymbol: companionSymbol, arena: arena, sema: sema,
                    interner: interner, instructions: &instructions
                )
            } else {
                emitSupertypeCompanionInitCalls(
                    for: superSymbol, sema: sema, arena: arena, interner: interner,
                    visited: &visited, instructions: &instructions
                )
            }
        }
        for superSymbol in supertypes {
            guard sema.symbols.symbol(superSymbol)?.kind == .interface else { continue }
            emitInterfaceCompanionInitCalls(
                for: superSymbol, sema: sema, arena: arena, interner: interner,
                visited: &visited, instructions: &instructions
            )
        }
    }

    private func emitInterfaceCompanionInitCalls(
        for interfaceSymbol: SymbolID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        visited: inout Set<SymbolID>,
        instructions: inout [KIRInstruction]
    ) {
        guard visited.insert(interfaceSymbol).inserted else { return }
        if interfaceDeclaresConcreteMember(interfaceSymbol, sema: sema),
           let companionSymbol = sema.symbols.companionObjectSymbolIfKnown(for: interfaceSymbol)
            ?? sema.symbols.companionBlockObjectSymbol(for: interfaceSymbol, interner: interner)
        {
            emitObjectLazyInitGuardIfNeeded(
                objectSymbol: companionSymbol, arena: arena, sema: sema,
                interner: interner, instructions: &instructions
            )
            return
        }
        for superSymbol in sema.symbols.directSupertypes(for: interfaceSymbol) {
            guard sema.symbols.symbol(superSymbol)?.kind == .interface else { continue }
            emitInterfaceCompanionInitCalls(
                for: superSymbol, sema: sema, arena: arena, interner: interner,
                visited: &visited, instructions: &instructions
            )
        }
    }

    private func interfaceDeclaresConcreteMember(
        _ interfaceSymbol: SymbolID,
        sema: SemaModule
    ) -> Bool {
        sema.symbols.children(of: interfaceSymbol).contains { child in
            guard let info = sema.symbols.symbol(child) else { return false }
            switch info.kind {
            case .function, .property:
                return !info.flags.contains(.abstractType)
            default:
                return false
            }
        }
    }

    func resolveDeferredObjectLazyInitGuards(arena: KIRArena) {
        let pending = ctx.deferredObjectLazyInitSymbols
        guard !pending.isEmpty else { return }
        let ownersBySymbol = Dictionary(uniqueKeysWithValues: pending.map { ($0.value, $0.key) })
        arena.transformFunctions { function in
            guard function.body.contains(where: { instruction in
                guard case let .call(symbol?, _, _, _, _, _, _, _) = instruction else { return false }
                return ownersBySymbol[symbol] != nil
            }) else { return function }
            var body: [KIRInstruction] = []
            var locations: [SourceRange?] = []
            for (index, instruction) in function.body.enumerated() {
                let location = index < function.instructionLocations.count ? function.instructionLocations[index] : nil
                if case let .call(symbol?, _, arguments, result, canThrow, thrownResult, isSuperCall, qualifiedSuperType) = instruction,
                   let owner = ownersBySymbol[symbol]
                {
                    guard let lazyInit = ctx.objectLazyInit(for: owner) else { continue }
                    body.append(.call(symbol: lazyInit.ensureInitSymbol, callee: lazyInit.ensureInitName,
                        arguments: arguments, result: result, canThrow: canThrow, thrownResult: thrownResult,
                        isSuperCall: isSuperCall, qualifiedSuperType: qualifiedSuperType))
                } else {
                    body.append(instruction)
                }
                locations.append(location)
            }
            var updated = function
            updated.replaceBody(body, locations: locations)
            return updated
        }
    }

    func synthesizeObjectInitializer(
        _ objectDecl: ObjectDecl,
        objectSymbol: SymbolID,
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        ctx.registerObjectInitializer(for: objectSymbol)
        let sema = shared.sema

        let interfaceSupertypes = ctx.nominalDispatchCache.transitiveInterfaceSupertypes(
            of: objectSymbol,
            sema: sema
        )

        let arena = shared.arena
        let interner = shared.interner

        let initializerSymbol = ctx.allocateSyntheticGeneratedSymbol()
        let initializerName = interner.intern("__object_init_\(objectSymbol.rawValue)")

        ctx.resetScopeForFunction()
        ctx.beginCallableLoweringScope()

        let objectType = sema.types.make(.classType(ClassType(
            classSymbol: objectSymbol, args: [], nullability: .nonNull
        )))
        let objectReceiverExpr = arena.appendExpr(.symbolRef(objectSymbol), type: objectType)
        ctx.setImplicitReceiver(symbol: objectSymbol, exprID: objectReceiverExpr)

        var body: KIRLoweringEmitContext = [.beginBlock]

        let intType = sema.types.intType
        let layout = sema.symbols.nominalLayout(for: objectSymbol)
        let slotCount = Int64(max(layout?.instanceSizeWords ?? 1, 1))
        let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
        body.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
        let classIDValue = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: objectSymbol, sema: sema, interner: interner
        )
        let classIDExpr = arena.appendExpr(.intLiteral(classIDValue), type: intType)
        body.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))
        let allocatedObj = arena.appendTemporary(type: objectType)
        let externalLink = sema.symbols.externalLinkNameIfKnown(for: objectSymbol)
        body.append(.call(
            callee: interner.intern(externalLink ?? "kk_object_new"),
            arguments: externalLink == nil ? [slotCountExpr, classIDExpr] : [],
            result: allocatedObj,
            canThrow: false
        ))

        body.append(.storeGlobal(value: allocatedObj, symbol: objectSymbol))

        var typeEdgeInstructions: [KIRInstruction] = []
        appendNominalSupertypeEdgeRegistrations(
            childSymbol: objectSymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &typeEdgeInstructions
        )
        body.append(contentsOf: typeEdgeInstructions)

        if let objectLayout = sema.symbols.nominalLayout(for: objectSymbol) {
            for interfaceSymbol in interfaceSupertypes {
                guard let interfaceLayout = sema.symbols.nominalLayout(for: interfaceSymbol) else { continue }
                let ifaceSlot = Int64(objectLayout.itableSlots[interfaceSymbol] ?? 0)
                let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                    symbol: interfaceSymbol,
                    sema: sema,
                    interner: interner
                )
                let interfaceTypeExpr = arena.appendExpr(.intLiteral(interfaceTypeID), type: intType)
                body.append(.constValue(result: interfaceTypeExpr, value: .intLiteral(interfaceTypeID)))
                let ifaceSlotExpr = arena.appendExpr(.intLiteral(ifaceSlot), type: intType)
                body.append(.constValue(result: ifaceSlotExpr, value: .intLiteral(ifaceSlot)))
                let registerIfaceResult = arena.appendTemporary(type: intType)
                body.append(.call(
                    callee: interner.intern("kk_object_register_itable_iface"),
                    arguments: [allocatedObj, interfaceTypeExpr, ifaceSlotExpr],
                    result: registerIfaceResult,
                    canThrow: false
                ))

                for (methodSymbol, methodSlotInt) in kirItableMethodEntries(
                    for: interfaceSymbol,
                    interfaceLayout: interfaceLayout,
                    sema: sema,
                    interner: interner
                ) {
                    let methodSlot = Int64(methodSlotInt)
                    let implementationSymbol = ctx.nominalDispatchCache.itableImplementation(
                        for: methodSymbol,
                        in: objectSymbol,
                        sema: sema,
                        interner: interner
                    )
                    let bridgeSymbol = itableBridgeSymbolForMethod(
                        interfaceMethod: methodSymbol,
                        implementation: implementationSymbol,
                        nominalSymbol: objectSymbol,
                        driver: self,
                        arena: arena,
                        sema: sema,
                        interner: interner
                    )
                    let methodSlotExpr = arena.appendExpr(.intLiteral(methodSlot), type: intType)
                    body.append(.constValue(result: methodSlotExpr, value: .intLiteral(methodSlot)))
                    let methodFnExpr = arena.appendExpr(.symbolRef(bridgeSymbol), type: intType)
                    body.append(.constValue(result: methodFnExpr, value: .symbolRef(bridgeSymbol)))
                    let registerMethodResult = arena.appendTemporary(type: intType)
                    body.append(.call(
                        callee: interner.intern("kk_object_register_itable_method"),
                        arguments: [allocatedObj, ifaceSlotExpr, methodSlotExpr, methodFnExpr],
                        result: registerMethodResult,
                        canThrow: false
                    ))
                }
            }
            appendObjectItablePropertyGetterRegistrations(
                objectValue: allocatedObj,
                nominalSymbol: objectSymbol,
                sema: sema,
                cache: ctx.nominalDispatchCache,
                arena: arena,
                interner: interner,
                instructions: &body.instructions
            )
            appendObjectItablePropertySetterRegistrations(
                objectValue: allocatedObj,
                nominalSymbol: objectSymbol,
                sema: sema,
                cache: ctx.nominalDispatchCache,
                arena: arena,
                interner: interner,
                instructions: &body.instructions
            )
        }
        appendObjectVtableMethodRegistrations(
            objectValue: allocatedObj,
            nominalSymbol: objectSymbol,
            driver: self,
            sema: sema,
            cache: ctx.nominalDispatchCache,
            arena: arena,
            interner: interner,
            instructions: &body.instructions
        )
        appendObjectAnyToStringRegistration(
            objectValue: allocatedObj,
            nominalSymbol: objectSymbol,
            driver: self,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body.instructions
        )
        // The singleton can reach erased `value::class` queries before any
        // class literal registers its name (e.g. a hidden object returned as
        // `Any` across an independent .kklib boundary), so register it here.
        callLowerer.emitKClassMetadataRegistration(
            objectSymbol: objectSymbol,
            typeID: classIDValue,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body.instructions
        )

        var declIDs: [KIRDeclID] = []
        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
        ctx.clearImplicitReceiver()

        if !objectDecl.modifiers.contains(.companion), externalLink == nil {
            declIDs.append(contentsOf: synthesizeObjectLazyInit(
                objectDecl,
                objectSymbol: objectSymbol,
                objectType: objectType,
                shared: shared
            ))
        }
        if let lazyInit = ctx.objectLazyInit(for: objectSymbol) {
            appendKClassObjectRegistration(
                objectSymbol: objectSymbol, objectType: objectType,
                ensureInitSymbol: lazyInit.ensureInitSymbol, shared: shared,
                instructions: &body.instructions
            )
        }

        body.append(.returnUnit)
        body.append(.endBlock)

        let initDeclID = arena.appendDecl(
            .function(KIRFunction(
                symbol: initializerSymbol, name: initializerName,
                params: [], returnType: sema.types.unitType,
                body: body, isSuspend: false, isInline: false,
                sourceRange: objectDecl.range
            ))
        )
        ctx.registerCompanionInitializer(symbol: initializerSymbol, name: initializerName)
        declIDs.insert(initDeclID, at: 0)
        return declIDs
    }

    func synthesizeUninitializedCompanionHandles(
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        let sema = shared.sema
        let arena = shared.arena

        var existingGlobals: Set<SymbolID> = []
        for declaration in arena.declarations {
            if case let .global(global) = declaration {
                existingGlobals.insert(global.symbol)
            }
        }

        var declIDs: [KIRDeclID] = []
        for symbolInfo in sema.symbols.allSymbols() where symbolInfo.kind == .object {
            let objectSymbol = symbolInfo.id
            guard let ownerSymbol = sema.symbols.parentSymbolIfKnown(for: objectSymbol),
                  sema.symbols.companionObjectSymbolIfKnown(for: ownerSymbol) == objectSymbol
            else { continue }
            guard symbolInfo.flags.contains(.synthetic)
                  || symbolInfo.flags.contains(.importedLibrary),
                  !symbolInfo.flags.contains(.expectDeclaration)
            else { continue }
            guard sema.symbols.objectInitializerSymbolIfKnown(for: objectSymbol) == nil,
                  sema.symbols.companionObjectInitializerSymbolIfKnown(for: ownerSymbol) == nil,
                  sema.symbols.externalLinkNameIfKnown(for: objectSymbol)?.isEmpty != false
            else { continue }

            let companionType = sema.types.make(.classType(ClassType(
                classSymbol: objectSymbol, args: [], nullability: .nonNull
            )))
            if !existingGlobals.contains(objectSymbol) {
                declIDs.append(arena.appendDecl(.global(KIRGlobal(
                    symbol: objectSymbol, type: companionType
                ))))
                existingGlobals.insert(objectSymbol)
            }
            declIDs.append(contentsOf: synthesizeCompanionHandleInitFunction(
                objectSymbol: objectSymbol,
                ownerSymbol: ownerSymbol,
                companionType: companionType,
                shared: shared
            ))
        }
        return declIDs
    }

    /// re-exports the initializer and downstream consumers can call it
    /// instead of synthesizing their own. The allocation is guarded by a
    /// zero check: more than one module can legitimately emit an initializer
    /// for the same shared root slot (two consumers of an artifact that has
    /// none), and the first allocation must win so `===` identity stays
    /// stable across module boundaries.
    private func synthesizeCompanionHandleInitFunction(
        objectSymbol: SymbolID,
        ownerSymbol: SymbolID,
        companionType: TypeID,
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner

        let initializerSymbol = ctx.allocateSyntheticGeneratedSymbol()
        let initializerName = interner.intern(
            "__companion_init_\(ownerSymbol.rawValue)_\(objectSymbol.rawValue)"
        )

        ctx.resetScopeForFunction()
        ctx.beginCallableLoweringScope()

        var body: KIRLoweringEmitContext = [.beginBlock]
        let intType = sema.types.intType

        let initLabel = ctx.makeLoopLabel()
        let doneLabel = ctx.makeLoopLabel()
        let slotExpr = arena.appendExpr(.symbolRef(objectSymbol), type: intType)
        body.append(.loadGlobal(result: slotExpr, symbol: objectSymbol))
        let zeroExpr = arena.appendExpr(.intLiteral(0), type: intType)
        body.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
        body.append(.jumpIfEqual(lhs: slotExpr, rhs: zeroExpr, target: initLabel))
        body.append(.jump(doneLabel))
        body.append(.label(initLabel))

        let layout = sema.symbols.nominalLayout(for: objectSymbol)
        let slotCount = Int64(max(layout?.instanceSizeWords ?? 1, 1))
        let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
        body.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
        let classIDValue = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: objectSymbol, sema: sema, interner: interner
        )
        let classIDExpr = arena.appendExpr(.intLiteral(classIDValue), type: intType)
        body.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))
        let allocatedObject = arena.appendTemporary(type: companionType)
        body.append(.call(
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: allocatedObject,
            canThrow: false
        ))
        body.append(.storeGlobal(value: allocatedObject, symbol: objectSymbol))

        appendNominalSupertypeEdgeRegistrations(
            childSymbol: objectSymbol,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body.instructions
        )
        appendObjectItableMethodRegistrations(
            objectValue: allocatedObject,
            nominalSymbol: objectSymbol,
            driver: self,
            sema: sema,
            cache: ctx.nominalDispatchCache,
            arena: arena,
            interner: interner,
            instructions: &body.instructions
        )
        appendObjectVtableMethodRegistrations(
            objectValue: allocatedObject,
            nominalSymbol: objectSymbol,
            driver: self,
            sema: sema,
            cache: ctx.nominalDispatchCache,
            arena: arena,
            interner: interner,
            instructions: &body.instructions
        )
        appendObjectAnyToStringRegistration(
            objectValue: allocatedObject,
            nominalSymbol: objectSymbol,
            driver: self,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body.instructions
        )
        callLowerer.emitKClassMetadataRegistration(
            objectSymbol: objectSymbol,
            typeID: classIDValue,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body.instructions
        )

        body.append(.label(doneLabel))
        body.append(.returnUnit)
        body.append(.endBlock)

        let initDeclID = arena.appendDecl(
            .function(
                KIRFunction(
                    symbol: initializerSymbol,
                    name: initializerName,
                    params: [],
                    returnType: sema.types.unitType,
                    body: body,
                    isSuspend: false,
                    isInline: false
                )
            )
        )
        ctx.registerCompanionInitializer(symbol: initializerSymbol, name: initializerName)

        var declIDs = ctx.drainGeneratedCallableDecls()
        declIDs.insert(initDeclID, at: 0)
        ctx.clearImplicitReceiver()
        return declIDs
    }

    private func synthesizeObjectLazyInit(
        _ objectDecl: ObjectDecl,
        objectSymbol: SymbolID,
        objectType: TypeID,
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner

        let (flagSymbol, flagGlobalDeclID) = makeObjectLazyInitFlag(
            for: objectSymbol, declSite: objectDecl.range, shared: shared
        )

        let ensureInitSymbol = ctx.allocateSyntheticGeneratedSymbol()
        let ensureInitName = interner.intern("__object_lazy_init_\(objectSymbol.rawValue)")

        ctx.resetScopeForFunction()
        ctx.beginCallableLoweringScope()

        let objectHandleExpr = arena.appendExpr(.symbolRef(objectSymbol), type: objectType)
        ctx.setImplicitReceiver(symbol: objectSymbol, exprID: objectHandleExpr)

        var body: KIRLoweringEmitContext = [.beginBlock]
        body.append(.loadGlobal(result: objectHandleExpr, symbol: objectSymbol))

        let boolType = sema.types.booleanType
        let trueExpr = arena.appendExpr(.boolLiteral(true), type: boolType)
        body.append(.constValue(result: trueExpr, value: .boolLiteral(true)))
        let flagLoadExpr = arena.appendExpr(.symbolRef(flagSymbol), type: boolType)
        body.append(.loadGlobal(result: flagLoadExpr, symbol: flagSymbol))
        let alreadyInitializedLabel = ctx.makeLoopLabel()
        body.append(.jumpIfEqual(lhs: flagLoadExpr, rhs: trueExpr, target: alreadyInitializedLabel))
        // Not yet initialized: set the flag *before* running the body so a
        // reentrant access from within an `init` block (Kotlin allows a
        // singleton's own init code to read its not-yet-fully-set-up state)
        // sees "already initialized" and does not recurse.
        body.append(.storeGlobal(value: trueExpr, symbol: flagSymbol))

        let companionBlockOwnerSymbol = sema.symbols.parentSymbolIfKnown(for: objectSymbol).flatMap { owner in
            sema.symbols.companionBlockObjectSymbol(for: owner, interner: interner) == objectSymbol ? owner : nil
        }

        emitSupertypeCompanionInitCalls(
            for: companionBlockOwnerSymbol ?? objectSymbol,
            sema: sema, arena: arena, interner: interner,
            instructions: &body.instructions
        )

        emitSingletonLateinitSentinels(objectDecl.memberProperties, shared: shared, body: &body)
        emitNamedObjectSuperConstructorCall(
            objectDecl,
            objectSymbol: objectSymbol,
            objectValue: objectHandleExpr,
            shared: shared,
            body: &body
        )
        emitClassDelegationInitializers(
            ownerSymbol: objectSymbol,
            receiverID: objectHandleExpr,
            shared: shared,
            body: &body
        )
        emitObjectBodyInitializers(objectDecl, shared: shared, body: &body)

        // KUU-3821: `companion {}` blocks and a `companion object` share one
        // companion scope on the JVM — touching either half initializes the
        // whole scope. When a named companion object also exists, chain to
        // its ensure-init after the block initializers so block-first entry
        // still runs the object's body (blocks-then-object order, matching
        // kotlinc). Reentry is cut by each ensure-init's own `$initialized`
        // flag, and the named companion's ensure-init calls back into this
        // one before its own body for the symmetric object-first entry.
        if let companionBlockOwnerSymbol,
           let namedCompanion = sema.symbols.companionObjectSymbolIfKnown(for: companionBlockOwnerSymbol)
        {
            emitObjectLazyInitGuardIfNeeded(
                objectSymbol: namedCompanion, arena: arena, sema: sema,
                interner: interner, instructions: &body.instructions
            )
        }

        body.append(.label(alreadyInitializedLabel))
        body.append(.returnUnit)
        body.append(.endBlock)

        let ensureInitDeclID = arena.appendDecl(
            .function(KIRFunction(
                symbol: ensureInitSymbol, name: ensureInitName,
                params: [], returnType: sema.types.unitType,
                body: body, isSuspend: false, isInline: false,
                sourceRange: objectDecl.range
            ))
        )
        ctx.registerObjectLazyInit(
            for: objectSymbol,
            ensureInitSymbol: ensureInitSymbol,
            ensureInitName: ensureInitName,
        )

        var declIDs: [KIRDeclID] = [flagGlobalDeclID, ensureInitDeclID]
        declIDs.append(contentsOf: ctx.drainGeneratedCallableDecls())
        ctx.clearImplicitReceiver()
        return declIDs
    }

    func emitNamedObjectSuperConstructorCall(
        _ objectDecl: ObjectDecl,
        objectSymbol: SymbolID,
        objectValue: KIRExprID,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner
        guard let superclassSymbol = sema.symbols.directSupertypes(for: objectSymbol).first(where: {
            let kind = sema.symbols.symbol($0)?.kind
            return kind == .class || kind == .enumClass
        }),
        let superclassInfo = sema.symbols.symbol(superclassSymbol)
        else {
            return
        }
        let callBinding = sema.bindings.constructorDelegationCallBinding(for: objectSymbol)
        let candidates = sema.symbols.lookupAll(
            fqName: superclassInfo.fqName + [interner.intern("<init>")]
        )
        guard let superCtorSymbol = callBinding?.chosenCallee ?? resolveObjectSuperConstructor(
            candidates: candidates,
            argExprs: objectDecl.superTypeConstructorArgs.map(\.expr),
            sema: sema
        )
        else {
            return
        }
        let superArgs = objectDecl.superTypeConstructorArgs
        if isRuntimeThrowableSuperConstructor(superCtorSymbol, sema: sema) {
            emitRuntimeThrowableSuperInitialization(
                superCtorSymbol: superCtorSymbol,
                superclassSymbol: superclassSymbol,
                receiver: objectValue,
                loweredArgs: superArgs.map { lowerExpr($0.expr, shared: shared, emit: &body) },
                spreadFlags: superArgs.map(\.isSpread),
                argumentLabels: superArgs.map(\.label),
                callBinding: callBinding,
                shared: shared,
                body: &body
            )
            return
        }
        // Source-backed constructors — bundled stdlib or imported .kklib
        // declarations — carry a linkable external body, so their non-empty
        // externalLinkName must not suppress the call (the same rule
        // emitSuperConstructorDelegation applies for named classes). Only
        // synthetic shells with no real body and runtime factory constructors
        // (whose ABI returns a fresh box instead of initializing `this`) are
        // skipped (Throwable factories are handled above).
        guard !(sema.symbols.symbol(superCtorSymbol)?.flags.contains(.synthetic) ?? false)
            || sema.symbols.isSourceBackedSymbol(superCtorSymbol),
            !callLowerer.isRuntimeFactoryConstructor(superCtorSymbol, sema: sema)
        else {
            return
        }
        if sema.symbols.symbol(superCtorSymbol)?.flags.contains(.synthetic) == true,
           sema.symbols.parentSymbol(for: superCtorSymbol) == sema.types.anyClassSymbol
        {
            return
        }

        let loweredArgs = superArgs.map { lowerExpr($0.expr, shared: shared, emit: &body) }
        let resultID = arena.appendTemporary(type: sema.types.unitType)
        emitDelegatedConstructorCall(
            target: superCtorSymbol,
            receiver: objectValue,
            loweredArgs: loweredArgs,
            spreadFlags: superArgs.map(\.isSpread),
            argumentLabels: superArgs.map(\.label),
            callBinding: callBinding,
            sourceArgExprs: superArgs.map(\.expr),
            result: resultID,
            shared: shared,
            body: &body
        )
    }

    func resolveObjectSuperConstructor(
        candidates: [SymbolID],
        argExprs: [ExprID],
        sema: SemaModule
    ) -> SymbolID? {
        guard candidates.count > 1 else {
            return candidates.first
        }
        let arityMatches = candidates.filter {
            sema.symbols.functionSignature(for: $0)?.parameterTypes.count == argExprs.count
        }
        guard arityMatches.count > 1 else {
            return arityMatches.first ?? candidates.first
        }
        let argTypes = argExprs.map { sema.bindings.exprTypes[$0] }
        let typeMatches = arityMatches.filter { candidate in
            guard let parameterTypes = sema.symbols.functionSignature(for: candidate)?.parameterTypes else {
                return false
            }
            for (paramType, argType) in zip(parameterTypes, argTypes) {
                guard let argType else { continue }
                if case .typeParam = sema.types.kind(of: paramType) { continue }
                if paramType != argType { return false }
            }
            return true
        }
        return typeMatches.count == 1 ? typeMatches[0] : arityMatches[0]
    }

    private func emitObjectBodyInitializers(
        _ objectDecl: ObjectDecl,
        shared: KIRLoweringSharedContext,
        body: inout KIRLoweringEmitContext
    ) {
        let ast = shared.ast
        let sema = shared.sema

        for member in objectDecl.classBodyInitOrder {
            switch member {
            case let .property(index):
                guard index < objectDecl.memberProperties.count else { continue }
                let propertyDeclID = objectDecl.memberProperties[index]
                guard let propertyDecl = ast.arena.decl(propertyDeclID),
                      case let .propertyDecl(property) = propertyDecl,
                      let propertySymbol = sema.bindings.declSymbols[propertyDeclID]
                else { continue }
                if property.delegateExpression != nil {
                    emitDelegatePropertyInitializer(
                        propertyDecl: property,
                        propSymbol: propertySymbol,
                        sema: sema,
                        arena: shared.arena,
                        shared: shared,
                        body: &body
                    )
                    continue
                }
                guard let initializer = property.initializer else { continue }
                let initializerValue = lowerExpr(initializer, shared: shared, emit: &body)
                let targetSymbol = sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
                // Initialization writes storage directly, without invoking a
                // virtual getter or setter synthesized for this property.
                body.append(.storeGlobal(value: initializerValue, symbol: targetSymbol))
            case let .initBlock(index):
                guard index < objectDecl.initBlocks.count else { continue }
                let initBlock = objectDecl.initBlocks[index]
                switch initBlock {
                case let .block(exprIDs, _):
                    for exprID in exprIDs {
                        _ = lowerExpr(exprID, shared: shared, emit: &body)
                    }
                case let .expr(exprID, _):
                    _ = lowerExpr(exprID, shared: shared, emit: &body)
                case .unit:
                    break
                }
            }
        }
    }
}
