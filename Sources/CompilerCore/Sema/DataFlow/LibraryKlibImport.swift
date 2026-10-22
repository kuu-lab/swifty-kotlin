import Foundation

extension DataFlowSemaPhase {
    struct KlibModule {
        let path: String
        let uniqueName: String
        let manifest: KlibManifest
        let container: KlibContainer
    }

    func loadKlibModule(path: String, diagnostics: DiagnosticEngine) -> KlibModule? {
        let libName = URL(fileURLWithPath: path).lastPathComponent
        let container: KlibContainer
        let manifest: KlibManifest
        do {
            container = try KlibContainer(path: path)
            manifest = try container.manifest()
        } catch let error as KlibFormatError {
            switch error {
            case .missingManifest, .missingManifestKey, .invalidManifest, .invalidKlibLayout,
                 .entryNotFound:
                diagnostics.error(
                    "KSWIFTK-LIB-0026",
                    "Invalid manifest in \(libName): \(error)",
                    range: nil
                )
            default:
                diagnostics.error(
                    "KSWIFTK-LIB-0025",
                    "Cannot read klib container \(libName): \(error)",
                    range: nil
                )
            }
            return nil
        } catch {
            diagnostics.error(
                "KSWIFTK-LIB-0025",
                "Cannot read klib container \(libName): \(error.localizedDescription)",
                range: nil
            )
            return nil
        }

        switch manifest.compatibility {
        case .supported:
            break
        case .unsupported(let reason):
            diagnostics.error("KSWIFTK-LIB-0027", reason, range: nil)
            return nil
        }

        return KlibModule(
            path: path,
            uniqueName: manifest.uniqueName,
            manifest: manifest,
            container: container
        )
    }

    struct LoadedKlibModule {
        let module: KlibModule
        let ir: KlibIrModule
        /// Every registered declaration keyed by its file-local signature
        /// entry, plus the *synthetic* accessor IDs assigned to serialized
        /// property getters/setters (they are emitted as KIR functions but
        /// are not real `SymbolTable` entries — mirroring source lowering).
        let symbolBySignature: [KlibSignatureKey: SymbolID]
        let symbolByPublicSignature: [KlibPublicSignature: SymbolID]

        var uniqueName: String { module.uniqueName }
    }

    /// Parses the `klib<fileIndex>_<signatureIndex>` mangled names that
    /// `KlibRecordMaterializer` stamps on every record back into signature
    /// keys.
    static func klibSignatureKey(fromMangledName mangledName: String) -> KlibSignatureKey? {
        guard mangledName.hasPrefix("klib") else { return nil }
        let parts = mangledName.dropFirst(4).split(separator: "_")
        guard parts.count == 2,
              let fileIndex = Int(parts[0]),
              let signatureIndex = Int(parts[1])
        else { return nil }
        return KlibSignatureKey(fileIndex: fileIndex, signatureIndex: signatureIndex)
    }

    /// Applies the property back-links that KIR lowering and member-access
    /// lowering rely on:
    ///
    /// * `backingFieldSymbol` links the property to its serialized backing
    ///   field record so layout synthesis keys the slot by the field symbol
    ///   and member reads/writes resolve the field offset.
    /// * `propertyHasCustomGetter` routes every read through the serialized
    ///   getter — correct for both stored properties (the serialized default
    ///   getter is a plain `getField`) and computed ones.
    /// * Serialized getter/setter signatures map to the synthetic accessor
    ///   symbols (`propertyAccessorSymbol(for:kind:)`) that source lowering
    ///   uses for accessor calls and vtable slots, so call sites and emitted
    ///   bodies share one key space.
    func finalizeKlibModule(
        module: KlibModule,
        ir: KlibIrModule,
        registered: [(record: ImportedLibrarySymbolRecord, symbol: SymbolID)],
        symbols: SymbolTable
    ) -> LoadedKlibModule {
        var symbolBySignature: [KlibSignatureKey: SymbolID] = [:]
        for pair in registered {
            guard let key = Self.klibSignatureKey(fromMangledName: pair.record.mangledName) else {
                continue
            }
            symbolBySignature[key] = pair.symbol
        }

        for fileIndex in 0 ..< ir.fileCount {
            guard let file = try? ir.file(fileIndex) else { continue }
            linkKlibPropertyDecls(
                file.declarationIds,
                fileIndex: fileIndex,
                ir: ir,
                symbolBySignature: &symbolBySignature,
                symbols: symbols
            )
        }
        var symbolByPublicSignature: [KlibPublicSignature: SymbolID] = [:]
        for (key, symbol) in symbolBySignature {
            if let signature = try? ir.publicSignature(key.signatureIndex, fileIndex: key.fileIndex) {
                symbolByPublicSignature[signature] = symbol
            }
        }
        return LoadedKlibModule(
            module: module, ir: ir, symbolBySignature: symbolBySignature,
            symbolByPublicSignature: symbolByPublicSignature
        )
    }

