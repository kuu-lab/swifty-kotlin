/// Shared by `LayoutSynthesis` (named class/object/interface declarations,
/// processed during header validation) and `ExprTypeChecker+ObjectLiteralInference`
/// (object literal expressions, whose own members are only known once the
/// enclosing function body is type-checked — after `synthesizeNominalLayouts`
/// has already run for every named nominal). Both need the same "which
/// inherited vtable slot does this `override` member reuse" logic so an
/// override's vtable entry is never left pointing at the base class's own
/// implementation.
struct VtableMethodDispatchKey: Hashable {
    let name: InternedString
    let arity: Int
    let isSuspend: Bool
}

func vtableMethodDispatchKey(for method: SemanticSymbol, symbols: SymbolTable) -> VtableMethodDispatchKey {
    let signature = symbols.functionSignature(for: method.id)
    return VtableMethodDispatchKey(
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
func resolveOverriddenVtableSlot(
    parameterTypes: [TypeID],
    candidates: [(parameterTypes: [TypeID], slot: Int)],
    types: TypeSystem
) -> Int? {
    if candidates.count == 1 {
        return candidates[0].slot
    }
    let compatibleSlots = Set(candidates.filter {
        isOverrideVtableParameterMatch(candidateParameterTypes: $0.parameterTypes, overrideParameterTypes: parameterTypes, types: types)
    }.map(\.slot))
    return compatibleSlots.count == 1 ? compatibleSlots.first : nil
}

func isOverrideVtableParameterMatch(
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

/// Groups `inheritedVtableSlots` (methodSymbol → slot) by dispatch key so an
/// `override` member can look up the slot(s) it might reuse. Mirrors
/// `LayoutSynthesis.synthesizeLayoutForNominal`'s local candidate map: built
/// once from genuine inheritance, one entry per distinct slot per key.
func vtableInheritedCandidatesByKey(
    inheritedVtableSlots: [SymbolID: Int],
    symbols: SymbolTable
) -> [VtableMethodDispatchKey: [(parameterTypes: [TypeID], slot: Int)]] {
    var result: [VtableMethodDispatchKey: [(parameterTypes: [TypeID], slot: Int)]] = [:]
    for methodID in inheritedVtableSlots.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
        guard let methodSymbol = symbols.symbol(methodID),
              let slot = inheritedVtableSlots[methodID]
        else { continue }
        let key = vtableMethodDispatchKey(for: methodSymbol, symbols: symbols)
        if result[key]?.contains(where: { $0.slot == slot }) == true {
            continue
        }
        let parameterTypes = symbols.functionSignature(for: methodID)?.parameterTypes ?? []
        result[key, default: []].append((parameterTypes, slot))
    }
    return result
}
