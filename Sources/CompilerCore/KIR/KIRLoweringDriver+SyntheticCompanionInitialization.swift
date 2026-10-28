extension KIRLoweringDriver {
    func synthesizeReferencedSyntheticCompanions(
        shared: KIRLoweringSharedContext
    ) -> [KIRDeclID] {
        let sema = shared.sema
        let arena = shared.arena
        let interner = shared.interner

        var companionSymbols: Set<SymbolID> = []
        for expression in arena.expressions {
            guard case let .symbolRef(companionSymbol) = expression,
                  let companion = sema.symbols.symbol(companionSymbol),
                  companion.kind == .object,
                  companion.flags.contains(.synthetic),
                  !companion.flags.contains(.expectDeclaration),
                  sema.symbols.externalLinkNameIfKnown(for: companionSymbol) == nil,
                  let ownerSymbol = sema.symbols.parentSymbolIfKnown(for: companionSymbol),
                  let owner = sema.symbols.symbol(ownerSymbol),
                  owner.kind == .class || owner.kind == .interface || owner.kind == .enumClass,
                  sema.symbols.companionObjectSymbol(for: ownerSymbol) == companionSymbol
            else {
                continue
            }
            companionSymbols.insert(companionSymbol)
        }

        guard !companionSymbols.isEmpty else { return [] }

        var existingGlobals: Set<SymbolID> = []
        var existingNominalTypes: Set<SymbolID> = []
        for declaration in arena.declarations {
            switch declaration {
            case let .global(global):
                existingGlobals.insert(global.symbol)
            case let .nominalType(nominal):
                existingNominalTypes.insert(nominal.symbol)
            case .function:
                break
            }
        }

        let sortedCompanions = companionSymbols.sorted { lhs, rhs in
            let lhsName = sema.symbols.symbol(lhs)?.fqName.map(interner.resolve).joined(separator: ".") ?? ""
            let rhsName = sema.symbols.symbol(rhs)?.fqName.map(interner.resolve).joined(separator: ".") ?? ""
            return lhsName < rhsName
        }
        var declIDs: [KIRDeclID] = []

        for companionSymbol in sortedCompanions where !existingGlobals.contains(companionSymbol) {
            guard sema.symbols.symbol(companionSymbol) != nil else { continue }
            let companionType = sema.types.make(.classType(ClassType(
                classSymbol: companionSymbol,
                args: [],
                nullability: .nonNull
            )))

            if !existingNominalTypes.contains(companionSymbol) {
                declIDs.append(arena.appendDecl(.nominalType(KIRNominalType(symbol: companionSymbol))))
                existingNominalTypes.insert(companionSymbol)
            }
            declIDs.append(arena.appendDecl(.global(KIRGlobal(
                symbol: companionSymbol,
                type: companionType
            ))))
            existingGlobals.insert(companionSymbol)

            let initializerSymbol = ctx.allocateSyntheticGeneratedSymbol()
            let initializerName = interner.intern("__kk_synthetic_companion_init_\(companionSymbol.rawValue)")
            var body: KIRLoweringEmitContext = [.beginBlock]

            let slotCount = Int64(max(sema.symbols.nominalLayout(for: companionSymbol)?.instanceSizeWords ?? 1, 1))
            let slotCountExpr = arena.appendExpr(.intLiteral(slotCount), type: sema.types.intType)
            body.append(.constValue(result: slotCountExpr, value: .intLiteral(slotCount)))

            let classID = RuntimeTypeCheckToken.stableNominalTypeID(
                symbol: companionSymbol,
                sema: sema,
                interner: interner
            )
            let classIDExpr = arena.appendExpr(.intLiteral(classID), type: sema.types.intType)
            body.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))

            let singleton = arena.appendTemporary(type: companionType)
            body.append(.call(
                callee: interner.intern("kk_object_new"),
                arguments: [slotCountExpr, classIDExpr],
                result: singleton,
                canThrow: false
            ))
            body.append(.storeGlobal(value: singleton, symbol: companionSymbol))
            body.append(.returnUnit)
            body.append(.endBlock)

            declIDs.append(arena.appendDecl(.function(KIRFunction(
                symbol: initializerSymbol,
                name: initializerName,
                params: [],
                returnType: sema.types.unitType,
                body: body,
                isSuspend: false,
                isInline: false
            ))))
            ctx.registerCompanionInitializer(symbol: initializerSymbol, name: initializerName)
        }

        return declIDs
    }
}
