import Foundation

extension DataFlowSemaPhase {
    func predeclareImportedPropertyAccessorShells(
        _ binding: ImportedLibraryBinding,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [(property: SymbolID, symbol: SymbolID, fqName: String, externalLinkName: String, isGetter: Bool)] {
        let record = binding.record
        let baseFQName = binding.qualifiedNameString
            ?? record.fqName.map { interner.resolve($0) }.joined(separator: ".")
        var accessors: [(property: SymbolID, symbol: SymbolID, fqName: String, externalLinkName: String, isGetter: Bool)] = []

        func predeclare(
            suffix: String,
            shortName: String,
            visibility: Visibility,
            externalLinkName: String,
            isGetter: Bool
        ) {
            let fqName = record.fqName + [interner.intern(suffix)]
            let symbol = symbols.lookupAll(fqName: fqName)
                .first(where: { symbols.symbol($0)?.kind == .function })
                ?? symbols.define(
                    kind: .function,
                    name: interner.intern(shortName),
                    fqName: fqName,
                    declSite: nil,
                    visibility: visibility,
                    flags: [.synthetic, .importedLibrary]
                )
            symbols.setParentSymbol(binding.symbol, for: symbol)
            symbols.setAccessorOwnerProperty(binding.symbol, for: symbol)
            if isGetter {
                symbols.setExtensionPropertyGetterAccessor(symbol, for: binding.symbol)
            } else {
                symbols.setExtensionPropertySetterAccessor(symbol, for: binding.symbol)
            }
            symbols.setExternalLinkName(externalLinkName, for: symbol)
            if binding.isStdlibArtifact { symbols.markImportedStdlibSymbol(symbol) }
            accessors.append((binding.symbol, symbol, "\(baseFQName).\(suffix)", externalLinkName, isGetter))
        }

        if let getterLink = record.propertyGetterExternalLinkName, !getterLink.isEmpty {
            predeclare(
                suffix: "$get",
                shortName: "get",
                visibility: record.propertyReceiverTypeSignature == nil ? record.visibility : .public,
                externalLinkName: getterLink,
                isGetter: true
            )
        }
        if record.isMutable,
           let setterLink = record.propertySetterExternalLinkName,
           !setterLink.isEmpty
        {
            predeclare(
                suffix: "$set",
                shortName: "set",
                visibility: .public,
                externalLinkName: setterLink,
                isGetter: false
            )
        }
        return accessors
    }

    /// Returns the symbols sorted by index order (T0, T1, T2, ...) matching the
    /// original generic parameter list.
    private func collectSyntheticTypeParameters(_ typeID: TypeID, types: TypeSystem) -> [SymbolID] {
        var collected: Set<SymbolID> = []
        collectSyntheticTypeParamsRecursive(typeID, types: types, base: Self.syntheticTypeParameterBase, into: &collected)
        return collected.sorted { $0.rawValue > $1.rawValue }
    }

    private func collectSyntheticTypeParamsRecursive(
        _ typeID: TypeID,
        types: TypeSystem,
        base: Int32,
        into collected: inout Set<SymbolID>
    ) {
        switch types.kind(of: typeID) {
        case let .typeParam(tp):
            if tp.symbol.rawValue <= base { collected.insert(tp.symbol) }
        case let .classType(ct):
            collectSyntheticParamsFromClassArgs(ct.args, types: types, base: base, into: &collected)
        case let .functionType(ft):
            collectSyntheticParamsFromFunctionType(ft, types: types, base: base, into: &collected)
        case let .intersection(parts):
            for part in parts {
                collectSyntheticTypeParamsRecursive(part, types: types, base: base, into: &collected)
            }
        case let .kClassType(kc):
            collectSyntheticTypeParamsRecursive(kc.argument, types: types, base: base, into: &collected)
        case .stringStruct, .primitive, .any, .unit, .nullableUnit, .platformUnit, .nothing, .error:
            break
        }
    }

    private func collectSyntheticParamsFromClassArgs(
        _ args: [TypeArg],
        types: TypeSystem,
        base: Int32,
        into collected: inout Set<SymbolID>
    ) {
        for arg in args {
            switch arg {
            case let .invariant(inner), let .out(inner), let .in(inner):
                collectSyntheticTypeParamsRecursive(inner, types: types, base: base, into: &collected)
            case .star:
                break
            }
        }
    }

    private func collectSyntheticParamsFromFunctionType(
        _ ft: FunctionType,
        types: TypeSystem,
        base: Int32,
        into collected: inout Set<SymbolID>
    ) {
        for contextReceiver in ft.contextReceivers {
            collectSyntheticTypeParamsRecursive(contextReceiver, types: types, base: base, into: &collected)
        }
        if let receiver = ft.receiver {
            collectSyntheticTypeParamsRecursive(receiver, types: types, base: base, into: &collected)
        }
        for param in ft.params {
            collectSyntheticTypeParamsRecursive(param, types: types, base: base, into: &collected)
        }
        collectSyntheticTypeParamsRecursive(ft.returnType, types: types, base: base, into: &collected)
    }

    func applyImportedBinding(
        _ binding: ImportedLibraryBinding,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        importedInlineFunctions: ImportedInlineFunctionStore,
        pendingSupertypeEdges: inout [(subtype: SymbolID, superFQName: [InternedString])],
        cache: LibraryMetadataCache?,
        isStdlibArtifact: Bool,
        phantomTypeParameterSymbols: [SymbolID] = []
    ) {
        binding.materialize()
        let record = binding.record
        let symbol = binding.symbol

        applyImportedBindingMetadata(record, symbol: symbol, symbols: symbols)

        if !record.annotations.isEmpty {
            symbols.setAnnotations(record.annotations, for: symbol)
        }

        applyImportedCallableMetadata(
            binding,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            importedInlineFunctions: importedInlineFunctions,
            cache: cache,
            isStdlibArtifact: isStdlibArtifact,
            phantomTypeParameterSymbols: phantomTypeParameterSymbols
        )
        applyImportedValueClassMetadata(
            binding,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            isStdlibArtifact: isStdlibArtifact
        )
        applyImportedTypeAliasMetadata(
            binding,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            cache: cache,
            isStdlibArtifact: isStdlibArtifact
        )
        applyImportedNominalMetadata(
            binding,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            cache: cache,
            isStdlibArtifact: isStdlibArtifact,
            pendingSupertypeEdges: &pendingSupertypeEdges
        )
    }

    private func applyImportedBindingMetadata(
        _ record: ImportedLibrarySymbolRecord,
        symbol: SymbolID,
        symbols: SymbolTable
    ) {
        if let linkName = record.externalLinkName, !linkName.isEmpty {
            symbols.setExternalLinkName(linkName, for: symbol)
        }
        restoreImportedParentSymbol(record, symbol: symbol, symbols: symbols)
    }

    func restoreImportedParentSymbol(
        _ record: ImportedLibrarySymbolRecord,
        symbol: SymbolID,
        symbols: SymbolTable
    ) {
        guard record.kind == .function || record.kind == .property || record.kind == .field
              || record.kind == .backingField || record.kind == .constructor
              || isNominalLayoutTargetSymbol(record.kind),
              record.fqName.count >= 2
        else {
            return
        }

        let ownerFQName = Array(record.fqName.dropLast())
        let ownerCandidates = symbols.lookupAll(fqName: ownerFQName).compactMap { symbols.symbol($0) }
        let nominalOwners = ownerCandidates.filter { isNominalLayoutTargetSymbol($0.kind) }
        // A source declaration can shadow an imported nominal at the same
        // fqName. Imported members still belong to the imported nominal;
        // attaching them to the shadowing source class would merge two
        // different member tables under one owner.
        let ownerSymbol = preferredNominalOwnerSymbol(
            among: nominalOwners, forMember: symbol, symbols: symbols
        )
        if let ownerSymbol {
            symbols.setParentSymbol(ownerSymbol, for: symbol)
        } else if (record.receiverOwnerFQName != nil || record.propertyReceiverTypeSignature != nil
                   || isNominalLayoutTargetSymbol(record.kind)),
                  let packageOwner = ownerCandidates.first(where: { $0.kind == .package })
        {
            // A package parent is semantically required for extension lookup.
            // Ordinary top-level declarations intentionally stay parentless,
            // matching eager import where package shells do not exist yet.
            symbols.setParentSymbol(packageOwner.id, for: symbol)
        }
    }

    /// Nominal owner for a member record at `fqName`. Imported members prefer
    /// the imported nominal so a shadowing source class does not absorb them;
    /// when no imported nominal exists they get no nominal owner at all.
    func preferredNominalOwnerSymbol(
        among nominalOwners: [SemanticSymbol],
        forMember member: SymbolID,
        symbols: SymbolTable
    ) -> SymbolID? {
        guard symbols.symbol(member)?.flags.contains(.importedLibrary) == true else {
            return nominalOwners.first?.id
        }
        return nominalOwners.first(where: { $0.flags.contains(.importedLibrary) })?.id
    }

    private func applyImportedCallableMetadata(
        _ binding: ImportedLibraryBinding,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        importedInlineFunctions: ImportedInlineFunctionStore,
        cache: LibraryMetadataCache?,
        isStdlibArtifact: Bool = false,
        phantomTypeParameterSymbols: [SymbolID] = []
    ) {
        let record = binding.record
        let symbol = binding.symbol

        if record.kind == .function || record.kind == .constructor {
            let signature = importedFunctionSignature(
                record: record,
                ownerSymbol: symbol,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                metadataPath: binding.metadataPath,
                cache: cache,
                allowPlaceholders: isStdlibArtifact,
                phantomTypeParameterSymbols: phantomTypeParameterSymbols,
                phantomTypeParameterSymbolCount: binding.deferredPhantomTypeParameterSymbolCount,
                phantomTypeParameterSymbolsProvider: binding.deferredPhantomTypeParameterSymbolCount > 0
                    ? { binding.materializeDeferredPhantomTypeParameterSymbols() }
                    : nil,
                isStdlibArtifact: isStdlibArtifact
            )
            let usesLegacyABI = symbols.symbol(symbol)?.flags.contains(.legacyReifiedClassTokenABI) == true
            let hasReferenceVararg = signature.parameterTypes.indices.contains { index in
                guard signature.valueParameterIsVararg.indices.contains(index), signature.valueParameterIsVararg[index] else { return false }
                if case .primitive(_, .nonNull) = types.kind(of: signature.parameterTypes[index]) { return false }
                return true
            }
            if usesLegacyABI, hasReferenceVararg, CallLowerer.isSourceBackedLinkName(record.externalLinkName) {
                diagnostics.error(
                    "KSWIFTK-LIB-0034",
                    "Source reference-vararg storage ABI is incompatible; rebuild the library with this compiler.",
                    range: nil
                )
                return
            }
            symbols.setFunctionSignature(signature, for: symbol)
            // Extension functions are represented as package-level FQ names in
            // metadata, but source compilation attaches them to their nominal
            // receiver for member fallback/dispatch lookup. Reconstruct that
            // ownership from the decoded receiver type so imported stdlib
            // extensions (for example Sequence.chunked/windowed) follow the
            // same resolution path as bundled source declarations.
            if !record.isMemberExtension,
               let receiverType = signature.receiverType,
               case let .classType(receiverClassType) = types.kind(of: types.makeNonNullable(receiverType)),
               let receiverSymbol = symbols.symbol(receiverClassType.classSymbol),
               isNominalLayoutTargetSymbol(receiverSymbol.kind)
            {
                symbols.setParentSymbol(receiverSymbol.id, for: symbol)
            }
            if let defaultStubLink = record.defaultStubExternalLinkName, !defaultStubLink.isEmpty,
               signature.valueParameterHasDefaultValues.contains(true)
            {
                let stubSymbol = SyntheticSymbolScheme.defaultStubSymbol(for: symbol)
                symbols.setExternalLinkName(defaultStubLink, for: stubSymbol)
                let intType = types.intType
                let reifiedCount = signature.reifiedTypeParameterIndices.count
                    * (usesLegacyABI || !CallLowerer.isSourceBackedLinkName(record.externalLinkName) ? 1 : 2)
                var stubReceiverType = signature.receiverType
                var stubLeadingParameters: [TypeID] = []
                if record.isMemberExtension,
                   let owner = symbols.parentSymbol(for: symbol)
                {
                    let ownerArgs: [TypeArg] = signature.typeParameterSymbols
                        .prefix(signature.classTypeParameterCount)
                        .map { .invariant(types.make(.typeParam(TypeParamType(symbol: $0, nullability: .nonNull)))) }
                    stubLeadingParameters.append(types.make(.classType(ClassType(
                        classSymbol: owner, args: ownerArgs, nullability: .nonNull
                    ))))
                    stubLeadingParameters.append(contentsOf: [signature.receiverType].compactMap { $0 })
                    stubReceiverType = nil
                }
                let stubParameterTypes = stubLeadingParameters + signature.parameterTypes
                    + Array(repeating: intType, count: reifiedCount) + [intType]
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: stubReceiverType,
                        parameterTypes: stubParameterTypes,
                        returnType: signature.returnType,
                        isSuspend: false,
                        canThrow: signature.canThrow,
                        valueParameterHasDefaultValues: [],
                        valueParameterIsVararg: Array(repeating: false, count: stubLeadingParameters.count)
                            + signature.valueParameterIsVararg
                            + Array(repeating: false, count: reifiedCount + 1),
                        typeParameterSymbols: signature.typeParameterSymbols,
                        reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices
                    ),
                    for: stubSymbol
                )
                if record.isInline, let inlineDir = binding.inlineKIRDir {
                    let directory = URL(fileURLWithPath: inlineDir).resolvingSymlinksInPath().standardizedFileURL
                    let path = directory.appendingPathComponent(
                        MetadataEncoder.inlineKIRFileName(for: defaultStubLink)
                    ).resolvingSymlinksInPath().standardizedFileURL.path
                    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
                    // Older libraries may have only a native default stub.
                    if path.hasPrefix(directory.path + "/"), attributes?[.type] as? FileAttributeType == .typeRegular {
                        importedInlineFunctions.register(
                            ImportedInlineFunctionStore.Descriptor(
                                path: path, signature: symbols.functionSignature(for: stubSymbol),
                                name: interner.intern(interner.resolve(record.fqName.last ?? interner.intern("_")) + "$default"),
                                // Stub signature already contains explicit
                                // hidden Int words/mask; only physical value
                                // storage needs replacement, after its leading
                                // member-extension parameters. The receiver
                                // remains the signature's separate first slot.
                                packedValueParameterTypes: importedInlinePackedValueTypes(
                                    signature, binding: binding, symbol: symbol,
                                    symbols: symbols, types: types, interner: interner
                                ).map { packed in
                                    stubLeadingParameters + packed
                                        + Array(repeating: intType, count: reifiedCount) + [intType]
                                }
                            ), for: stubSymbol
                        )
                    }
                }
            }
            if let abiSig = record.abiReturnTypeSignature,
               let abiReturnType = decodeImportedTypeSignature(
                   token: abiSig,
                   symbols: symbols,
                   types: types,
                   interner: interner,
                   diagnostics: diagnostics,
                   metadataPath: binding.metadataPath,
                   ownerFQName: record.fqName,
                   cache: cache,
                   allowPlaceholders: isStdlibArtifact
               )
            {
                symbols.setFunctionABIReturnType(abiReturnType, for: symbol)
            }
            importInlineFunctionIfNeeded(
                binding,
                symbol: symbol,
                signature: signature, symbols: symbols, types: types,
                diagnostics: diagnostics,
                interner: interner,
                importedInlineFunctions: importedInlineFunctions
            )
            return
        }

