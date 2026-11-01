import Foundation

extension DataFlowSemaPhase {
    func importedInlineUsesComponentTokens(
        _ binding: ImportedLibraryBinding, symbol: SymbolID, symbols: SymbolTable
    ) -> Bool {
        symbols.symbol(symbol)?.flags.contains(.legacyReifiedClassTokenABI) != true
            && CallLowerer.isSourceBackedLinkName(binding.record.externalLinkName)
    }

    func importedInlinePackedValueTypes(
        _ signature: FunctionSignature?, binding: ImportedLibraryBinding,
        symbol: SymbolID, symbols: SymbolTable, types: TypeSystem, interner: StringInterner
    ) -> [TypeID]? {
        guard let signature, CallLowerer.isSourceBackedLinkName(binding.record.externalLinkName) else { return nil }
        let current = importedInlineUsesComponentTokens(binding, symbol: symbol, symbols: symbols)
        return signature.parameterTypes.enumerated().map { index, element in
            guard signature.valueParameterIsVararg.indices.contains(index), signature.valueParameterIsVararg[index] else { return element }
            let name: String
            if case let .primitive(primitive, .nonNull) = types.kind(of: element) { name = primitive.kotlinName + "Array" }
            else {
                // Legacy source reference-varargs are rejected at import;
                // primitive arrays keep their physical ABI in either version.
                guard current else { return element }
                name = "Array"
            }
            guard let array = symbols.lookup(fqName: ["kotlin", name].map(interner.intern)) else { return element }
            return types.make(.classType(ClassType(classSymbol: array, args: name == "Array" ? [.out(element)] : [])))
        }
    }

    func importInlineFunctionIfNeeded(
        _ binding: ImportedLibraryBinding,
        symbol: SymbolID,
        signature: FunctionSignature,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        importedInlineFunctions: ImportedInlineFunctionStore
    ) {
        let record = binding.record
        guard record.isInline,
              !record.mangledName.isEmpty,
              binding.inlineKIRDir != nil
        else {
            return
        }

        // Indexed metadata defers `.kir` body parsing: a signature query that
        // materializes the declaration must not read the inline body file.
        // The binding was already registered as pending at shell creation, so
        // lowering can resolve the body on demand for callees the module
        // actually invokes.
        if binding.defersInlineBodyImport {
            return
        }

        guard let inlinePath = resolvedImportedInlineKIRPath(
            binding,
            diagnostics: diagnostics
        ) else {
            return
        }
        importedInlineFunctions.register(
            ImportedInlineFunctionStore.Descriptor(
                path: inlinePath,
                signature: signature,
                name: record.fqName.last ?? interner.intern("_"),
                reifiedComponentTokens: importedInlineUsesComponentTokens(binding, symbol: symbol, symbols: symbols),
                packedValueParameterTypes: importedInlinePackedValueTypes(signature, binding: binding, symbol: symbol, symbols: symbols, types: types, interner: interner)
            ),
            for: symbol
        )
    }

