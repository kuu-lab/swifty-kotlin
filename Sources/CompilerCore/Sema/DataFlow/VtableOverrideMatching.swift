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

struct VtableOverrideCandidate {
    let method: SymbolID
    let parameterTypes: [TypeID]
    let slot: Int
}

/// Reuse the unique inherited slot with matching method bounds and argument
/// shape after class specialization and binder alpha-alignment. Signatures
/// without method binders retain the legacy class-parameter wildcard fallback.
func resolveOverriddenVtableSlot(
    method: SemanticSymbol,
    parameterTypes: [TypeID],
    candidates: [VtableOverrideCandidate],
    symbols: SymbolTable,
    types: TypeSystem
) -> Int? {
    let candidates = candidates.filter { candidate in
        guard let source = symbols.functionSignature(for: candidate.method),
              let target = symbols.functionSignature(for: method.id),
              let owner = symbols.parentSymbol(for: method.id)
        else { return true }
        guard methodUpperBoundsMatch(source: source, target: target,
                                     sourceOwner: symbols.parentSymbol(for: candidate.method),
                                     targetOwner: owner, types: types) else { return false }
        if source.typeParameterSymbols.count > source.classTypeParameterCount {
            let alignedSource = alignedMethodParameterTypes(source: source, target: target,
                                                            sourceOwner: symbols.parentSymbol(for: candidate.method),
                                                            instanceOwner: owner, types: types)
            return methodIdentityParameterTypesMatch(candidateParameterTypes: target.parameterTypes,
                                                     interfaceParameterTypes: alignedSource, types: types)
        }
        return true
    }
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

/// Mirrors `LayoutSynthesis.synthesizeLayoutForNominal`'s local candidate map:
/// built once from genuine inheritance, one entry per distinct slot per key.
func vtableInheritedCandidatesByKey(
    inheritedVtableSlots: [SymbolID: Int],
    symbols: SymbolTable
) -> [VtableMethodDispatchKey: [VtableOverrideCandidate]] {
    var result: [VtableMethodDispatchKey: [VtableOverrideCandidate]] = [:]
    for methodID in inheritedVtableSlots.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
        guard let methodSymbol = symbols.symbol(methodID),
              let slot = inheritedVtableSlots[methodID]
        else { continue }
        let key = vtableMethodDispatchKey(for: methodSymbol, symbols: symbols)
        if result[key]?.contains(where: { $0.slot == slot }) == true {
            continue
        }
        let parameterTypes = symbols.functionSignature(for: methodID)?.parameterTypes ?? []
        result[key, default: []].append(VtableOverrideCandidate(method: methodID, parameterTypes: parameterTypes, slot: slot))
    }
    return result
}
