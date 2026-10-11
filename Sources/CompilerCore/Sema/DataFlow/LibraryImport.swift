import Foundation

extension DataFlowSemaPhase {
    struct LibraryManifestInfo {
        let metadataPath: String
        let inlineKIRDir: String?
        let moduleName: String?
        let isValid: Bool
        var topLevelInitializerLinkName: String? = nil
    }

    struct LibraryImportDeferredWork {
        let pendingSupertypeEdges: [(subtype: SymbolID, superFQName: [InternedString])]
        let importedBindings: [ImportedLibraryBinding]
        let lazyLoaderState: ImportedLibraryLazyLoaderState?
        /// The stdlib artifact's module name, already interned and validated
        /// against its manifest.json by the loop below. Callers that need to
        /// filter symbols by stdlib-module membership (e.g.
        /// `mergeImportedStdlibSymbolsIntoBundledIndex`) should use this
        /// instead of re-reading and re-parsing manifest.json themselves: a
        /// second independent read has no diagnostic on failure and is
        /// redundant with the validation already performed here.
        let stdlibModuleName: InternedString?
        /// Kotlin `.klib` modules discovered on the search path: manifest
        /// parsed and version-gated, container and decoded IR kept open for
        /// the body materialization that runs during KIR lowering.
        let klibModules: [LoadedKlibModule]
    }

    /// Shared state for indexed metadata materialization. The inline-function
    /// sink is connected to `SemaModule` after the import phase constructs it.
    final class ImportedLibraryLazyLoaderState {
        var importedInlineFunctions: ImportedInlineFunctionStore
        var descriptorSink: ((SymbolID, ImportedInlineFunctionStore.Descriptor) -> Void)?
        var bundledIndex: BundledDeclarationIndex = .empty
        /// Indexed inline bodies kept unparsed past materialization. They are
        /// resolved on demand once lowering knows which callees the module
        /// actually calls — materializing a symbol for a signature query must
        /// not read its `.kir` file.
        var pendingInlineBindings: [SymbolID: ImportedLibraryBinding] = [:]
        /// Pending symbols grouped by simple name, consulted only by
        /// symbol-unresolved `.call` sites that resolve through the name
        /// fallback.
        var pendingInlineSymbolsByName: [InternedString: [SymbolID]] = [:]
        /// Populated by `loadImportedLibrarySymbols`; resolves pending bodies
        /// for callees demanded by the module. Forwarded onto `SemaModule`.
        var resolveDemandedInlineBodies: ((KIRModule) -> Void)?
        /// Lazy materialization can apply a nominal layout before the
        /// synthetic bootstrap stubs it references (e.g. `MutableMap.put`)
        /// exist. Until `applyImportedLibraryDeferredWork` runs, layout
        /// warnings are withheld and those bindings are re-applied there,
        /// mirroring the eager path's "layout after bootstrap" ordering.
        var layoutBootstrapComplete = false
        var pendingLayoutRetries: [ImportedLibraryBinding] = []
        var indexedBindingsBySymbol: [SymbolID: ImportedLibraryBinding] = [:]

        init(importedInlineFunctions: ImportedInlineFunctionStore = ImportedInlineFunctionStore()) {
            self.importedInlineFunctions = importedInlineFunctions
        }
    }

