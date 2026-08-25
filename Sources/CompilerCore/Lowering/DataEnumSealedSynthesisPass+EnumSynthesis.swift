/// Enum synthesis methods: `values()`, `entries`, ordinal-to-name,
/// `valueOf(...)`, and the static-init function that materializes
/// enum entry singletons.
///
/// Split out from `DataEnumSealedSynthesisPass.swift`.
extension DataEnumSealedSynthesisPass {
    /// enum entry singletons.
    /// The body is: kk_array_new(count) -> kk_array_set for each entry -> kk_enum_make_values_array.
    func appendSyntheticEnumValuesIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        entries: [SemanticSymbol],
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))

        // Keep the public Kotlin signature as Array<Enum> in Sema and metadata;
        // the runtime array storage remains erased in the generated body.
        let enumType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let arrayFQName = [interner.intern("kotlin"), interner.intern("Array")]
        let returnType: TypeID = if let arraySymbol = sema.symbols.lookup(fqName: arrayFQName) {
            sema.types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(enumType)],
                nullability: .nonNull
            )))
        } else {
            sema.types.anyType
        }

        let signature = FunctionSignature(parameterTypes: [], returnType: returnType, isSuspend: false)

        var body: [KIRInstruction] = []
        let (arrayExpr, countExpr) = appendEnumOrdinalArrayCreation(
            enumClassSymbol: owner.id,
            entries: entries,
            intType: intType,
            body: &body,
            module: module,
            sema: sema,
            interner: interner
        )

        // kk_enum_make_values_array(array, count) -- result uses the enum type
        let listExpr = module.arena.appendTemporary(type: returnType
        )
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_enum_make_values_array"),
            arguments: [arrayExpr, countExpr],
            result: listExpr,
            canThrow: false,
            thrownResult: nil
        ))

        body.append(.returnValue(listExpr))

        // Use the existing stub symbol when Sema already registered `values`
        // directly on the enum class (collectSyntheticEnumValuesMember). Sema
        // resolves `Direction.values()` call sites to that symbol's ID during
        // type-checking, before this Lowering pass ever runs; calling
        // `appendSyntheticFunctionIfNeeded` unconditionally would re-invoke
        // `SymbolTable.define`, which mints a *second*, disconnected SymbolID
        // for the same (fqName, .function) pair (functions are allowed to
        // coexist as overloads), silently orphaning the already-resolved call
        // sites from the KIR body generated here. Mirrors how
        // `appendSyntheticEnumValueOfIfNeeded` reuses the companion's
        // Sema-registered `valueOf` stub below.
        let fqName = owner.fqName + [name]
        let existingValues = sema.symbols.lookupAll(fqName: fqName).first { candidate in
            guard let sym = sema.symbols.symbol(candidate),
                  sym.kind == .function,
                  sym.flags.contains(.synthetic),
                  sema.symbols.parentSymbol(for: candidate) == owner.id
            else { return false }
            return true
        }
        if let existingSymbol = existingValues, !existingFunctionSymbols.contains(existingSymbol) {
            appendSyntheticFunctionWithSymbol(
                functionSymbol: existingSymbol,
                name: name,
                module: module,
                sema: sema,
                signature: signature,
                params: [],
                body: body
            )
        } else {
            appendSyntheticFunctionIfNeeded(
                name: name,
                owner: owner,
                module: module,
                sema: sema,
                signature: signature,
                params: [],
                body: body,
                existingFunctionSymbols: existingFunctionSymbols
            )
        }
    }

    /// Synthesizes the `entries` getter on the companion object.
    /// `Color.entries` returns an EnumEntries (List) containing all enum entry singletons.
    /// The body is: kk_array_new(count) → kk_array_set for each entry → kk_enum_make_entries_list.
    func appendSyntheticEnumEntriesGetterIfNeeded(
        owner: SemanticSymbol,
        enumSymbol: SemanticSymbol,
        entries: [SemanticSymbol],
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let getterName = interner.intern("entries$get")

        // Preserve EnumEntries<Enum> for the public getter signature. Only the
        // generated runtime call itself uses erased collection storage.
        let enumType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol.id,
            args: [],
            nullability: .nonNull
        )))
        let enumEntriesFQName = [
            interner.intern("kotlin"),
            interner.intern("enums"),
            interner.intern("EnumEntries")
        ]
        let returnType: TypeID = if let enumEntriesSymbol = sema.symbols.lookup(fqName: enumEntriesFQName) {
            sema.types.make(.classType(ClassType(
                classSymbol: enumEntriesSymbol,
                args: [.invariant(enumType)],
                nullability: .nonNull
            )))
        } else {
            sema.types.anyType
        }

        let signature = FunctionSignature(parameterTypes: [], returnType: returnType, isSuspend: false)

        var body: [KIRInstruction] = []
        let (arrayExpr, countExpr) = appendEnumOrdinalArrayCreation(
            enumClassSymbol: enumSymbol.id,
            entries: entries,
            intType: intType,
            body: &body,
            module: module,
            sema: sema,
            interner: interner
        )

        // kk_enum_make_entries_list(array, count) -- returns List for EnumEntries
        let listExpr = module.arena.appendTemporary(type: returnType
        )
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_enum_make_entries_list"),
            arguments: [arrayExpr, countExpr],
            result: listExpr,
            canThrow: false,
            thrownResult: nil
        ))

        body.append(.returnValue(listExpr))

        appendSyntheticFunctionIfNeeded(
            name: getterName,
            owner: owner,
            module: module,
            sema: sema,
            signature: signature,
            params: [],
            body: body,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    private func appendEnumOrdinalArrayCreation(
        enumClassSymbol: SymbolID,
        entries: [SemanticSymbol],
        intType: TypeID,
        body: inout [KIRInstruction],
        module: KIRModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> (array: KIRExprID, count: KIRExprID) {
        let countExpr = module.arena.appendTemporary(type: intType
        )
        body.append(.constValue(result: countExpr, value: .intLiteral(Int64(entries.count))))

        let arrayExpr = module.arena.appendTemporary(type: sema.types.anyType
        )
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_array_new"),
            arguments: [countExpr],
            result: arrayExpr,
            canThrow: false,
            thrownResult: nil
        ))

        let stringType = sema.types.stringType
        let boxOrdinalCallee = interner.intern("kk_enum_box_ordinal")
        let classID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: enumClassSymbol,
            symbols: sema.symbols,
            interner: interner
        )
        let classIDExpr = module.arena.appendExpr(.intLiteral(classID), type: intType)
        body.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))

        for (ordinal, entry) in entries.enumerated() {
            let indexExpr = module.arena.appendTemporary(type: intType
            )
            body.append(.constValue(result: indexExpr, value: .intLiteral(Int64(ordinal))))

            let nameExpr = module.arena.appendExpr(.stringLiteral(entry.name), type: stringType)
            body.append(.constValue(result: nameExpr, value: .stringLiteral(entry.name)))

            // Box the ordinal (tagged with its declared name and the enum
            // class's stable nominal type ID, see kk_enum_box_ordinal) instead
            // of storing a pre-baked name string. Every other enum value is a
            // raw ordinal Int, so an element read back out of values()/entries
            // must round-trip through the same boxing/unboxing pair to behave
            // correctly for println, equality, and `when` -- storing the name
            // string outright broke all three (it only happened to look right
            // when the whole collection was printed generically).
            let boxedEntry = module.arena.appendTemporary(type: sema.types.anyType)
            body.append(.call(
                symbol: nil,
                callee: boxOrdinalCallee,
                arguments: [indexExpr, nameExpr, classIDExpr],
                result: boxedEntry,
                canThrow: false,
                thrownResult: nil
            ))

            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_array_set"),
                arguments: [arrayExpr, indexExpr, boxedEntry],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
        }

        return (arrayExpr, countExpr)
    }

    /// Synthesizes `$enumOrdinalToName$<encodedFqName>(ordinal: Int): String` for (valueOf result).name.
    /// Switches on ordinal and returns the entry name via the per-entry $enumName helpers.
    ///
    /// The bare name is suffixed with a length-prefixed encoding of the enum
    /// class's fully qualified name so it stays unique across every enum class
    /// in the module — `emitEnumOrdinalBoxCall` (KIRCallEmissionHelpers.swift)
    /// calls this helper by bare name (`symbol: nil`) from lowering passes that
    /// run *before* this one, when there is no Sema symbol yet to call by ID.
    func appendSyntheticEnumOrdinalToNameIfNeeded(
        owner: SemanticSymbol,
        entries: [SemanticSymbol],
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.stringType
        let name = NameMangler.enumOrdinalToNameHelperName(for: owner, interner: interner)
        let fqName = owner.fqName + [name]
        let paramName = interner.intern("$ordinal")
        let paramSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: paramName,
            fqName: fqName + [paramName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let param = KIRParameter(symbol: paramSymbol, type: intType)
        let paramRef = module.arena.appendExpr(.symbolRef(paramSymbol), type: intType)
        var body: [KIRInstruction] = []
        body.append(.constValue(result: paramRef, value: .symbolRef(paramSymbol)))
        let unboxedOrdinalRef = emitNonThrowingCall(
            callee: ABILoweringPass.primitiveUnboxingCallee(for: .int, interner: interner),
            arg: paramRef,
            resultType: intType,
            arena: module.arena,
            into: &body
        )
        var labelCounter: Int32 = 6000

        for (ordinal, entry) in entries.enumerated() {
            let helperName = NameMangler.enumEntryNameHelperName(for: entry, interner: interner)
            let resultExpr = module.arena.appendTemporary(type: stringType
            )
            let ordinalExpr = module.arena.appendExpr(
                .intLiteral(Int64(ordinal)),
                type: intType
            )
            body.append(.constValue(result: ordinalExpr, value: .intLiteral(Int64(ordinal))))
            let nextLabel = labelCounter
            labelCounter += 1
            let matchLabel = labelCounter
            labelCounter += 1
            body.append(.jumpIfEqual(lhs: unboxedOrdinalRef, rhs: ordinalExpr, target: matchLabel))
            body.append(.jump(nextLabel))
            body.append(.label(matchLabel))
            body.append(.call(
                symbol: nil,
                callee: helperName,
                arguments: [],
                result: resultExpr,
                canThrow: false,
                thrownResult: nil
            ))
            body.append(.returnValue(resultExpr))
            body.append(.label(nextLabel))
        }
        let emptyExpr = module.arena.appendExpr(
            .stringLiteral(interner.intern("")),
            type: stringType
        )
        body.append(.constValue(result: emptyExpr, value: .stringLiteral(interner.intern(""))))
        body.append(.returnValue(emptyExpr))

        let signature = FunctionSignature(
            parameterTypes: [intType],
            returnType: stringType,
            isSuspend: false,
            valueParameterSymbols: [paramSymbol],
            valueParameterHasDefaultValues: [false],
            valueParameterIsVararg: [false]
        )
        appendSyntheticFunctionIfNeeded(
            name: name,
            owner: owner,
            module: module,
            sema: sema,
            signature: signature,
            params: [param],
            body: body,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    /// Synthesizes `valueOf(String)` which does a linear comparison of the
    /// argument against each entry name and returns the matching ordinal.
    /// If no match is found, it calls `kk_enum_valueOf_throw` to signal an
    /// IllegalArgumentException. When owner is the companion, uses the stub's
    /// symbol so Color.valueOf resolves to the same KIR function.
    func appendSyntheticEnumValueOfIfNeeded(
        name: InternedString,
        owner: SemanticSymbol,
        enumName: String,
        enumType: TypeID,
        entries: [SemanticSymbol],
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        let stringType = sema.types.stringType

        let fqName = owner.fqName + [name]
        let parameterName = interner.intern("$name")
        let parameterSymbol = sema.symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: fqName + [parameterName],
            declSite: owner.declSite,
            visibility: .private,
            flags: [.synthetic]
        )
        let parameter = KIRParameter(symbol: parameterSymbol, type: stringType)
        let paramRef = module.arena.appendExpr(
            .symbolRef(parameterSymbol),
            type: stringType
        )

        var body: [KIRInstruction] = []
        body.append(.constValue(result: paramRef, value: .symbolRef(parameterSymbol)))

        var labelCounter: Int32 = 5000

        // For each entry, compare name and return ordinal if matched
        for (ordinal, entry) in entries.enumerated() {
            let entryNameStr = interner.intern(interner.resolve(entry.name))
            let entryNameExpr = module.arena.appendExpr(
                .stringLiteral(entryNameStr),
                type: stringType
            )
            body.append(.constValue(result: entryNameExpr, value: .stringLiteral(entryNameStr)))

            let boxedCmpResult = module.arena.appendTemporary(type: sema.types.anyType)
            let cmpCallee = interner.intern("kk_string_equals_flat")
            body.append(.call(
                symbol: nil,
                callee: cmpCallee,
                arguments: [paramRef, entryNameExpr],
                result: boxedCmpResult,
                canThrow: false,
                thrownResult: nil
            ))

            let cmpResult = module.arena.appendTemporary(
                type: sema.types.make(.primitive(.boolean, .nonNull))
            )
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_unbox_bool"),
                arguments: [boxedCmpResult],
                result: cmpResult,
                canThrow: false,
                thrownResult: nil
            ))

            let falseExpr = module.arena.appendExpr(
                .boolLiteral(false),
                type: sema.types.make(.primitive(.boolean, .nonNull))
            )
            body.append(.constValue(result: falseExpr, value: .boolLiteral(false)))

            let nextLabel = labelCounter
            labelCounter += 1

            body.append(.jumpIfEqual(lhs: cmpResult, rhs: falseExpr, target: nextLabel))

            // Match found – return ordinal (enum values are represented as ordinals)
            let ordinalExpr = module.arena.appendExpr(
                .intLiteral(Int64(ordinal)),
                type: enumType
            )
            body.append(.constValue(result: ordinalExpr, value: .intLiteral(Int64(ordinal))))
            body.append(.returnValue(ordinalExpr))

            body.append(.label(nextLabel))
        }

        // No match – build "ClassName." + name and call throw helper.
        // Kotlin throws: IllegalArgumentException: No enum constant ClassName.value
        let prefixInterned = interner.intern("\(enumName).")
        let prefixExpr = module.arena.appendExpr(
            .stringLiteral(prefixInterned),
            type: stringType
        )
        body.append(.constValue(result: prefixExpr, value: .stringLiteral(prefixInterned)))

        let qualifiedNameExpr = module.arena.appendTemporary(type: stringType
        )
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_string_concat_flat"),
            arguments: [prefixExpr, paramRef],
            result: qualifiedNameExpr,
            canThrow: false,
            thrownResult: nil
        ))

        let throwCallee = interner.intern("kk_enum_valueOf_throw")
        let throwResult = module.arena.appendTemporary(type: sema.types.nothingType
        )
        body.append(.call(
            symbol: nil,
            callee: throwCallee,
            arguments: [qualifiedNameExpr],
            result: throwResult,
            canThrow: true,
            thrownResult: nil
        ))
        body.append(.returnValue(throwResult))

        let companionType = sema.types.make(.classType(ClassType(
            classSymbol: owner.id,
            args: [],
            nullability: .nonNull
        )))
        let signature = FunctionSignature(
            receiverType: companionType,
            parameterTypes: [stringType],
            returnType: enumType,
            isSuspend: false,
            valueParameterSymbols: [parameterSymbol],
            valueParameterHasDefaultValues: [false],
            valueParameterIsVararg: [false]
        )

        // Use existing stub symbol when companion has valueOf from Sema
        let existingValueOf = sema.symbols.lookupAll(fqName: fqName).first { candidate in
            guard let sym = sema.symbols.symbol(candidate),
                  sym.kind == .function,
                  sym.flags.contains(.synthetic),
                  sema.symbols.parentSymbol(for: candidate) == owner.id
            else { return false }
            return true
        }
        if let existingSymbol = existingValueOf, !existingFunctionSymbols.contains(existingSymbol) {
            let receiverParam = KIRParameter(
                symbol: sema.symbols.define(
                    kind: .valueParameter,
                    name: interner.intern("$self"),
                    fqName: fqName + [interner.intern("$self")],
                    declSite: owner.declSite,
                    visibility: .private,
                    flags: [.synthetic]
                ),
                type: companionType
            )
            appendSyntheticFunctionWithSymbol(
                functionSymbol: existingSymbol,
                name: name,
                module: module,
                sema: sema,
                signature: signature,
                params: [receiverParam, parameter],
                body: body
            )
        } else {
            let receiverParam = KIRParameter(
                symbol: sema.symbols.define(
                    kind: .valueParameter,
                    name: interner.intern("$self"),
                    fqName: fqName + [interner.intern("$self")],
                    declSite: owner.declSite,
                    visibility: .private,
                    flags: [.synthetic]
                ),
                type: companionType
            )
            appendSyntheticFunctionIfNeeded(
                name: name,
                owner: owner,
                module: module,
                sema: sema,
                signature: signature,
                params: [receiverParam, parameter],
                body: body,
                existingFunctionSymbols: existingFunctionSymbols
            )
        }
    }

    /// Synthesizes `__enum_static_init_<ClassName>()` which initialises the
    /// global slots for each enum entry with their ordinal values, and ensures
    /// KIRGlobal declarations exist so that codegen allocates LLVM global
    /// variables for the entries. These globals model ordinal storage, so the
    /// slot declarations and writes must stay typed as `Int`.
    func appendSyntheticEnumStaticInitIfNeeded(
        owner: SemanticSymbol,
        entries: [SemanticSymbol],
        module: KIRModule,
        sema: SemaModule,
        existingFunctionSymbols: Set<SymbolID>,
        interner: StringInterner
    ) {
        guard !entries.isEmpty else { return }

        let intType = sema.types.make(.primitive(.int, .nonNull))
        // Collect existing global symbols so we don't create duplicates.
        var existingGlobalSymbols = Set(module.arena.declarations.compactMap { decl -> SymbolID? in
            guard case let .global(global) = decl else {
                return nil
            }
            return global.symbol
        })

        // Ensure a KIRGlobal exists for every entry field. BuildKIR emits these
        // for `enumEntryDecl` nodes, but when the enum class comes from a
        // nominalType-only module (e.g. library metadata) the globals may be
        // absent. Adding them here is idempotent thanks to the guard.
        for entry in entries {
            // swiftlint:disable:next for_where
            if !existingGlobalSymbols.contains(entry.id) {
                _ = module.arena.appendDecl(.global(KIRGlobal(symbol: entry.id, type: intType)))
                existingGlobalSymbols.insert(entry.id)
            }
        }

        // Build the static initialiser body.
        let ownerName = interner.resolve(owner.name)
        let initName = interner.intern("__enum_static_init_\(ownerName)")

        var body: [KIRInstruction] = []

        for (ordinal, entry) in entries.enumerated() {
            // Produce the ordinal value.
            let ordinalExpr = module.arena.appendExpr(
                .intLiteral(Int64(ordinal)),
                type: intType
            )
            body.append(.constValue(result: ordinalExpr, value: .intLiteral(Int64(ordinal))))

            // Reference the entry's global slot.
            let entryRef = module.arena.appendExpr(
                .symbolRef(entry.id),
                type: intType
            )
            body.append(.constValue(result: entryRef, value: .symbolRef(entry.id)))

            // Store ordinal into the global slot.
            body.append(.copy(from: ordinalExpr, to: entryRef))
        }

        // Register supertype edges so boxed enum values can answer `is`/`as`
        // against kotlin.Enum and implemented interfaces (e.g. Comparable).
        let classIDValue = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: owner.id, sema: sema, interner: interner
        )
        let classIDExpr = module.arena.appendExpr(.intLiteral(classIDValue), type: intType)
        body.append(.constValue(result: classIDExpr, value: .intLiteral(classIDValue)))
        let kotlinPkg = [interner.intern("kotlin")]
        var extraEnumSupers: [SymbolID] = []
        if let enumBaseSymbol = sema.symbols.lookup(fqName: kotlinPkg + [interner.intern("Enum")]) {
            extraEnumSupers.append(enumBaseSymbol)
        }
        if let comparableSymbol = sema.types.comparableInterfaceSymbol {
            extraEnumSupers.append(comparableSymbol)
        }
        for superSymbol in sema.symbols.directSupertypes(for: owner.id) + extraEnumSupers {
            let parentTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                symbol: superSymbol, sema: sema, interner: interner
            )
            guard parentTypeID != 0 else { continue }
            let parentExpr = module.arena.appendExpr(.intLiteral(parentTypeID), type: intType)
            body.append(.constValue(result: parentExpr, value: .intLiteral(parentTypeID)))
            let registerResult = module.arena.appendTemporary(type: intType)
            let superKind = sema.symbols.symbol(superSymbol)?.kind
            let registerCallee: InternedString = if superKind == .interface {
                interner.intern("kk_type_register_iface")
            } else {
                interner.intern("kk_type_register_super")
            }
            body.append(.call(
                symbol: nil,
                callee: registerCallee,
                arguments: [classIDExpr, parentExpr],
                result: registerResult,
                canThrow: false,
                thrownResult: nil
            ))
        }

        body.append(.returnUnit)

        let unitType = sema.types.unitType
        let signature = FunctionSignature(parameterTypes: [], returnType: unitType, isSuspend: false)

        appendSyntheticFunctionIfNeeded(
            name: initName,
            owner: owner,
            module: module,
            sema: sema,
            signature: signature,
            params: [],
            body: body,
            existingFunctionSymbols: existingFunctionSymbols
        )
    }

    /// Appends a KIR function using an existing symbol (e.g. from Sema). Used when the symbol
    /// was already registered for resolution so call sites bind to the same symbol.
}
