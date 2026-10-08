
extension CallLowerer {
    func lowerEnumValuesCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        // Preserve the intrinsic and its hidden token until inline expansion
        // supplies the concrete enum. The marker is preserved in serialized
        // inline bodies; native template bodies cannot execute the intrinsic.
        if let binding = sema.bindings.callBindings[exprID],
           let type = binding.substitutedTypeArguments.first,
           case let .typeParam(parameter) = sema.types.kind(of: type),
           sema.bindings.stdlibSpecialCallKind(for: exprID) == .enumValues {
            let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: parameter.symbol)
            let token: KIRExprID
            if let capturedToken = driver.ctx.localValue(for: tokenSymbol) {
                token = capturedToken
            } else {
                token = arena.appendExpr(.symbolRef(tokenSymbol), type: sema.types.intType)
                instructions.append(.constValue(result: token, value: .symbolRef(tokenSymbol)))
            }
            let result = arena.appendTemporary(type: sema.bindings.exprTypes[exprID])
            instructions.append(.call(
                symbol: binding.chosenCallee, callee: interner.intern("$reifiedEnumValues"),
                arguments: [token], result: result, canThrow: false, thrownResult: nil
            ))
            return result
        }
        return lowerEnumEntryCollectionCallExpr(
            exprID,
            args: args,
            kind: .enumValues,
            runtimeCalleeName: "kk_enum_make_values_array",
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    func lowerEnumEntriesCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        lowerEnumEntryCollectionCallExpr(
            exprID,
            args: args,
            kind: .enumEntries,
            runtimeCalleeName: "kk_enum_make_entries_list_cached",
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }

    private func lowerEnumEntryCollectionCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        kind: StdlibSpecialCallKind,
        runtimeCalleeName: String,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.stdlibSpecialCallKind(for: exprID) == kind,
              args.isEmpty,
              let callBinding = sema.bindings.callBindings[exprID],
              let typeArg = callBinding.substitutedTypeArguments.first,
              case let .classType(classType) = sema.types.kind(of: typeArg),
              let nominalSymbol = sema.symbols.symbol(classType.classSymbol),
              nominalSymbol.kind == .enumClass
        else {
            return nil
        }

        return emitEnumEntryCollection(
            classType: classType, nominalSymbol: nominalSymbol,
            boundType: sema.bindings.exprTypes[exprID] ?? sema.types.anyType,
            kind: kind, runtimeCalleeName: runtimeCalleeName,
            sema: sema, arena: arena, interner: interner, instructions: &instructions
        )
    }

    func lowerEnumValueOfCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.stdlibSpecialCallKind(for: exprID) == .enumValueOf,
              args.count == 1,
              let callBinding = sema.bindings.callBindings[exprID],
              let typeArg = callBinding.substitutedTypeArguments.first,
              case let .classType(classType) = sema.types.kind(of: typeArg),
              let nominalSymbol = sema.symbols.symbol(classType.classSymbol),
              nominalSymbol.kind == .enumClass
        else {
            return nil
        }

        let valueOfName = interner.intern("valueOf")
        let companionSymbol = sema.symbols.companionObjectSymbol(for: classType.classSymbol) ?? nominalSymbol.id
        let companionSymbolLookup = sema.symbols.symbol(companionSymbol)
        let companionFQName = (companionSymbolLookup?.fqName ?? nominalSymbol.fqName)
        let valueOfFQName = companionFQName + [valueOfName]
        let valueOfSymbol = sema.symbols.lookupAll(fqName: valueOfFQName).first
        guard let valueOfSymbol else {
            return nil
        }

        let companionType = sema.types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let boundType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType

        let companionReceiverExpr = arena.appendExpr(.symbolRef(companionSymbol), type: companionType)
        instructions.append(.constValue(result: companionReceiverExpr, value: .symbolRef(companionSymbol)))

        let nameArg = driver.lowerExpr(
            args[0].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        let result = arena.appendTemporary(type: boundType)
        instructions.append(.call(
            symbol: valueOfSymbol,
            callee: valueOfName,
            arguments: [companionReceiverExpr, nameArg],
            result: result,
            canThrow: true,
            thrownResult: nil
        ))
        return result
    }
}

