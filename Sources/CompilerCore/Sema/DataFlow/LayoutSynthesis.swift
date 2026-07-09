
extension DataFlowSemaPhase {
    func synthesizeNominalLayouts(symbols: SymbolTable, types: TypeSystem) {
        let nominalKinds: [SymbolKind] = [.class, .interface, .object, .enumClass, .annotationClass]
        let nominalIDs = nominalKinds.flatMap { symbols.symbols(ofKind: $0) }
            .sorted(by: { $0.rawValue < $1.rawValue })
        guard !nominalIDs.isEmpty else { return }
        let topoOrder = buildTopoOrder(nominalIDs: nominalIDs, symbols: symbols)
        for nominalID in topoOrder {
            synthesizeLayoutForNominal(nominalID, symbols: symbols, types: types)
        }
    }

    private func buildTopoOrder(nominalIDs: [SymbolID], symbols: SymbolTable) -> [SymbolID] {
        var topoOrder: [SymbolID] = []
        var visited: Set<SymbolID> = []

        func visit(_ symbolID: SymbolID) {
            guard visited.insert(symbolID).inserted else { return }
            let superNominals = symbols.directSupertypes(for: symbolID)
                .filter { superID in
                    guard let superSymbol = symbols.symbol(superID) else { return false }
                    return isNominalLayoutTargetSymbol(superSymbol.kind)
                }
                .sorted(by: { $0.rawValue < $1.rawValue })
            for superNominal in superNominals {
                visit(superNominal)
            }
            topoOrder.append(symbolID)
        }

        for nominalID in nominalIDs {
            visit(nominalID)
        }
        return topoOrder
    }

    private func synthesizeLayoutForNominal(_ nominalID: SymbolID, symbols: SymbolTable, types: TypeSystem) {
        guard let nominalSymbol = symbols.symbol(nominalID) else { return }
        if nominalSymbol.flags.contains(.synthetic),
           symbols.nominalLayout(for: nominalID) != nil
        {
            return
        }

        let directSuperNominals = symbols.directSupertypes(for: nominalID)
            .compactMap { symbols.symbol($0) }
            .filter { isNominalLayoutTargetSymbol($0.kind) }
            .sorted(by: { $0.id.rawValue < $1.id.rawValue })

        let superClass = directSuperNominals.first(where: { $0.kind != .interface })?.id
        let layoutHint = symbols.nominalLayoutHint(for: nominalID)

        let inheritedVtable = superClass.flatMap { symbols.nominalLayout(for: $0)?.vtableSlots } ?? [:]
        let inheritedVtableSize = superClass.flatMap { symbols.nominalLayout(for: $0)?.vtableSize } ?? 0
        var vtableSlots = inheritedVtable
        // Bucketed by the coarse (name, arity, isSuspend) key: two sibling overloads
        // that merely share arity (e.g. `nextBytes(array: ByteArray)` and
        // `nextBytes(size: Int)`) must not be conflated into one vtable slot, so each
        // key can hold multiple candidates disambiguated by parameter types below.
        // Built once from genuine inheritance and never mutated afterwards, so that:
        // (1) a multi-level generic override chain doesn't see spurious "multiple
        // candidates" just because each ancestor level stored its own distinct
        // type-parameter symbols for what is really the same slot — deduped by slot
        // number below; (2) a same-class non-override sibling can never leak into
        // the candidate set that a later override in this same class consults.
        var inheritedCandidatesByKey: [MethodDispatchKey: [(parameterTypes: [TypeID], slot: Int)]] = [:]
        for methodID in inheritedVtable.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let methodSymbol = symbols.symbol(methodID),
                  let slot = inheritedVtable[methodID]
            else { continue }
            let key = methodDispatchKey(for: methodSymbol, symbols: symbols)
            if inheritedCandidatesByKey[key]?.contains(where: { $0.slot == slot }) == true {
                continue
            }
            let parameterTypes = symbols.functionSignature(for: methodID)?.parameterTypes ?? []
            inheritedCandidatesByKey[key, default: []].append((parameterTypes, slot))
        }

