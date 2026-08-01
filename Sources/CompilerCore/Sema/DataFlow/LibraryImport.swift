import Foundation

extension DataFlowSemaPhase {
    struct LibraryManifestInfo {
        let metadataPath: String
        let inlineKIRDir: String?
        let moduleName: String?
        let isValid: Bool
    }

    struct LibraryImportDeferredWork {
        let pendingSupertypeEdges: [(subtype: SymbolID, superFQName: [InternedString])]
        let importedBindings: [ImportedLibraryBinding]
    }

    func loadImportedLibrarySymbols(
        options: CompilerOptions,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        importedInlineFunctions: inout [SymbolID: KIRFunction],
        cache: LibraryMetadataCache? = nil
    ) -> LibraryImportDeferredWork {
        let libraryDirs = discoverLibraryDirectories(searchPaths: options.effectiveLibrarySearchPaths)
        var pendingSupertypeEdges: [(subtype: SymbolID, superFQName: [InternedString])] = []
        var importedBindings: [ImportedLibraryBinding] = []
        var stdlibArtifactLoaded = false

        func isStdlibArtifact(_ libraryDir: String) -> Bool {
            guard let stdlibLibraryPath = options.stdlibLibraryPath else { return false }
            return URL(fileURLWithPath: libraryDir).standardizedFileURL.path
                == URL(fileURLWithPath: stdlibLibraryPath).standardizedFileURL.path
        }

        for libraryDir in libraryDirs {
            let stdlibArtifact = isStdlibArtifact(libraryDir)
            let manifestInfo: LibraryManifestInfo
            if let cached = cache?.cachedManifestInfo(libraryDir: libraryDir, target: options.target) {
                manifestInfo = cached
            } else {
                manifestInfo = resolveLibraryManifestInfo(
                    libraryDir: libraryDir,
                    currentTarget: options.target,
                    diagnostics: diagnostics,
                    isStdlibArtifact: stdlibArtifact
                )
                cache?.cacheManifestInfo(manifestInfo, libraryDir: libraryDir, target: options.target)
            }
            if stdlibArtifact {
                stdlibArtifactLoaded = manifestInfo.isValid
            }
            guard manifestInfo.isValid else {
                continue
            }
            let metadataPath = manifestInfo.metadataPath
            let libraryModuleFQN: InternedString? = manifestInfo.moduleName.map { interner.intern($0) }
            let records: [ImportedLibrarySymbolRecord]
            if let cached = cache?.cachedMetadataRecords(metadataPath: metadataPath, interner: interner) {
                records = cached
            } else {
                guard let parsed = parseLibraryMetadata(
                    path: metadataPath,
                    diagnostics: diagnostics,
                    interner: interner
                ) else {
                    continue
                }
                records = parsed
                cache?.cacheMetadataRecords(records, metadataPath: metadataPath, interner: interner)
            }

            for record in records {
                guard !record.fqName.isEmpty else {
                    continue
                }
                let name = record.fqName.last ?? interner.intern("_")
                var flags: SymbolFlags = [.synthetic, .importedLibrary]
                if record.isSuspend, record.kind == .function {
                    flags.insert(.suspendFunction)
                }
                if record.isInline, record.kind == .function {
                    flags.insert(.inlineFunction)
                }
                if record.isDataClass {
                    flags.insert(.dataType)
                }
                if record.isSealedClass {
                    flags.insert(.sealedType)
                }
                if record.isValueClass {
                    flags.insert(.valueType)
                }
                if record.isExpect {
                    flags.insert(.expectDeclaration)
                }
                if record.isActual {
                    flags.insert(.actualDeclaration)
                }
                if record.isMutable, record.kind == .property || record.kind == .field {
                    flags.insert(.mutable)
                }
                let symbol = symbols.define(
                    kind: record.kind,
                    name: name,
                    fqName: record.fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: flags
                )
                if let libraryModuleFQN {
                    symbols.setModuleFQN(libraryModuleFQN, for: symbol)
                }
                importedBindings.append(ImportedLibraryBinding(
                    record: record,
                    symbol: symbol,
                    metadataPath: metadataPath,
                    inlineKIRDir: manifestInfo.inlineKIRDir,
                    isStdlibArtifact: stdlibArtifact
                ))
            }
        }

        if options.stdlibLibraryPath != nil && !stdlibArtifactLoaded {
            diagnostics.error(
                "KSWIFTK-LIB-0020",
                "Stdlib library artifact '\(options.stdlibLibraryPath!)' could not be loaded",
                range: nil
            )
            return LibraryImportDeferredWork(pendingSupertypeEdges: [], importedBindings: [])
        }

        var externalLinkNameToSymbol: [String: SymbolID] = [:]
        for binding in importedBindings {
            if let linkName = binding.record.externalLinkName, !linkName.isEmpty {
                externalLinkNameToSymbol[linkName] = binding.symbol
            }
        }

        for binding in importedBindings {
            applyImportedBinding(
                binding,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                importedInlineFunctions: &importedInlineFunctions,
                pendingSupertypeEdges: &pendingSupertypeEdges,
                cache: cache,
                isStdlibArtifact: binding.isStdlibArtifact,
                externalLinkNameToSymbol: externalLinkNameToSymbol
            )
        }

        var syntheticPackagePaths: Set<[InternedString]> = []
        var syntheticPackageModules: [[InternedString]: InternedString] = [:]
        for binding in importedBindings where binding.record.kind != .package {
            let fq = binding.record.fqName
            let moduleFQN = symbols.moduleFQN(for: binding.symbol)
            for length in 1 ..< fq.count {
                let prefix = Array(fq.prefix(length))
                syntheticPackagePaths.insert(prefix)
                if let moduleFQN {
                    syntheticPackageModules[prefix] = moduleFQN
                }
            }
        }
        for packagePath in syntheticPackagePaths {
            let existing = symbols.lookupAll(fqName: packagePath)
            let alreadyHasPackage = existing.contains { id in
                symbols.symbol(id)?.kind == .package
            }
            if !alreadyHasPackage {
                let name = packagePath.last ?? interner.intern("_")
                let packageSymbol = symbols.define(
                    kind: .package,
                    name: name,
                    fqName: packagePath,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                if let moduleFQN = syntheticPackageModules[packagePath] {
                    symbols.setModuleFQN(moduleFQN, for: packageSymbol)
                }
            }
        }

        return LibraryImportDeferredWork(
            pendingSupertypeEdges: pendingSupertypeEdges,
            importedBindings: importedBindings
        )
    }

    func applyImportedLibraryDeferredWork(
        _ work: LibraryImportDeferredWork,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine
    ) {
        for edge in work.pendingSupertypeEdges {
            guard let superSymbol = symbols.lookupAll(fqName: edge.superFQName)
                .compactMap({ symbols.symbol($0) })
                .first(where: { isNominalLayoutTargetSymbol($0.kind) })?.id
            else {
                continue
            }
            var supertypes = symbols.directSupertypes(for: edge.subtype)
            if !supertypes.contains(superSymbol) {
                supertypes.append(superSymbol)
                supertypes.sort(by: { $0.rawValue < $1.rawValue })
                symbols.setDirectSupertypes(supertypes, for: edge.subtype)
                types.setNominalDirectSupertypes(supertypes, for: edge.subtype)
            }
        }

        for binding in work.importedBindings where isNominalLayoutTargetSymbol(binding.record.kind) {
            applyImportedNominalLayout(
                record: binding.record,
                symbol: binding.symbol,
                symbols: symbols,
                diagnostics: diagnostics,
                metadataPath: binding.metadataPath
            )
        }

        // P5-78: resolve sealed subclass FQ names to SymbolIDs for cross-module exhaustiveness
        for binding in work.importedBindings where binding.record.isSealedClass && !binding.record.sealedSubclassFQNames.isEmpty {
            let resolvedSubclasses: [SymbolID] = binding.record.sealedSubclassFQNames.compactMap { subFQName in
                symbols.lookupAll(fqName: subFQName)
                    .compactMap { symbols.symbol($0) }
                    .first(where: { isNominalLayoutTargetSymbol($0.kind) })?.id
            }
            // Only record concrete sealed subclasses when all declared subclass FQ names could be resolved.
            // If any subclass fails to resolve, mark the sealed type as having unknown/incomplete subclasses
            // by recording an empty sealed-subclass list as a sentinel, preventing the directSubtypes fallback
            // from incorrectly treating an incomplete set as exhaustive.
            if resolvedSubclasses.count == binding.record.sealedSubclassFQNames.count {
                symbols.setSealedSubclasses(resolvedSubclasses, for: binding.symbol)
            } else {
                symbols.setSealedSubclasses([], for: binding.symbol)
            }
        }
    }

    struct ImportedFieldOffsetEntry {
        let fqName: [InternedString]
        let offset: Int
    }

    struct ImportedVTableSlotEntry {
        let fqName: [InternedString]
        let arity: Int
        let isSuspend: Bool
        let slot: Int
    }

    struct ImportedITableSlotEntry {
        let fqName: [InternedString]
        let slot: Int
    }

    struct ImportedLibrarySymbolRecord {
        let kind: SymbolKind
        let mangledName: String
        let fqName: [InternedString]
        let arity: Int
        let isSuspend: Bool
        let isInline: Bool
        let valueParameterIsVararg: [Bool]
        let valueParameterHasDefaultValues: [Bool]
        let typeSignature: String?
        let defaultStubExternalLinkName: String?
        let externalLinkName: String?
        let declaredFieldCount: Int?
        let declaredInstanceSizeWords: Int?
        let declaredVtableSize: Int?
        let declaredItableSize: Int?
        let superFQName: [InternedString]?
        let fieldOffsets: [ImportedFieldOffsetEntry]
        let vtableSlots: [ImportedVTableSlotEntry]
        let itableSlots: [ImportedITableSlotEntry]
        let isDataClass: Bool
        let isSealedClass: Bool
        let isValueClass: Bool
        let isExpect: Bool
        let isActual: Bool
        let valueClassUnderlyingTypeSig: String?
        let annotations: [MetadataAnnotationRecord]
        let sealedSubclassFQNames: [[InternedString]]
        let propertyReceiverTypeSignature: String?
        let propertyGetterExternalLinkName: String?
        let abiReturnTypeSignature: String?
        let propertyGetterAbiReturnTypeSignature: String?
        let isMutable: Bool
    }

    struct ImportedLibraryBinding {
        let record: ImportedLibrarySymbolRecord
        let symbol: SymbolID
        let metadataPath: String
        let inlineKIRDir: String?
        let isStdlibArtifact: Bool
    }

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
        case .stringStruct, .primitive, .any, .unit, .nothing, .error:
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

    func renderFQName(_ fqName: [InternedString], interner: StringInterner) -> String {
        fqName.map { interner.resolve($0) }.joined(separator: ".")
    }

    private func applyImportedBinding(
        _ binding: ImportedLibraryBinding,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        importedInlineFunctions: inout [SymbolID: KIRFunction],
        pendingSupertypeEdges: inout [(subtype: SymbolID, superFQName: [InternedString])],
        cache: LibraryMetadataCache?,
        isStdlibArtifact: Bool,
        externalLinkNameToSymbol: [String: SymbolID]
    ) {
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
            importedInlineFunctions: &importedInlineFunctions,
            cache: cache,
            isStdlibArtifact: isStdlibArtifact,
            externalLinkNameToSymbol: externalLinkNameToSymbol
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
        applyImportedNominalMetadata(binding, symbols: symbols, pendingSupertypeEdges: &pendingSupertypeEdges)
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

    private func restoreImportedParentSymbol(
        _ record: ImportedLibrarySymbolRecord,
        symbol: SymbolID,
        symbols: SymbolTable
    ) {
        guard record.kind == .function || record.kind == .property || record.kind == .field,
              record.fqName.count >= 2
        else {
            return
        }

        let ownerFQName = Array(record.fqName.dropLast())
        let ownerCandidates = symbols.lookupAll(fqName: ownerFQName).compactMap { symbols.symbol($0) }
        if let packageOwner = ownerCandidates.first(where: { $0.kind == .package }) {
            symbols.setParentSymbol(packageOwner.id, for: symbol)
            return
        }
        guard let ownerSymbol = ownerCandidates.first(where: { isNominalLayoutTargetSymbol($0.kind) })?.id else {
            return
        }
        symbols.setParentSymbol(ownerSymbol, for: symbol)
    }

    private func applyImportedCallableMetadata(
        _ binding: ImportedLibraryBinding,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        importedInlineFunctions: inout [SymbolID: KIRFunction],
        cache: LibraryMetadataCache?,
        isStdlibArtifact: Bool = false,
        externalLinkNameToSymbol: [String: SymbolID] = [:]
    ) {
        let record = binding.record
        let symbol = binding.symbol

        if record.kind == .function {
            let signature = importedFunctionSignature(
                record: record,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                metadataPath: binding.metadataPath,
                cache: cache,
                allowPlaceholders: isStdlibArtifact
            )
            symbols.setFunctionSignature(signature, for: symbol)
            if let defaultStubLink = record.defaultStubExternalLinkName, !defaultStubLink.isEmpty,
               signature.valueParameterHasDefaultValues.contains(true)
            {
                let stubSymbol = SyntheticSymbolScheme.defaultStubSymbol(for: symbol)
                symbols.setExternalLinkName(defaultStubLink, for: stubSymbol)
                let intType = types.intType
                let reifiedCount = signature.reifiedTypeParameterIndices.count
                let stubParameterTypes = signature.parameterTypes + Array(repeating: intType, count: reifiedCount) + [intType]
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: signature.receiverType,
                        parameterTypes: stubParameterTypes,
                        returnType: signature.returnType,
                        isSuspend: false,
                        canThrow: false,
                        valueParameterHasDefaultValues: [],
                        valueParameterIsVararg: [],
                        typeParameterSymbols: signature.typeParameterSymbols,
                        reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices
                    ),
                    for: stubSymbol
                )
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
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                importedInlineFunctions: &importedInlineFunctions,
                externalLinkNameToSymbol: externalLinkNameToSymbol
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

            let getName = interner.intern("get")
            let getterFQName = record.fqName + [getName]
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

            if record.isMutable {
                let setName = interner.intern("set")
                let setterFQName = record.fqName + [setName]
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
                        returnType: types.unitType
                    ),
                    for: setterSymbol
                )
                symbols.setExtensionPropertySetterAccessor(setterSymbol, for: symbol)
            }
        }
    }

    private func importInlineFunctionIfNeeded(
        _ binding: ImportedLibraryBinding,
        symbol: SymbolID,
        signature: FunctionSignature,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        importedInlineFunctions: inout [SymbolID: KIRFunction],
        externalLinkNameToSymbol: [String: SymbolID]
    ) {
        let record = binding.record
        guard record.isInline,
              !record.mangledName.isEmpty,
              let inlineDir = binding.inlineKIRDir
        else {
            return
        }

        let fileName = MetadataEncoder.inlineKIRFileName(for: record.mangledName)
        let inlinePath = URL(fileURLWithPath: inlineDir)
            .appendingPathComponent(fileName)
            .standardized
            .path
        let inlineDirResolved = URL(fileURLWithPath: inlineDir).standardized.path
        guard inlinePath.hasPrefix(inlineDirResolved + "/") else {
            diagnostics.error(
                "KSWIFTK-LIB-0019",
                "Inline KIR path for '\(record.mangledName)' escapes inline directory",
                range: nil
            )
            return
        }
        guard let inlineFunction = parseImportedInlineFunction(
            path: inlinePath,
            importedSymbol: symbol,
            signature: signature,
            types: types,
            interner: interner,
            diagnostics: diagnostics,
            externalLinkNameToSymbol: externalLinkNameToSymbol
        ) else {
            return
        }
        importedInlineFunctions[symbol] = inlineFunction
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
        pendingSupertypeEdges: inout [(subtype: SymbolID, superFQName: [InternedString])]
    ) {
        let record = binding.record
        guard isNominalLayoutTargetSymbol(record.kind) else {
            return
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
        if let superFQName = record.superFQName, !superFQName.isEmpty {
            pendingSupertypeEdges.append((subtype: binding.symbol, superFQName: superFQName))
        }
    }
}
