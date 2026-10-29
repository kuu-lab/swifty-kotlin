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

func kirEnumEntryDispatchHelper(
    for accessorSymbol: SymbolID,
    in enumSymbol: SymbolID,
    sema: SemaModule,
    interner: StringInterner
) -> SymbolID? {
    guard sema.symbols.symbol(enumSymbol)?.kind == .enumClass,
          let enumInfo = sema.symbols.symbol(enumSymbol)
    else {
        return nil
    }
    let helperName = NameMangler.enumEntryDispatchHelperName(for: accessorSymbol, interner: interner)
    return sema.symbols.lookupAll(fqName: enumInfo.fqName + [helperName]).first { candidate in
        sema.symbols.symbol(candidate)?.kind == .function
            && sema.symbols.parentSymbol(for: candidate) == enumSymbol
            && sema.symbols.enumEntryDispatchBaseSymbol(for: candidate) == accessorSymbol
    }
}

/// A stored property declared on an open superclass may implement an
/// interface property only in a descendant. Materialize its ordinary
/// accessor so the descendant's itable bridge has a real function to call.
func kirStoredPropertyInheritedInterfaceAccessors(
    propertySymbol: SymbolID,
    ownerSymbol: SymbolID,
    sema: SemaModule
) -> (getter: Bool, setter: Bool) {
    guard let property = sema.symbols.symbol(propertySymbol),
          property.kind == .property,
          let owner = sema.symbols.symbol(ownerSymbol),
          owner.kind == .class,
          !sema.symbols.directSubtypes(of: ownerSymbol).isEmpty
    else {
        return (false, false)
    }

    let ownerGetter = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
    let ownerSetter = SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySymbol)
    let supportsSetter = property.flags.contains(.mutable)
    var needsGetter = false
    var needsSetter = false

    var pending = sema.symbols.directSubtypes(of: ownerSymbol)
    var visited: Set<SymbolID> = []
    while let nominal = pending.popLast() {
        guard visited.insert(nominal).inserted else {
            continue
        }
        pending.append(contentsOf: sema.symbols.directSubtypes(of: nominal))

        for interface in kirTransitiveInterfaceSupertypes(of: nominal, sema: sema) {
            guard let interfaceInfo = sema.symbols.symbol(interface) else {
                continue
            }
            for candidate in sema.symbols.lookupAll(fqName: interfaceInfo.fqName + [property.name]) {
                guard let candidateInfo = sema.symbols.symbol(candidate),
                      candidateInfo.kind == .property,
                      sema.symbols.parentSymbol(for: candidate) == interface
                else {
                    continue
                }
                if kirFindOverridePropertyGetter(for: candidate, in: nominal, sema: sema) == ownerGetter {
                    needsGetter = true
                }
                if supportsSetter, candidateInfo.flags.contains(.mutable),
                   kirFindOverridePropertySetter(for: candidate, in: nominal, sema: sema) == ownerSetter
                {
                    needsSetter = true
                }
                if needsGetter, !supportsSetter || needsSetter {
                    return (needsGetter, needsSetter)
                }
            }
        }
    }
    return (needsGetter, needsSetter)
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
    let isClosedFloatingPointRange = interfaceInfo.fqName == [
        interner.intern("kotlin"), interner.intern("ranges"), interner.intern("ClosedFloatingPointRange"),
    ]
    var properties = sema.symbols.children(ofFQName: interfaceInfo.fqName)
        .compactMap { id -> (symbol: SymbolID?, name: InternedString)? in
            guard let property = sema.symbols.symbol(id), property.kind == .property else { return nil }
            let isSyntheticCollectionSize = isCollectionOrMap && property.name == sizeName
            let isFloatingPointEndpoint = isClosedFloatingPointRange
                && [interner.intern("start"), interner.intern("endInclusive")].contains(property.name)
            // BUG-240: Map's other runtime-bridged view properties
            // (keys/values/entries/size) need itable getter slots too so a
            // custom Map — delegated (`class C : Map<K,V> by d`) or
            // hand-written — stays observable through `kk_map_keys` /
            // `kk_map_values` / `kk_map_entries`, whose non-box path looks
            // the getter up dynamically.
            let isSyntheticMapProperty = interfaceInfo.fqName == knownNames.kotlinCollectionsMapFQName
                && [
                    interner.intern("entries"), interner.intern("keys"),
                    sizeName, interner.intern("values"),
                ].contains(property.name)
            // Continuation.context is likewise runtime-bridged
            // (`__kk_coroutine_continuation_context`), and that bridge falls
            // back to source-backed itable dispatch for user-defined
            // Continuation implementations — keep its getter slot so the
            // fallback has a registered target.
            let isContinuationContext = interfaceInfo.fqName == [
                interner.intern("kotlin"), interner.intern("coroutines"), interner.intern("Continuation"),
            ] && property.name == interner.intern("context")
            // Stdlib interface properties bridged to a runtime `kk_*` getter
            // (e.g. `length`) are read through their external link, not an
            // itable slot — leave them out of the property getter table.
            // Collection/Map runtime-backed properties are the exception: their
            // bridges can fall back to source-backed itable dispatch for custom
            // views.
            let hasRuntimeLink = sema.symbols.externalLinkName(for: id)?.isEmpty == false
                || sema.symbols.annotations(for: id).contains {
                    KnownCompilerAnnotation.ksSymbolName.matches($0.annotationFQName)
                }
            // Imported properties can carry the bridge on their getter instead
            // of the property symbol. Preserve the source-side slot layout.
            if hasRuntimeLink, !isSyntheticMapProperty, !isSyntheticCollectionSize, !isContinuationContext {
                return nil
            }
            // Likewise for synthetic runtime members registered on an otherwise
            // Kotlin-declared interface: only declarations that exist in Kotlin
            // (source, or the same declaration imported from a precompiled
            // library) own an itable getter slot. Collection/Map runtime-backed
            // properties are intentional exceptions: source-backed generic
            // helpers need custom implementations to remain observable through
            // the existing bridge.
            guard property.declSite != nil
                || property.flags.contains(.importedLibrary)
                || isSyntheticCollectionSize
                || isSyntheticMapProperty
                || isFloatingPointEndpoint
            else {
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
    // A candidate implements `interfaceProperty` only from the interface
    // that declares it or from a descendant interface — an unrelated
    // interface's same-named member is not an override. `nil` when the owner
    // is unknown keeps the legacy name-only fallback.
    let interfaceOwner = sema.symbols.parentSymbol(for: interfaceProperty)

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
            // A `private` member never overrides, so it cannot implement an
            // interface member — e.g. `C`'s `private val c` must not fill
            // `A.c`'s itable slot (kt2477).
            if candidateSym.visibility == .private {
                continue
            }
            return sema.symbols.extensionPropertyGetterAccessor(for: candidate)
                ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: candidate)
        }
        if ownerSym.flags.contains(.synthetic) {
            for candidate in sema.symbols.lookupByShortName(propertySym.name) {
                guard let receiver = sema.symbols.extensionPropertyReceiverType(for: candidate),
                      case let .classType(receiverClass) = sema.types.kind(of: receiver),
                      receiverClass.classSymbol == nominal,
                      let getter = sema.symbols.extensionPropertyGetterAccessor(for: candidate)
                else { continue }
                return getter
            }
        }
        current = kirSuperclass(of: nominal, sema: sema)
    }

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
        // An interface unrelated to `interfaceProperty`'s owner cannot hold
        // a default for it: `B.c` is not a `A.c` implementation even when the
        // names collide (kt2477).
        if let interfaceOwner,
           iface != interfaceOwner,
           !kirTransitiveInterfaceSupertypes(of: iface, sema: sema).contains(interfaceOwner)
        {
            continue
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
            // A `private` member never overrides — except the interface
            // property's own declaration, which is the required default for
            // its own itable slot even when it is `private`.
            if candidate != interfaceProperty,
               candidateSym.visibility == .private
            {
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
        // A `private` member never overrides (kt2477).
        if candidateSym.visibility == .private {
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
struct KIRInterfacePropertySetterSlot {
    let propertySymbol: SymbolID
    let propertyName: InternedString
    let slot: Int
}

func kirInterfacePropertySetterSlots(
    from getterSlots: [KIRInterfacePropertyGetterSlot],
    sema: SemaModule
) -> [KIRInterfacePropertySetterSlot] {
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
    interner: StringInterner,
    cache: KIRNominalDispatchCache
) -> Int? {
    cache.interfacePropertySetterSlot(
        for: interfaceProperty,
        in: interfaceSymbol,
        sema: sema,
        interner: interner
    )
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
    // See `kirFindOverridePropertyGetter`: only the declaring interface or a
    // descendant can hold a default for `interfaceProperty`.
    let interfaceOwner = sema.symbols.parentSymbol(for: interfaceProperty)

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
            // A `private` member never overrides (kt2477).
            if candidateSym.visibility == .private {
                continue
            }
            return sema.symbols.extensionPropertySetterAccessor(for: candidate)
                ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: candidate)
        }
        current = kirSuperclass(of: nominal, sema: sema)
    }

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
        if let interfaceOwner,
           iface != interfaceOwner,
           !kirTransitiveInterfaceSupertypes(of: iface, sema: sema).contains(interfaceOwner)
        {
            continue
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
            // A `private` member never overrides — except the interface
            // property's own declaration (kt2477).
            if candidate != interfaceProperty,
               candidateSym.visibility == .private
            {
                continue
            }
            return sema.symbols.extensionPropertySetterAccessor(for: candidate)
                ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: candidate)
        }
    }

    return nil
}