/// Shared by concrete calls and reified calls specialized after inlining.
func emitEnumEntryCollection(
    classType: ClassType,
    nominalSymbol: SemanticSymbol,
    boundType: TypeID,
    kind: StdlibSpecialCallKind,
    runtimeCalleeName: String,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout [KIRInstruction]
) -> KIRExprID {
    let intType = sema.types.intType

    let fieldOffsets = sema.symbols.nominalLayout(for: nominalSymbol.id)?.fieldOffsets ?? [:]
    let entries = sema.symbols.children(ofFQName: nominalSymbol.fqName)
        .compactMap { sema.symbols.symbol($0) }
        .filter { $0.kind == .field }
        .sorted(by: {
            let lhsOffset = $0.declSite?.start.offset ?? Int.max
            let rhsOffset = $1.declSite?.start.offset ?? Int.max
            if lhsOffset != rhsOffset { return lhsOffset < rhsOffset }
            // Imported entries have no declaration ranges. Layout metadata
            // retains their declaration order, independently of import IDs.
            let lhsFieldOffset = fieldOffsets[$0.id] ?? Int.max
            let rhsFieldOffset = fieldOffsets[$1.id] ?? Int.max
            if lhsFieldOffset != rhsFieldOffset { return lhsFieldOffset < rhsFieldOffset }
            return $0.id.rawValue < $1.id.rawValue
        })

    let enumValuesArray = arena.appendTemporary(type: sema.types.anyType)
    let entriesCountExpr = arena.appendExpr(.intLiteral(Int64(entries.count)), type: intType)
    instructions.append(.constValue(result: entriesCountExpr, value: .intLiteral(Int64(entries.count))))
    instructions.append(.call(
        symbol: nil, callee: interner.intern("kk_array_new"),
        arguments: [entriesCountExpr], result: enumValuesArray,
        canThrow: false, thrownResult: nil
    ))

    let stringType = sema.types.stringType
    let boxOrdinalCallee = interner.intern("kk_enum_box_ordinal")
    let classID = RuntimeTypeCheckToken.stableNominalTypeID(
        symbol: classType.classSymbol,
        symbols: sema.symbols,
        interner: interner
    )
    let classIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
    instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))
    for (index, entry) in entries.enumerated() {
        let indexExpr = arena.appendExpr(.intLiteral(Int64(index)), type: intType)
        instructions.append(.constValue(result: indexExpr, value: .intLiteral(Int64(index))))

        let nameExpr = arena.appendExpr(.stringLiteral(entry.name), type: stringType)
        instructions.append(.constValue(result: nameExpr, value: .stringLiteral(entry.name)))

        // Box the ordinal (tagged with its declared name and the enum
        // class's stable nominal type ID, see kk_enum_box_ordinal) instead
        // of storing a pre-baked name string -- see the matching fix in
        // DataEnumSealedSynthesisPass+EnumSynthesis.swift's
        // appendEnumOrdinalArrayCreation for the full rationale. This is
        // a separate, duplicated code path (enumValues<T>()/enumEntries<T>()
        // rather than T.values()/T.entries) that had the same bug.
        let entryExpr = arena.appendTemporary(type: sema.types.anyType)
        instructions.append(.call(
            symbol: nil,
            callee: boxOrdinalCallee,
            arguments: [indexExpr, nameExpr, classIDExpr],
            result: entryExpr,
            canThrow: false,
            thrownResult: nil
        ))
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_set"),
            arguments: [enumValuesArray, indexExpr, entryExpr],
            result: nil,
            canThrow: false,
            thrownResult: nil
        ))
    }

    // Look up Color$enumValuesCount or fallback to the enum field count.
    let enumName = interner.resolve(nominalSymbol.name)
    let countHelperName = interner.intern("\(enumName)$enumValuesCount")
    let countHelperFQName = nominalSymbol.fqName + [countHelperName]
    let countSymbol = sema.symbols.lookupAll(fqName: countHelperFQName).first

    let countExpr: KIRExprID
    if let countSymbol {
        let countResult = arena.appendTemporary(type: intType)
        instructions.append(.call(
            symbol: countSymbol,
            callee: countHelperName,
            arguments: [],
            result: countResult,
            canThrow: false,
            thrownResult: nil
        ))
        countExpr = countResult
    } else {
        // Fallback: use entries count from children
        let countLiteral = arena.appendExpr(.intLiteral(Int64(entries.count)), type: intType)
        instructions.append(.constValue(result: countLiteral, value: .intLiteral(Int64(entries.count))))
        countExpr = countLiteral
    }

    let cachedClassIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
    instructions.append(.constValue(result: cachedClassIDExpr, value: .intLiteral(classID)))

    let result = arena.appendTemporary(type: boundType)
    instructions.append(.call(
        symbol: nil,
        callee: interner.intern(runtimeCalleeName),
        arguments: kind == .enumEntries
            ? [enumValuesArray, countExpr, cachedClassIDExpr]
            : [enumValuesArray, countExpr],
        result: result,
        canThrow: false,
        thrownResult: nil
    ))
    return result
}