        var nextVtableSlot = max(inheritedVtableSize, (vtableSlots.values.max() ?? -1) + 1)
        let ownMethods = symbols.children(ofFQName: nominalSymbol.fqName)
            .filter { id in symbols.symbol(id)?.kind == .function }
            .sorted(by: { $0.rawValue < $1.rawValue })
            .compactMap { symbols.symbol($0) }
        for method in ownMethods {
            let key = methodDispatchKey(for: method, symbols: symbols)
            let candidates = inheritedCandidatesByKey[key]
            let parameterTypes = symbols.functionSignature(for: method.id)?.parameterTypes ?? []
            // Only a genuine `override` may reuse an inherited slot: a
            // freshly-declared (non-override) method can share (name, arity) with
            // an unrelated inherited overload without ever being in an override
            // relationship with it (Kotlin disallows two identical-signature
            // siblings, so any same-key sibling is necessarily a distinct overload
            // needing its own slot).
            if method.flags.contains(.overrideMember), let candidates {
                if let matchedSlot = resolveOverriddenSlot(parameterTypes: parameterTypes, candidates: candidates, types: types) {
                    vtableSlots[method.id] = matchedSlot
                    continue
                }
            }
            if let candidates,
               let matchedSlot = resolveImplicitImportedOverrideSlot(
                   method: method,
                   owner: nominalSymbol,
                   declaredVtableSize: layoutHint?.declaredVtableSize,
                   nextVtableSlot: nextVtableSlot,
                   parameterTypes: parameterTypes,
                   candidates: candidates,
                   types: types
               )
            {
                vtableSlots[method.id] = matchedSlot
                continue
            }
            vtableSlots[method.id] = nextVtableSlot
            nextVtableSlot += 1
        }
        let vtableSize = max(nextVtableSlot, layoutHint?.declaredVtableSize ?? 0)

        let inheritedItable = superClass.flatMap { symbols.nominalLayout(for: $0)?.itableSlots } ?? [:]
        let inheritedItableSize = superClass.flatMap { symbols.nominalLayout(for: $0)?.itableSize } ?? 0
        var itableSlots = inheritedItable
        var nextItableSlot = max(inheritedItableSize, (itableSlots.values.max() ?? -1) + 1)
        for interfaceID in collectInterfaceSupertypes(of: nominalID, symbols: symbols) where itableSlots[interfaceID] == nil {
            itableSlots[interfaceID] = nextItableSlot
            nextItableSlot += 1
        }
        let itableSize = max(nextItableSlot, layoutHint?.declaredItableSize ?? 0)

