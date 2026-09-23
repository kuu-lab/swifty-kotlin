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

struct KIRInterfacePropertyGetterSlot {
    let propertySymbol: SymbolID?
    let propertyName: InternedString
    let slot: Int
}

/// The interface's own instance properties that participate in itable dispatch,
/// paired with the itable method slot each getter occupies. Ordered by property
/// name so the dispatch site and the registration site agree even when they are
/// in different compilation units (a precompiled library registers the getters,
/// its consumer dispatches through them, and symbol ids differ between the two).
func kirInterfacePropertyGetterSlots(
    interfaceSymbol: SymbolID,
    sema: SemaModule,
    interner: StringInterner
) -> [KIRInterfacePropertyGetterSlot] {
    guard sema.symbols.symbol(interfaceSymbol)?.kind == .interface,
          let interfaceInfo = sema.symbols.symbol(interfaceSymbol),
          let layout = sema.symbols.nominalLayout(for: interfaceSymbol)
    else {
        return []
    }

    let base = layout.vtableSize
    let knownNames = KnownCompilerNames(interner: interner)
    let sizeName = knownNames.size
    let isCollectionOrMap = interfaceInfo.fqName == knownNames.kotlinCollectionsCollectionFQName
        || interfaceInfo.fqName == knownNames.kotlinCollectionsMapFQName
    var properties = sema.symbols.children(ofFQName: interfaceInfo.fqName)
        .compactMap { id -> (symbol: SymbolID?, name: InternedString)? in
            guard let property = sema.symbols.symbol(id), property.kind == .property else { return nil }
            let isSyntheticCollectionSize = isCollectionOrMap && property.name == sizeName
            // BUG-240: Map's other runtime-bridged view properties
            // (keys/values/entries) need itable getter slots too so a custom
            // Map — delegated (`class C : Map<K,V> by d`) or hand-written — is
            // observable through `kk_map_keys`/`kk_map_values`/`kk_map_entries`,
            // whose non-box path looks the getter up dynamically.
            let isRuntimeBridgedMapViewProperty = interfaceInfo.fqName == knownNames.kotlinCollectionsMapFQName
                && [
                    interner.intern("keys"),
                    interner.intern("values"),
                    interner.intern("entries"),
                ].contains(property.name)
            let isBridgedCollectionProperty = isSyntheticCollectionSize
                || isRuntimeBridgedMapViewProperty
            // Stdlib interface properties bridged to a runtime `kk_*` getter
            // (e.g. `length`) are read through their external link, not an
            // itable slot — leave them out of the property getter table.
            // Collection `size` and Map's view properties are the exception:
            // their runtime bridges can fall back to source-backed itable
            // dispatch for custom implementations.
            if let linkName = sema.symbols.externalLinkName(for: id),
               !linkName.isEmpty,
               !isBridgedCollectionProperty
            {
                return nil
            }
            // Likewise for synthetic runtime members registered on an otherwise
            // Kotlin-declared interface: only declarations that exist in Kotlin
            // (source, or the same declaration imported from a precompiled
            // library) own an itable getter slot. Collection `size` is the
            // intentional exception: source-backed generic helpers need custom
            // implementations to remain observable through the existing bridge.
            guard property.declSite != nil || property.flags.contains(.importedLibrary) || isSyntheticCollectionSize else {
                return nil
            }
            return (symbol: id, name: property.name)
        }
    // Collection/Map size is currently a synthetic interface surface. Keep a
    // KIR-only slot when the declaration is absent so source-defined concrete
    // implementations still participate in dynamic property dispatch without
    // making every ordinary `map.size` sema reference synthetic.
    if isCollectionOrMap, !properties.contains(where: { $0.name == sizeName }) {
        properties.append((symbol: nil, name: sizeName))
    }
    // Resolve names once up front: interner.resolve is a lock-protected lookup,
    // so calling it inside the comparator costs O(n log n) resolves per build.
    let sortedProperties = properties
        .map { (resolvedName: interner.resolve($0.name), property: $0) }
        .sorted { lhs, rhs in
            if lhs.resolvedName != rhs.resolvedName { return lhs.resolvedName < rhs.resolvedName }
            return (lhs.property.symbol?.rawValue ?? -1) < (rhs.property.symbol?.rawValue ?? -1)
        }

    return sortedProperties.enumerated().map { index, entry in
        KIRInterfacePropertyGetterSlot(
            propertySymbol: entry.property.symbol,
            propertyName: entry.property.name,
            slot: base + index
        )
    }
}

