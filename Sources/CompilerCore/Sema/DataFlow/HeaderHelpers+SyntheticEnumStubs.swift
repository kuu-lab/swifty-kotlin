
extension DataFlowSemaPhase {
    /// Registers synthetic enum type/container stubs: kotlin.Enum<T> and
    /// EnumEntries<T>. The top-level enum functions are bundled source
    /// declarations; their concrete calls are expanded by the enum-specific
    /// type checker/lowerer.
    func registerSyntheticEnumStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        if symbols.lookup(fqName: kotlinPkg) == nil {
            _ = symbols.define(
                kind: .package, name: interner.intern("kotlin"), fqName: kotlinPkg,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        let kotlinCollectionsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("collections")]
        if symbols.lookup(fqName: kotlinCollectionsPkg) == nil {
            _ = symbols.define(
                kind: .package, name: interner.intern("collections"), fqName: kotlinCollectionsPkg,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }
        let kotlinEnumsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("enums")]
        if symbols.lookup(fqName: kotlinEnumsPkg) == nil {
            _ = symbols.define(
                kind: .package, name: interner.intern("enums"), fqName: kotlinEnumsPkg,
                declSite: nil, visibility: .public, flags: [.synthetic]
            )
        }

        // Bootstrap kotlin.Enum<T> with name: String, ordinal: Int. KSP-732
        // and KSP-837 declare the nominal class and its six public members in
        // `Stdlib/kotlin/Enum.kt`; bundle loading reuses this shell and its
        // source-backed members replace the fallback properties below. Keep
        // the shell's type parameter in the TypeSystem so header collection
        // does not define a fresh, orphaned `kotlin.Enum.$<id>.T`.
        let enumName = interner.intern("Enum")
        let enumFQName = kotlinPkg + [enumName]
        let enumSymbol = ensureEnumClassSymbol(symbols: symbols, interner: interner, kotlinPkg: kotlinPkg)
        // KUU-2673: reading an imported shell's type parameters decodes it;
        // run the check after materialization instead.
        let ensureEnumTypeParameters = { [self] in
            if types.nominalTypeParameterSymbols(for: enumSymbol).isEmpty {
                let enumTypeParamSymbol = ensureEnumTypeParameter(symbols: symbols, interner: interner, enumFQName: enumFQName)
                types.setNominalTypeParameterSymbols([enumTypeParamSymbol], for: enumSymbol)
                types.setNominalTypeParameterVariances([.invariant], for: enumSymbol)
            }
        }
        if !symbols.deferUntilAfterImportedShellMaterializes(enumSymbol, work: ensureEnumTypeParameters) {
            ensureEnumTypeParameters()
        }
        // `Enum<T>` is `Comparable<T>` with a concrete final `compareTo`
        // (Stdlib/kotlin/Enum.kt). The synthetic shell used when that source
        // does not participate (JVM stdlib build, --no-stdlib) carried
        // neither, so the abstract-member completeness check believed every
        // enum entry still owed `compareTo` (KUU-3764).
        let registerComparableContract = { [self] in
            registerEnumComparableContract(
                symbols: symbols,
                types: types,
                interner: interner,
                enumSymbol: enumSymbol,
                enumFQName: enumFQName,
                kotlinPkg: kotlinPkg
            )
        }
        if !symbols.deferUntilAfterImportedShellMaterializes(enumSymbol, work: registerComparableContract) {
            registerComparableContract()
        }
        registerEnumNameOrdinalProperties(
            symbols: symbols,
            types: types,
            interner: interner,
            enumSymbol: enumSymbol,
            enumFQName: kotlinPkg + [interner.intern("Enum")]
        )

        let enumEntriesInterfaceSymbol = ensureEnumEntriesInterface(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinEnumsPkg: kotlinEnumsPkg,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )
        registerEnumEntriesGetOperator(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinEnumsPkg: kotlinEnumsPkg,
            enumEntriesSymbol: enumEntriesInterfaceSymbol
        )

    }

