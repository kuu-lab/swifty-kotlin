func kirVtableImplementations(
    for nominalSymbol: SymbolID,
    sema: SemaModule
) -> [(slot: Int, implementation: SymbolID)] {
    guard let layout = sema.symbols.nominalLayout(for: nominalSymbol) else {
        return []
    }

    let virtualSlots = Set(layout.vtableSlots.compactMap { methodSymbol, slot -> Int? in
        guard let owner = sema.symbols.parentSymbol(for: methodSymbol),
              !sema.symbols.directSubtypes(of: owner).isEmpty
        else {
            return nil
        }
        return slot
    })
    guard !virtualSlots.isEmpty else {
        return []
    }

    var bestBySlot: [Int: (distance: Int, implementation: SymbolID)] = [:]
    for (methodSymbol, slot) in layout.vtableSlots where virtualSlots.contains(slot) {
        guard sema.symbols.symbol(methodSymbol)?.kind == .function,
              let owner = sema.symbols.parentSymbol(for: methodSymbol),
              let distance = kirNominalDistance(from: nominalSymbol, to: owner, sema: sema)
        else {
            continue
        }
        if let current = bestBySlot[slot] {
            let isMoreSpecific = distance < current.distance
            let isStableTieBreak = distance == current.distance
                && methodSymbol.rawValue > current.implementation.rawValue
            if isMoreSpecific || isStableTieBreak {
                bestBySlot[slot] = (distance, methodSymbol)
            }
        } else {
            bestBySlot[slot] = (distance, methodSymbol)
        }
    }

    return bestBySlot
        .map { (slot: $0.key, implementation: $0.value.implementation) }
        .sorted { lhs, rhs in
            if lhs.slot != rhs.slot { return lhs.slot < rhs.slot }
            return lhs.implementation.rawValue < rhs.implementation.rawValue
        }
}

func appendObjectVtableMethodRegistrations(
    objectValue: KIRExprID,
    nominalSymbol: SymbolID,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout [KIRInstruction]
) {
    let implementations = kirVtableImplementations(for: nominalSymbol, sema: sema)
    guard !implementations.isEmpty else {
        return
    }

    let intType = sema.types.intType
    let registerCallee = interner.intern("kk_object_register_vtable_method")
    for implementation in implementations {
        let slotExpr = arena.appendExpr(.intLiteral(Int64(implementation.slot)), type: intType)
        instructions.append(.constValue(result: slotExpr, value: .intLiteral(Int64(implementation.slot))))
        let methodFnExpr = arena.appendExpr(.symbolRef(implementation.implementation), type: intType)
        instructions.append(.constValue(result: methodFnExpr, value: .symbolRef(implementation.implementation)))
        let registerResult = arena.appendTemporary(type: intType)
        instructions.append(.call(
            symbol: nil,
            callee: registerCallee,
            arguments: [objectValue, slotExpr, methodFnExpr],
            result: registerResult,
            canThrow: false,
            thrownResult: nil
        ))
    }
}

private func kirNominalDistance(
    from nominalSymbol: SymbolID,
    to targetSymbol: SymbolID,
    sema: SemaModule
) -> Int? {
    var queue: [(symbol: SymbolID, distance: Int)] = [(nominalSymbol, 0)]
    var visited: Set<SymbolID> = []

    while !queue.isEmpty {
        let current = queue.removeFirst()
        guard visited.insert(current.symbol).inserted else {
            continue
        }
        if current.symbol == targetSymbol {
            return current.distance
        }
        for superSymbol in sema.symbols.directSupertypes(for: current.symbol) {
            guard let superInfo = sema.symbols.symbol(superSymbol) else {
                continue
            }
            switch superInfo.kind {
            case .class, .object, .enumClass, .annotationClass, .interface:
                queue.append((superSymbol, current.distance + 1))
            default:
                continue
            }
        }
    }

    return nil
}
