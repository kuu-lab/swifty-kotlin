/// Emits `kk_type_register_iface`/`kk_type_register_super` calls for the
/// full transitive closure of `rootSymbol`'s supertypes, not just its direct
/// ones.
///
/// BUG-219: a supertype reachable only through another, never-instantiated
/// nominal (typically an interface, e.g. `Ranked` between `Bronze` and
/// `Comparable` in `interface Ranked : Comparable<Ranked>`) never gets its
/// own edge to ITS supertypes registered anywhere, because interfaces (and
/// abstract classes) are never themselves constructed — only concrete
/// instantiation sites emit these registrations. `runtimeIsAssignable`'s BFS
/// over `state.typeParents` (`Sources/Runtime/RuntimeHelpers.swift`) walks
/// one edge per node, so it needs an entry at every node along the chain,
/// not just at `rootSymbol` itself. Register one edge for every (node,
/// direct parent) pair reachable from `rootSymbol`, keyed by each node's own
/// stable nominal type ID.
///
/// Registration is idempotent (`runtimeRegisterTypeEdge` inserts into a
/// `Set`), so redundantly re-registering an edge shared by multiple
/// constructed types (or re-registering the same type's edges on every one
/// of its constructions) is harmless — this matches the pre-existing
/// per-construction-site registration model, just walked to full depth
/// instead of one hop.
func appendTypeAncestryRegistrations<Instructions: RangeReplaceableCollection>(
    rootSymbol: SymbolID,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout Instructions
) where Instructions.Element == KIRInstruction {
    let intType = sema.types.intType

    func emitTypeIDConst(_ symbol: SymbolID) -> KIRExprID {
        let typeID = RuntimeTypeCheckToken.stableNominalTypeID(symbol: symbol, sema: sema, interner: interner)
        let expr = arena.appendExpr(.intLiteral(typeID), type: intType)
        instructions.append(.constValue(result: expr, value: .intLiteral(typeID)))
        return expr
    }

    var stack: [SymbolID] = [rootSymbol]
    var visited: Set<SymbolID> = []
    while let node = stack.popLast() {
        guard visited.insert(node).inserted else { continue }
        let directSupers = sema.symbols.directSupertypes(for: node)
        guard !directSupers.isEmpty else { continue }
        let childExpr = emitTypeIDConst(node)
        for superSymbol in directSupers {
            let parentExpr = emitTypeIDConst(superSymbol)
            let registerResult = arena.appendTemporary(type: intType)
            let superKind = sema.symbols.symbol(superSymbol)?.kind
            let registerCallee: InternedString = if superKind == .interface {
                interner.intern("kk_type_register_iface")
            } else {
                interner.intern("kk_type_register_super")
            }
            instructions.append(.call(
                symbol: nil,
                callee: registerCallee,
                arguments: [childExpr, parentExpr],
                result: registerResult,
                canThrow: false,
                thrownResult: nil
            ))
            stack.append(superSymbol)
        }
    }
}