/// The interface itself is already registered by the method-registration pass
/// (`kk_object_register_itable_iface`), so this only appends the getter slots.
func appendObjectItablePropertyGetterRegistrations<C: RangeReplaceableCollection>(
    objectValue: KIRExprID,
    nominalSymbol: SymbolID,
    sema: SemaModule,
    cache: KIRNominalDispatchCache,
    arena: KIRArena,
    interner: StringInterner,
    interfaceFilter: SymbolID? = nil,
    instructions: inout C
) where C.Element == KIRInstruction {
    guard let objectLayout = sema.symbols.nominalLayout(for: nominalSymbol) else {
        return
    }

    let intType = sema.types.intType
    let registerCallee = interner.intern("kk_object_register_itable_method")
    let interfaceSupertypes = cache.transitiveInterfaceSupertypes(of: nominalSymbol, sema: sema)

    for interfaceSymbol in interfaceSupertypes {
        if let interfaceFilter, interfaceSymbol != interfaceFilter { continue }
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
            let implGetter: SymbolID?
            if let propertySymbol = getterSlot.propertySymbol {
                let interfaceGetter = sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol)
                    ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySymbol)
                implGetter = kirEnumEntryDispatchHelper(
                    for: interfaceGetter,
                    in: nominalSymbol,
                    sema: sema,
                    interner: interner
                ) ?? kirFindOverridePropertyGetter(
                    for: propertySymbol, in: nominalSymbol, sema: sema
                )
            } else {
                implGetter = kirFindOverridePropertyGetter(
                    named: getterSlot.propertyName,
                    in: nominalSymbol,
                    sema: sema
                )
            }
            guard let implGetter else {
                continue
            }

            synthesizeEnumBaseOrdinalGetterIfNeeded(
                implGetter,
                sema: sema,
                arena: arena,
                interner: interner
            )

            // A concrete String/primitive getter must implement the erased
            // return ABI of an interface property such as Entry<K,V>. Build
            // this adapter without a driver so boxed enum registrations use
            // the same contract as ordinary constructor registrations.
            var registeredGetter = implGetter
            if let interfaceProperty = getterSlot.propertySymbol,
               let interfaceReturn = sema.symbols.propertyType(for: interfaceProperty) {
                let interfaceReceiver = sema.types.make(.classType(ClassType(
                    classSymbol: interfaceSymbol, args: [], nullability: .nonNull
                )))
                let implementationProperty = sema.symbols.propertySymbol(forAccessor: implGetter)
                let implementationFn = arena.function(for: implGetter)
                let implementationReturn = implementationFn?.returnType
                    ?? implementationProperty.flatMap { sema.symbols.propertyType(for: $0) }
                    ?? sema.symbols.functionSignature(for: implGetter)?.returnType
                if let implementationReturn {
                    let implementationReceiver = implementationFn?.params.first?.type
                        ?? sema.symbols.functionSignature(for: implGetter)?.receiverType
                        ?? sema.types.make(.classType(ClassType(
                            classSymbol: nominalSymbol, args: [], nullability: .nonNull
                        )))
                    registeredGetter = itableBridgeSymbolForMethod(
                        interfaceMethod: interfaceProperty, implementation: implGetter,
                        nominalSymbol: nominalSymbol,
                        interfaceSignature: FunctionSignature(
                            receiverType: interfaceReceiver, parameterTypes: [],
                            returnType: interfaceReturn, canThrow: true
                        ),
                        implementationSignature: FunctionSignature(
                            receiverType: implementationReceiver, parameterTypes: [],
                            returnType: implementationReturn, canThrow: true
                        ),
                        arena: arena, sema: sema, interner: interner
                    )
                }
            }

            let methodSlot = Int64(getterSlot.slot)
            let methodSlotExpr = arena.appendExpr(.intLiteral(methodSlot), type: intType)
            instructions.append(.constValue(result: methodSlotExpr, value: .intLiteral(methodSlot)))

            let methodFnExpr = arena.appendExpr(.symbolRef(registeredGetter), type: intType)
            instructions.append(.constValue(result: methodFnExpr, value: .symbolRef(registeredGetter)))

            let registerResult = arena.appendTemporary(type: intType)
            instructions.append(.call(
                callee: registerCallee,
                arguments: [objectValue, ifaceSlotExpr, methodSlotExpr, methodFnExpr],
                result: registerResult,
                canThrow: false
            ))
        }
    }
}

