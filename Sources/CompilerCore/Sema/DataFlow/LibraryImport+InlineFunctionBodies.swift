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
        let inlineAttributes = try? FileManager.default.attributesOfItem(atPath: inlinePath)
        guard inlineAttributes?[.type] as? FileAttributeType == .typeRegular else {
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
        resolver: ImportedSymbolResolver
    ) {
        func resolveOne(_ symbol: SymbolID) -> KIRFunction? {
            guard let binding = state.pendingInlineBindings.removeValue(forKey: symbol) else {
                return nil
            }
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
                guard case let .call(callSymbol, calleeName, _, _, _, _, _, _) = instruction else {
                    continue
                }
                let targets: [SymbolID] = callSymbol.map { [$0] }
                    ?? drainThenRead(calleeName)
                for target in targets where scannedSymbols.insert(target).inserted {
                    if let function = resolveOne(target) {
                        bodiesToScan.append(function.body)
                    }
                }
            }
        }
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