/// The itable method slot the getter for `interfaceProperty` occupies, or nil
/// when the property does not participate in itable dispatch.
func kirInterfacePropertyGetterSlot(
    interfaceProperty: SymbolID,
    interfaceSymbol: SymbolID,
    sema: SemaModule,
    interner: StringInterner,
    cache: KIRNominalDispatchCache? = nil
) -> Int? {
    if let cache {
        return cache.interfacePropertyGetterSlot(
            for: interfaceProperty,
            in: interfaceSymbol,
            sema: sema,
            interner: interner
        )
    }
    return kirInterfacePropertyGetterSlots(interfaceSymbol: interfaceSymbol, sema: sema, interner: interner)
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
    guard let propertySym = sema.symbols.symbol(interfaceProperty) else {
        return nil
    }

    var visited: Set<SymbolID> = []
    var current: SymbolID? = nominalSymbol
    while let nominal = current, visited.insert(nominal).inserted {
        guard let ownerSym = sema.symbols.symbol(nominal) else { break }
        let overrideFQName = ownerSym.fqName + [propertySym.name]
        for candidate in sema.symbols.lookupAll(fqName: overrideFQName) {
            guard let candidateSym = sema.symbols.symbol(candidate),
                  candidateSym.kind == .property,
                  sema.symbols.parentSymbol(for: candidate) == nominal
            else {
                continue
            }
            return sema.symbols.extensionPropertyGetterAccessor(for: candidate)
                ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: candidate)
        }
        current = kirSuperclass(of: nominal, sema: sema)
    }

    // If no class override was found, check implemented interfaces in BFS order (most derived first)
    // for an override or default implementation.
    var queue: [SymbolID] = []
    var visitedNominals: Set<SymbolID> = []
    var currentNominal: SymbolID? = nominalSymbol
    while let nominal = currentNominal, visitedNominals.insert(nominal).inserted {
        for supertype in sema.symbols.directSupertypes(for: nominal) {
            if sema.symbols.symbol(supertype)?.kind == .interface {
                queue.append(supertype)
            }
        }
        currentNominal = kirSuperclass(of: nominal, sema: sema)
    }

    var visitedInterfaces: Set<SymbolID> = []
    while !queue.isEmpty {
        let iface = queue.removeFirst()
        guard visitedInterfaces.insert(iface).inserted else { continue }
        for supertype in sema.symbols.directSupertypes(for: iface) {
            if sema.symbols.symbol(supertype)?.kind == .interface {
                queue.append(supertype)
            }
        }
        guard let ifaceSym = sema.symbols.symbol(iface) else { continue }
        let ifacePropertyFQName = ifaceSym.fqName + [propertySym.name]
        for candidate in sema.symbols.lookupAll(fqName: ifacePropertyFQName) {
            guard let candidateSym = sema.symbols.symbol(candidate),
                  candidateSym.kind == .property,
                  sema.symbols.parentSymbol(for: candidate) == iface
            else {
                continue
            }
            return sema.symbols.extensionPropertyGetterAccessor(for: candidate)
                ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: candidate)
        }
    }

    return nil
}

