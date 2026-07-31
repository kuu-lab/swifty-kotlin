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

func appendObjectItableMethodRegistrations(
    objectValue: KIRExprID,
    nominalSymbol: SymbolID,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout [KIRInstruction]
) {
    guard let objectLayout = sema.symbols.nominalLayout(for: nominalSymbol) else {
        return
    }

    let intType = sema.types.intType
    let interfaceSupertypes = kirTransitiveInterfaceSupertypes(of: nominalSymbol, sema: sema)
    for interfaceSymbol in interfaceSupertypes {
        guard let interfaceLayout = sema.symbols.nominalLayout(for: interfaceSymbol) else {
            continue
        }

        let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: interfaceSymbol,
            sema: sema,
            interner: interner
        )
        let interfaceTypeExpr = arena.appendExpr(.intLiteral(interfaceTypeID), type: intType)
        instructions.append(.constValue(result: interfaceTypeExpr, value: .intLiteral(interfaceTypeID)))

        let ifaceSlot = Int64(objectLayout.itableSlots[interfaceSymbol] ?? 0)
        let ifaceSlotExpr = arena.appendExpr(.intLiteral(ifaceSlot), type: intType)
        instructions.append(.constValue(result: ifaceSlotExpr, value: .intLiteral(ifaceSlot)))

        let registerIfaceResult = arena.appendTemporary(type: intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_register_itable_iface"),
            arguments: [objectValue, interfaceTypeExpr, ifaceSlotExpr],
            result: registerIfaceResult,
            canThrow: false,
            thrownResult: nil
        ))

        // Sorted by slot number for deterministic codegen: vtableSlots is a
        // Dictionary, whose iteration order is unspecified and can vary
        // between process invocations (or even between two compilations in
        // the same process, depending on insertion history) even for the
        // same key set. Iterating it directly here previously went
        // unnoticed because so few nominals reached this registration path
        // with more than one interface method — StringBuilder's Appendable
        // conformance (BUG-166) was the first to make it visible, as two
        // otherwise-identical compilations of the same source emitted their
        // three kk_object_register_itable_method calls in different orders.
        for (methodSymbol, methodSlotInt) in interfaceLayout.vtableSlots.sorted(by: { $0.value < $1.value }) {
            let implementationSymbol = kirFindOverrideMethod(
                for: methodSymbol,
                in: nominalSymbol,
                sema: sema
            ) ?? methodSymbol
            let methodSlot = Int64(methodSlotInt)
            let methodSlotExpr = arena.appendExpr(.intLiteral(methodSlot), type: intType)
            instructions.append(.constValue(result: methodSlotExpr, value: .intLiteral(methodSlot)))

            let methodFnExpr = arena.appendExpr(.symbolRef(implementationSymbol), type: intType)
            instructions.append(.constValue(result: methodFnExpr, value: .symbolRef(implementationSymbol)))

            let registerMethodResult = arena.appendTemporary(type: intType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_object_register_itable_method"),
                arguments: [objectValue, ifaceSlotExpr, methodSlotExpr, methodFnExpr],
                result: registerMethodResult,
                canThrow: false,
                thrownResult: nil
            ))
        }
    }

    // BUG-141: also register interface property getters into the itable.
    appendObjectItablePropertyGetterRegistrations(
        objectValue: objectValue,
        nominalSymbol: nominalSymbol,
        sema: sema,
        arena: arena,
        interner: interner,
        instructions: &instructions
    )
}

/// Interfaces reachable from `nominalSymbol` through the whole supertype
/// closure, including those implemented by base classes rather than by the
/// nominal itself. The itable layout assigns slots for exactly this set
/// (`LayoutSynthesis.collectInterfaceSupertypes`), so instances must register
/// every one of them to be dispatchable through an interface static type.
func kirTransitiveInterfaceSupertypes(
    of nominalSymbol: SymbolID,
    sema: SemaModule
) -> [SymbolID] {
    var stack = sema.symbols.directSupertypes(for: nominalSymbol)
    var visited: Set<SymbolID> = []
    var interfaces: [SymbolID] = []

    while let current = stack.popLast() {
        guard visited.insert(current).inserted else {
            continue
        }
        if sema.symbols.symbol(current)?.kind == .interface {
            interfaces.append(current)
        }
        stack.append(contentsOf: sema.symbols.directSupertypes(for: current))
    }

    return interfaces.sorted { $0.rawValue < $1.rawValue }
}

/// Resolves the implementation an instance of `nominalSymbol` must expose for
/// `interfaceMethod`. The override may live on the nominal itself or on any of
/// its base classes (`class IntBox : AbstractBox<Int>()` inheriting
/// `AbstractBox.get`), so the class chain is walked most-derived first.
func kirFindOverrideMethod(
    for interfaceMethod: SymbolID,
    in nominalSymbol: SymbolID,
    sema: SemaModule
) -> SymbolID? {
    guard let methodSym = sema.symbols.symbol(interfaceMethod) else {
        return nil
    }

    let interfaceParamCount = sema.symbols.functionSignature(for: interfaceMethod)?.parameterTypes.count

    var visited: Set<SymbolID> = []
    var current: SymbolID? = nominalSymbol
    while let nominal = current, visited.insert(nominal).inserted {
        if let ownerSym = sema.symbols.symbol(nominal) {
            let overrideFQName = ownerSym.fqName + [methodSym.name]
            var firstCandidate: SymbolID?
            for candidate in sema.symbols.lookupAll(fqName: overrideFQName) {
                guard let candidateSym = sema.symbols.symbol(candidate),
                      candidateSym.kind == .function,
                      sema.symbols.parentSymbol(for: candidate) == nominal
                else {
                    continue
                }
                if firstCandidate == nil {
                    firstCandidate = candidate
                }
                // BUG-166: a nominal can have several same-named overloads
                // (e.g. StringBuilder's many `append` variants), only one of
                // which matches a given interface method's arity. Returning
                // the first name match regardless of parameter count wires
                // the wrong implementation into that interface method's
                // itable slot, corrupting the call's argument list at
                // runtime. Prefer an arity-matching candidate; keep the old
                // first-match behavior as a fallback for interface methods
                // whose signature isn't tracked.
                if let interfaceParamCount,
                   let candidateSig = sema.symbols.functionSignature(for: candidate),
                   candidateSig.parameterTypes.count == interfaceParamCount
                {
                    return candidate
                }
            }
            if let firstCandidate {
                return firstCandidate
            }
        }
        current = kirSuperclass(of: nominal, sema: sema)
    }
    return nil
}

private func kirSuperclass(of nominalSymbol: SymbolID, sema: SemaModule) -> SymbolID? {
    sema.symbols.directSupertypes(for: nominalSymbol).first { superSymbol in
        switch sema.symbols.symbol(superSymbol)?.kind {
        case .class, .enumClass, .object:
            true
        default:
            false
        }
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
