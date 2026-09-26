import Foundation

let maximumImportedNominalLayoutValue = 1_000_000

extension DataFlowSemaPhase {
    func parseImportedFieldOffsets(
        token: String,
        diagnostics: DiagnosticEngine,
        metadataPath: String,
        ownerFQName: [InternedString],
        interner: StringInterner
    ) -> [ImportedFieldOffsetEntry] {
        let pairs = parseImportedKeySlotPairs(
            token: token,
            diagnostics: diagnostics,
            metadataPath: metadataPath,
            ownerFQName: ownerFQName,
            interner: interner
        )
        return pairs.compactMap { key, offset in
            let fqName = key.split(separator: ".").map { interner.intern(String($0)) }
            guard !fqName.isEmpty else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0003",
                    "Invalid fieldOffsets entry in metadata at \(metadataPath): \(key)",
                    range: nil
                )
                return nil
            }
            return ImportedFieldOffsetEntry(fqName: fqName, offset: offset)
        }
    }

    func parseImportedVTableSlots(
        token: String,
        diagnostics: DiagnosticEngine,
        metadataPath: String,
        ownerFQName: [InternedString],
        interner: StringInterner
    ) -> [ImportedVTableSlotEntry] {
        // v2-prefixed tokens use `|` as the separator because the
        // type-signature component may contain commas; legacy tokens are
        // comma-separated and contain at most `fqName#arity#isSuspend`.
        let tokenBody: String
        let separator: Character
        if token.hasPrefix("v2:") {
            tokenBody = String(token.dropFirst(3))
            separator = "|"
        } else {
            tokenBody = token
            separator = ","
        }
        let pairs = parseImportedKeySlotPairs(
            token: tokenBody,
            diagnostics: diagnostics,
            metadataPath: metadataPath,
            ownerFQName: ownerFQName,
            interner: interner,
            separator: separator
        )
        return pairs.compactMap { key, slot in
            let propertyAccessorKind: PropertyAccessorKind?
            let normalizedKey: String
            if key.hasPrefix("pget:") {
                propertyAccessorKind = .getter
                normalizedKey = String(key.dropFirst("pget:".count))
            } else if key.hasPrefix("pset:") {
                propertyAccessorKind = .setter
                normalizedKey = String(key.dropFirst("pset:".count))
            } else {
                propertyAccessorKind = nil
                normalizedKey = key
            }
            if let propertyAccessorKind {
                let fqName = normalizedKey.split(separator: ".").map { interner.intern(String($0)) }
                guard !fqName.isEmpty else {
                    diagnostics.warning(
                        "KSWIFTK-LIB-0003",
                        "Invalid property accessor vtable entry in metadata at \(metadataPath): \(key)",
                        range: nil
                    )
                    return nil
                }
                return ImportedVTableSlotEntry(
                    fqName: fqName,
                    arity: 0,
                    isSuspend: false,
                    slot: slot,
                    typeSignature: nil,
                    propertyAccessorKind: propertyAccessorKind
                )
            }
            let components = key.split(separator: "#", omittingEmptySubsequences: false).map(String.init)
            guard (components.count == 3 || components.count == 4),
                  let arity = Int(components[1])
            else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0003",
                    "Invalid vtableSlots entry in metadata at \(metadataPath): \(key)",
                    range: nil
                )
                return nil
            }
            // `property:` was emitted by the initial BUG-227 serializer before
            // the metadata format gained an explicit accessor discriminator.
            // Continue accepting it as a getter for already-built libraries.
            let isLegacyProperty = components[0].hasPrefix("property:")
            let rawFQName = isLegacyProperty
                ? String(components[0].dropFirst("property:".count))
                : components[0]
            let fqName = rawFQName.split(separator: ".").map { interner.intern(String($0)) }
            guard !fqName.isEmpty else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0003",
                    "Invalid vtableSlots entry in metadata at \(metadataPath): \(key)",
                    range: nil
                )
                return nil
            }
            let suspendToken = components[2].lowercased()
            let isSuspend = suspendToken == "1" || suspendToken == "true"
            let typeSignature: String? = if components.count == 4 {
                components[3]
            } else {
                nil
            }
            return ImportedVTableSlotEntry(
                fqName: fqName,
                arity: max(0, arity),
                isSuspend: isSuspend,
                slot: slot,
                typeSignature: typeSignature,
                propertyAccessorKind: isLegacyProperty ? .getter : nil
            )
        }
    }

    func parseImportedITableSlots(
        token: String,
        diagnostics: DiagnosticEngine,
        metadataPath: String,
        ownerFQName: [InternedString],
        interner: StringInterner
    ) -> [ImportedITableSlotEntry] {
        let pairs = parseImportedKeySlotPairs(
            token: token,
            diagnostics: diagnostics,
            metadataPath: metadataPath,
            ownerFQName: ownerFQName,
            interner: interner
        )
        return pairs.compactMap { key, slot in
            let fqName = key.split(separator: ".").map { interner.intern(String($0)) }
            guard !fqName.isEmpty else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0003",
                    "Invalid itableSlots entry in metadata at \(metadataPath): \(key)",
                    range: nil
                )
                return nil
            }
            return ImportedITableSlotEntry(fqName: fqName, slot: slot)
        }
    }

    private func parseImportedKeySlotPairs(
        token: String,
        diagnostics: DiagnosticEngine,
        metadataPath: String,
        ownerFQName: [InternedString],
        interner: StringInterner,
        separator: Character = ","
    ) -> [(String, Int)] {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }
        var result: [(String, Int)] = []
        for rawEntry in trimmed.split(separator: separator, omittingEmptySubsequences: true) {
            let entry = String(rawEntry)
            guard let separatorIndex = entry.lastIndex(of: "@"),
                  separatorIndex < entry.index(before: entry.endIndex),
                  let slot = Int(entry[entry.index(after: separatorIndex)...])
            else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0003",
                    "Malformed metadata slot entry at \(metadataPath): \(entry) (\(renderFQName(ownerFQName, interner: interner)))",
                    range: nil
                )
                continue
            }
            let key = String(entry[..<separatorIndex])
            guard !key.isEmpty else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0003",
                    "Malformed metadata slot entry at \(metadataPath): \(entry)",
                    range: nil
                )
                continue
            }
            result.append((key, slot))
        }
        return result
    }

    func applyImportedNominalLayout(
        record: ImportedLibrarySymbolRecord,
        symbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        metadataPath: String,
        interner: StringInterner,
        indexedBindingsBySymbol: [SymbolID: ImportedLibraryBinding]? = nil
    ) {
        let declaredLayoutValues = [
            record.declaredFieldCount,
            record.declaredInstanceSizeWords,
            record.declaredVtableSize,
            record.declaredItableSize,
        ].compactMap { $0 }
        let slotValues = record.fieldOffsets.map(\.offset)
            + record.vtableSlots.map(\.slot)
            + record.itableSlots.map(\.slot)
        guard declaredLayoutValues.allSatisfy({ (0 ... maximumImportedNominalLayoutValue).contains($0) }),
              slotValues.allSatisfy({ (0 ... maximumImportedNominalLayoutValue).contains($0) }),
              record.fieldOffsets.count <= maximumImportedNominalLayoutValue,
              record.vtableSlots.count <= maximumImportedNominalLayoutValue,
              record.itableSlots.count <= maximumImportedNominalLayoutValue
        else {
            diagnoseInvalidImportedLayout(
                diagnostics: diagnostics,
                metadataPath: metadataPath,
                symbol: symbol
            )
            return
        }
        guard !record.fieldOffsets.isEmpty || !record.vtableSlots.isEmpty || !record.itableSlots.isEmpty else {
            return
        }

        var resolvedFieldOffsets: [SymbolID: Int] = [:]
        for entry in record.fieldOffsets {
            guard let fieldSymbol = resolveImportedFieldSymbol(entry.fqName, symbols: symbols) else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0004",
                    "Unknown metadata field symbol in \(metadataPath): \(renderFQName(entry.fqName, interner: interner))",
                    range: nil
                )
                continue
            }
            resolvedFieldOffsets[fieldSymbol] = entry.offset
        }

        var resolvedVTableSlots: [SymbolID: Int] = [:]
        for entry in record.vtableSlots {
            if let propertyAccessorKind = entry.propertyAccessorKind {
                guard let propertySymbol = resolveImportedPropertySymbol(
                    fqName: entry.fqName,
                    typeSignature: entry.typeSignature,
                    symbols: symbols,
                    types: types,
                    interner: interner
                ) else {
                    let fq = entry.fqName.map { interner.resolve($0) }.joined(separator: ".")
                    diagnostics.warning(
                        "KSWIFTK-LIB-0004",
                        "Unknown metadata property accessor vtable symbol in \(metadataPath): \(fq)",
                        range: nil
                    )
                    continue
                }
                let accessorSymbol = SyntheticSymbolScheme.propertyAccessorSymbol(
                    for: propertySymbol,
                    kind: propertyAccessorKind
                )
                resolvedVTableSlots[accessorSymbol] = entry.slot
                continue
            }
            guard let methodSymbol = resolveImportedMethodSymbol(
                fqName: entry.fqName,
                arity: entry.arity,
                isSuspend: entry.isSuspend,
                typeSignature: entry.typeSignature,
                symbols: symbols,
                types: types,
                interner: interner,
                indexedBindingsBySymbol: indexedBindingsBySymbol
            ) else {
                let fq = entry.fqName.map { interner.resolve($0) }.joined(separator: ".")
                diagnostics.warning(
                    "KSWIFTK-LIB-0004",
                    "Unknown metadata vtable symbol in \(metadataPath): \(fq) (arity=\(entry.arity), isSuspend=\(entry.isSuspend))",
                    range: nil
                )
                continue
            }
            resolvedVTableSlots[methodSymbol] = entry.slot
        }

        var resolvedITableSlots: [SymbolID: Int] = [:]
        for entry in record.itableSlots {
            guard let interfaceSymbol = resolveImportedInterfaceSymbol(entry.fqName, symbols: symbols) else {
                diagnostics.warning(
                    "KSWIFTK-LIB-0004",
                    "Unknown metadata interface symbol in \(metadataPath): \(entry.fqName)",
                    range: nil
                )
                continue
            }
            resolvedITableSlots[interfaceSymbol] = entry.slot
        }

        let objectHeaderWords = 2
        let (maxFieldOffsetSize, fieldOffsetOverflow) =
            (resolvedFieldOffsets.values.max() ?? (objectHeaderWords - 1)).addingReportingOverflow(1)
        let instanceFieldCount = max(record.declaredFieldCount ?? 0, resolvedFieldOffsets.count)
        let (headerAndFields, fieldCountOverflow) = objectHeaderWords.addingReportingOverflow(instanceFieldCount)
        let (maxVTableSize, vtableSlotOverflow) = (resolvedVTableSlots.values.max() ?? -1).addingReportingOverflow(1)
        let (maxITableSize, itableSlotOverflow) = (resolvedITableSlots.values.max() ?? -1).addingReportingOverflow(1)
        guard !fieldOffsetOverflow, !fieldCountOverflow, !vtableSlotOverflow, !itableSlotOverflow else {
            diagnoseInvalidImportedLayout(
                diagnostics: diagnostics,
                metadataPath: metadataPath,
                symbol: symbol
            )
            return
        }
        let instanceSizeWords = max(
            record.declaredInstanceSizeWords ?? 0,
            max(headerAndFields, maxFieldOffsetSize)
        )
        if let declaredVTableSize = record.declaredVtableSize,
           declaredVTableSize >= 0,
           declaredVTableSize < maxVTableSize
        {
            diagnostics.warning(
                "KSWIFTK-LIB-0005",
                "metadata vtable size mismatch at \(metadataPath) for symbol \(symbol.rawValue)",
                range: nil
            )
        }
        if let declaredITableSize = record.declaredItableSize,
           declaredITableSize >= 0,
           declaredITableSize < maxITableSize
        {
            diagnostics.warning(
                "KSWIFTK-LIB-0005",
                "metadata itable size mismatch at \(metadataPath) for symbol \(symbol.rawValue)",
                range: nil
            )
        }
        let vtableSize = max(record.declaredVtableSize ?? 0, maxVTableSize)
        let itableSize = max(record.declaredItableSize ?? 0, maxITableSize)
        let superClass = symbols.directSupertypes(for: symbol)
            .compactMap { symbols.symbol($0) }
            .first(where: { $0.kind != .interface })?.id

        symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: objectHeaderWords,
                instanceFieldCount: max(0, instanceFieldCount),
                instanceSizeWords: max(0, instanceSizeWords),
                fieldOffsets: resolvedFieldOffsets,
                vtableSlots: resolvedVTableSlots,
                itableSlots: resolvedITableSlots,
                vtableSize: max(0, vtableSize),
                itableSize: max(0, itableSize),
                superClass: superClass
            ),
            for: symbol
        )
    }

    private func diagnoseInvalidImportedLayout(
        diagnostics: DiagnosticEngine,
        metadataPath: String,
        symbol: SymbolID
    ) {
        diagnostics.warning(
            "KSWIFTK-LIB-0003",
            "Invalid nominal layout values in metadata at \(metadataPath) for symbol \(symbol.rawValue)",
            range: nil
        )
    }

    private func resolveImportedFieldSymbol(
        _ fqName: [InternedString],
        symbols: SymbolTable
    ) -> SymbolID? {
        symbols.lookupAll(fqName: fqName)
            .compactMap { symbols.symbol($0) }
            .first(where: {
                $0.kind == .field || $0.kind == .property || $0.kind == .backingField
            })?
            .id
    }

    private func resolveImportedMethodSymbol(
        fqName: [InternedString],
        arity: Int,
        isSuspend: Bool,
        typeSignature: String?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        indexedBindingsBySymbol: [SymbolID: ImportedLibraryBinding]?
    ) -> SymbolID? {
        let allSymbolIDs = symbols.lookupAll(fqName: fqName)
        let functionSymbols = allSymbolIDs
            .compactMap { symbols.symbol($0) }
            .filter { $0.kind == .function }
        let candidates = functionSymbols
            .filter { symbol in
                guard let signature = symbols.functionSignature(for: symbol.id) else {
                    return false
                }
                return signature.parameterTypes.count == arity && signature.isSuspend == isSuspend
            }
            .sorted(by: { $0.id.rawValue < $1.id.rawValue })

        // Decoding a member signature can recursively materialize its nominal
        // owner before that member's signature has been stored. Resolve the
        // owner's vtable entry from the compact index shape/body in that case
        // instead of treating the in-progress member as missing.
        let indexedCandidates = functionSymbols
            .filter { symbol in
                guard let record = indexedBindingsBySymbol?[symbol.id]?.record else {
                    return false
                }
                return record.kind == .function
                    && record.arity == arity
                    && record.isSuspend == isSuspend
            }
            .sorted(by: { $0.id.rawValue < $1.id.rawValue })

        if let typeSignature, !typeSignature.isEmpty {
            let mangler = NameMangler()
            let nameResolver: (InternedString) -> String = { interner.resolve($0) }
            if let exact = candidates.first(where: { candidate in
                let candidateSig = mangler.mangledSignature(
                    for: candidate,
                    symbols: symbols,
                    types: types,
                    nameResolver: nameResolver
                )
                return candidateSig == typeSignature
            }) {
                return exact.id
            }
            if let exact = indexedCandidates.first(where: { candidate in
                indexedBindingsBySymbol?[candidate.id]?.record.typeSignature == typeSignature
            }) {
                return exact.id
            }
            // Fall back to legacy arity-only resolution for metadata that lacks a signature.
        }

        return candidates.first?.id ?? indexedCandidates.first?.id
    }

    private func resolveImportedPropertySymbol(
        fqName: [InternedString],
        typeSignature: String?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID? {
        let candidates = symbols.lookupAll(fqName: fqName)
            .compactMap { symbols.symbol($0) }
            .filter { $0.kind == .property }
            .sorted(by: { $0.id.rawValue < $1.id.rawValue })
        if let typeSignature, !typeSignature.isEmpty {
            let mangler = NameMangler()
            let nameResolver: (InternedString) -> String = { interner.resolve($0) }
            if let exact = candidates.first(where: { candidate in
                guard let propertyType = symbols.propertyType(for: candidate.id) else { return false }
                let candidateSig = mangler.encodeType(
                    propertyType,
                    symbols: symbols,
                    types: types,
                    nameResolver: nameResolver
                )
                return candidateSig == typeSignature
            }) {
                return exact.id
            }
        }
        return candidates.first?.id
    }

    private func resolveImportedInterfaceSymbol(
        _ fqName: [InternedString],
        symbols: SymbolTable
    ) -> SymbolID? {
        symbols.lookupAll(fqName: fqName)
            .compactMap { symbols.symbol($0) }
            .first(where: { $0.kind == .interface })?
            .id
    }
}