    /// Run after imported signatures have been bound, before source calls are
    /// resolved. Finalizing the raw IR keys happens earlier than that binding.
    func inheritKlibDefaultArguments(module: LoadedKlibModule, symbols: SymbolTable) {
        let ir = module.ir
        let symbolBySignature = module.symbolBySignature
        let symbolByPublicSignature = module.symbolByPublicSignature
        var overriddenBySymbol: [SymbolID: [SymbolID]] = [:]
        func symbol(_ ref: KlibSymbolRef, fileIndex: Int) -> SymbolID? {
            if let local = symbolBySignature[KlibSignatureKey(fileIndex: fileIndex, signatureIndex: ref.signatureIndex)] {
                return local
            }
            guard let signature = try? ir.publicSignature(ref.signatureIndex, fileIndex: fileIndex) else { return nil }
            return symbolByPublicSignature[signature]
        }
        func collect(_ declaration: KlibIrDeclaration, fileIndex: Int) {
            switch declaration {
            case .class(let klass):
                for member in klass.declarations { collect(member, fileIndex: fileIndex) }
            case .function(let function):
                guard let owner = symbol(function.base.base.symbol, fileIndex: fileIndex),
                      !function.overridden.isEmpty else { return }
                overriddenBySymbol[owner] = function.overridden.compactMap { symbol($0, fileIndex: fileIndex) }
            default:
                break
            }
        }
        for index in 0 ..< ir.fileCount {
            for declaration in (try? ir.declarations(fileIndex: index)) ?? [] {
                collect(declaration, fileIndex: index)
            }
        }
        func defaultOwner(_ symbol: SymbolID, visiting: Set<SymbolID>) -> SymbolID? {
            guard !visiting.contains(symbol) else { return nil }
            if symbols.functionSignature(for: symbol)?.valueParameterHasDefaultValues.contains(true) == true {
                return symbols.overrideDefaultsBaseSymbol(for: symbol) ?? symbol
            }
            var visiting = visiting
            visiting.insert(symbol)
            for base in overriddenBySymbol[symbol] ?? [] {
                if let owner = defaultOwner(base, visiting: visiting) { return owner }
            }
            return nil
        }
        for symbol in overriddenBySymbol.keys {
            guard let signature = symbols.functionSignature(for: symbol),
                  !signature.valueParameterHasDefaultValues.contains(true),
                  let owner = defaultOwner(symbol, visiting: []),
                  let defaults = symbols.functionSignature(for: owner)?.valueParameterHasDefaultValues,
                  defaults.count == signature.parameterTypes.count else { continue }
            symbols.setFunctionSignature(FunctionSignature(
                receiverType: signature.receiverType,
                contextReceiverTypes: signature.contextReceiverTypes,
                contextParameterSymbols: signature.contextParameterSymbols,
                contextParameterTypes: signature.contextParameterTypes,
                parameterTypes: signature.parameterTypes,
                returnType: signature.returnType,
                isSuspend: signature.isSuspend,
                canThrow: signature.canThrow,
                valueParameterSymbols: signature.valueParameterSymbols,
                valueParameterUnsafeVarianceTypeParameterSymbols: signature.valueParameterUnsafeVarianceTypeParameterSymbols,
                valueParameterHasDefaultValues: defaults,
                valueParameterIsVararg: signature.valueParameterIsVararg,
                valueParameterAllowsNonLocalReturn: signature.valueParameterAllowsNonLocalReturn,
                hasExplicitInlineParameterMetadata: signature.hasExplicitInlineParameterMetadata,
                typeParameterSymbols: signature.typeParameterSymbols,
                reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices,
                typeParameterUpperBounds: signature.typeParameterUpperBounds,
                typeParameterUpperBoundsList: signature.typeParameterUpperBoundsList,
                classTypeParameterCount: signature.classTypeParameterCount
            ), for: symbol)
            symbols.setOverrideDefaultsBaseSymbol(owner, for: symbol)
        }
    }

    /// Returns the `.klib`s ordered so dependencies come first. `depends` names
    /// producer `unique_name`s; the special `stdlib` entry resolves to the
    /// bundled/precompiled standard library rather than another `.klib` on
    /// the search path. Module-init order follows this ordering, so a
    /// dependency's top-level initializers and singleton allocations run
    /// before the dependent's.
    func resolveKlibDependencies(
        _ klibs: [KlibModule],
        stdlibPresent: Bool,
        diagnostics: DiagnosticEngine
    ) -> [KlibModule] {
        var byName: [String: KlibModule] = [:]
        for klib in klibs where byName[klib.uniqueName] == nil {
            byName[klib.uniqueName] = klib
        }
        var state: [String: Int] = [:] // 1 = on DFS stack, 2 = emitted
        var ordered: [KlibModule] = []
        func visit(_ klib: KlibModule) {
            let name = klib.uniqueName
            // Kotlin forbids circular library dependencies; a defensive cycle
            // check stops recursion and keeps the first-seen order.
            guard state[name] == nil else { return }
            state[name] = 1
            for dependency in klib.manifest.depends where !dependency.isEmpty {
                if let dependencyModule = byName[dependency] {
                    visit(dependencyModule)
                } else if dependency != "stdlib" || !stdlibPresent {
                    diagnostics.warning(
                        "KSWIFTK-LIB-0030",
                        "klib '\(name)' depends on '\(dependency)' which was not found on the library search path",
                        range: nil
                    )
                }
            }
            state[name] = 2
            ordered.append(klib)
        }
        for klib in klibs {
            visit(klib)
        }
        return ordered
    }

