import Foundation

extension DataFlowSemaPhase {
    /// Walk a decoded type and collect all synthetic type parameter symbols
    /// (those with rawValue <= syntheticTypeParameterBase). Returns them sorted
    /// by index order (T0, T1, T2, ...) matching the original generic parameter list.
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
        case .stringStruct, .primitive, .any, .unit, .nullableUnit, .nothing, .error:
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
        phantomTypeParameterSymbolsByOwnerFQName: [[InternedString]: [SymbolID]] = [:]
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
            phantomTypeParameterSymbolsByOwnerFQName: phantomTypeParameterSymbolsByOwnerFQName
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
              || record.kind == .backingField || record.kind == .constructor,
              record.fqName.count >= 2
        else {
            return
        }

        let ownerFQName = Array(record.fqName.dropLast())
        let ownerCandidates = symbols.lookupAll(fqName: ownerFQName).compactMap { symbols.symbol($0) }
        if let ownerSymbol = ownerCandidates.first(where: { isNominalLayoutTargetSymbol($0.kind) })?.id {
            symbols.setParentSymbol(ownerSymbol, for: symbol)
        } else if (record.receiverOwnerFQName != nil || record.propertyReceiverTypeSignature != nil),
                  let packageOwner = ownerCandidates.first(where: { $0.kind == .package })
        {
            // A package parent is semantically required for extension lookup.
            // Ordinary top-level declarations intentionally stay parentless,
            // matching eager import where package shells do not exist yet.
            symbols.setParentSymbol(packageOwner.id, for: symbol)
        }
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
        phantomTypeParameterSymbolsByOwnerFQName: [[InternedString]: [SymbolID]] = [:]
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
                phantomTypeParameterSymbols: phantomTypeParameterSymbolsByOwnerFQName[record.fqName] ?? []
            )
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
                                name: interner.intern(interner.resolve(record.fqName.last ?? interner.intern("_")) + "$default")
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
                signature: signature,
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
        }

        // Restore extension property accessor(s). Extension properties are
        // compiled as precompiled getter functions in the artifact objects;
        // we synthesize the accessor symbol and point it at that link name.
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
            let getterSymbol = symbols.define(
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
                let setterSymbol = symbols.define(
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
            let getterSymbol = symbols.define(
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
            let setterSymbol = symbols.define(
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

        // Import the precompiled enum static initializer link so the consumer
        // can call it before `main`, ensuring enum entry globals are initialized.
        if record.kind == .enumClass,
           let enumStaticInitLink = record.enumStaticInitLinkName,
           !enumStaticInitLink.isEmpty
        {
            let initName = interner.intern("__enum_static_init")
            let initFQName = record.fqName + [initName]
            let initSymbol = symbols.define(
                kind: .function,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .importedLibrary]
            )
            symbols.setExternalLinkName(enumStaticInitLink, for: initSymbol)
            symbols.setParentSymbol(binding.symbol, for: initSymbol)
            symbols.setEnumStaticInitSymbol(initSymbol, for: binding.symbol)
        }
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
    }
}