        let ownFields: [SemanticSymbol] = if nominalSymbol.kind == .interface {
            // Interfaces have no backing field storage; skip property fields.
            []
        } else {
            symbols.children(ofFQName: nominalSymbol.fqName)
                .filter { id in
                    guard let kind = symbols.symbol(id)?.kind else { return false }
                    return kind == .field || kind == .property
                }
                .sorted(by: { $0.rawValue < $1.rawValue })
                .compactMap { symbols.symbol($0) }
        }
        let ownFieldCount = ownFields.count
        let inheritedFieldCount = superClass.flatMap { symbols.nominalLayout(for: $0)?.instanceFieldCount } ?? 0
        // Keep nominal layout in sync with Runtime.KKObjHeader (typeInfo + flags/size).
        let objectHeaderWords = 2
        let inheritedFieldOffsets = superClass.flatMap { symbols.nominalLayout(for: $0)?.fieldOffsets } ?? [:]
        var fieldOffsets = inheritedFieldOffsets
        var nextFieldOffset = (inheritedFieldOffsets.values.max() ?? (objectHeaderWords - 1)) + 1
        for field in ownFields where fieldOffsets[field.id] == nil {
            fieldOffsets[field.id] = nextFieldOffset
            nextFieldOffset += 1
        }
        let instanceFieldCount = max(inheritedFieldCount + ownFieldCount, layoutHint?.declaredFieldCount ?? 0)
        let inheritedInstanceSizeWords = superClass.flatMap { symbols.nominalLayout(for: $0)?.instanceSizeWords } ?? 0
        let instanceSizeWords = max(
            max(objectHeaderWords + instanceFieldCount, inheritedInstanceSizeWords),
            layoutHint?.declaredInstanceSizeWords ?? 0
        )
        symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: objectHeaderWords,
                instanceFieldCount: instanceFieldCount,
                instanceSizeWords: instanceSizeWords,
                fieldOffsets: fieldOffsets,
                vtableSlots: vtableSlots,
                itableSlots: itableSlots,
                vtableSize: vtableSize,
                itableSize: itableSize,
                superClass: superClass
            ),
            for: nominalID
        )
    }

    func isNominalLayoutTargetSymbol(_ kind: SymbolKind) -> Bool {
        switch kind {
        case .class, .interface, .object, .enumClass, .annotationClass:
            true
        default:
            false
        }
    }

    private func collectInterfaceSupertypes(of symbol: SymbolID, symbols: SymbolTable) -> [SymbolID] {
        var stack: [SymbolID] = symbols.directSupertypes(for: symbol)
        var visited: Set<SymbolID> = []
        var interfaces: [SymbolID] = []

        while let current = stack.popLast() {
            guard visited.insert(current).inserted else {
                continue
            }
            guard let currentSymbol = symbols.symbol(current) else {
                continue
            }

            if currentSymbol.kind == .interface {
                interfaces.append(current)
            }
            let next = symbols.directSupertypes(for: current)
                .sorted(by: { $0.rawValue < $1.rawValue })
            for candidate in next {
                stack.append(candidate)
            }
        }

        return interfaces.sorted(by: { $0.rawValue < $1.rawValue })
    }

    private struct MethodDispatchKey: Hashable, CustomStringConvertible {
        let name: InternedString
        let arity: Int
        let isSuspend: Bool

        var description: String {
            return "\(name):\(arity)"
        }
    }

    private func methodDispatchKey(for method: SemanticSymbol, symbols: SymbolTable) -> MethodDispatchKey {
        let signature = symbols.functionSignature(for: method.id)
        return MethodDispatchKey(
            name: method.name,
            arity: signature?.parameterTypes.count ?? 0,
            isSuspend: signature?.isSuspend ?? false
        )
    }

    /// Picks which same-(name, arity) candidate an `override` member actually
    /// overrides. A single candidate is used as-is. With multiple candidates —
    /// e.g. a base class declaring both `nextBytes(array: ByteArray)` and
    /// `nextBytes(size: Int)` — a candidate whose parameter type is a bare type
    /// parameter (e.g. `fun foo(x: T)`) is treated as a wildcard, since a generic
    /// override's substituted concrete type will never textually equal it; every
    /// other position must match exactly. Returning `nil` when zero or 2+
    /// candidates are compatible is deliberate: the caller then allocates a fresh
    /// slot rather than guessing, since aliasing the override onto the wrong
    /// candidate could silently corrupt an unrelated overload's vtable entry.
    private func resolveOverriddenSlot(
        parameterTypes: [TypeID],
        candidates: [(parameterTypes: [TypeID], slot: Int)],
        types: TypeSystem
    ) -> Int? {
        if candidates.count == 1 {
            return candidates[0].slot
        }
        let compatibleSlots = Set(candidates.filter {
            isOverrideParameterMatch(candidateParameterTypes: $0.parameterTypes, overrideParameterTypes: parameterTypes, types: types)
        }.map(\.slot))
        return compatibleSlots.count == 1 ? compatibleSlots.first : nil
    }

    /// Legacy imported metadata can provide only the final vtable size without
    /// per-method slot entries or override flags. If allocating a fresh slot
    /// would exceed that imported size, preserve the metadata layout by reusing
    /// the one compatible inherited slot.
    private func resolveImplicitImportedOverrideSlot(
        method: SemanticSymbol,
        owner: SemanticSymbol,
        declaredVtableSize: Int?,
        nextVtableSlot: Int,
        parameterTypes: [TypeID],
        candidates: [(parameterTypes: [TypeID], slot: Int)],
        types: TypeSystem
    ) -> Int? {
        guard method.flags.contains(.importedLibrary),
              owner.flags.contains(.importedLibrary),
              let declaredVtableSize,
              nextVtableSlot + 1 > declaredVtableSize
        else {
            return nil
        }
        let compatibleSlots = Set(candidates.filter {
            isOverrideParameterMatch(candidateParameterTypes: $0.parameterTypes, overrideParameterTypes: parameterTypes, types: types)
        }.map(\.slot))
        return compatibleSlots.count == 1 ? compatibleSlots.first : nil
    }

    private func isOverrideParameterMatch(
        candidateParameterTypes: [TypeID],
        overrideParameterTypes: [TypeID],
        types: TypeSystem
    ) -> Bool {
        guard candidateParameterTypes.count == overrideParameterTypes.count else { return false }
        for (candidateType, overrideType) in zip(candidateParameterTypes, overrideParameterTypes) {
            if case .typeParam = types.kind(of: candidateType) {
                continue
            }
            if candidateType != overrideType {
                return false
            }
        }
        return true
    }
}
