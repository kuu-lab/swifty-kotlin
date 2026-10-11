import Foundation

extension DataFlowSemaPhase {
    func importInlineFunctionIfNeeded(
        _ binding: ImportedLibraryBinding,
        symbol: SymbolID,
        signature: FunctionSignature,
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
            diagnostics: diagnostics,
            interner: interner
        ) else {
            return
        }
        importedInlineFunctions.register(
            ImportedInlineFunctionStore.Descriptor(
                path: inlinePath,
                signature: signature,
                name: record.fqName.last ?? interner.intern("_")
            ),
            for: symbol
        )
    }

    /// Reads and parses the `.kir` inline body file for an imported inline
    /// function. Shared by the eager import path and the deferred resolver
    /// that lowering invokes for demanded callees.
    private func loadImportedInlineFunctionBody(
        _ binding: ImportedLibraryBinding,
        symbol: SymbolID,
        signature: FunctionSignature,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        externalLinkNameToSymbol: [String: SymbolID],
        importedSymbolByFQName: [String: SymbolID]
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
            externalLinkNameToSymbol: externalLinkNameToSymbol,
            importedSymbolByFQName: importedSymbolByFQName
        )
    }

    /// Resolves deferred imported inline bodies for the callees a module's
    /// KIR actually invokes. `.call` instructions carrying a resolved callee
    /// symbol resolve that binding; symbol-unresolved calls fall back to the
    /// pending name index (resolving every candidate is safe — extra bodies
    /// simply join the expansion table). Freshly parsed bodies are scanned in
    /// turn so transitive inline-to-inline calls resolve as well.
    func resolveDemandedImportedInlineBodies(
        module: KIRModule,
        state: ImportedLibraryLazyLoaderState,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        externalLinkNameToSymbol: [String: SymbolID],
        importedSymbolByFQName: [String: SymbolID]
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
            guard let inlinePath = resolvedImportedInlineKIRPath(
                binding,
                diagnostics: diagnostics,
                interner: interner
            ) else {
                return nil
            }
            let signature = symbols.functionSignature(for: symbol)
            let descriptor = ImportedInlineFunctionStore.Descriptor(
                path: inlinePath,
                signature: signature,
                name: binding.record.fqName.last ?? interner.intern("_")
            )
            state.importedInlineFunctions.register(descriptor, for: symbol)
            state.descriptorSink?(symbol, descriptor)

            guard let signature,
                  let function = loadImportedInlineFunctionBody(
                      binding,
                      symbol: symbol,
                      signature: signature,
                      types: types,
                      diagnostics: diagnostics,
                      interner: interner,
                      externalLinkNameToSymbol: externalLinkNameToSymbol,
                      importedSymbolByFQName: importedSymbolByFQName
                  )
            else {
                return nil
            }
            return function
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
                    ?? state.pendingInlineSymbolsByName[calleeName] ?? []
                for target in targets where scannedSymbols.insert(target).inserted {
                    if let function = resolveOne(target) {
                        bodiesToScan.append(function.body)
                    }
                }
            }
        }
    }

    private func resolvedImportedInlineKIRPath(
        _ binding: ImportedLibraryBinding,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
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