    private func linkKlibPropertyDecls(
        _ declarationIds: [Int32],
        fileIndex: Int,
        ir: KlibIrModule,
        symbolBySignature: inout [KlibSignatureKey: SymbolID],
        symbols: SymbolTable
    ) {
        for declarationId in declarationIds {
            guard let declaration = try? ir.declaration(declarationId, fileIndex: fileIndex) else {
                continue
            }
            linkKlibPropertyDecl(declaration, fileIndex: fileIndex, ir: ir,
                                 symbolBySignature: &symbolBySignature, symbols: symbols)
        }
    }

    private func linkKlibPropertyDecl(
        _ declaration: KlibIrDeclaration,
        fileIndex: Int,
        ir: KlibIrModule,
        symbolBySignature: inout [KlibSignatureKey: SymbolID],
        symbols: SymbolTable
    ) {
        switch declaration {
        case .class(let klass):
            linkKlibPropertyDecls(
                klass.declarations,
                fileIndex: fileIndex,
                ir: ir,
                symbolBySignature: &symbolBySignature,
                symbols: symbols
            )
        case .property(let property):
            let propertyKey = KlibSignatureKey(
                fileIndex: fileIndex,
                signatureIndex: property.base.symbol.signatureIndex
            )
            guard let propertySymbol = symbolBySignature[propertyKey] else { return }
            if let field = property.backingField,
               let fieldSymbol = symbolBySignature[KlibSignatureKey(
                   fileIndex: fileIndex,
                   signatureIndex: field.base.symbol.signatureIndex
               )]
            {
                symbols.setBackingFieldSymbol(fieldSymbol, for: propertySymbol)
                // `.backingField` records skip the imported parent-link
                // pass — restore the owner here so member-field lowering can
                // resolve `nominalLayout(for: owner).fieldOffsets[field]`.
                if let owner = symbols.parentSymbol(for: propertySymbol) {
                    symbols.setParentSymbol(owner, for: fieldSymbol)
                }
            }
            // Member reads fall back to `propertyGetterAccessorSymbol`, but
            // top-level and extension-property reads/writes resolve only
            // through the extension-accessor maps (the read path requires a
            // non-nil `extensionPropertyGetterAccessor` to emit the call).
            // Registering the synthetic ID there keeps both call sites and
            // emitted accessor bodies in one key space.
            let parentKind = symbols.parentSymbol(for: propertySymbol)
                .flatMap { symbols.symbol($0)?.kind }
            let needsExtensionAccessorMap = parentKind == nil || parentKind == .package
                || symbols.extensionPropertyReceiverType(for: propertySymbol) != nil
            if let getter = property.getter {
                let getterSymbol = SyntheticSymbolScheme.propertyGetterAccessorSymbol(
                    for: propertySymbol
                )
                symbolBySignature[KlibSignatureKey(
                    fileIndex: fileIndex,
                    signatureIndex: getter.base.base.symbol.signatureIndex
                )] = getterSymbol
                symbols.setPropertyHasCustomGetter(true, for: propertySymbol)
                if needsExtensionAccessorMap {
                    symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: propertySymbol)
                }
            }
            if let setter = property.setter {
                let setterSymbol = SyntheticSymbolScheme.propertySetterAccessorSymbol(
                    for: propertySymbol
                )
                symbolBySignature[KlibSignatureKey(
                    fileIndex: fileIndex,
                    signatureIndex: setter.base.base.symbol.signatureIndex
                )] = setterSymbol
                if needsExtensionAccessorMap {
                    symbols.setExtensionPropertySetterAccessor(setterSymbol, for: propertySymbol)
                }
            }
        default:
            break
        }
    }

    private func linkKlibPropertyDecls(
        _ declarations: [KlibIrDeclaration],
        fileIndex: Int,
        ir: KlibIrModule,
        symbolBySignature: inout [KlibSignatureKey: SymbolID],
        symbols: SymbolTable
    ) {
        for declaration in declarations {
            linkKlibPropertyDecl(declaration, fileIndex: fileIndex, ir: ir,
                                 symbolBySignature: &symbolBySignature, symbols: symbols)
        }
    }
}
