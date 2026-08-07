/// BUG-141: interface stored/abstract properties (`override val`, no custom
/// getter) had no virtual dispatch path. Reading such a property through an
/// interface-typed receiver fell back to an undefined symbol and produced a
/// `KSWIFTK-LINK-0001` link error. These helpers model an interface property as
/// a getter method that lives in the interface's itable, mirroring how member
/// functions are dispatched (see `resolveItableDispatch` /
/// `appendObjectItableMethodRegistrations`).
///
/// Property getter slots are laid out *after* the interface's method slots
/// (`[vtableSize, vtableSize + propertyCount)`) so they never collide with
/// method slots and require no change to the persisted `NominalLayout`.

/// The interface's own instance properties that participate in itable dispatch,
/// paired with the itable method slot each getter occupies. Deterministically
/// ordered by symbol id so the dispatch site and the registration site agree.
func kirInterfacePropertyGetterSlots(
    interfaceSymbol: SymbolID,
    sema: SemaModule
) -> [(propertySymbol: SymbolID, slot: Int)] {
    guard sema.symbols.symbol(interfaceSymbol)?.kind == .interface,
          let interfaceInfo = sema.symbols.symbol(interfaceSymbol),
          let layout = sema.symbols.nominalLayout(for: interfaceSymbol)
    else {
        return []
    }

    let base = layout.vtableSize
    let properties = sema.symbols.children(ofFQName: interfaceInfo.fqName)
        .compactMap { id -> SymbolID? in
            guard sema.symbols.symbol(id)?.kind == .property else { return nil }
            // Stdlib interface properties bridged to a runtime `kk_*` getter
            // (e.g. `size`, `length`) are read through their external link, not
            // an itable slot — leave them out of the property getter table.
            if let linkName = sema.symbols.externalLinkName(for: id), !linkName.isEmpty {
                return nil
            }
            return id
        }
        .sorted { $0.rawValue < $1.rawValue }

    return properties.enumerated().map { index, propertySymbol in
        (propertySymbol: propertySymbol, slot: base + index)
    }
}

/// The itable method slot the getter for `interfaceProperty` occupies, or nil
/// when the property does not participate in itable dispatch.
func kirInterfacePropertyGetterSlot(
    interfaceProperty: SymbolID,
    interfaceSymbol: SymbolID,
    sema: SemaModule
) -> Int? {
    kirInterfacePropertyGetterSlots(interfaceSymbol: interfaceSymbol, sema: sema)
        .first { $0.propertySymbol == interfaceProperty }?
        .slot
}

/// The implementing getter accessor symbol for `interfaceProperty` in
/// `nominalSymbol` (a class or object-literal nominal), or nil when the type
/// does not declare an override for it.
func kirFindOverridePropertyGetter(
    for interfaceProperty: SymbolID,
    in nominalSymbol: SymbolID,
    sema: SemaModule
) -> SymbolID? {
    guard let propertySym = sema.symbols.symbol(interfaceProperty),
          let ownerSym = sema.symbols.symbol(nominalSymbol)
    else {
        return nil
    }

    let overrideFQName = ownerSym.fqName + [propertySym.name]
    for candidate in sema.symbols.lookupAll(fqName: overrideFQName) {
        guard let candidateSym = sema.symbols.symbol(candidate),
              candidateSym.kind == .property,
              sema.symbols.parentSymbol(for: candidate) == nominalSymbol
        else {
            continue
        }
        return sema.symbols.extensionPropertyGetterAccessor(for: candidate)
            ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: candidate)
    }
    return nil
}

/// Registers each implemented interface property getter into the object's
/// itable, alongside the method registrations emitted for the same interfaces.
/// The interface itself is already registered by the method-registration pass
/// (`kk_object_register_itable_iface`), so this only appends the getter slots.
func appendObjectItablePropertyGetterRegistrations(
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
    let registerCallee = interner.intern("kk_object_register_itable_method")
    let interfaceSupertypes = sema.symbols.directSupertypes(for: nominalSymbol).filter { superSymbol in
        sema.symbols.symbol(superSymbol)?.kind == .interface
    }

    for interfaceSymbol in interfaceSupertypes {
        let getterSlots = kirInterfacePropertyGetterSlots(interfaceSymbol: interfaceSymbol, sema: sema)
        guard !getterSlots.isEmpty else {
            continue
        }

        let ifaceSlot = Int64(objectLayout.itableSlots[interfaceSymbol] ?? 0)
        let ifaceSlotExpr = arena.appendExpr(.intLiteral(ifaceSlot), type: intType)
        instructions.append(.constValue(result: ifaceSlotExpr, value: .intLiteral(ifaceSlot)))

        for (propertySymbol, slotInt) in getterSlots {
            guard let implGetter = kirFindOverridePropertyGetter(
                for: propertySymbol,
                in: nominalSymbol,
                sema: sema
            ) else {
                continue
            }

            let methodSlot = Int64(slotInt)
            let methodSlotExpr = arena.appendExpr(.intLiteral(methodSlot), type: intType)
            instructions.append(.constValue(result: methodSlotExpr, value: .intLiteral(methodSlot)))

            let methodFnExpr = arena.appendExpr(.symbolRef(implGetter), type: intType)
            instructions.append(.constValue(result: methodFnExpr, value: .symbolRef(implGetter)))

            let registerResult = arena.appendTemporary(type: intType)
            instructions.append(.call(
                symbol: nil,
                callee: registerCallee,
                arguments: [objectValue, ifaceSlotExpr, methodSlotExpr, methodFnExpr],
                result: registerResult,
                canThrow: false,
                thrownResult: nil
            ))
        }
    }
}