    private func loadImportedInlineFunctionBody(
        _ binding: ImportedLibraryBinding,
        symbol: SymbolID,
        signature: FunctionSignature,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        resolver: ImportedSymbolResolver
    ) -> KIRFunction? {
        let record = binding.record
        guard let inlineDir = binding.inlineKIRDir else { return nil }

        let fileName = MetadataEncoder.inlineKIRFileName(for: record.mangledName)
        let inlineDirURL = URL(fileURLWithPath: inlineDir).resolvingSymlinksInPath().standardizedFileURL
        let inlinePathURL = inlineDirURL
            .appendingPathComponent(fileName)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let inlinePath = inlinePathURL.path
        let inlineDirResolved = inlineDirURL.path
        guard inlinePath.hasPrefix(inlineDirResolved.hasSuffix("/") ? inlineDirResolved : inlineDirResolved + "/") else {
            diagnostics.error(
                "KSWIFTK-LIB-0019",
                "Inline KIR path for '\(record.mangledName)' escapes inline directory",
                range: nil
            )
            return nil
        }
        guard CompilerFileSystem.isRegularFile(at: inlinePathURL) else {
            diagnostics.error(
                "KSWIFTK-LIB-0019",
                "Inline KIR path for '\(record.mangledName)' is missing or is not a regular file",
                range: nil
            )
            return nil
        }
        guard FileManager.default.fileExists(atPath: inlinePath) else {
            let recordFQName = record.fqName.map { interner.resolve($0) }.joined(separator: ".")
            if binding.isStdlibArtifact {
                diagnostics.error(
                    "KSWIFTK-LIB-0023",
                    "Stdlib artifact is missing inline KIR for '" + recordFQName + "': " + inlinePath,
                    range: nil
                )
            } else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0002",
                    "Unable to read inline KIR artifact: " + inlinePath,
                    range: nil
                )
            }
            return nil
        }
        return Self.parseImportedInlineFunction(
            path: inlinePath,
            importedSymbol: symbol,
            signature: signature,
            types: types,
            interner: interner,
            diagnostics: diagnostics,
            resolver: resolver,
            reifiedComponentTokens: importedInlineUsesComponentTokens(binding, symbol: symbol, symbols: symbols),
            packedValueParameterTypes: importedInlinePackedValueTypes(signature, binding: binding, symbol: symbol, symbols: symbols, types: types, interner: interner)
        )
    }

    /// Symbol-unresolved calls fall back to the pending name index (resolving
    /// every candidate is safe — extra bodies simply join the expansion
    /// table). Freshly parsed bodies are scanned in turn so transitive
    /// inline-to-inline calls resolve as well.
    func resolveDemandedImportedInlineBodies(
        module: KIRModule,
        state: ImportedLibraryLazyLoaderState,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        resolver: ImportedSymbolResolver,
        materializeInitBodiesForWasm: Bool = false
    ) {
        // Wasm has no object linker, so init-family bodies that native
        // resolves from the artifact's .o must instead materialize from the
        // serialized KIR shipped in inline-kir/ (see CodegenPhase).
        var initBodySymbols: Set<SymbolID> = []
        var initSymbolsByLinkName: [String: SymbolID] = [:]
        if materializeInitBodiesForWasm {
            (initBodySymbols, initSymbolsByLinkName) = registerWasmInitBodyDescriptors(
                state: state, symbols: symbols, interner: interner
            )
        }
        func isInitBodySymbol(_ symbol: SymbolID) -> Bool {
            initBodySymbols.contains(symbol)
        }

        // Bodies reach inline-kir/ two ways without an index binding: init
        // shells (symbols created by `applyImportedInitializerShells`) and
        // synthetic or non-inline functions whose bodies the producer
        // serialized because init code reaches them transitively. When a
        // `kk_fn_` link name has a shipped body, register a descriptor for
        // the resolving symbol — synthesizing a shell when no symbol exists
        // (`__ctor_reflect_init_*`, per-object lazy-init trampolines).
        let linkNameDrivenDirs = materializeInitBodiesForWasm
            ? Array(Set(state.allImportedBindings.compactMap(\.inlineKIRDir)))
            : []
        var linkNameDrivenShells: [String: SymbolID] = [:]
        var linkNameDrivenMisses: Set<String> = []
        func linkNameDrivenShellSymbol(_ linkName: String) -> SymbolID? {
            if let memo = linkNameDrivenShells[linkName] {
                return memo
            }
            func memoize(_ symbol: SymbolID?) -> SymbolID? {
                if let symbol {
                    linkNameDrivenShells[linkName] = symbol
                } else {
                    linkNameDrivenMisses.insert(linkName)
                }
                return symbol
            }
            guard linkName.hasPrefix("kk_fn_"), !linkNameDrivenMisses.contains(linkName) else {
                return nil
            }
            let fileName = MetadataEncoder.inlineKIRFileName(for: linkName)
            guard let dir = linkNameDrivenDirs.first(where: {
                FileManager.default.fileExists(atPath: $0 + "/" + fileName)
            }) else {
                return memoize(nil)
            }
            let symbol: SymbolID
            if let existing = resolver.symbol(forLinkName: linkName) {
                symbol = existing
            } else {
                let name = interner.intern(linkName)
                symbol = symbols.define(
                    kind: .function,
                    name: name,
                    fqName: [name],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic, .importedLibrary]
                )
                symbols.setExternalLinkName(linkName, for: symbol)
            }
            state.importedInlineFunctions.register(
                ImportedInlineFunctionStore.Descriptor(
                    path: dir + "/" + fileName,
                    signature: symbols.functionSignature(for: symbol),
                    name: interner.intern(linkName)
                ),
                for: symbol
            )
            initBodySymbols.insert(symbol)
            initSymbolsByLinkName[linkName] = symbol
            return memoize(symbol)
        }
        func resolveOne(_ symbol: SymbolID) -> KIRFunction? {
            guard let binding = state.pendingInlineBindings.removeValue(forKey: symbol) else {
                return materializeInitBodiesForWasm
                    ? state.importedInlineFunctions.function(
                        for: symbol, arena: module.arena
                    )
                    : nil
            }
            state.importedInlineFunctions.clearPendingBody(for: symbol)
            if let name = binding.record.fqName.last,
               var siblings = state.pendingInlineSymbolsByName[name]
            {
                siblings.removeAll { $0 == symbol }
                if siblings.isEmpty {
                    state.pendingInlineSymbolsByName.removeValue(forKey: name)
                } else {
                    state.pendingInlineSymbolsByName[name] = siblings
                }
            }
            guard let signature = symbols.functionSignature(for: symbol),
                  registerImportedInlineFunctionDescriptor(
                      binding,
                      symbol: symbol,
                      signature: signature,
                      state: state,
                      symbols: symbols,
                      types: types,
                      diagnostics: diagnostics,
                      interner: interner
                  ) != nil,
                  let function = loadImportedInlineFunctionBody(
                      binding,
                      symbol: symbol,
                      signature: signature, symbols: symbols,
                      types: types,
                      diagnostics: diagnostics,
                      interner: interner,
                      resolver: resolver
                  )
            else {
                return nil
            }
            return function
        }

        /// Name-fallback callees may sit in still-pending index entries. The
        /// short-name drain registers them, filling `pendingInlineSymbolsByName`
        /// through `appendImportedBinding` before the map is read.
        func drainThenRead(_ calleeName: InternedString) -> [SymbolID] {
            _ = symbols.lookupByShortName(calleeName)
            return state.pendingInlineSymbolsByName[calleeName] ?? []
        }

        var scannedSymbols: Set<SymbolID> = []
        var bodiesToScan: [[KIRInstruction]] = module.arena.declarations.compactMap { decl in
            guard case let .function(function) = decl else { return nil }
            return function.body
        }
        while let body = bodiesToScan.popLast() {
            for instruction in body {
                // `.virtualCall` also reaches kklib member bodies (`getValue`
                // on Lazy, enum `values` adapters) — without scanning it the
                // target's body never materializes and the site stubs.
                // `.constValue(.symbolRef)` is the third carrier: vtable/
                // itable registrations inside materialized init bodies hold
                // raw member symbols whose bodies must ship as well, or the
                // registered slot dispatches into a stub.
                let callSite: (symbol: SymbolID?, name: InternedString?)?
                switch instruction {
                case let .call(s, n, _, _, _, _, _, _): callSite = (s, n)
                case let .virtualCall(s, n, _, _, _, _, _, _): callSite = (s, n)
                case let .constValue(_, .symbolRef(s)): callSite = (s, nil)
                default: callSite = nil
                }
                guard let (callSymbol, calleeName) = callSite else { continue }
                var targets: [SymbolID] = callSymbol.map { [$0] }
                    ?? calleeName.map { drainThenRead($0) }
                    ?? []
                // Init shells aren't index bindings, so their link names
                // never enter pendingInlineSymbolsByName — resolve them
                // through the registered descriptor map, synthesizing a
                // shell when the link name has a shipped body but no symbol.
                if targets.isEmpty, materializeInitBodiesForWasm,
                   let calleeName,
                   let initSymbol = initSymbolsByLinkName[interner.resolve(calleeName)]
                        ?? linkNameDrivenShellSymbol(interner.resolve(calleeName))
                {
                    targets = [initSymbol]
                }
                for target in targets where scannedSymbols.insert(target).inserted {
                    var function = resolveOne(target)
                    // A resolved callee whose record is not inline still has
                    // a shipped body when init reaches it transitively —
                    // retry once after registering its descriptor. The callee
                    // *name* may itself be the `kk_fn_` link name even when
                    // the symbol carries no external link name; the resolved
                    // shell (existing or synthesized) then owns the body, so
                    // scan *it*, not the dead-end target.
                    if function == nil, materializeInitBodiesForWasm {
                        if let linkName = symbols.externalLinkNameIfKnown(for: target),
                           linkNameDrivenShellSymbol(linkName) != nil
                        {
                            function = resolveOne(target)
                        } else if let calleeName,
                                  let shell = linkNameDrivenShellSymbol(interner.resolve(calleeName)),
                                  scannedSymbols.insert(shell).inserted
                        {
                            function = resolveOne(shell)
                        }
                    }
                    if let function {
                        bodiesToScan.append(function.body)
                    }
                }
            }
        }

        // Wasm emits no separate object file for imported init functions, so
        // the materialized bodies join the module as ordinary decls. Globals
        // they touch (the singleton handle, `$initialized` flags) need slots
        // owned by this compilation too.
        if materializeInitBodiesForWasm {
            var seenFunctions: Set<SymbolID> = []
            var seenGlobals: Set<SymbolID> = []
            for decl in module.arena.declarations {
                switch decl {
                case let .function(function): seenFunctions.insert(function.symbol)
                case let .global(global): seenGlobals.insert(global.symbol)
                default: break
                }
            }
            for symbol in scannedSymbols {
                guard let function = state.importedInlineFunctions.functions[symbol]
                else { continue }
                if isInitBodySymbol(symbol), !seenFunctions.contains(symbol) {
                    _ = module.arena.appendDecl(.function(function))
                }
                // Globals reach this module two ways: appended init decls
                // read/write them directly, and inlined callee bodies embed
                // loadGlobal/storeGlobal into their callers. Cover both.
                for instruction in function.body {
                    let globalSymbol: SymbolID?
                    switch instruction {
                    case let .loadGlobal(_, symbol): globalSymbol = symbol
                    case let .storeGlobal(_, symbol): globalSymbol = symbol
                    default: globalSymbol = nil
                    }
                    guard let globalSymbol, seenGlobals.insert(globalSymbol).inserted else { continue }
                    _ = module.arena.appendDecl(.global(KIRGlobal(
                        symbol: globalSymbol,
                        type: symbols.propertyType(for: globalSymbol) ?? types.anyType,
                        isThreadLocal: false
                    )))
                }
            }
        }
    }

    /// Registers lazy descriptors for the imported object/companion/enum
    /// init shells (`applyImportedInitializerShells`) so a call site bearing
    /// one of their symbols — or only its `kk_fn_` link name — materializes
    /// the shipped kirbin on demand. Returns the covered symbols plus the
    /// link-name index for symbol-less call sites.
    private func registerWasmInitBodyDescriptors(
        state: ImportedLibraryLazyLoaderState,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> (symbols: Set<SymbolID>, byLinkName: [String: SymbolID]) {
        let prefixes = [
            "__object_init_", "__companion_init_", "__enum_static_init_",
            "__kk_library_top_level_init_", "__kk_synthetic_companion_init_",
            "__klib_object_init_", "__klib_object_lazy_init_",
            "__object_lazy_init_", "__companion_lazy_init_", "__ctor_reflect_init_",
            "__member_reflect_init_",
        ]
        let store = state.importedInlineFunctions
        var initSymbols: Set<SymbolID> = []
        for binding in state.allImportedBindings {
            for getter in [
                symbols.objectInitializerSymbolIfKnown,
                symbols.companionObjectInitializerSymbolIfKnown,
                symbols.enumStaticInitSymbolIfKnown,
                symbols.objectLazyInitializerSymbol,
            ] {
                guard let initSymbol = getter(binding.symbol) else { continue }
                initSymbols.insert(initSymbol)
            }
        }
        // Shells reachable only by link name (the library's own
        // `__kk_library_top_level_init_`, lazy-init trampolines) never appear
        // in the per-record initializer slots — sweep imported function
        // symbols by external link name instead.
        for info in symbols.allSymbols() {
            guard info.kind == .function,
                  info.flags.contains(.importedLibrary),
                  let linkName = symbols.externalLinkNameIfKnown(for: info.id),
                  prefixes.contains(where: { linkName.contains($0) })
            else { continue }
            initSymbols.insert(info.id)
        }
        let dirs = Array(Set(state.allImportedBindings.compactMap(\.inlineKIRDir)))
        var byLinkName: [String: SymbolID] = [:]
        for symbol in initSymbols {
            guard let linkName = symbols.externalLinkName(for: symbol),
                  linkName.hasPrefix("kk_fn_"),
                  prefixes.contains(where: { linkName.contains($0) })
            else { continue }
            byLinkName[linkName] = symbol
            let fileName = MetadataEncoder.inlineKIRFileName(for: linkName)
            guard let dir = dirs.first(where: {
                FileManager.default.fileExists(atPath: $0 + "/" + fileName)
            }) else { continue }
            store.register(
                ImportedInlineFunctionStore.Descriptor(
                    path: dir + "/" + fileName,
                    signature: symbols.functionSignature(for: symbol),
                    name: symbols.symbol(symbol)?.name ?? interner.intern(linkName)
                ),
                for: symbol
            )
        }
        return (initSymbols, byLinkName)
    }

    /// Snapshot archives bypass the compact-index provider on consumer loads,
    /// so persist descriptors for every imported inline body while building
    /// the archive. The bodies remain lazy and are parsed only if a consumer
    /// actually expands the corresponding call.
    func registerAllImportedInlineFunctionDescriptors(
        state: ImportedLibraryLazyLoaderState,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        for symbol in state.pendingInlineBindings.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let binding = state.pendingInlineBindings[symbol],
                  let signature = symbols.functionSignature(for: symbol)
            else {
                continue
            }
            _ = registerImportedInlineFunctionDescriptor(
                binding,
                symbol: symbol,
                signature: signature,
                state: state,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner
            )
        }
        // A snapshot missing a descriptor silently degrades to an unresolved
        // external call at link time. Fail the capture build instead of
        // writing an under-registered snapshot.
        let missing = state.pendingInlineBindings.keys.filter {
            state.importedInlineFunctions.descriptors[$0] == nil
        }
        for symbol in missing.sorted(by: { $0.rawValue < $1.rawValue }) {
            let record = state.pendingInlineBindings[symbol]?.record
            let name = record?.fqName.map { interner.resolve($0) }.joined(separator: ".")
                ?? "#\(symbol.rawValue)"
            diagnostics.error(
                "KSWIFTK-LIB-0032",
                "Could not register inline KIR descriptor for '\(name)' in the stdlib Sema snapshot",
                range: nil
            )
        }
    }

    private func registerImportedInlineFunctionDescriptor(
        _ binding: ImportedLibraryBinding,
        symbol: SymbolID,
        signature: FunctionSignature,
        state: ImportedLibraryLazyLoaderState,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) -> ImportedInlineFunctionStore.Descriptor? {
        let record = binding.record
        guard record.isInline,
              !record.mangledName.isEmpty,
              let inlinePath = resolvedImportedInlineKIRPath(binding, diagnostics: diagnostics)
        else {
            return nil
        }
        let descriptor = ImportedInlineFunctionStore.Descriptor(
            path: inlinePath,
            signature: signature,
            name: record.fqName.last ?? interner.intern("_"),
            reifiedComponentTokens: importedInlineUsesComponentTokens(binding, symbol: symbol, symbols: symbols),
            packedValueParameterTypes: importedInlinePackedValueTypes(
                signature,
                binding: binding,
                symbol: symbol,
                symbols: symbols,
                types: types,
                interner: interner
            )
        )
        state.importedInlineFunctions.register(descriptor, for: symbol)
        state.descriptorSink?(symbol, descriptor)
        return descriptor
    }

    private func resolvedImportedInlineKIRPath(
        _ binding: ImportedLibraryBinding,
        diagnostics: DiagnosticEngine
    ) -> String? {
        let record = binding.record
        guard let inlineDir = binding.inlineKIRDir else { return nil }
        let fileName = MetadataEncoder.inlineKIRFileName(for: record.mangledName)
        let inlineDirURL = URL(fileURLWithPath: inlineDir).resolvingSymlinksInPath().standardizedFileURL
        let inlinePathURL = inlineDirURL
            .appendingPathComponent(fileName)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let inlinePath = inlinePathURL.path
        let inlineDirResolved = inlineDirURL.path
        guard inlinePath.hasPrefix(inlineDirResolved.hasSuffix("/") ? inlineDirResolved : inlineDirResolved + "/") else {
            diagnostics.error(
                "KSWIFTK-LIB-0019",
                "Inline KIR path for '\(record.mangledName)' escapes inline directory",
                range: nil
            )
            return nil
        }
        return inlinePath
    }
}