/// Enum classes have a compiler-provided `ordinal` property, not a source
/// accessor with a KIR body. Materialize its getter before its symbol is used
/// in the interface table.
private func synthesizeEnumBaseOrdinalGetterIfNeeded(
    _ getterSymbol: SymbolID,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner
) {
    guard arena.function(for: getterSymbol) == nil,
          let decoded = SyntheticSymbolScheme.decodedPropertyAccessor(getterSymbol),
          decoded.kind == .getter,
          let property = sema.symbols.symbol(decoded.property),
          property.kind == .property,
          property.name == interner.intern("ordinal"),
          let ownerSymbol = sema.symbols.parentSymbol(for: decoded.property),
          sema.symbols.symbol(ownerSymbol)?.kind == .enumClass,
          property.flags.contains(.synthetic),
          let propertyType = sema.symbols.propertyType(for: decoded.property),
          propertyType == sema.types.intType
    else {
        return
    }

    let ownerType = sema.types.make(.classType(ClassType(
        classSymbol: ownerSymbol, args: [], nullability: .nonNull
    )))
    let receiverSymbol = SyntheticSymbolScheme.receiverParameterSymbol(for: decoded.property)
    let receiver = arena.appendExpr(.symbolRef(receiverSymbol), type: ownerType)
    let ordinal = arena.appendTemporary(type: propertyType)
    let ordinalCallee = interner.intern("kk_unbox_int")
    let function = KIRFunction(
        symbol: getterSymbol,
        name: interner.intern("get"),
        params: [KIRParameter(symbol: receiverSymbol, type: ownerType)],
        returnType: propertyType,
        body: [
            .beginBlock,
            .constValue(result: receiver, value: .symbolRef(receiverSymbol)),
            .call(callee: ordinalCallee, arguments: [receiver], result: ordinal, canThrow: false),
            .returnValue(ordinal),
            .endBlock,
        ],
        isSuspend: false,
        isInline: false
    )
    sema.symbols.setFunctionSignature(
        FunctionSignature(receiverType: ownerType, parameterTypes: [], returnType: propertyType),
        for: getterSymbol
    )
    _ = arena.appendDecl(.function(function))
}