private func kirFindOverridePropertyGetter(
    named propertyName: InternedString,
    in nominalSymbol: SymbolID,
    sema: SemaModule
) -> SymbolID? {
    guard let ownerSym = sema.symbols.symbol(nominalSymbol) else {
        return nil
    }
    let overrideFQName = ownerSym.fqName + [propertyName]
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

/// The interface's own instance `var` properties that participate in itable
/// dispatch, paired with the itable slot each setter occupies. Setter slots
/// are laid out *after* every getter slot (`[vtableSize + getterCount, ...)`)
/// so a setter registration can never collide with a getter registration for
/// the same or a different property on the same interface.
///
/// Reuses `kirInterfacePropertyGetterSlots`'s eligibility filtering (stdlib
/// runtime bridges, non-Kotlin-declared synthetic members) so a property
/// only gets a setter slot when it already has a getter slot — every `var`
/// is also a `val`-shaped read, so this is not an additional restriction.
private struct KIRInterfacePropertySetterSlot {
    let propertySymbol: SymbolID
    let propertyName: InternedString
    let slot: Int
}

private func kirInterfacePropertySetterSlots(
    interfaceSymbol: SymbolID,
    sema: SemaModule,
    interner: StringInterner
) -> [KIRInterfacePropertySetterSlot] {
    let getterSlots = kirInterfacePropertyGetterSlots(interfaceSymbol: interfaceSymbol, sema: sema, interner: interner)
    guard !getterSlots.isEmpty else {
        return []
    }
    let base = (getterSlots.map(\.slot).max() ?? -1) + 1
    let mutableProperties = getterSlots.compactMap { getterSlot -> (symbol: SymbolID, name: InternedString)? in
        guard let propertySymbol = getterSlot.propertySymbol,
              sema.symbols.symbol(propertySymbol)?.flags.contains(.mutable) == true
        else {
            return nil
        }
        return (symbol: propertySymbol, name: getterSlot.propertyName)
    }
    return mutableProperties.enumerated().map { index, property in
        KIRInterfacePropertySetterSlot(propertySymbol: property.symbol, propertyName: property.name, slot: base + index)
    }
}

/// The itable slot the setter for `interfaceProperty` occupies, or nil when
/// the property does not participate in itable dispatch (not mutable, or
/// excluded by `kirInterfacePropertyGetterSlots`'s eligibility rules).
func kirInterfacePropertySetterSlot(
    interfaceProperty: SymbolID,
    interfaceSymbol: SymbolID,
    sema: SemaModule,
    interner: StringInterner
) -> Int? {
    kirInterfacePropertySetterSlots(interfaceSymbol: interfaceSymbol, sema: sema, interner: interner)
        .first { $0.propertySymbol == interfaceProperty }?
        .slot
}

/// The implementing setter accessor symbol for `interfaceProperty` in
/// `nominalSymbol`, or nil when the type does not declare an override for
/// it. The setter counterpart of `kirFindOverridePropertyGetter` above.
func kirFindOverridePropertySetter(
    for interfaceProperty: SymbolID,
    in nominalSymbol: SymbolID,
    sema: SemaModule
) -> SymbolID? {
    guard let propertySym = sema.symbols.symbol(interfaceProperty) else {
        return nil
    }

    var visited: Set<SymbolID> = []
    var current: SymbolID? = nominalSymbol
    while let nominal = current, visited.insert(nominal).inserted {
        guard let ownerSym = sema.symbols.symbol(nominal) else { break }
        let overrideFQName = ownerSym.fqName + [propertySym.name]
        for candidate in sema.symbols.lookupAll(fqName: overrideFQName) {
            guard let candidateSym = sema.symbols.symbol(candidate),
                  candidateSym.kind == .property,
                  sema.symbols.parentSymbol(for: candidate) == nominal
            else {
                continue
            }
            return sema.symbols.extensionPropertySetterAccessor(for: candidate)
                ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: candidate)
        }
        current = kirSuperclass(of: nominal, sema: sema)
    }

    // If no class override was found, check implemented interfaces in BFS order (most derived first)
    // for an override or default implementation.
    var queue: [SymbolID] = []
    var visitedNominals: Set<SymbolID> = []
    var currentNominal: SymbolID? = nominalSymbol
    while let nominal = currentNominal, visitedNominals.insert(nominal).inserted {
        for supertype in sema.symbols.directSupertypes(for: nominal) {
            if sema.symbols.symbol(supertype)?.kind == .interface {
                queue.append(supertype)
            }
        }
        currentNominal = kirSuperclass(of: nominal, sema: sema)
    }

    var visitedInterfaces: Set<SymbolID> = []
    while !queue.isEmpty {
        let iface = queue.removeFirst()
        guard visitedInterfaces.insert(iface).inserted else { continue }
        for supertype in sema.symbols.directSupertypes(for: iface) {
            if sema.symbols.symbol(supertype)?.kind == .interface {
                queue.append(supertype)
            }
        }
        guard let ifaceSym = sema.symbols.symbol(iface) else { continue }
        let ifacePropertyFQName = ifaceSym.fqName + [propertySym.name]
        for candidate in sema.symbols.lookupAll(fqName: ifacePropertyFQName) {
            guard let candidateSym = sema.symbols.symbol(candidate),
                  candidateSym.kind == .property,
                  sema.symbols.parentSymbol(for: candidate) == iface
            else {
                continue
            }
            return sema.symbols.extensionPropertySetterAccessor(for: candidate)
                ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: candidate)
        }
    }

    return nil
}

