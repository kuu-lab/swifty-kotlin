import Foundation

extension DataFlowSemaPhase {
    /// A recognized Kotlin `.klib` library: validated manifest plus an open
    /// container that IR/metadata readers pull entries from.
    struct KlibModule {
        let path: String
        let uniqueName: String
        let manifest: KlibManifest
        let container: KlibContainer
    }

    /// Opens a `.klib` path (packed zip or unpacked directory), parses its
    /// manifest and applies the version gate. Declaration/body materialization
    /// happens in later stages of the pipeline; on success the module is
    /// returned for the caller to keep.
    func loadKlibModule(path: String, diagnostics: DiagnosticEngine) -> KlibModule? {
        let libName = URL(fileURLWithPath: path).lastPathComponent
        let container: KlibContainer
        let manifest: KlibManifest
        do {
            container = try KlibContainer(path: path)
            manifest = try container.manifest()
        } catch let error as KlibFormatError {
            switch error {
            case .missingManifest, .missingManifestKey, .invalidKlibLayout,
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
        case .bestEffort(let reason):
            diagnostics.warning("KSWIFTK-LIB-0027", reason, range: nil)
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

    /// A `.klib` module that survived declaration import: keeps the open
    /// container plus the decoded IR module and the
    /// `(fileIndex, signatureIndex) → SymbolID` map so KIR lowering can
    /// materialize serialized bodies against real consumer symbols.
    struct LoadedKlibModule {
        let module: KlibModule
        let ir: KlibIrModule
        /// Every registered declaration keyed by its file-local signature
        /// entry, plus the *synthetic* accessor IDs assigned to serialized
        /// property getters/setters (they are emitted as KIR functions but
        /// are not real `SymbolTable` entries — mirroring source lowering).
        let symbolBySignature: [KlibSignatureKey: SymbolID]

        var uniqueName: String { module.uniqueName }
    }

    /// Parses the `klib<fileIndex>_<signatureIndex>` mangled names that
    /// `KlibRecordMaterializer` stamps on every record back into signature
    /// keys. Returns `nil` for records that did not originate from a klib.
    static func klibSignatureKey(fromMangledName mangledName: String) -> KlibSignatureKey? {
        guard mangledName.hasPrefix("klib") else { return nil }
        let parts = mangledName.dropFirst(4).split(separator: "_")
        guard parts.count == 2,
              let fileIndex = Int(parts[0]),
              let signatureIndex = Int(parts[1])
        else { return nil }
        return KlibSignatureKey(fileIndex: fileIndex, signatureIndex: signatureIndex)
    }

    /// Builds the signature→symbol map for a klib module whose records have
    /// just been registered, and applies the property back-links that KIR
    /// lowering and member-access lowering rely on:
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
        return LoadedKlibModule(module: module, ir: ir, symbolBySignature: symbolBySignature)
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