    private func ensureEnumClassSymbol(
        symbols: SymbolTable,
        interner: StringInterner,
        kotlinPkg: [InternedString]
    ) -> SymbolID {
        let enumName = interner.intern("Enum")
        let enumFQName = kotlinPkg + [enumName]
        if let existing = symbols.lookup(fqName: enumFQName) {
            return existing
        }
        let symbol = symbols.define(
            kind: .class,
            name: enumName,
            fqName: enumFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .abstractType]
        )
        if let pkg = symbols.lookup(fqName: kotlinPkg), pkg != .invalid {
            symbols.setParentSymbol(pkg, for: symbol)
        }
        return symbol
    }

    /// Mirrors the `Enum<T> : Comparable<T>` contract the source declaration
    /// carries: the nominal supertype edge plus a concrete `compareTo` member.
    /// Without them, supertype member-provider lookups cannot see `compareTo`
    /// as supplied by the Enum base and the enum-entry abstract-member check
    /// demands it from every entry.
    private func registerEnumComparableContract(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        enumSymbol: SymbolID,
        enumFQName: [InternedString],
        kotlinPkg: [InternedString]
    ) {
        guard let comparableSymbol = types.comparableInterfaceSymbol
            ?? symbols.lookup(fqName: kotlinPkg + [interner.intern("Comparable")])
        else { return }

        if !symbols.directSupertypes(for: enumSymbol).contains(comparableSymbol) {
            symbols.setDirectSupertypes(
                symbols.directSupertypes(for: enumSymbol) + [comparableSymbol],
                for: enumSymbol
            )
        }
        if !types.directNominalSupertypes(for: enumSymbol).contains(comparableSymbol) {
            types.setNominalDirectSupertypes(
                types.directNominalSupertypes(for: enumSymbol) + [comparableSymbol],
                for: enumSymbol
            )
        }

        guard let tParamSymbol = types.nominalTypeParameterSymbols(for: enumSymbol).first
        else { return }
        let tParamType = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
        if symbols.supertypeTypeArgs(for: enumSymbol, supertype: comparableSymbol).isEmpty {
            let comparableArgs: [TypeArg] = [.in(tParamType)]
            symbols.setSupertypeTypeArgs(comparableArgs, for: enumSymbol, supertype: comparableSymbol)
            types.setNominalSupertypeTypeArgs(comparableArgs, for: enumSymbol, supertype: comparableSymbol)
        }
        registerEnumCompareToMember(
            symbols: symbols,
            types: types,
            interner: interner,
            enumSymbol: enumSymbol,
            enumFQName: enumFQName,
            tParamSymbol: tParamSymbol,
            tParamType: tParamType
        )
    }

    /// Registers `final override fun compareTo(other: T): Int` on the
    /// synthetic `kotlin.Enum` shell — the member the bundled `Enum.kt`
    /// declares with `@KsSymbolName("kk_enum_compareTo")`. Skipped when a
    /// bundled or already-registered declaration owns the real member.
    private func registerEnumCompareToMember(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        enumSymbol: SymbolID,
        enumFQName: [InternedString],
        tParamSymbol: SymbolID,
        tParamType: TypeID
    ) {
        let compareToName = interner.intern("compareTo")
        let compareToFQName = enumFQName + [compareToName]
        guard !BundledSyntheticStubRegistration.bundledIndex.contains(
            ownerFQName: enumFQName,
            name: compareToName,
            arity: 1
        ), symbols.lookupAll(fqName: compareToFQName)
            .compactMap({ symbols.symbol($0) })
            .allSatisfy({ $0.kind != .function })
        else { return }

        let otherName = interner.intern("other")
        let otherParam = symbols.define(
            kind: .valueParameter,
            name: otherName,
            fqName: compareToFQName + [otherName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setPropertyType(tParamType, for: otherParam)
        let enumReceiver = types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [.invariant(tParamType)],
            nullability: .nonNull
        )))
        let compareToSymbol = symbols.define(
            kind: .function,
            name: compareToName,
            fqName: compareToFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction, .overrideMember, .finalMember]
        )
        symbols.setParentSymbol(enumSymbol, for: compareToSymbol)
        symbols.setParentSymbol(compareToSymbol, for: otherParam)
        symbols.setExternalLinkName("kk_enum_compareTo", for: compareToSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: enumReceiver,
                parameterTypes: [tParamType],
                returnType: types.intType,
                isSuspend: false,
                valueParameterSymbols: [otherParam],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false],
                typeParameterSymbols: [tParamSymbol],
                classTypeParameterCount: 1
            ),
            for: compareToSymbol
        )
    }

    private func ensureEnumTypeParameter(
        symbols: SymbolTable,
        interner: StringInterner,
        enumFQName: [InternedString]
    ) -> SymbolID {
        let tName = interner.intern("T")
        let tFQName = enumFQName + [tName]
        if let existing = symbols.lookup(fqName: tFQName) {
            return existing
        }
        return symbols.define(
            kind: .typeParameter,
            name: tName,
            fqName: tFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
    }

    private func registerEnumNameOrdinalProperties(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        enumSymbol: SymbolID,
        enumFQName: [InternedString]
    ) {
        let stringType = types.stringType
        let intType = types.make(.primitive(.int, .nonNull))

        func ensureProperty(name: String, returnType: TypeID) {
            let nameInterned = interner.intern(name)
            let fqName = enumFQName + [nameInterned]
            guard symbols.lookupAll(fqName: fqName).compactMap({ symbols.symbol($0) }).allSatisfy({ $0.kind != .property }) else {
                return
            }
            let propSymbol = symbols.define(
                kind: .property,
                name: nameInterned,
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(enumSymbol, for: propSymbol)
            symbols.setPropertyType(returnType, for: propSymbol)
        }

        ensureProperty(name: "name", returnType: stringType)
        ensureProperty(name: "ordinal", returnType: intType)
    }

    private func ensureEnumEntriesInterface(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinEnumsPkg: [InternedString],
        kotlinCollectionsPkg: [InternedString]
    ) -> SymbolID {
        let enumEntriesName = interner.intern("EnumEntries")
        let enumEntriesFQName = kotlinEnumsPkg + [enumEntriesName]
        let tParamName = interner.intern("T")
        let tParamFQName = enumEntriesFQName + [tParamName]

        let enumEntriesSymbol: SymbolID
        if let existing = symbols.lookup(fqName: enumEntriesFQName) {
            enumEntriesSymbol = existing
        } else {
            _ = symbols.define(
                kind: .typeParameter,
                name: tParamName,
                fqName: tParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            enumEntriesSymbol = symbols.define(
                kind: .interface,
                name: enumEntriesName,
                fqName: enumEntriesFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let pkg = symbols.lookup(fqName: kotlinEnumsPkg), pkg != .invalid {
                symbols.setParentSymbol(pkg, for: enumEntriesSymbol)
            }
        }

        // kotlin.enums.EnumEntries<T> : kotlin.collections.List<T> (Kotlin 1.9+:
        // `EnumClass.entries` is a read-only List<T>). Registering the
        // supertype relationship in both the SymbolTable and TypeSystem
        // nominal-supertype graphs (mirroring how List/Collection/Iterable
        // register their own supertypes, e.g. registerSyntheticListStub) lets
        // ordinary member-call resolution and the collection member-call
        // fallback find List's real members (.size, .forEach, etc.) on an
        // EnumEntries<T>-typed receiver instead of reporting "Unresolved
        // member function".
        guard let tParamSymbol = symbols.lookup(fqName: tParamFQName),
              let listInterfaceSymbol = symbols.lookupNominal(fqName: kotlinCollectionsPkg + [interner.intern("List")])
        else {
            return enumEntriesSymbol
        }
        let tParamType = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
        types.setNominalTypeParameterSymbols([tParamSymbol], for: enumEntriesSymbol)
        types.setNominalTypeParameterVariances([.out], for: enumEntriesSymbol)
        symbols.setDirectSupertypes([listInterfaceSymbol], for: enumEntriesSymbol)
        types.setNominalDirectSupertypes([listInterfaceSymbol], for: enumEntriesSymbol)
        symbols.setSupertypeTypeArgs([.out(tParamType)], for: enumEntriesSymbol, supertype: listInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.out(tParamType)], for: enumEntriesSymbol, supertype: listInterfaceSymbol)

        return enumEntriesSymbol
    }

    /// Registers `operator fun get(index: Int): T` on `EnumEntries<T>`.
    ///
    /// `EnumEntries<T>` has no declared members or supertypes (see
    /// `ensureEnumEntriesInterface`), so without an owned `get`, indexed access
    /// (`entries[0]`) finds no `operator fun get` candidate in Sema and the KIR
    /// indexed-access lowering falls back to the generic built-in path, which
    /// always emits `kk_array_get` regardless of the receiver's actual runtime
    /// representation. `entries`'s runtime representation is a `RuntimeListBox`
    /// (`kk_enum_make_entries_list_cached`), not a `RuntimeArrayBox`, so that
    /// fallback panics at runtime (BUG-178). EnumEntries uses a dedicated
    /// checked bridge because its get contract throws on an invalid index.
    private func registerEnumEntriesGetOperator(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinEnumsPkg: [InternedString],
        enumEntriesSymbol: SymbolID
    ) {
        let enumEntriesFQName = kotlinEnumsPkg + [interner.intern("EnumEntries")]
        let tParamFQName = enumEntriesFQName + [interner.intern("T")]
        guard let tParamSymbol = symbols.lookup(fqName: tParamFQName) else { return }

        let getName = interner.intern("get")
        let getFQName = enumEntriesFQName + [getName]
        guard symbols.lookup(fqName: getFQName) == nil else { return }

        let tParamType = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: enumEntriesSymbol,
            args: [.out(tParamType)],
            nullability: .nonNull
        )))
        let getSymbol = symbols.define(
            kind: .function,
            name: getName,
            fqName: getFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction, .throwingFunction]
        )
        symbols.setParentSymbol(enumEntriesSymbol, for: getSymbol)
        symbols.setExternalLinkName("__kk_enum_entries_get", for: getSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [types.intType],
                returnType: tParamType,
                canThrow: true,
                typeParameterSymbols: [tParamSymbol],
                classTypeParameterCount: 1
            ),
            for: getSymbol
        )
    }

    func collectSyntheticEnumEntryProperties(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope,
        interner: StringInterner
    ) {
        let stringType = types.stringType
        let intType = types.make(.primitive(.int, .nonNull))

        for (name, returnType) in [("name", stringType), ("ordinal", intType)] {
            let nameInterned = interner.intern(name)
            let fqName = ownerFQName + [nameInterned]
            guard symbols.lookupAll(fqName: fqName).compactMap({ symbols.symbol($0) }).allSatisfy({ $0.kind != .property }) else {
                continue
            }
            let propSymbol = symbols.define(
                kind: .property,
                name: nameInterned,
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ownerSymbol, for: propSymbol)
            symbols.setPropertyType(returnType, for: propSymbol)
            scope.insert(propSymbol)
        }
    }

    /// Registers the synthetic `values(): Array<T>` static factory on an enum
    /// class itself (e.g. `Direction.values()`), mirroring how real Kotlin
    /// exposes `values()` as a pseudo-static member of the enum class rather
    /// than its companion. Like `entries` (also registered on the enum class
    /// by `collectSyntheticEnumCompanionMembers`), and unlike `valueOf`
    /// (registered on the companion), `values()` is
    /// looked up directly under the enum class's own FQ name by the
    /// class-name-receiver static-call resolution path (see
    /// `inferRegularMemberCall`'s `staticMethodFQName` lookup), so its owner
    /// here must be `ownerSymbol` (the enum class), not the companion.
    ///
    /// The corresponding KIR function body is synthesized later by
    /// `DataEnumSealedSynthesisPass.appendSyntheticEnumValuesIfNeeded`, which
    /// reuses this exact symbol (by FQ name + owner) so the call resolved
    /// here at Sema time links to the KIR body generated during Lowering.
    /// Called from HeaderCollection when processing enum classes.
    func collectSyntheticEnumValuesMember(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        enumType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope,
        interner: StringInterner
    ) {
        let valuesName = interner.intern("values")
        // Source-backed enum extensions such as
        // `RequiresOptIn.Level.values()` own the class-name API. Do not add
        // the generated enum member as a duplicate in that case.
        guard !BundledSyntheticStubRegistration.bundledIndex.contains(
            ownerFQName: ownerFQName,
            name: valuesName,
            arity: 0
        ) else {
            return
        }
        let valuesFQName = ownerFQName + [valuesName]
        let existingFunctions = symbols.lookupAll(fqName: valuesFQName).compactMap { symbolID in
            symbols.symbol(symbolID).map { (symbolID, $0) }
        }.filter { $0.1.kind == .function }
        guard !existingFunctions.contains(where: { symbols.parentSymbol(for: $0.0) == ownerSymbol }) else {
            return
        }
        // Class-name lookup filters by exact owner, so transfer the common stub
        // when an actual enum follows the expect declaration.
        if symbols.symbol(ownerSymbol)?.flags.contains(.actualDeclaration) == true,
           let expectStub = existingFunctions.first(where: { candidate in
               guard candidate.1.flags.contains(.synthetic),
                     let parent = symbols.parentSymbol(for: candidate.0),
                     let parentSymbol = symbols.symbol(parent)
               else {
                   return false
               }
               return parentSymbol.flags.contains(.expectDeclaration)
           }) {
            symbols.setParentSymbol(ownerSymbol, for: expectStub.0)
            scope.insert(expectStub.0)
            return
        }
        guard existingFunctions.isEmpty else { return }
        let arrayFQName = [interner.intern("kotlin"), interner.intern("Array")]
        guard let arraySymbol = symbols.lookup(fqName: arrayFQName) else {
            return
        }
        let arrayType = types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.invariant(enumType)],
            nullability: .nonNull
        )))
        let funcSymbol = symbols.define(
            kind: .function,
            name: valuesName,
            fqName: valuesFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(ownerSymbol, for: funcSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: arrayType,
                isSuspend: false
            ),
            for: funcSymbol
        )
        scope.insert(funcSymbol)
    }

    /// Registers the synthetic enum API that Kotlin exposes through the enum
    /// class name: `valueOf` on the companion (`E.Companion.valueOf`, reached
    /// by `E.valueOf` through companion shorthand) and `entries` on the enum
    /// class itself (`E.entries`). Kotlin synthesizes `Enum.entries` directly
    /// on the enum class — it is never a companion member — so
    /// `E.Companion.entries` stays a user-declared member (or unresolved)
    /// while `E.entries` keeps returning the synthetic `EnumEntries` list
    /// even when a companion `val entries`, a nested `object entries`, or a
    /// constructor `val entries` exists. Those user declarations register
    /// first and keep winning member/instance lookups by declaration order;
    /// the qualified `E.entries` read resolves the `.static` synthetic
    /// instead (KUU-3544).
    func collectSyntheticEnumCompanionMembers(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        companionSymbol: SymbolID,
        companionFQName: [InternedString],
        enumType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        scope: Scope,
        interner: StringInterner
    ) {
        let stringType = types.stringType
        let companionType = types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))

        // valueOf(name: String): T — companion receiver so Color.valueOf resolves
        let valueOfName = interner.intern("valueOf")
        let valueOfFQName = companionFQName + [valueOfName]
        if symbols.lookupAll(fqName: valueOfFQName).compactMap({ symbols.symbol($0) }).allSatisfy({ $0.kind != .function }) {
            let paramName = interner.intern("name")
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: valueOfFQName + [paramName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            let funcSymbol = symbols.define(
                kind: .function,
                name: valueOfName,
                fqName: valueOfFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
            symbols.setParentSymbol(companionSymbol, for: funcSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: companionType,
                    parameterTypes: [stringType],
                    returnType: enumType,
                    isSuspend: false,
                    valueParameterSymbols: [paramSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false]
                ),
                for: funcSymbol
            )
            scope.insert(funcSymbol)
        }

        let enumEntriesName = interner.intern("EnumEntries")
        let enumEntriesFQName = [interner.intern("kotlin"), interner.intern("enums"), enumEntriesName]
        guard let enumEntriesSymbol = symbols.lookup(fqName: enumEntriesFQName) else { return }

        let entriesName = interner.intern("entries")
        let entriesFQName = ownerFQName + [entriesName]
        // Always synthesize `entries` on the enum class: Kotlin generates it
        // unconditionally and lets ordinary member-scope order shadow it, so a
        // user instance property (for example a primary-constructor
        // `val entries`) coexists with the synthetic and keeps winning
        // instance lookups. Only an already-registered static `entries` (an
        // imported or re-registered stub) suppresses a second definition.
        let hasStaticEntries = symbols.lookupAll(fqName: entriesFQName).contains { candidate in
            guard let candidateSymbol = symbols.symbol(candidate) else { return false }
            return candidateSymbol.kind == .property && candidateSymbol.flags.contains(.static)
        }
        if !hasStaticEntries {
            let entriesType = types.make(.classType(ClassType(
                classSymbol: enumEntriesSymbol,
                args: [.invariant(enumType)],
                nullability: .nonNull
            )))
            let propSymbol = symbols.define(
                kind: .property,
                name: entriesName,
                fqName: entriesFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
            // `define` may return an existing symbol at this FQName — only
            // annotate the one that is actually the synthetic stub so a
            // user-declared `entries` keeps its own type and ownership.
            if symbols.symbol(propSymbol)?.flags.contains(.synthetic) == true {
                symbols.setParentSymbol(ownerSymbol, for: propSymbol)
                symbols.setPropertyType(entriesType, for: propSymbol)
            }
        }
    }
}
