import RuntimeABI

extension KIRLoweringDriver {
    /// Allocates an instance of `ownerSymbol` via `kk_object_new` and performs
    /// supertype, itable, and vtable runtime registrations.
    func emitAllocatePluginNominalInstance(
        ownerSymbol: SymbolID,
        resultType: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let intType = sema.types.intType
        let slotCount = Int64(max(sema.symbols.nominalLayout(for: ownerSymbol)?.instanceSizeWords ?? 1, 1))
        let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: intType)
        instructions.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))
        let classIDValue = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: ownerSymbol,
            sema: sema,
            interner: interner
        )
        let classIDExpr = arena.appendExpr(.intLiteral(classIDValue), type: intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))
        let allocatedObj = arena.appendTemporary(type: resultType)
        instructions.append(.call(
            callee: interner.intern("kk_object_new"),
            arguments: [slotCountExpr, classIDExpr],
            result: allocatedObj,
            canThrow: false
        ))
        for superSymbol in sema.symbols.directSupertypes(for: ownerSymbol) {
            let parentTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                symbol: superSymbol,
                sema: sema,
                interner: interner
            )
            let parentExpr = arena.appendExpr(.intLiteral(parentTypeID), type: intType)
            instructions.append(.constValue(result: parentExpr, value: .intLiteral(parentTypeID)))
            let regCallee = sema.symbols.symbol(superSymbol)?.kind == .interface
                ? interner.intern("kk_type_register_iface")
                : interner.intern("kk_type_register_super")
            let regResult = arena.appendTemporary(type: intType)
            instructions.append(.call(
                callee: regCallee,
                arguments: [classIDExpr, parentExpr],
                result: regResult,
                canThrow: false
            ))
        }
        appendObjectItableMethodRegistrations(
            objectValue: allocatedObj,
            nominalSymbol: ownerSymbol,
            driver: self,
            sema: sema,
            cache: ctx.nominalDispatchCache,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        appendObjectVtableMethodRegistrations(
            objectValue: allocatedObj,
            nominalSymbol: ownerSymbol,
            driver: self,
            sema: sema,
            cache: ctx.nominalDispatchCache,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        return allocatedObj
    }

    func makePluginSyntheticParam(
        ownerFQName: [InternedString],
        paramName: String = "$self",
        shared: KIRLoweringSharedContext
    ) -> SymbolID {
        let name = shared.interner.intern(paramName)
        return shared.sema.symbols.define(
            kind: .valueParameter,
            name: name,
            fqName: ownerFQName + [name],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
    }

    func resolvePluginPropertyOffset(
        ownerClass: SymbolID,
        propertySymbol: SymbolID,
        sema: SemaModule
    ) -> Int? {
        guard let layout = sema.symbols.nominalLayout(for: ownerClass) else {
            return nil
        }
        let backingField = sema.symbols.backingFieldSymbol(for: propertySymbol) ?? propertySymbol
        return layout.fieldOffsets[backingField] ?? layout.fieldOffsets[propertySymbol]
    }

    func emitLoadPluginSingletonObject(
        objectSymbol: SymbolID,
        resultType: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        emitObjectLazyInitGuardIfNeeded(
            objectSymbol: objectSymbol,
            arena: arena,
            sema: sema,
            interner: interner,
            instructions: &instructions
        )
        let expr = arena.appendTemporary(type: resultType)
        instructions.append(.loadGlobal(result: expr, symbol: objectSymbol))
        return expr
    }

    func findPluginMethodSymbol(
        on ownerSymbol: SymbolID,
        named name: String,
        arity: Int,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let interned = interner.intern(name)
        var queue: [SymbolID] = [ownerSymbol]
        var visited: Set<SymbolID> = []
        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard visited.insert(current).inserted else { continue }
            if let currentSym = sema.symbols.symbol(current) {
                let candidates = sema.symbols.lookupAll(fqName: currentSym.fqName + [interned])
                for candidate in candidates {
                    guard sema.symbols.symbol(candidate)?.kind == .function,
                          sema.symbols.parentSymbol(for: candidate) == current,
                          sema.symbols.functionSignature(for: candidate)?.parameterTypes.count == arity
                    else { continue }
                    return candidate
                }
            }
            for superSym in sema.symbols.directSupertypes(for: current) {
                queue.append(superSym)
            }
        }
        return nil
    }

    func emitPluginMemberCall(
        receiver: KIRExprID,
        receiverNominalSymbol: SymbolID,
        methodSymbol: SymbolID,
        arguments: [KIRExprID],
        returnType: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let resultExpr: KIRExprID? = returnType == sema.types.unitType
            ? nil
            : arena.appendTemporary(type: returnType)
        let calleeName = sema.symbols.symbol(methodSymbol)?.name ?? interner.intern("")
        let methodOwner = sema.symbols.parentSymbol(for: methodSymbol) ?? receiverNominalSymbol
        let ownerKind = sema.symbols.symbol(methodOwner)?.kind

        if ownerKind == .interface {
            let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                symbol: methodOwner,
                sema: sema,
                interner: interner
            )
            let interfaceLayout = sema.symbols.nominalLayout(for: methodOwner)
            let methodSlot = interfaceLayout?.vtableSlots[methodSymbol]
                ?? interfaceLayout?.itableSlots[methodSymbol]
                ?? 0
            instructions.append(.virtualCall(
                symbol: methodSymbol,
                callee: calleeName,
                receiver: receiver,
                arguments: arguments,
                result: resultExpr,
                canThrow: false,
                dispatch: .itableDynamic(interfaceTypeID: interfaceTypeID, methodSlot: methodSlot)
            ))
        } else if let layout = sema.symbols.nominalLayout(for: receiverNominalSymbol),
                  let vtableSlot = layout.vtableSlots[methodSymbol],
                  let methodOwnerInfo = sema.symbols.symbol(methodOwner),
                  methodOwnerInfo.flags.contains(.abstractType)
                      || methodOwnerInfo.flags.contains(.openType)
                      || !sema.symbols.directSubtypes(of: methodOwner).isEmpty
        {
            instructions.append(.virtualCall(
                symbol: methodSymbol,
                callee: calleeName,
                receiver: receiver,
                arguments: arguments,
                result: resultExpr,
                canThrow: false,
                dispatch: .vtable(slot: vtableSlot)
            ))
        } else {
            let externalName = sema.symbols.externalLinkName(for: methodSymbol).map { interner.intern($0) }
                ?? calleeName
            instructions.append(.call(
                symbol: methodSymbol,
                callee: externalName,
                arguments: [receiver] + arguments,
                result: resultExpr,
                canThrow: false
            ))
        }
        return resultExpr
    }

    func emitPluginSingletonInitializer(
        objectSymbol: SymbolID,
        objectType: TypeID,
        shared: KIRLoweringSharedContext
    ) -> KIRDeclID {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner

        let initializerSymbol = ctx.allocateSyntheticGeneratedSymbol()
        let initializerName = interner.intern("__kk_plugin_object_init_\(objectSymbol.rawValue)")
        var body: [KIRInstruction] = []
        let singleton = emitAllocatePluginNominalInstance(
            ownerSymbol: objectSymbol,
            resultType: objectType,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &body
        )
        body.append(.storeGlobal(value: singleton, symbol: objectSymbol))
        body.append(.returnUnit)

        ctx.registerCompanionInitializer(symbol: initializerSymbol, name: initializerName)
        return arena.appendDecl(.function(KIRFunction(
            symbol: initializerSymbol,
            name: initializerName,
            params: [],
            returnType: sema.types.unitType,
            body: body,
            isSuspend: false,
            isInline: false
        )))
    }
}