/// Registers each implemented interface property getter into the object's
/// itable, alongside the method registrations emitted for the same interfaces.
/// The interface itself is already registered by the method-registration pass
/// (`kk_object_register_itable_iface`), so this only appends the getter slots.
func appendObjectItablePropertyGetterRegistrations<C: RangeReplaceableCollection>(
    objectValue: KIRExprID,
    nominalSymbol: SymbolID,
    sema: SemaModule,
    cache: KIRNominalDispatchCache,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout C
) where C.Element == KIRInstruction {
    guard let objectLayout = sema.symbols.nominalLayout(for: nominalSymbol) else {
        return
    }

    let intType = sema.types.intType
    let registerCallee = interner.intern("kk_object_register_itable_method")
    let interfaceSupertypes = cache.transitiveInterfaceSupertypes(of: nominalSymbol, sema: sema)

    for interfaceSymbol in interfaceSupertypes {
        let getterSlots = cache.interfacePropertyGetterSlots(
            for: interfaceSymbol,
            sema: sema,
            interner: interner
        )
        guard !getterSlots.isEmpty else {
            continue
        }

        let ifaceSlot = Int64(objectLayout.itableSlots[interfaceSymbol] ?? 0)
        let ifaceSlotExpr = arena.appendExpr(.intLiteral(ifaceSlot), type: intType)
        instructions.append(.constValue(result: ifaceSlotExpr, value: .intLiteral(ifaceSlot)))

        for getterSlot in getterSlots {
            let implGetter: SymbolID? = if let propertySymbol = getterSlot.propertySymbol {
                kirFindOverridePropertyGetter(
                    for: propertySymbol,
                    in: nominalSymbol,
                    sema: sema
                )
            } else {
                kirFindOverridePropertyGetter(
                    named: getterSlot.propertyName,
                    in: nominalSymbol,
                    sema: sema
                )
            }
            guard let implGetter else {
                continue
            }

            let methodSlot = Int64(getterSlot.slot)
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

/// Registers each implemented interface property setter into the object's
/// itable, alongside the getter registrations above. The setter counterpart
/// of `appendObjectItablePropertyGetterRegistrations` — without it, writing a
/// `var` through an interface-typed receiver has no dispatch target to find
/// at the write site (`tryLowerInterfaceItablePropertySetterWrite` in
/// `CallLowerer+MemberAssignment.swift`), even though every concrete
/// overriding class already has a real setter accessor function registered
/// (BUG-227's `synthesizeStoredPropertySetterAccessor` emits one
/// unconditionally for any `override var`).
func appendObjectItablePropertySetterRegistrations<C: RangeReplaceableCollection>(
    objectValue: KIRExprID,
    nominalSymbol: SymbolID,
    sema: SemaModule,
    cache: KIRNominalDispatchCache,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout C
) where C.Element == KIRInstruction {
    guard let objectLayout = sema.symbols.nominalLayout(for: nominalSymbol) else {
        return
    }

    let intType = sema.types.intType
    let registerCallee = interner.intern("kk_object_register_itable_method")
    let interfaceSupertypes = cache.transitiveInterfaceSupertypes(of: nominalSymbol, sema: sema)

    for interfaceSymbol in interfaceSupertypes {
        let setterSlots = kirInterfacePropertySetterSlots(
            interfaceSymbol: interfaceSymbol,
            sema: sema,
            interner: interner
        )
        guard !setterSlots.isEmpty else {
            continue
        }

        let ifaceSlot = Int64(objectLayout.itableSlots[interfaceSymbol] ?? 0)
        let ifaceSlotExpr = arena.appendExpr(.intLiteral(ifaceSlot), type: intType)
        instructions.append(.constValue(result: ifaceSlotExpr, value: .intLiteral(ifaceSlot)))

        for setterSlot in setterSlots {
            guard let implSetter = kirFindOverridePropertySetter(
                for: setterSlot.propertySymbol,
                in: nominalSymbol,
                sema: sema
            ) else {
                continue
            }

            let methodSlot = Int64(setterSlot.slot)
            let methodSlotExpr = arena.appendExpr(.intLiteral(methodSlot), type: intType)
            instructions.append(.constValue(result: methodSlotExpr, value: .intLiteral(methodSlot)))

            let methodFnExpr = arena.appendExpr(.symbolRef(implSetter), type: intType)
            instructions.append(.constValue(result: methodFnExpr, value: .symbolRef(implSetter)))

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