        guard record.kind == .property || record.kind == .field else {
            return
        }
        let propertyType = importedPropertyType(
            record: record,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            metadataPath: binding.metadataPath,
            cache: cache,
            allowPlaceholders: isStdlibArtifact
        )
        symbols.setPropertyType(propertyType, for: symbol)

        // `const val` values are inlined at every use site, so carry the literal
        // across the library boundary instead of reading the (never initialized)
        // global slot of a precompiled library.
        if let constValueLiteral = record.constValueLiteral,
           let constValue = MetadataConstValueCoder.decode(constValueLiteral, interner: { interner.intern($0) })
        {
            symbols.setConstValueExprKind(constValue, for: symbol)
            // Both metadata encoders reserve property const literals for
            // declarations that carry the const contract.
            if record.kind == .property, !record.isMutable {
                symbols.insertFlags(.constValue, for: symbol)
            }
        }

        // Extension properties are compiled as precompiled getter functions in
        // the artifact objects; we synthesize the accessor symbol and point it
        // at that link name.
        if let receiverSig = record.propertyReceiverTypeSignature,
           let receiverType = decodeImportedTypeSignature(
               token: receiverSig,
               symbols: symbols,
               types: types,
               interner: interner,
               diagnostics: diagnostics,
               metadataPath: binding.metadataPath,
               ownerFQName: record.fqName,
               cache: cache,
               allowPlaceholders: isStdlibArtifact
           )
        {
            symbols.setExtensionPropertyReceiverType(receiverType, for: symbol)

            var propertyTypeParameters = record.callableTypeParameterSignatures.compactMap { token -> SymbolID? in
                guard let decoded = decodeImportedTypeSignature(
                    token: token, symbols: symbols, types: types, interner: interner,
                    diagnostics: diagnostics, metadataPath: binding.metadataPath, ownerFQName: record.fqName,
                    cache: cache, allowPlaceholders: isStdlibArtifact
                ), case let .typeParam(parameter) = types.kind(of: decoded) else { return nil }
                return parameter.symbol
            }
            let ownerParameters = symbols.parentSymbol(for: symbol).map { types.nominalTypeParameterSymbols(for: $0) } ?? []
            let ownerParameterCount = record.isMemberExtension ? min(ownerParameters.count, propertyTypeParameters.count) : 0
            if ownerParameterCount > 0 {
                propertyTypeParameters.replaceSubrange(0 ..< ownerParameterCount, with: ownerParameters.prefix(ownerParameterCount))
            }
            let propertyUpperBounds = propertyTypeParameters.indices.map { index -> [TypeID] in
                guard record.typeParameterUpperBoundsSignatures.indices.contains(index) else { return [] }
                return record.typeParameterUpperBoundsSignatures[index].compactMap {
                    guard let bound = decodeImportedTypeSignature(
                        token: $0, symbols: symbols, types: types, interner: interner,
                        diagnostics: diagnostics, metadataPath: binding.metadataPath, ownerFQName: record.fqName,
                        cache: cache, allowPlaceholders: isStdlibArtifact
                    ) else { return nil }
                    return normalizeImportedOwnerTypeParameters(
                        bound, record: record, symbols: symbols, types: types,
                        diagnostics: diagnostics, interner: interner, metadataPath: binding.metadataPath,
                        cache: cache, allowPlaceholders: isStdlibArtifact
                    )
                }
            }
            for (parameter, bounds) in zip(propertyTypeParameters, propertyUpperBounds) {
                if !bounds.isEmpty { symbols.setTypeParameterUpperBounds(bounds, for: parameter) }
            }

            // Match the source-path convention: the accessor's short name is
            // `get` while its FQ name is `<property>.$get` (HeaderCollection).
            let getName = interner.intern("get")
            let getterFQName = record.fqName + [interner.intern("$get")]
            let getterSymbol = symbols.extensionPropertyGetterAccessor(for: symbol) ?? symbols.define(
                kind: .function,
                name: getName,
                fqName: getterFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .importedLibrary]
            )
            symbols.setParentSymbol(symbol, for: getterSymbol)
            symbols.setAccessorOwnerProperty(symbol, for: getterSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: propertyType,
                    typeParameterSymbols: propertyTypeParameters,
                    reifiedTypeParameterIndices: record.reifiedTypeParameterIndices,
                    typeParameterUpperBoundsList: propertyUpperBounds,
                    classTypeParameterCount: ownerParameterCount
                ),
                for: getterSymbol
            )
            symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: symbol)
            if let getterLink = record.propertyGetterExternalLinkName, !getterLink.isEmpty {
                symbols.setExternalLinkName(getterLink, for: getterSymbol)
            }
            if let getterAbiSig = record.propertyGetterAbiReturnTypeSignature,
               let getterAbiReturnType = decodeImportedTypeSignature(
                   token: getterAbiSig,
                   symbols: symbols,
                   types: types,
                   interner: interner,
                   diagnostics: diagnostics,
                   metadataPath: binding.metadataPath,
                   ownerFQName: record.fqName,
                   cache: cache,
                   allowPlaceholders: isStdlibArtifact
               )
            {
                symbols.setFunctionABIReturnType(getterAbiReturnType, for: getterSymbol)
            }

            if record.isMutable {
                let setName = interner.intern("set")
                let setterFQName = record.fqName + [interner.intern("$set")]
                let setterSymbol = symbols.extensionPropertySetterAccessor(for: symbol) ?? symbols.define(
                    kind: .function,
                    name: setName,
                    fqName: setterFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .importedLibrary]
                )
                symbols.setParentSymbol(symbol, for: setterSymbol)
                symbols.setAccessorOwnerProperty(symbol, for: setterSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [propertyType],
                        returnType: types.unitType,
                        typeParameterSymbols: propertyTypeParameters,
                        reifiedTypeParameterIndices: record.reifiedTypeParameterIndices,
                        typeParameterUpperBoundsList: propertyUpperBounds,
                        classTypeParameterCount: ownerParameterCount
                    ),
                    for: setterSymbol
                )
                symbols.setExtensionPropertySetterAccessor(setterSymbol, for: symbol)
                if let setterLink = record.propertySetterExternalLinkName, !setterLink.isEmpty {
                    symbols.setExternalLinkName(setterLink, for: setterSymbol)
                }
            }
        }
        // Member and top-level properties with custom getters also carry a
        // precompiled getter link name. Restore a synthetic accessor so reads
        // route through it instead of through a global slot the artifact never
        // allocates.
        // A nominal owner is restored by restoreImportedParentSymbol before this
        // runs, so an owner that is absent or a package means the property is
        // top-level and its getter takes no receiver.
        let getterOwnerInfo = symbols.parentSymbol(for: symbol).flatMap { symbols.symbol($0) }
        if record.propertyGetterExternalLinkName != nil,
           record.propertyReceiverTypeSignature == nil,
           getterOwnerInfo == nil || getterOwnerInfo?.kind == .package
               || getterOwnerInfo?.kind == .class || getterOwnerInfo?.kind == .enumClass
               || getterOwnerInfo?.kind == .interface
               || getterOwnerInfo?.kind == .object
        {
            symbols.setPropertyHasCustomGetter(true, for: symbol)
            let ownerType: TypeID? = getterOwnerInfo.flatMap { ownerInfo in
                ownerInfo.kind == .package
                    ? nil
                    : types.make(.classType(ClassType(classSymbol: ownerInfo.id, args: [], nullability: .nonNull)))
            }
            let getName = interner.intern("get")
            let getterFQName = record.fqName + [interner.intern("$get")]
            let getterSymbol = symbols.extensionPropertyGetterAccessor(for: symbol) ?? symbols.define(
                kind: .function,
                name: getName,
                fqName: getterFQName,
                declSite: nil,
                visibility: record.visibility,
                flags: [.synthetic, .importedLibrary]
            )
            symbols.setParentSymbol(symbol, for: getterSymbol)
            symbols.setAccessorOwnerProperty(symbol, for: getterSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: ownerType,
                    parameterTypes: [],
                    returnType: propertyType
                ),
                for: getterSymbol
            )
            symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: symbol)
            if let getterLink = record.propertyGetterExternalLinkName, !getterLink.isEmpty {
                symbols.setExternalLinkName(getterLink, for: getterSymbol)
            }
            if let getterAbiSig = record.propertyGetterAbiReturnTypeSignature,
               let getterAbiReturnType = decodeImportedTypeSignature(
                   token: getterAbiSig,
                   symbols: symbols,
                   types: types,
                   interner: interner,
                   diagnostics: diagnostics,
                   metadataPath: binding.metadataPath,
                   ownerFQName: record.fqName,
                   cache: cache,
                   allowPlaceholders: isStdlibArtifact
               )
            {
                symbols.setFunctionABIReturnType(getterAbiReturnType, for: getterSymbol)
            }
        }
        // `var` properties with a custom setter carry the precompiled setter
        // link for the same reason as the getter: without it a consumer's
        // `a.prop = x` lowers to a call named `set` and fails to link.
        let setterOwnerInfo = symbols.parentSymbol(for: symbol).flatMap { symbols.symbol($0) }
        if record.isMutable,
           let setterLink = record.propertySetterExternalLinkName,
           !setterLink.isEmpty,
           record.propertyReceiverTypeSignature == nil,
           setterOwnerInfo == nil || setterOwnerInfo?.kind == .package
               || setterOwnerInfo?.kind == .class || setterOwnerInfo?.kind == .enumClass
               || setterOwnerInfo?.kind == .interface
               || setterOwnerInfo?.kind == .object
        {
            let ownerType: TypeID? = setterOwnerInfo.flatMap { ownerInfo in
                ownerInfo.kind == .package
                    ? nil
                    : types.make(.classType(ClassType(classSymbol: ownerInfo.id, args: [], nullability: .nonNull)))
            }
            let setName = interner.intern("set")
            let setterFQName = record.fqName + [interner.intern("$set")]
            let setterSymbol = symbols.extensionPropertySetterAccessor(for: symbol) ?? symbols.define(
                kind: .function,
                name: setName,
                fqName: setterFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .importedLibrary]
            )
            symbols.setParentSymbol(symbol, for: setterSymbol)
            symbols.setAccessorOwnerProperty(symbol, for: setterSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: ownerType,
                    parameterTypes: [propertyType],
                    returnType: types.unitType
                ),
                for: setterSymbol
            )
            symbols.setExtensionPropertySetterAccessor(setterSymbol, for: symbol)
            symbols.setExternalLinkName(setterLink, for: setterSymbol)
        }
    }

    private func applyImportedValueClassMetadata(
        _ binding: ImportedLibraryBinding,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        isStdlibArtifact: Bool = false
    ) {
        let record = binding.record
        guard record.isValueClass else {
            return
        }

        if let signature = record.valueClassUnderlyingTypeSig {
            let underlyingType = importedValueClassUnderlyingType(
                signature: signature,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                metadataPath: binding.metadataPath,
                ownerFQName: record.fqName,
                allowPlaceholders: isStdlibArtifact
            )
            if let underlyingType {
                symbols.setValueClassUnderlyingType(underlyingType, for: binding.symbol)
            }
            return
        }

        diagnostics.warning(
            "KSWIFTK-LIB-0007",
            "Value class '\(renderFQName(record.fqName, interner: interner))' has no underlying type signature"
                + " in library metadata at '\(binding.metadataPath)'. Boxing elision will be skipped for this type.",
            range: nil
        )
    }

    private func applyImportedTypeAliasMetadata(
        _ binding: ImportedLibraryBinding,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        cache: LibraryMetadataCache?,
        isStdlibArtifact: Bool = false
    ) {
        let record = binding.record
        guard record.kind == .typeAlias else {
            return
        }

        let underlyingType = importedTypeAliasUnderlyingType(
            record: record,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            metadataPath: binding.metadataPath,
            cache: cache,
            allowPlaceholders: isStdlibArtifact
        )
        guard let underlyingType else {
            return
        }
        symbols.setTypeAliasUnderlyingType(underlyingType, for: binding.symbol)
        let syntheticParams = collectSyntheticTypeParameters(underlyingType, types: types)
        if !syntheticParams.isEmpty {
            symbols.setTypeAliasTypeParameters(syntheticParams, for: binding.symbol)
        }
    }

    private func applyImportedNominalMetadata(
        _ binding: ImportedLibraryBinding,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        cache: LibraryMetadataCache?,
        isStdlibArtifact: Bool,
        pendingSupertypeEdges: inout [(subtype: SymbolID, superFQName: [InternedString])]
    ) {
        let record = binding.record
        guard isNominalLayoutTargetSymbol(record.kind) else {
            return
        }

        applyImportedNominalTypeParameters(
            binding,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            cache: cache,
            isStdlibArtifact: isStdlibArtifact
        )

        // Restore the parent link for imported nominal types (e.g. nested enum
        // classes like Base64.PaddingOption). Without this, member lookup on
        // the nested owner fails and the consumer falls back to treating the
        // nested type as a constructor call, breaking enum entry references.
        if record.fqName.count >= 2 {
            let ownerFQName = Array(record.fqName.dropLast())
            let ownerCandidates = symbols.lookupAll(fqName: ownerFQName).compactMap { symbols.symbol($0) }
            if let ownerSymbol = ownerCandidates.first(where: { isNominalLayoutTargetSymbol($0.kind) })?.id {
                symbols.setParentSymbol(ownerSymbol, for: binding.symbol)
            } else if let packageOwner = ownerCandidates.first(where: { $0.kind == .package }) {
                symbols.setParentSymbol(packageOwner.id, for: binding.symbol)
            }
        }

        if record.kind == .class, record.isInnerClass {
            // The enclosing-instance link is private ABI storage, not a public
            // property/extra value parameter. Its producer slot must not be guessed.
            let outerName = interner.intern("$outer")
            let outerFQName = record.fqName + [outerName]
            let entries = record.fieldOffsets.filter { $0.fqName == outerFQName }
            guard let owner = symbols.parentSymbol(for: binding.symbol),
                  let outerOwner = symbols.symbol(owner),
                  outerOwner.kind == .class || outerOwner.kind == .enumClass,
                  entries.count == 1,
                  let entry = entries.first,
                  entry.offset >= 2,
                  let size = record.declaredInstanceSizeWords,
                  entry.offset < size
            else {
                diagnostics.error(
                    "KSWIFTK-LIB-0024",
                    "Inner class '\(renderFQName(record.fqName, interner: interner))' has invalid enclosing-instance storage metadata",
                    range: nil
                )
                return
            }
            symbols.ensureLazyImportedMetadataLoaded(for: owner)
            let field = symbols.define(
                kind: .field, name: outerName, fqName: outerFQName, declSite: nil,
                visibility: .private, flags: [.synthetic, .importedLibrary]
            )
            symbols.setParentSymbol(binding.symbol, for: field)
            if let module = symbols.moduleFQN(for: binding.symbol) {
                symbols.setModuleFQN(module, for: field)
            }
            let arguments: [TypeArg] = types.nominalTypeParameterSymbols(for: owner).map {
                .invariant(types.make(.typeParam(TypeParamType(symbol: $0))))
            }
            symbols.setPropertyType(types.make(.classType(ClassType(
                classSymbol: owner, args: arguments, nullability: .nonNull
            ))), for: field)
            symbols.setOuterInstanceFieldSymbol(field, for: binding.symbol)
        }

        let hasLayoutHint =
            record.declaredFieldCount != nil ||
            record.declaredInstanceSizeWords != nil ||
            record.declaredVtableSize != nil ||
            record.declaredItableSize != nil
        if hasLayoutHint {
            symbols.setNominalLayoutHint(
                NominalLayoutHint(
                    declaredFieldCount: record.declaredFieldCount,
                    declaredInstanceSizeWords: record.declaredInstanceSizeWords,
                    declaredVtableSize: record.declaredVtableSize,
                    declaredItableSize: record.declaredItableSize
                ),
                for: binding.symbol
            )
        }
        let allSuperFQNames = record.superFQNames ?? record.superFQName.map { [$0] } ?? []
        for superFQName in allSuperFQNames where !superFQName.isEmpty {
            pendingSupertypeEdges.append((subtype: binding.symbol, superFQName: superFQName))
        }

        // The precompiled initializer stubs (object/companion/enum static)
        // are compact-index facts and are already synthesized at shell
        // registration; this call only fills any path that still lacks them.
        applyImportedInitializerShells(
            record: record,
            symbol: binding.symbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    /// Restores the declaration-order type parameters of an imported generic
    /// nominal type. Without them the consumer treats the type as non-generic,
    /// so explicit type arguments (`ArrayDeque<Int>()`) and member type
    /// substitution fail to resolve.
    private func applyImportedNominalTypeParameters(
        _ binding: ImportedLibraryBinding,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        cache: LibraryMetadataCache?,
        isStdlibArtifact: Bool
    ) {
        guard let encoded = binding.record.nominalTypeParameters, !encoded.isEmpty else {
            return
        }

        var typeParameterSymbols: [SymbolID] = []
        var variances: [TypeVariance] = []
        for entry in encoded.split(separator: ",") {
            let parts = entry.split(separator: ":", maxSplits: 1)
            guard let token = parts.first,
                  let decoded = decodeImportedTypeSignature(
                      token: String(token),
                      symbols: symbols,
                      types: types,
                      interner: interner,
                      diagnostics: diagnostics,
                      metadataPath: binding.metadataPath,
                      ownerFQName: binding.record.fqName,
                      cache: cache,
                      allowPlaceholders: isStdlibArtifact
                  ),
                  case let .typeParam(typeParam) = types.kind(of: decoded)
            else {
                return
            }
            typeParameterSymbols.append(typeParam.symbol)
            switch parts.count > 1 ? String(parts[1]) : "i" {
            case "o": variances.append(.out)
            case "n": variances.append(.in)
            default: variances.append(.invariant)
            }
        }

        guard !typeParameterSymbols.isEmpty else {
            return
        }
        types.setNominalTypeParameterSymbols(typeParameterSymbols, for: binding.symbol)
        types.setNominalTypeParameterVariances(variances, for: binding.symbol)
        let nominalBounds = typeParameterSymbols.indices.map { index -> [TypeID] in
            guard binding.record.typeParameterUpperBoundsSignatures.indices.contains(index) else { return [] }
            return binding.record.typeParameterUpperBoundsSignatures[index].compactMap {
                decodeImportedTypeSignature(
                    token: $0, symbols: symbols, types: types, interner: interner,
                    diagnostics: diagnostics, metadataPath: binding.metadataPath,
                    ownerFQName: binding.record.fqName, cache: cache, allowPlaceholders: isStdlibArtifact
                )
            }
        }
        // T indices are local to the producer. Keep nominal bounds on their
        // owner so independent artifacts cannot overwrite each other's bounds.
        if nominalBounds.contains(where: { !$0.isEmpty }) {
            types.setNominalTypeParameterUpperBounds(nominalBounds, for: binding.symbol)
        }
    }
}