/// The setter counterpart of `appendObjectItablePropertyGetterRegistrations` —
/// without it, writing a `var` through an interface-typed receiver has no
/// dispatch target to find at the write site
/// (`tryLowerInterfaceItablePropertySetterWrite` in
/// `CallLowerer+MemberAssignment.swift`), even though every concrete overriding
/// class already has a real setter accessor function registered (BUG-227's
/// `synthesizeStoredPropertySetterAccessor` emits one unconditionally for any
/// `override var`).
func appendObjectItablePropertySetterRegistrations<C: RangeReplaceableCollection>(
    objectValue: KIRExprID,
    nominalSymbol: SymbolID,
    sema: SemaModule,
    cache: KIRNominalDispatchCache,
    arena: KIRArena,
    interner: StringInterner,
    interfaceFilter: SymbolID? = nil,
    instructions: inout C
) where C.Element == KIRInstruction {
    guard let objectLayout = sema.symbols.nominalLayout(for: nominalSymbol) else {
        return
    }

    let intType = sema.types.intType
    let registerCallee = interner.intern("kk_object_register_itable_method")
    let interfaceSupertypes = cache.transitiveInterfaceSupertypes(of: nominalSymbol, sema: sema)

    for interfaceSymbol in interfaceSupertypes {
        if let interfaceFilter, interfaceSymbol != interfaceFilter { continue }
        let setterSlots = cache.interfacePropertySetterSlots(
            for: interfaceSymbol,
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
            let interfaceSetter = sema.symbols.extensionPropertySetterAccessor(for: setterSlot.propertySymbol)
                ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: setterSlot.propertySymbol)
            guard let implSetter = kirEnumEntryDispatchHelper(
                for: interfaceSetter,
                in: nominalSymbol,
                sema: sema,
                interner: interner
            ) ?? kirFindOverridePropertySetter(
                for: setterSlot.propertySymbol, in: nominalSymbol, sema: sema
            ) else {
                continue
            }

            // An implementation such as `String` has a more specific setter
            // ABI than the erased type parameter in `A<T>.set(T)`. Register a
            // bridge with the interface ABI, just as the getter path does for
            // generic return types.
            var registeredSetter = implSetter
            if let interfaceParameter = sema.symbols.propertyType(for: setterSlot.propertySymbol) {
                let interfaceReceiver = sema.types.make(.classType(ClassType(
                    classSymbol: interfaceSymbol, args: [], nullability: .nonNull
                )))
                let implementationProperty = sema.symbols.propertySymbol(forAccessor: implSetter)
                let implementationFn = arena.function(for: implSetter)
                let implementationOwner = implementationProperty.flatMap {
                    sema.symbols.parentSymbol(for: $0)
                }
                let implementationReceiver = implementationFn?.params.first?.type
                    ?? sema.symbols.functionSignature(for: implSetter)?.receiverType
                    ?? implementationOwner.flatMap { owner in
                        sema.symbols.symbol(owner).map {
                            sema.types.make(.classType(ClassType(
                                classSymbol: $0.id, args: [], nullability: .nonNull
                            )))
                        }
                    }
                let implementationParameter = implementationFn?.params.last?.type
                    ?? sema.symbols.functionSignature(for: implSetter)?.parameterTypes.last
                    ?? implementationProperty.flatMap { sema.symbols.propertyType(for: $0) }
                if let implementationReceiver, let implementationParameter {
                    let implementationSignature = sema.symbols.functionSignature(for: implSetter)
                    registeredSetter = itableBridgeSymbolForMethod(
                        interfaceMethod: setterSlot.propertySymbol,
                        implementation: implSetter,
                        nominalSymbol: nominalSymbol,
                        interfaceSignature: FunctionSignature(
                            receiverType: interfaceReceiver,
                            parameterTypes: [interfaceParameter],
                            returnType: sema.types.unitType,
                            canThrow: true
                        ),
                        implementationSignature: FunctionSignature(
                            receiverType: implementationReceiver,
                            parameterTypes: [implementationParameter],
                            returnType: implementationFn?.returnType ?? sema.types.unitType,
                            canThrow: implementationSignature?.canThrow ?? true
                        ),
                        arena: arena,
                        sema: sema,
                        interner: interner
                    )
                }
            }

            let methodSlot = Int64(setterSlot.slot)
            let methodSlotExpr = arena.appendExpr(.intLiteral(methodSlot), type: intType)
            instructions.append(.constValue(result: methodSlotExpr, value: .intLiteral(methodSlot)))

            let methodFnExpr = arena.appendExpr(.symbolRef(registeredSetter), type: intType)
            instructions.append(.constValue(result: methodFnExpr, value: .symbolRef(registeredSetter)))

            let registerResult = arena.appendTemporary(type: intType)
            instructions.append(.call(
                callee: registerCallee,
                arguments: [objectValue, ifaceSlotExpr, methodSlotExpr, methodFnExpr],
                result: registerResult,
                canThrow: false
            ))
        }
    }
}
