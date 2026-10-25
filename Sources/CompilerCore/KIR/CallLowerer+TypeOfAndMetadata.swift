extension CallLowerer {
    /// Lowers `typeOf<T>()` calls to `kk_typeof(typeToken, nameHint, argsRaw, isNullable)`.
    func lowerTypeOfCallExpr(
        _ exprID: ExprID,
        calleeExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.stdlibSpecialCallKind(for: exprID) == .typeOf else {
            return nil
        }

        let knownNames = KnownCompilerNames(interner: interner)
        guard let callee = ast.arena.expr(calleeExpr) else {
            return nil
        }
        switch callee {
        case let .nameRef(name, _):
            guard name == knownNames.typeOf else { return nil }
        case let .memberCall(_, member, _, _, _):
            guard member == knownNames.typeOf else { return nil }
        default:
            return nil
        }

        let callBinding = sema.bindings.callBindings[exprID]
        let typeArg: TypeID
        if let binding = callBinding,
           !binding.substitutedTypeArguments.isEmpty
        {
            typeArg = binding.substitutedTypeArguments[0]
        } else {
            typeArg = sema.types.anyType
        }

        let resultType = sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        let lowered = driver.lowerKTypeExpr(
            for: typeArg,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
        let result = arena.appendTemporary(type: resultType)
        instructions.append(.copy(from: lowered, to: result))
        return result
    }

    /// This mirrors `ObjectLiteralLowerer.registerKClassMetadata` but is used
    /// for regular class constructor invocations.
    func emitKClassMetadataRegistration(
        objectSymbol: SymbolID,
        typeID: Int64,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        guard let symbol = sema.symbols.symbol(objectSymbol) else { return }

        let intType = sema.types.intType

        let typeToken = RuntimeTypeCheckToken.encode(
            base: RuntimeTypeCheckToken.nominalBase,
            nullable: false,
            payload: typeID
        )
        let typeTokenExpr = arena.appendExpr(.intLiteral(typeToken), type: intType)
        instructions.append(.constValue(result: typeTokenExpr, value: .intLiteral(typeToken)))

        let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
        let fqNameInterned = interner.intern(fqName)
        let fqNameExpr = arena.appendExpr(.stringLiteral(fqNameInterned), type: intType)
        instructions.append(.constValue(result: fqNameExpr, value: .stringLiteral(fqNameInterned)))

        let simpleName = interner.resolve(symbol.name)
        let simpleNameInterned = interner.intern(simpleName)
        let simpleNameExpr = arena.appendExpr(.stringLiteral(simpleNameInterned), type: intType)
        instructions.append(.constValue(result: simpleNameExpr, value: .stringLiteral(simpleNameInterned)))

        let supertypeNameExpr: KIRExprID
        if let joined = kclassSupertypeDisplayNamesJoined(
            for: objectSymbol, sema: sema, interner: interner
        ) {
            let superInterned = interner.intern(joined)
            supertypeNameExpr = arena.appendExpr(.stringLiteral(superInterned), type: intType)
            instructions.append(.constValue(result: supertypeNameExpr, value: .stringLiteral(superInterned)))
        } else {
            supertypeNameExpr = arena.appendExpr(.intLiteral(0), type: intType)
            instructions.append(.constValue(result: supertypeNameExpr, value: .intLiteral(0)))
        }

        var flags: Int64 = 0
        if symbol.flags.contains(.dataType) { flags |= 1 << 0 }
        if symbol.flags.contains(.sealedType) { flags |= 1 << 1 }
        if symbol.flags.contains(.valueType) { flags |= 1 << 2 }
        if symbol.kind == .interface { flags |= 1 << 3 }
        if symbol.kind == .object { flags |= 1 << 4 }
        if symbol.kind == .enumClass { flags |= 1 << 5 }
        if symbol.kind == .annotationClass { flags |= 1 << 6 }
        // Reflection reports Kotlin modality, not the internal inheritance flags.
        let isSealed = symbol.flags.contains(.sealedType)
        let isAbstract = !isSealed && (symbol.kind == .interface || symbol.kind == .annotationClass || symbol.flags.contains(.abstractType))
        if isAbstract { flags |= 1 << 7 }
        if !isSealed && !isAbstract && !symbol.flags.contains(.openType) { flags |= 1 << 8 }
        if !isSealed && !isAbstract && symbol.flags.contains(.openType) { flags |= 1 << 9 }
        // STDLIB-REFLECT-067: bits 10-12 for inner / companion / funInterface
        if symbol.flags.contains(.innerClass) { flags |= 1 << 10 }
        if symbol.flags.contains(.funInterface) { flags |= 1 << 12 }
        if symbol.kind == .object {
            let parentFQName = Array(symbol.fqName.dropLast())
            if let parentSymbol = sema.symbols.lookup(fqName: parentFQName),
               sema.symbols.companionObjectSymbol(for: parentSymbol) == objectSymbol {
                flags |= 1 << 11
            }
        }
        let ownerKind = sema.symbols.parentSymbol(for: objectSymbol)
            .flatMap { sema.symbols.symbol($0)?.kind }
        let isLocalOrAnonymous = symbol.fqName.contains { component in
            let name = interner.resolve(component)
            return name.hasPrefix("__localdecl_") || name.hasPrefix("__ObjectLiteral_")
        }
        if isLocalOrAnonymous
            || ownerKind.map({ [.function, .property, .local].contains($0) }) == true
            || (symbol.kind == .object && symbol.flags.contains(.synthetic)) {
            flags |= 1 << 13
        }
        let flagsExpr = arena.appendExpr(.intLiteral(flags), type: intType)
        instructions.append(.constValue(result: flagsExpr, value: .intLiteral(flags)))

        let fieldCount: Int64
        if let layout = sema.symbols.nominalLayout(for: objectSymbol) {
            fieldCount = Int64(layout.instanceFieldCount)
        } else {
            fieldCount = -1
        }
        let fieldCountExpr = arena.appendExpr(.intLiteral(fieldCount), type: intType)
        instructions.append(.constValue(result: fieldCountExpr, value: .intLiteral(fieldCount)))

        let memberCount: Int64
        if let layout = sema.symbols.nominalLayout(for: objectSymbol) {
            memberCount = Int64(layout.instanceFieldCount + layout.vtableSize)
        } else {
            memberCount = -1
        }
        let memberCountExpr = arena.appendExpr(.intLiteral(memberCount), type: intType)
        instructions.append(.constValue(result: memberCountExpr, value: .intLiteral(memberCount)))

        let constructorCount = Int64(sema.symbols.children(ofFQName: symbol.fqName).filter { child in
            sema.symbols.symbol(child)?.kind == .constructor
        }.count)
        let constructorCountExpr = arena.appendExpr(.intLiteral(constructorCount), type: intType)
        instructions.append(.constValue(result: constructorCountExpr, value: .intLiteral(constructorCount)))

        let registerResult = arena.appendTemporary(type: intType)
        instructions.append(.call(
            callee: interner.intern("__kk_kclass_register_metadata"),
            arguments: [typeTokenExpr, fqNameExpr, simpleNameExpr, supertypeNameExpr, flagsExpr, fieldCountExpr, memberCountExpr, constructorCountExpr],
            result: registerResult,
            canThrow: false
        ))
        emitKClassDisplayNameRegistration(
            symbol: objectSymbol, typeTokenExpr: typeTokenExpr,
            sema: sema, arena: arena, interner: interner, instructions: &instructions
        )
        emitKClassCompanionAndNestedRegistration(
            classSymbol: objectSymbol, typeTokenExpr: typeTokenExpr,
            sema: sema, arena: arena, interner: interner, instructions: &instructions
        )

        emitKClassAnnotationRegistration(
            objectSymbol: objectSymbol,
            typeTokenExpr: typeTokenExpr,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )

        // KUU-1448: construction also makes this class reachable through
        // `KType.classifier`/`__kk_kclass_of` handles, so its ancestors need
        // metadata too. Seeded with `objectSymbol` so a sealed ancestor's
        // subclass walk cannot re-emit this registration.
        var visitedClassSymbols: Set<SymbolID> = [objectSymbol]
        emitTransitiveSupertypeKClassMetadataRegistrations(
            for: objectSymbol,
            visitedClassSymbols: &visitedClassSymbols,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }
}