    func loadImportedLibrarySymbols(
        options: CompilerOptions,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        importedInlineFunctions: ImportedInlineFunctionStore,
        cache: LibraryMetadataCache? = nil
    ) -> LibraryImportDeferredWork {
        // Imported function bounds may refer to java.io.Closeable before the
        // synthetic FileIO registration phase creates its compatibility anchor.
        _ = ensureJavaIOCloseableCompatibilityAnchor(
            symbols: symbols,
            interner: interner
        )
        let libraryDirs = discoverLibraryDirectories(searchPaths: options.effectiveLibrarySearchPaths)
        var pendingSupertypeEdges: [(subtype: SymbolID, superFQName: [InternedString])] = []
        var importedBindings: [ImportedLibraryBinding] = []
        /// The library that claimed each symbol, as a user-facing origin
        /// label (module name, or metadata path when unnamed) and the
        /// metadata path that identifies it. `SymbolTable.define` merges a
        /// record onto the first symbol declared at its FQ name; when two
        /// libraries export the same declaration the second record therefore
        /// lands on an already-bound symbol. First on the search path wins —
        /// the loser's record is shadowed so the symbol's signature, owning
        /// module, and inline body stay consistent — while its external link
        /// names still alias to the merged symbol so bodies in the losing
        /// library that reference the declaration keep resolving.
        var boundSymbolOrigins: [SymbolID: (origin: String, metadataPath: String)] = [:]
        var shadowedDuplicateRecords: [(record: ImportedLibrarySymbolRecord, symbol: SymbolID)] = []
        /// FQ names of records that were shadowed — the duplicates
        /// themselves plus the member records hidden underneath them — so
        /// deeper declarations (nested classes, enum entries, parameters of
        /// shadowed callables) shadow transitively.
        var shadowedDeclOrigins: [[InternedString]: String] = [:]
        /// Member records shadowed with their owner. They never receive a
        /// symbol, but their external link names still resolve — against the
        /// merged declaration space, where a same-FQName counterpart from the
        /// winning library may exist — so bodies in the losing library that
        /// call the member dispatch consistently.
        var shadowedMemberRecords: [ImportedLibrarySymbolRecord] = []
        /// Member machinery (parameters, backing fields, locals, labels):
        /// hidden silently with its owner — these records encode part of a
        /// callable, not a declaration a consumer names directly.
        func isShadowedMemberMachinery(_ kind: SymbolKind) -> Bool {
            switch kind {
            case .valueParameter, .typeParameter, .backingField, .local, .label:
                true
            default:
                false
            }
        }
        /// The winning library when `record` is a member of a declaration
        /// another library already owns, else nil. A class that loses the
        /// merge must take its whole member surface with it: binding the
        /// losing class's fields, accessors (resolved at losing-layout
        /// offsets), and loser-only members onto the winning layout would
        /// compile and then crash or read garbage at runtime. Callables
        /// legitimately coexist as overloads, so parameter-kind records are
        /// shadowed only when the callable's owner — not the callable itself
        /// — is a foreign-owned nominal (e.g. `dup.Shadow.<init>.v` loses
        /// through `dup.Shadow`, while a `dup.helper` overload's parameters
        /// survive).
        func shadowedOwnerOrigin(
            for record: ImportedLibrarySymbolRecord,
            metadataPath: String
        ) -> String? {
            guard record.kind != .package else { return nil }
            let ownerFQName = Array(record.fqName.dropLast())
            if let winner = shadowedDeclOrigins[ownerFQName] { return winner }
            let probeFQName: [InternedString]
            if isShadowedMemberMachinery(record.kind) {
                probeFQName = Array(record.fqName.dropLast(2))
                if probeFQName != ownerFQName,
                   let winner = shadowedDeclOrigins[probeFQName]
                { return winner }
            } else {
                probeFQName = ownerFQName
            }
            guard !probeFQName.isEmpty,
                  let ownerSymbol = symbols.lookupAll(fqName: probeFQName).first,
                  let ownerKind = symbols.symbol(ownerSymbol)?.kind,
                  isNominalLayoutTargetSymbol(ownerKind),
                  let bound = boundSymbolOrigins[ownerSymbol],
                  bound.metadataPath != metadataPath
            else { return nil }
            return bound.origin
        }
        let lazyLoaderState = ImportedLibraryLazyLoaderState(importedInlineFunctions: importedInlineFunctions)
        var klibModules: [LoadedKlibModule] = []
        /// Every `.klib` that passed manifest gating — including ones whose
        /// IR failed to decode — so `depends` checks see the full set.
        var recognizedKlibs: [KlibModule] = []
        var stdlibArtifactLoaded = false
        var stdlibModuleName: InternedString?

        func isStdlibArtifact(_ libraryDir: String) -> Bool {
            guard let stdlibLibraryPath = options.stdlibLibraryPath else { return false }
            return URL(fileURLWithPath: libraryDir).standardizedFileURL.path
                == URL(fileURLWithPath: stdlibLibraryPath).standardizedFileURL.path
        }

        @discardableResult
        func appendImportedBinding(
            _ record: ImportedLibrarySymbolRecord,
            metadataPath: String,
            inlineKIRDir: String?,
            isStdlibArtifact: Bool,
            materializeBody: (() -> ImportedLibrarySymbolRecord?)? = nil,
            moduleFQN: InternedString?
        ) -> SymbolID? {
            guard !record.fqName.isEmpty else { return nil }
            let origin = moduleFQN.map { "module '\(interner.resolve($0))'" }
                ?? "'\(metadataPath)'"
            if let winner = shadowedOwnerOrigin(for: record, metadataPath: metadataPath) {
                if !isShadowedMemberMachinery(record.kind) {
                    diagnostics.warning(
                        "KSWIFTK-LIB-0031",
                        "Declaration '\(renderFQName(record.fqName, interner: interner))' imported from \(origin) ignored; its owner is provided by \(winner)",
                        range: nil
                    )
                }
                shadowedDeclOrigins[record.fqName] = winner
                shadowedMemberRecords.append(record)
                return nil
            }
            let name = record.fqName.last ?? interner.intern("_")
            var flags: SymbolFlags = [.synthetic, .importedLibrary]
            if record.isSuspend, record.kind == .function {
                flags.insert(.suspendFunction)
            }
            if record.isInline, record.kind == .function {
                flags.insert(.inlineFunction)
            }
            if record.isOperator, record.kind == .function {
                flags.insert(.operatorFunction)
            }
            if record.isInfix, record.kind == .function {
                flags.insert(.infixFunction)
            }
            if record.isMemberExtension { flags.insert(.memberExtension) }
            // Overrides must stay marked so member lookup can shadow the
            // supertype declaration instead of reporting an ambiguity.
            if record.isOverride,
               record.kind == .function || record.kind == .property || record.kind == .field
            {
                flags.insert(.overrideMember)
            }
            if record.isDataClass { flags.insert(.dataType) }
            if record.isOpenClass { flags.insert(.openType) }
            switch record.modality {
            case .abstract: flags.insert(.abstractType)
            case .open: flags.insert(.openType)
            case .final: break
            }
            if record.isSealedClass { flags.insert(.sealedType) }
            if record.isFunInterface { flags.insert(.funInterface) }
            if record.isValueClass { flags.insert(.valueType) }
            if record.isExpect { flags.insert(.expectDeclaration) }
            if record.isActual { flags.insert(.actualDeclaration) }
            if record.isMutable, record.kind == .property || record.kind == .field {
                flags.insert(.mutable)
            }
            let symbol = symbols.define(
                kind: record.kind,
                name: name,
                fqName: record.fqName,
                declSite: nil,
                visibility: record.visibility,
                flags: flags
            )
            if let winner = boundSymbolOrigins[symbol] {
                diagnostics.warning(
                    "KSWIFTK-LIB-0031",
                    "Duplicate declaration '\(renderFQName(record.fqName, interner: interner))' imported from \(origin) ignored; \(winner.origin) takes precedence",
                    range: nil
                )
                shadowedDuplicateRecords.append((record: record, symbol: symbol))
                shadowedDeclOrigins[record.fqName] = winner.origin
                return symbol
            }
            boundSymbolOrigins[symbol] = (origin: origin, metadataPath: metadataPath)
            if let moduleFQN {
                symbols.setModuleFQN(moduleFQN, for: symbol)
            }
            if materializeBody != nil,
               record.kind == .function || record.kind == .property || record.kind == .field
            {
                symbols.setImportedMemberIndexShape(
                    ImportedMemberIndexShape(
                        arity: record.kind == .function ? record.arity : 0,
                        receiverOwnerFQName: record.receiverOwnerFQName
                    ),
                    for: symbol
                )
            }
            let binding = ImportedLibraryBinding(
                record: record,
                symbol: symbol,
                metadataPath: metadataPath,
                inlineKIRDir: inlineKIRDir,
                isStdlibArtifact: isStdlibArtifact,
                materializeBody: materializeBody
            )
            // Indexed inline bodies stay unparsed until lowering resolves the
            // callees the module actually invokes. Registering at shell
            // creation — not at materialization — also covers
            // symbol-unresolved `.call` sites that reach the body through the
            // name fallback before any semantic query materializes it.
            if binding.defersInlineBodyImport,
               record.isInline, !record.mangledName.isEmpty, inlineKIRDir != nil
            {
                lazyLoaderState.pendingInlineBindings[symbol] = binding
                if let name = record.fqName.last {
                    lazyLoaderState.pendingInlineSymbolsByName[name, default: []].append(symbol)
                }
            }
            importedBindings.append(binding)
            return symbol
        }

        for libraryDir in libraryDirs {
            if libraryDir.hasSuffix(".klib") {
                if let module = loadKlibModule(path: libraryDir, diagnostics: diagnostics) {
                    recognizedKlibs.append(module)
                    let stdlibArtifact = isStdlibArtifact(libraryDir)
                    if stdlibArtifact {
                        stdlibArtifactLoaded = true
                        stdlibModuleName = interner.intern(module.uniqueName)
                    }
                    let klibModuleFQN = interner.intern(module.uniqueName)
                    let (records, ir) = materializeKlibRecords(
                        module: module,
                        interner: interner,
                        diagnostics: diagnostics
                    )
                    var registered: [(record: ImportedLibrarySymbolRecord, symbol: SymbolID)] = []
                    registered.reserveCapacity(records.count)
                    for record in records {
                        if let symbol = appendImportedBinding(
                            record,
                            metadataPath: "\(libraryDir)/ir",
                            inlineKIRDir: nil,
                            isStdlibArtifact: stdlibArtifact,
                            moduleFQN: klibModuleFQN
                        ) {
                            registered.append((record: record, symbol: symbol))
                        }
                    }
                    if let ir {
                        klibModules.append(finalizeKlibModule(
                            module: module,
                            ir: ir,
                            registered: registered,
                            symbols: symbols
                        ))
                    }
                }
                continue
            }
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
            if let linkName = manifestInfo.topLevelInitializerLinkName,
               !linkName.isEmpty,
               let moduleName = manifestInfo.moduleName {
                let name = interner.intern("__kk_library_top_level_init_\(moduleName)")
                let symbol = symbols.define(
                    kind: .function,
                    name: name,
                    fqName: [interner.intern(moduleName), name],
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .importedLibrary]
                )
                symbols.setFunctionSignature(
                    FunctionSignature(parameterTypes: [], returnType: types.unitType),
                    for: symbol
                )
                symbols.setExternalLinkName(linkName, for: symbol)
            }
            let metadataPath = manifestInfo.metadataPath
            let libraryModuleFQN: InternedString? = manifestInfo.moduleName.map { interner.intern($0) }
            if stdlibArtifact {
                stdlibModuleName = libraryModuleFQN
            }
            let indexedFile = cache?.cachedIndexedMetadataFile(metadataPath: metadataPath)
                ?? (try? Data(contentsOf: URL(fileURLWithPath: metadataPath))).flatMap(IndexedMetadataFile.init(data:))
            if let indexedFile {
                cache?.cacheIndexedMetadataFile(indexedFile, metadataPath: metadataPath)
                let nominalTypeParametersByFQName = Dictionary(
                    uniqueKeysWithValues: indexedFile.entries.compactMap { entry -> (String, String)? in
                        guard let signature = entry.record.nominalTypeParametersSignature else { return nil }
                        return (entry.record.fqName, signature)
                    }
                )
                for entry in indexedFile.entries {
                    guard let shell = makeImportedLibraryRecord(
                        entry.record,
                        path: metadataPath,
                        diagnostics: diagnostics,
                        interner: interner,
                        nominalTypeParametersByFQName: nominalTypeParametersByFQName
                    ) else { continue }
                    appendImportedBinding(
                        shell,
                        metadataPath: metadataPath,
                        inlineKIRDir: manifestInfo.inlineKIRDir,
                        isStdlibArtifact: stdlibArtifact,
                        materializeBody: { [indexedFile] in
                            guard let bodyRecord = indexedFile.record(for: entry)
                            else { return nil }
                            return self.makeImportedLibraryRecord(
                                bodyRecord,
                                path: metadataPath,
                                diagnostics: diagnostics,
                                interner: interner,
                                nominalTypeParametersByFQName: nominalTypeParametersByFQName
                            )
                        },
                        moduleFQN: libraryModuleFQN
                    )
                }
            } else {
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
                    appendImportedBinding(
                        record,
                        metadataPath: metadataPath,
                        inlineKIRDir: manifestInfo.inlineKIRDir,
                        isStdlibArtifact: stdlibArtifact,
                        moduleFQN: libraryModuleFQN
                    )
                }
            }
        }

        if options.stdlibLibraryPath != nil && !stdlibArtifactLoaded {
            diagnostics.error(
                "KSWIFTK-LIB-0020",
                "Stdlib library artifact '\(options.stdlibLibraryPath!)' could not be loaded",
                range: nil
            )
            return LibraryImportDeferredWork(
                pendingSupertypeEdges: [],
                importedBindings: [],
                lazyLoaderState: nil,
                stdlibModuleName: nil,
                klibModules: []
            )
        }

        // Member lookup needs the owner edge before it can ask the lazy loader
        // for a member's signature. Restore this structural relationship from
        // the compact index without decoding any declaration body.
        for binding in importedBindings {
            restoreImportedParentSymbol(binding.record, symbol: binding.symbol, symbols: symbols)
        }
        // Class-name receiver resolution needs the companion edge before it
        // asks for any declaration body. The compact index carries only the
        // companion FQ name, which is enough to restore that structural link
        // without materializing either nominal record.
        for binding in importedBindings {
            guard let companionFQName = binding.record.companionObjectFQName,
                  let companionSymbol = symbols.lookupAll(fqName: companionFQName)
                    .first(where: { candidate in
                        guard let candidateSymbol = symbols.symbol(candidate) else { return false }
                        return candidateSymbol.kind == .object
                            || candidateSymbol.kind == .class
                            || candidateSymbol.kind == .interface
                    })
            else {
                continue
            }
            symbols.setCompanionObjectSymbol(companionSymbol, for: binding.symbol)
        }

        var externalLinkNameToSymbol: [String: SymbolID] = [:]
        var importedSymbolByFQName: [String: SymbolID] = [:]
        for binding in importedBindings {
            if let linkName = binding.record.externalLinkName, !linkName.isEmpty {
                externalLinkNameToSymbol[linkName] = binding.symbol
            }
            // Inline bodies can call a default stub whose signature is restored
            // below. Resolve it to that symbol so ABI lowering retains the
            // parameter and return types, including the flat String ABI.
            if let linkName = binding.record.defaultStubExternalLinkName, !linkName.isEmpty {
                externalLinkNameToSymbol[linkName] = SyntheticSymbolScheme.defaultStubSymbol(for: binding.symbol)
            }
            let fQName = binding.record.fqName
                .map { interner.resolve($0) }
                .joined(separator: ".")
            if !fQName.isEmpty {
                importedSymbolByFQName[fQName] = binding.symbol
            }
        }
        // A shadowed member contributes its external link names the same
        // way a duplicate does — aliased to the winning library's
        // same-FQName counterpart. Members with no counterpart (loser-only
        // declarations) stay unmapped; no consumer code can name them, and
        // the losing library's own archive code remains self-consistent.
        for record in shadowedMemberRecords {
            guard let counterpart = symbols.lookupAll(fqName: record.fqName).first else {
                continue
            }
            shadowedDuplicateRecords.append((record: record, symbol: counterpart))
        }
        // A shadowed duplicate still contributes its external link names as
        // aliases of the merged symbol: call sites inside the losing library
        // (including its surviving non-duplicate declarations) resolve by
        // that library's own link names.
        for shadowed in shadowedDuplicateRecords {
            if let linkName = shadowed.record.externalLinkName, !linkName.isEmpty {
                externalLinkNameToSymbol[linkName] = shadowed.symbol
            }
            if let linkName = shadowed.record.defaultStubExternalLinkName, !linkName.isEmpty {
                externalLinkNameToSymbol[linkName] = SyntheticSymbolScheme.defaultStubSymbol(for: shadowed.symbol)
            }
        }

        // BUG-KSP-1217-PHANTOM-TYPE-PARAMS: a function's type parameter is
        // "phantom" when it never appears in its receiver, value parameters,
        // or return type (only inside the function body via explicit type
        // arguments, e.g. `kotlin.native.concurrent.callContinuation1<T1>`).
        // `importedFunctionSignature`/`collectTypeParameterSymbols` rebuild
        // `typeParameterSymbols` by structurally scanning the decoded function
        // type, so phantom parameters are silently dropped. Every declared
        // type parameter (phantom or not) is independently exported as its
        // own `.typeParameter`-kind record with fqName
        // `<ownerFQName>.$<producerSymbolID>.<paramName>` (see
        // HeaderCollection.swift's `$\(symbol.rawValue)` namespace segment),
        // so group those records by owner FQ name to recover at least the
        // correct total COUNT of declared type parameters. The `$<id>`
        // disambiguator itself is a producer-internal id with no stable
        // meaning on the consumer side, so this is restricted to owner FQ
        // names with exactly one function/constructor binding -- an
        // overloaded name could mix phantom parameters from different
        // overloads and there is no reliable way to tell them apart.
        var functionBindingCountByFQName: [[InternedString]: Int] = [:]
        var typeParameterBindingSymbolsByOwnerFQName: [[InternedString]: [SymbolID]] = [:]
        for binding in importedBindings {
            switch binding.record.kind {
            case .function, .constructor:
                functionBindingCountByFQName[binding.record.fqName, default: 0] += 1
            case .typeParameter:
                let fqName = binding.record.fqName
                guard fqName.count >= 3, interner.resolve(fqName[fqName.count - 2]).hasPrefix("$") else {
                    continue
                }
                let ownerFQName = Array(fqName.dropLast(2))
                typeParameterBindingSymbolsByOwnerFQName[ownerFQName, default: []].append(binding.symbol)
            default:
                break
            }
        }
        let phantomTypeParameterSymbolsByOwnerFQName = typeParameterBindingSymbolsByOwnerFQName.filter {
            functionBindingCountByFQName[$0.key] == 1
        }

        // Property getter accessors are synthesized while applying their
        // property records. Import those records before inline function bodies
        // so a producer getter link (for example Lazy.value) resolves to the
        // consumer-side accessor symbol when the inline virtual call is parsed.
        let propertyBindingsWithGetter = importedBindings.filter { binding in
            (binding.record.kind == .property || binding.record.kind == .field)
                && binding.record.propertyGetterExternalLinkName?.isEmpty == false
                // Enum `entries` has a metadata type of `kotlin.enums.EnumEntries`,
                // whose residual interface is registered after imports. Leave
                // this property lazy so its signature is decoded after the
                // synthetic enum foundations are available.
                && !(
                    binding.record.fqName.last == interner.intern("entries")
                    && binding.record.fqName.dropLast().last == interner.intern("Companion")
                )
        }
        for binding in propertyBindingsWithGetter {
            applyImportedBinding(
                binding,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                importedInlineFunctions: importedInlineFunctions,
                pendingSupertypeEdges: &pendingSupertypeEdges,
                cache: cache,
                isStdlibArtifact: binding.isStdlibArtifact,
                phantomTypeParameterSymbolsByOwnerFQName: phantomTypeParameterSymbolsByOwnerFQName
            )
        }
        for binding in propertyBindingsWithGetter {
            guard let getterLink = binding.record.propertyGetterExternalLinkName,
                  let getterSymbol = symbols.extensionPropertyGetterAccessor(for: binding.symbol)
            else {
                continue
            }
            externalLinkNameToSymbol[getterLink] = getterSymbol
        }
        for shadowed in shadowedDuplicateRecords {
            guard shadowed.record.kind == .property || shadowed.record.kind == .field,
                  let getterLink = shadowed.record.propertyGetterExternalLinkName,
                  !getterLink.isEmpty,
                  let getterSymbol = symbols.extensionPropertyGetterAccessor(for: shadowed.symbol)
            else {
                continue
            }
            externalLinkNameToSymbol[getterLink] = getterSymbol
        }

        let preloadedGetterBindingSymbols = Set(propertyBindingsWithGetter.map(\.symbol))
        let lazyMetadataEnabled = importedBindings.contains { !$0.isMaterialized }

        // Indexed declarations stay as shells. The callback is invoked by
        // SymbolTable semantic-data accessors and applies exactly one body
        // record before returning the requested value.
        let bindingsBySymbol = Dictionary(uniqueKeysWithValues: importedBindings.map { ($0.symbol, $0) })
        lazyLoaderState.indexedBindingsBySymbol = bindingsBySymbol
        if lazyMetadataEnabled {
            // `symbols` is weak: this closure is stored on the symbol table
            // itself, so a strong capture would be a retain cycle leaking the
            // table (and every captured import structure) past compilation end.
            symbols.setLazyImportedMetadataLoader(alreadyLoaded: preloadedGetterBindingSymbols) { [self, weak symbols] symbol in
            guard let symbols else { return }
            guard let binding = bindingsBySymbol[symbol] else { return }
            var bindingEdges: [(subtype: SymbolID, superFQName: [InternedString])] = []
            self.applyImportedBinding(
                binding,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                importedInlineFunctions: importedInlineFunctions,
                pendingSupertypeEdges: &bindingEdges,
                cache: cache,
                isStdlibArtifact: binding.isStdlibArtifact,
                phantomTypeParameterSymbolsByOwnerFQName: phantomTypeParameterSymbolsByOwnerFQName
            )
            let layoutDiagnostics: DiagnosticEngine
            if lazyLoaderState.layoutBootstrapComplete {
                layoutDiagnostics = diagnostics
            } else {
                layoutDiagnostics = DiagnosticEngine()
                lazyLoaderState.pendingLayoutRetries.append(binding)
            }
            self.applyImportedLibraryBindingDeferredDetails(
                binding,
                pendingSupertypeEdges: bindingEdges,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                layoutDiagnostics: layoutDiagnostics,
                bundledIndexReady: lazyLoaderState.layoutBootstrapComplete,
                interner: interner,
                bundledIndex: lazyLoaderState.bundledIndex,
                indexedBindingsBySymbol: bindingsBySymbol
            )
            self.normalizeImportedMemberBinding(
                binding,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                cache: cache
            )
            }
            // Stored on `lazyLoaderState` itself; weak captures break the
            // self-cycle and the state -> symbols back-reference.
            lazyLoaderState.resolveDemandedInlineBodies = { [self, weak symbols, weak lazyLoaderState] module in
                guard let symbols, let lazyLoaderState else { return }
                self.resolveDemandedImportedInlineBodies(
                    module: module,
                    state: lazyLoaderState,
                    symbols: symbols,
                    types: types,
                    diagnostics: diagnostics,
                    interner: interner,
                    externalLinkNameToSymbol: externalLinkNameToSymbol,
                    importedSymbolByFQName: importedSymbolByFQName
                )
            }
        } else {
            // Legacy metadata has already been fully decoded. Preserve its
            // eager import behavior and the existing cache/test contract.
            for binding in importedBindings where !preloadedGetterBindingSymbols.contains(binding.symbol) {
                applyImportedBinding(
                    binding,
                    symbols: symbols,
                    types: types,
                    diagnostics: diagnostics,
                    interner: interner,
                    importedInlineFunctions: importedInlineFunctions,
                    pendingSupertypeEdges: &pendingSupertypeEdges,
                    cache: cache,
                    isStdlibArtifact: binding.isStdlibArtifact,
                    phantomTypeParameterSymbolsByOwnerFQName: phantomTypeParameterSymbolsByOwnerFQName
                )
            }
        }

        var syntheticPackagePaths: Set<[InternedString]> = []
        var syntheticPackageModules: [[InternedString]: InternedString] = [:]
        // STDLIB-SHARED-011: Type/value parameters and local symbols belong to a
        // real owner; their FQ name prefixes must not be synthesised as packages.
        let packageOwnerRecordKinds: Set<SymbolKind> = [
            .class, .interface, .object, .enumClass, .annotationClass,
            .typeAlias, .function, .property, .constructor
        ]
        for binding in importedBindings
            where binding.record.kind != .package
            && packageOwnerRecordKinds.contains(binding.record.kind)
        {
            let fq = binding.record.fqName
            let moduleFQN = symbols.moduleFQN(for: binding.symbol)
            for length in 1 ..< fq.count {
                let prefix = Array(fq.prefix(length))
                // Constructors are named below their nominal owner (for
                // example, `pkg.Type.<init>`). Keep that owner path nominal
                // when it already exists; package-level functions may legally
                // share the same FQ-name prefix as a class and still require
                // a package symbol for import resolution.
                if binding.record.kind == .constructor,
                   prefix == Array(fq.dropLast()),
                   symbols.lookupAll(fqName: prefix).contains(where: { id in
                    symbols.symbol(id)?.kind != .package
                }) {
                    continue
                }
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

        if lazyMetadataEnabled {
            // Enum class-name APIs are structural shells, not declaration
            // bodies. Register them from the compact records so `Enum.entries`
            // can resolve before a body query, while keeping ordinary members
            // lazy. Stdlib enum APIs are supplied by the bundled source pass.
            let importedEnumWork = LibraryImportDeferredWork(
                pendingSupertypeEdges: [],
                importedBindings: importedBindings.filter { !$0.isStdlibArtifact },
                lazyLoaderState: nil,
                stdlibModuleName: nil,
                klibModules: []
            )
            applyImportedEnumSyntheticMembers(
                work: importedEnumWork,
                symbols: symbols,
                types: types,
                interner: interner,
                bundledIndex: .empty
            )
        }

        // Bind the resolution context for deferred inline-body parses only
        // after every binding has been applied, so a lazy parse resolves
        // callees against the final link-name and FQ-name maps — exactly the
        // maps the eager parse observed.
        importedInlineFunctions.bindParseContext(
            types: types,
            interner: interner,
            diagnostics: diagnostics,
            externalLinkNameToSymbol: externalLinkNameToSymbol,
            importedSymbolByFQName: importedSymbolByFQName
        )

        // `depends` ordering: a dependency's module init (top-level field
        // stores, object pre-allocations) must run before its dependents'.
        // KIR lowering iterates `klibModules` in this order.
        if !recognizedKlibs.isEmpty {
            let ordered = resolveKlibDependencies(
                recognizedKlibs,
                stdlibPresent: stdlibArtifactLoaded || options.includeStdlib,
                diagnostics: diagnostics
            )
            var rank: [String: Int] = [:]
            for (index, module) in ordered.enumerated() {
                rank[module.uniqueName] = index
            }
            klibModules.sort {
                (rank[$0.module.uniqueName] ?? .max) < (rank[$1.module.uniqueName] ?? .max)
            }
        }

        return LibraryImportDeferredWork(
            pendingSupertypeEdges: pendingSupertypeEdges,
            importedBindings: importedBindings,
            lazyLoaderState: lazyMetadataEnabled ? lazyLoaderState : nil,
            stdlibModuleName: stdlibModuleName,
            klibModules: klibModules
        )
    }

    private func applyImportedLibraryBindingDeferredDetails(
        _ binding: ImportedLibraryBinding,
        pendingSupertypeEdges: [(subtype: SymbolID, superFQName: [InternedString])],
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        layoutDiagnostics: DiagnosticEngine,
        bundledIndexReady: Bool,
        interner: StringInterner,
        bundledIndex: BundledDeclarationIndex,
        indexedBindingsBySymbol: [SymbolID: ImportedLibraryBinding]
    ) {
        for edge in pendingSupertypeEdges {
            guard let superSymbol = symbols.lookupAll(fqName: edge.superFQName)
                .compactMap({ symbols.symbol($0) })
                .first(where: { isNominalLayoutTargetSymbol($0.kind) })?.id
            else { continue }
            var supertypes = symbols.directSupertypes(for: edge.subtype)
            if !supertypes.contains(superSymbol) {
                supertypes.append(superSymbol)
                supertypes.sort(by: { $0.rawValue < $1.rawValue })
                symbols.setDirectSupertypes(supertypes, for: edge.subtype)
                types.setNominalDirectSupertypes(supertypes, for: edge.subtype)
            }
        }

        guard isNominalLayoutTargetSymbol(binding.record.kind) else { return }
        applyImportedNominalGenerics(
            binding,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner
        )

        if let companionFQName = binding.record.companionObjectFQName,
           let companionSymbol = symbols.lookupAll(fqName: companionFQName)
               .compactMap({ symbols.symbol($0) })
               .first(where: { $0.kind == .object || $0.kind == .class || $0.kind == .interface })?.id
        {
            symbols.setCompanionObjectSymbol(companionSymbol, for: binding.symbol)
        }

        applyImportedNominalLayout(
            record: binding.record,
            symbol: binding.symbol,
            symbols: symbols,
            types: types,
            diagnostics: layoutDiagnostics,
            metadataPath: binding.metadataPath,
            interner: interner,
            indexedBindingsBySymbol: indexedBindingsBySymbol
        )

        let singleBindingWork = LibraryImportDeferredWork(
            pendingSupertypeEdges: [],
            importedBindings: [binding],
            lazyLoaderState: nil,
            stdlibModuleName: nil,
            klibModules: []
        )
        applyImportedObjectAndCompanionInitializerSymbols(
            work: singleBindingWork,
            symbols: symbols,
            types: types,
            interner: interner
        )

        if binding.record.isSealedClass, !binding.record.sealedSubclassFQNames.isEmpty {
            let resolvedSubclasses: [SymbolID] = binding.record.sealedSubclassFQNames.compactMap { subFQName in
                symbols.lookupAll(fqName: subFQName)
                    .compactMap { symbols.symbol($0) }
                    .first(where: { isNominalLayoutTargetSymbol($0.kind) })?.id
            }
            if resolvedSubclasses.count == binding.record.sealedSubclassFQNames.count {
                symbols.setSealedSubclasses(resolvedSubclasses, for: binding.symbol)
            } else {
                symbols.setSealedSubclasses([], for: binding.symbol)
            }
        }

        // Before the bundled index is installed the `values` skip guard cannot
        // see source-backed enums; the deferred-work retry applies them then.
        if binding.record.kind == .enumClass, bundledIndexReady {
            applyImportedEnumSyntheticMembers(
                work: singleBindingWork,
                symbols: symbols,
                types: types,
                interner: interner,
                bundledIndex: bundledIndex
            )
        }
    }

    func applyImportedLibraryDeferredWork(
        _ work: LibraryImportDeferredWork,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        bundledIndex: BundledDeclarationIndex
    ) {
        if let lazyLoaderState = work.lazyLoaderState {
            // Bootstrap stubs now exist: re-apply layouts that were computed
            // earlier (warnings withheld) so unresolved slots are reported
            // only if they are still unresolved, and later materializations
            // report directly.
            lazyLoaderState.layoutBootstrapComplete = true
            let retries = lazyLoaderState.pendingLayoutRetries
            lazyLoaderState.pendingLayoutRetries = []
            for binding in retries {
                // Synthetic bootstrap registration may have replaced the
                // direct supertypes of a binding materialized before it ran;
                // the eager path applies these edges after bootstrap, so
                // restore any that were dropped.
                let allSuperFQNames = binding.record.superFQNames
                    ?? binding.record.superFQName.map { [$0] } ?? []
                for superFQName in allSuperFQNames where !superFQName.isEmpty {
                    guard let superSymbol = symbols.lookupAll(fqName: superFQName)
                        .compactMap({ symbols.symbol($0) })
                        .first(where: { isNominalLayoutTargetSymbol($0.kind) })?.id
                    else { continue }
                    var supertypes = symbols.directSupertypes(for: binding.symbol)
                    if !supertypes.contains(superSymbol) {
                        supertypes.append(superSymbol)
                        supertypes.sort(by: { $0.rawValue < $1.rawValue })
                        symbols.setDirectSupertypes(supertypes, for: binding.symbol)
                        types.setNominalDirectSupertypes(supertypes, for: binding.symbol)
                    }
                }
                if binding.record.kind == .enumClass {
                    applyImportedEnumSyntheticMembers(
                        work: LibraryImportDeferredWork(
                            pendingSupertypeEdges: [],
                            importedBindings: [binding],
                            lazyLoaderState: nil,
                            stdlibModuleName: nil,
                            klibModules: []
                        ),
                        symbols: symbols,
                        types: types,
                        interner: interner,
                        bundledIndex: bundledIndex
                    )
                }
                applyImportedNominalLayout(
                    record: binding.record,
                    symbol: binding.symbol,
                    symbols: symbols,
                    types: types,
                    diagnostics: diagnostics,
                    metadataPath: binding.metadataPath,
                    interner: interner,
                    indexedBindingsBySymbol: lazyLoaderState.indexedBindingsBySymbol
                )
            }
            // Indexed metadata owns its deferred work and resolves it from the
            // per-symbol materialization callback. Eagerly walking all nominal
            // records here would defeat ARCH-029's lazy boundary.
            for edge in work.pendingSupertypeEdges {
                guard let superSymbol = symbols.lookupAll(fqName: edge.superFQName)
                    .compactMap({ symbols.symbol($0) })
                    .first(where: { isNominalLayoutTargetSymbol($0.kind) })?.id
                else { continue }
                var supertypes = symbols.directSupertypes(for: edge.subtype)
                if !supertypes.contains(superSymbol) {
                    supertypes.append(superSymbol)
                    supertypes.sort(by: { $0.rawValue < $1.rawValue })
                    symbols.setDirectSupertypes(supertypes, for: edge.subtype)
                    types.setNominalDirectSupertypes(supertypes, for: edge.subtype)
                }
            }
            return
        }
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
            applyImportedNominalGenerics(
                binding,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner
            )
        }

        // Resolve companion object references so ClassName.member() shorthand works.
        for binding in work.importedBindings where isNominalLayoutTargetSymbol(binding.record.kind) {
            if let companionFQName = binding.record.companionObjectFQName,
               let companionSymbol = symbols.lookupAll(fqName: companionFQName)
                   .compactMap({ symbols.symbol($0) })
                   .first(where: { $0.kind == .object || $0.kind == .class || $0.kind == .interface })?.id
            {
                symbols.setCompanionObjectSymbol(companionSymbol, for: binding.symbol)
            }
        }

        for binding in work.importedBindings where isNominalLayoutTargetSymbol(binding.record.kind) {
            applyImportedNominalLayout(
                record: binding.record,
                symbol: binding.symbol,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                metadataPath: binding.metadataPath,
                interner: interner
            )
        }

        applyImportedObjectAndCompanionInitializerSymbols(
            work: work,
            symbols: symbols,
            types: types,
            interner: interner
        )

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

        // Imported enum classes have no AST declarations, so the per-decl enum
        // member synthesis in HeaderCollection never runs for them. Register
        // the implicit enum API (name/ordinal, values(), valueOf(_:), entries)
        // here so it resolves on the artifact path as well. Lowering reuses
        // these symbols when it synthesizes their KIR bodies
        // (DataEnumSealedSynthesisPass looks them up by FQ name and owner).
        applyImportedEnumSyntheticMembers(
            work: work,
            symbols: symbols,
            types: types,
            interner: interner,
            bundledIndex: bundledIndex
        )
    }

    /// Registers the implicit enum members that HeaderCollection normally
    /// creates from an enum declaration for enums that only exist as imported
    /// library records. Mirrors `collectSyntheticEnumEntryProperties`,
    /// `collectSyntheticEnumValuesMember`, and
    /// `collectSyntheticEnumCompanionMembers`, including the source-path flag
    /// set so golden rendering matches between the two paths.
    private func applyImportedEnumSyntheticMembers(
        work: LibraryImportDeferredWork,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        bundledIndex: BundledDeclarationIndex
    ) {
        let stringType = types.stringType
        let intType = types.make(.primitive(.int, .nonNull))
        let enumEntriesSymbol = symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("enums"),
            interner.intern("EnumEntries"),
        ])
        let arraySymbol = symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("Array"),
        ])

        for binding in work.importedBindings where binding.record.kind == .enumClass {
            let enumSymbol = binding.symbol
            let enumFQName = binding.record.fqName
            let enumType = types.make(.classType(ClassType(
                classSymbol: enumSymbol,
                args: [],
                nullability: .nonNull
            )))

            for (memberName, memberType) in [
                (interner.intern("name"), stringType),
                (interner.intern("ordinal"), intType),
            ] {
                let memberFQName = enumFQName + [memberName]
                if let existingProperty = symbols.lookupAll(fqName: memberFQName)
                    .compactMap({ symbols.symbol($0) })
                    .first(where: { $0.kind == .property })
                {
                    symbols.setParentSymbol(enumSymbol, for: existingProperty.id)
                    continue
                }
                let propertySymbol = symbols.define(
                    kind: .property,
                    name: memberName,
                    fqName: memberFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(enumSymbol, for: propertySymbol)
                symbols.setPropertyType(memberType, for: propertySymbol)
            }

            // Mirror `collectSyntheticEnumValuesMember`: skip `values` when a
            // source-backed declaration already owns the class-name API for
            // this enum (for example `RequiresOptIn.Level.values()`).
            let valuesName = interner.intern("values")
            let valuesFQName = enumFQName + [valuesName]
            if !bundledIndex.contains(ownerFQName: enumFQName, name: valuesName, arity: 0),
               let existingValues = symbols.lookupAll(fqName: valuesFQName)
                   .compactMap({ symbols.symbol($0) })
                   .first(where: { $0.kind == .function })
            {
                symbols.setParentSymbol(enumSymbol, for: existingValues.id)
            } else if !bundledIndex.contains(ownerFQName: enumFQName, name: valuesName, arity: 0),
                      symbols.lookupAll(fqName: valuesFQName).allSatisfy({
                          symbols.symbol($0)?.kind != .function
                      }), let arraySymbol {
                let arrayType = types.make(.classType(ClassType(
                    classSymbol: arraySymbol,
                    args: [.invariant(enumType)],
                    nullability: .nonNull
                )))
                let valuesSymbol = symbols.define(
                    kind: .function,
                    name: valuesName,
                    fqName: valuesFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .static]
                )
                symbols.setParentSymbol(enumSymbol, for: valuesSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        parameterTypes: [],
                        returnType: arrayType,
                        isSuspend: false
                    ),
                    for: valuesSymbol
                )
            }

            let companionSymbol: SymbolID
            let companionLookupFQName = binding.record.companionObjectFQName
                ?? enumFQName + [interner.intern("Companion")]
            if let indexedCompanion = symbols.lookupAll(fqName: companionLookupFQName)
                .compactMap({ symbols.symbol($0) })
                .first(where: { $0.kind == .object })
            {
                companionSymbol = indexedCompanion.id
                symbols.setCompanionObjectSymbol(companionSymbol, for: enumSymbol)
            } else if let existingCompanion = symbols.companionObjectSymbol(for: enumSymbol) {
                companionSymbol = existingCompanion
            } else {
                let companionName = interner.intern("Companion")
                if let found = symbols.lookupAll(fqName: companionLookupFQName).first(where: {
                    symbols.symbol($0)?.kind == .object
                }) {
                    companionSymbol = found
                } else {
                    companionSymbol = symbols.define(
                        kind: .object,
                        name: companionName,
                        fqName: companionLookupFQName,
                        declSite: nil,
                        visibility: .public,
                        flags: [.synthetic]
                    )
                    symbols.setParentSymbol(enumSymbol, for: companionSymbol)
                }
                symbols.setCompanionObjectSymbol(companionSymbol, for: enumSymbol)
            }
            guard let companionInfo = symbols.symbol(companionSymbol) else {
                continue
            }
            let companionFQName = companionInfo.fqName
            let companionType = types.make(.classType(ClassType(
                classSymbol: companionSymbol,
                args: [],
                nullability: .nonNull
            )))

            let valueOfName = interner.intern("valueOf")
            let valueOfFQName = companionFQName + [valueOfName]
            if symbols.lookupAll(fqName: valueOfFQName).allSatisfy({
                symbols.symbol($0)?.kind != .function
            }) {
                let paramName = interner.intern("name")
                let paramSymbol = symbols.define(
                    kind: .valueParameter,
                    name: paramName,
                    fqName: valueOfFQName + [paramName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                let valueOfSymbol = symbols.define(
                    kind: .function,
                    name: valueOfName,
                    fqName: valueOfFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .static]
                )
                symbols.setParentSymbol(companionSymbol, for: valueOfSymbol)
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
                    for: valueOfSymbol
                )
            }

            if let enumEntriesSymbol {
                let entriesName = interner.intern("entries")
                let entriesFQName = companionFQName + [entriesName]
                if let existingEntries = symbols.lookupAll(fqName: entriesFQName)
                    .compactMap({ symbols.symbol($0) })
                    .first(where: { $0.kind == .property })
                {
                    symbols.insertFlags([.static], for: existingEntries.id)
                    symbols.setParentSymbol(companionSymbol, for: existingEntries.id)
                } else {
                    let entriesType = types.make(.classType(ClassType(
                        classSymbol: enumEntriesSymbol,
                        args: [.invariant(enumType)],
                        nullability: .nonNull
                    )))
                    let entriesSymbol = symbols.define(
                        kind: .property,
                        name: entriesName,
                        fqName: entriesFQName,
                        declSite: nil,
                        visibility: .public,
                        flags: [.synthetic, .static]
                    )
                    symbols.setParentSymbol(companionSymbol, for: entriesSymbol)
                    symbols.setPropertyType(entriesType, for: entriesSymbol)
                }
            }

        }
    }

    /// Normalizes imported member signatures after synthetic bundled anchors
    /// have been registered. Those anchors may provide the consumer's actual
    /// owner type-parameter symbols, which are not available during the
    /// initial library-record pass.
    func normalizeImportedLibraryMemberSignatures(
        _ work: LibraryImportDeferredWork,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        let cache = LibraryMetadataCache()
        for binding in work.importedBindings {
            guard binding.isMaterialized else { continue }
            normalizeImportedMemberBinding(
                binding,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                cache: cache
            )
        }
    }

    private func normalizeImportedMemberBinding(
        _ binding: ImportedLibraryBinding,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        cache: LibraryMetadataCache?
    ) {
        switch binding.record.kind {
        case .function, .constructor:
            guard let signature = symbols.functionSignature(for: binding.symbol) else {
                return
            }
            if let parentSymbol = symbols.parentSymbol(for: binding.symbol),
               let parent = symbols.symbol(parentSymbol),
               isNominalLayoutTargetSymbol(parent.kind)
            {
                symbols.ensureLazyImportedMetadataLoaded(for: parentSymbol)
            }
            let normalize: (TypeID) -> TypeID = { type in
                self.normalizeImportedOwnerTypeParameters(
                    type,
                    record: binding.record,
                    symbols: symbols,
                    types: types,
                    diagnostics: diagnostics,
                    interner: interner,
                    metadataPath: binding.metadataPath,
                    cache: cache,
                    allowPlaceholders: binding.isStdlibArtifact
                )
            }
            let ownerTypeParameters = symbols.parentSymbol(for: binding.symbol)
                .map { types.nominalTypeParameterSymbols(for: $0) } ?? []
            let ownerCount = min(signature.classTypeParameterCount, ownerTypeParameters.count)
            let normalizedTypeParameterSymbols = ownerCount == 0
                ? signature.typeParameterSymbols
                : Array(ownerTypeParameters.prefix(ownerCount))
                    + signature.typeParameterSymbols.dropFirst(ownerCount)
            let normalizedUpperBoundsList = signature.typeParameterUpperBoundsList.map { $0.map(normalize) }
            for index in 0 ..< min(signature.classTypeParameterCount, normalizedTypeParameterSymbols.count) {
                guard index < normalizedUpperBoundsList.count else {
                    continue
                }
                let upperBounds = normalizedUpperBoundsList[index]
                let typeParameterSymbol = normalizedTypeParameterSymbols[index]
                if !upperBounds.isEmpty,
                   symbols.typeParameterUpperBounds(for: typeParameterSymbol).isEmpty
                {
                    symbols.setTypeParameterUpperBounds(upperBounds, for: typeParameterSymbol)
                }
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: signature.receiverType.map(normalize),
                    parameterTypes: signature.parameterTypes.map(normalize),
                    returnType: normalize(signature.returnType),
                    isSuspend: signature.isSuspend,
                    canThrow: signature.canThrow,
                    valueParameterSymbols: signature.valueParameterSymbols,
                    valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                    valueParameterIsVararg: signature.valueParameterIsVararg,
                    valueParameterAllowsNonLocalReturn: signature.valueParameterAllowsNonLocalReturn,
                    hasExplicitInlineParameterMetadata: signature.hasExplicitInlineParameterMetadata,
                    typeParameterSymbols: normalizedTypeParameterSymbols,
                    reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices,
                    typeParameterUpperBoundsList: normalizedUpperBoundsList,
                    classTypeParameterCount: signature.classTypeParameterCount
                ),
                for: binding.symbol
            )
        case .property, .field:
            if let parentSymbol = symbols.parentSymbol(for: binding.symbol),
               let parent = symbols.symbol(parentSymbol),
               isNominalLayoutTargetSymbol(parent.kind)
            {
                symbols.ensureLazyImportedMetadataLoaded(for: parentSymbol)
            }
            let propertyType = importedPropertyType(
                record: binding.record,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                metadataPath: binding.metadataPath,
                cache: cache,
                allowPlaceholders: binding.isStdlibArtifact
            )
            symbols.setPropertyType(propertyType, for: binding.symbol)
            if binding.record.isMemberExtension {
                normalizeImportedExtensionPropertyAccessors(
                    binding, symbols: symbols, types: types, diagnostics: diagnostics,
                    interner: interner, cache: cache
                )
            }
        default:
            return
        }
    }

    /// Property getter links are preloaded before lazy owner callbacks are
    /// installed. Complete their owner parameter prefix after owner metadata
    /// becomes available, just as for imported member function signatures.
    private func normalizeImportedExtensionPropertyAccessors(
        _ binding: ImportedLibraryBinding,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        cache: LibraryMetadataCache?
    ) {
        guard let owner = symbols.parentSymbol(for: binding.symbol) else { return }
        let ownerParameters = types.nominalTypeParameterSymbols(for: owner)
        let normalize: (TypeID) -> TypeID = {
            self.normalizeImportedOwnerTypeParameters(
                $0, record: binding.record, symbols: symbols, types: types,
                diagnostics: diagnostics, interner: interner,
                metadataPath: binding.metadataPath, cache: cache,
                allowPlaceholders: binding.isStdlibArtifact
            )
        }
        if let receiver = symbols.extensionPropertyReceiverType(for: binding.symbol) {
            symbols.setExtensionPropertyReceiverType(normalize(receiver), for: binding.symbol)
        }
        let accessors = [symbols.extensionPropertyGetterAccessor(for: binding.symbol),
                         symbols.extensionPropertySetterAccessor(for: binding.symbol)].compactMap { $0 }
        for accessor in accessors {
            guard let signature = symbols.functionSignature(for: accessor) else { continue }
            let ownerCount = min(ownerParameters.count, signature.typeParameterSymbols.count)
            let parameters = Array(ownerParameters.prefix(ownerCount))
                + signature.typeParameterSymbols.dropFirst(ownerCount)
            let bounds = signature.typeParameterUpperBoundsList.map { $0.map(normalize) }
            for (parameter, upperBounds) in zip(parameters, bounds) where !upperBounds.isEmpty {
                symbols.setTypeParameterUpperBounds(upperBounds, for: parameter)
            }
            symbols.setFunctionSignature(FunctionSignature(
                receiverType: signature.receiverType.map(normalize),
                contextReceiverTypes: signature.contextReceiverTypes.map(normalize),
                parameterTypes: signature.parameterTypes.map(normalize),
                returnType: normalize(signature.returnType),
                isSuspend: signature.isSuspend, canThrow: signature.canThrow,
                valueParameterSymbols: signature.valueParameterSymbols,
                valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                valueParameterIsVararg: signature.valueParameterIsVararg,
                valueParameterAllowsNonLocalReturn: signature.valueParameterAllowsNonLocalReturn,
                hasExplicitInlineParameterMetadata: signature.hasExplicitInlineParameterMetadata,
                typeParameterSymbols: parameters,
                reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices,
                typeParameterUpperBoundsList: bounds, classTypeParameterCount: ownerCount
            ), for: accessor)
        }
    }

    /// Restores the generic shape of an imported nominal type: its own type
    /// parameters (with declared variance) and the type arguments it passes to
    /// each generic supertype. Without them a `class Sub<T> : Base<T>` read back
    /// from metadata behaves like a raw type, so `Sub<Int>` neither lifts to
    /// `Base<Int>` nor substitutes `T` in its members' signatures.
    private func applyImportedNominalGenerics(
        _ binding: ImportedLibraryBinding,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        binding.materialize()
        let record = binding.record
        let decode: (String) -> ClassType? = { token in
            guard let decoded = self.decodeImportedTypeSignature(
                token: token,
                symbols: symbols,
                types: types,
                interner: interner,
                diagnostics: diagnostics,
                metadataPath: binding.metadataPath,
                ownerFQName: record.fqName,
                allowPlaceholders: binding.isStdlibArtifact
            ), case let .classType(classType) = types.kind(of: decoded) else {
                return nil
            }
            return classType
        }

        if types.nominalTypeParameterSymbols(for: binding.symbol).isEmpty,
           let selfSignature = record.nominalTypeParametersSignature,
           let selfType = decode(selfSignature)
        {
            var typeParameterSymbols: [SymbolID] = []
            var variances: [TypeVariance] = []
            var isValid = true
            arguments: for arg in selfType.args {
                let argType: TypeID
                switch arg {
                case let .invariant(type):
                    argType = type
                    variances.append(.invariant)
                case let .out(type):
                    argType = type
                    variances.append(.out)
                case let .in(type):
                    argType = type
                    variances.append(.in)
                case .star:
                    isValid = false
                    break arguments
                }
                guard case let .typeParam(typeParam) = types.kind(of: argType) else {
                    isValid = false
                    break arguments
                }
                typeParameterSymbols.append(typeParam.symbol)
            }
            if isValid && !typeParameterSymbols.isEmpty {
                types.setNominalTypeParameterSymbols(typeParameterSymbols, for: binding.symbol)
                if variances.contains(where: { $0 != .invariant }) {
                    types.setNominalTypeParameterVariances(variances, for: binding.symbol)
                }
            }
        }

        // The nominal's own type parameters may already be bound to real
        // declaration symbols (e.g. `kotlin.Enum<T>` declared by the bundled
        // source shell) while the metadata signatures spell them as synthetic
        // `T<n>` symbols. `liftedNominalSupertypeArgs` substitutes by the
        // registered symbols, so rewrite the synthetic ones to the registered
        // ones or `Enum<Color>` would lift to `Comparable<T<n>>` instead of
        // `Comparable<Color>`.
        let syntheticToRegisteredParameters = importedSyntheticToRegisteredTypeParameters(
            record: record,
            registeredSymbols: types.nominalTypeParameterSymbols(for: binding.symbol),
            decode: decode,
            types: types
        )
        for supertypeSignature in record.nominalSupertypeSignatures {
            guard let supertype = decode(supertypeSignature),
                  !supertype.args.isEmpty,
                  types.nominalSupertypeTypeArgs(for: binding.symbol, supertype: supertype.classSymbol).isEmpty
            else {
                continue
            }
            let args = syntheticToRegisteredParameters.map { mapping in
                supertype.args.map { types.substitutingTypeParameterSymbols($0, mapping: mapping) }
            } ?? supertype.args
            types.setNominalSupertypeTypeArgs(args, for: binding.symbol, supertype: supertype.classSymbol)
        }

        if binding.record.kind == .enumClass,
           let enumBaseSymbol = symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("Enum"),
           ]),
           symbols.directSupertypes(for: binding.symbol).contains(enumBaseSymbol),
           types.nominalSupertypeTypeArgs(for: binding.symbol, supertype: enumBaseSymbol).isEmpty
        {
            let enumType = types.make(.classType(ClassType(
                classSymbol: binding.symbol,
                args: [],
                nullability: .nonNull
            )))
            let enumTypeArg: [TypeArg] = [.invariant(enumType)]
            symbols.setSupertypeTypeArgs(enumTypeArg, for: binding.symbol, supertype: enumBaseSymbol)
            types.setNominalSupertypeTypeArgs(enumTypeArg, for: binding.symbol, supertype: enumBaseSymbol)
        }
    }

    /// Maps the synthetic type-parameter symbols spelled by an imported
    /// nominal's `typeParamsSig` to the symbols already registered for it, by
    /// position. Returns `nil` when there is nothing to rewrite (no registered
    /// parameters, no self signature, or both spellings already agree).
    private func importedSyntheticToRegisteredTypeParameters(
        record: ImportedLibrarySymbolRecord,
        registeredSymbols: [SymbolID],
        decode: (String) -> ClassType?,
        types: TypeSystem
    ) -> [SymbolID: SymbolID]? {
        guard !registeredSymbols.isEmpty,
              let selfSignature = record.nominalTypeParametersSignature,
              let selfType = decode(selfSignature),
              selfType.args.count == registeredSymbols.count
        else {
            return nil
        }
        var mapping: [SymbolID: SymbolID] = [:]
        for (arg, registered) in zip(selfType.args, registeredSymbols) {
            switch arg {
            case let .invariant(type), let .out(type), let .in(type):
                guard case let .typeParam(typeParam) = types.kind(of: type) else { return nil }
                if typeParam.symbol != registered {
                    mapping[typeParam.symbol] = registered
                }
            case .star:
                return nil
            }
        }
        return mapping.isEmpty ? nil : mapping
    }

    /// Synthesizes function symbols for precompiled object/companion initializers
    /// discovered in library metadata so that consumers can call them before user `main`.
    private func applyImportedObjectAndCompanionInitializerSymbols(
        work: LibraryImportDeferredWork,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        for binding in work.importedBindings where isNominalLayoutTargetSymbol(binding.record.kind) {
            let record = binding.record
            let ownerSymbol = binding.symbol

            if record.kind == .object,
               let linkName = record.objectInitializerLinkName,
               !linkName.isEmpty
            {
                let name = interner.intern("__object_init")
                let fqName = record.fqName + [name]
                let initSymbol = symbols.define(
                    kind: .function,
                    name: name,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .importedLibrary]
                )
                symbols.setParentSymbol(ownerSymbol, for: initSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        parameterTypes: [],
                        returnType: types.unitType
                    ),
                    for: initSymbol
                )
                symbols.setExternalLinkName(linkName, for: initSymbol)
                symbols.setObjectInitializerSymbol(initSymbol, for: ownerSymbol)
            }

            if record.kind == .object,
               let linkName = record.objectLazyInitializerLinkName,
               !linkName.isEmpty
            {
                let name = interner.intern(linkName)
                let fqName = record.fqName + [interner.intern("__object_lazy_init")]
                let initSymbol = symbols.define(
                    kind: .function,
                    name: name,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .importedLibrary]
                )
                symbols.setParentSymbol(ownerSymbol, for: initSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        parameterTypes: [],
                        returnType: types.unitType
                    ),
                    for: initSymbol
                )
                symbols.setExternalLinkName(linkName, for: initSymbol)
                symbols.setObjectLazyInitializerSymbol(initSymbol, for: ownerSymbol)
            }

            if let linkName = record.companionInitializerLinkName,
               !linkName.isEmpty,
               symbols.companionObjectSymbol(for: ownerSymbol) != nil
            {
                let name = interner.intern("__companion_init")
                let fqName = record.fqName + [name]
                let initSymbol = symbols.define(
                    kind: .function,
                    name: name,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .importedLibrary]
                )
                symbols.setParentSymbol(ownerSymbol, for: initSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        parameterTypes: [],
                        returnType: types.unitType
                    ),
                    for: initSymbol
                )
                symbols.setExternalLinkName(linkName, for: initSymbol)
                symbols.setCompanionObjectInitializerSymbol(initSymbol, for: ownerSymbol)
            }
        }
    }

    func renderFQName(_ fqName: [InternedString], interner: StringInterner) -> String {
        fqName.map { interner.resolve($0) }.joined(separator: ".")
    }
}
