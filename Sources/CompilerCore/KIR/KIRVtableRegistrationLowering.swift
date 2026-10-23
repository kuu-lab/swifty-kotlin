/// Memoizes the per-nominal dispatch-registration queries KIR lowering runs at
/// every object construction site. Each result below is a pure function of the
/// nominal symbol and `sema`, which is immutable during lowering, so entries
/// computed once are identical for every site constructing the same nominal.
/// Shared between `KIRLoweringContext` (driver passes) and `KIRContext`
/// (driver-less passes such as collection-factory rewriting).
final class KIRNominalDispatchCache {
    private var vtableImplementationsByNominal: [SymbolID: [(slot: Int, dispatchMethod: SymbolID, implementation: SymbolID)]] = [:]
    private var vtableAccessorImplementationsByNominal: [SymbolID: [(slot: Int, dispatchAccessor: SymbolID, implementation: SymbolID)]] = [:]
    private var transitiveInterfaceSupertypesByNominal: [SymbolID: [SymbolID]] = [:]
    /// Nominal → interface method → implementation the nominal must expose:
    /// the `kirFindOverrideMethod` result, or the method itself when no
    /// override exists (both call sites apply that same fallback).
    private var itableImplementationsByNominal: [SymbolID: [SymbolID: SymbolID]] = [:]
    /// Interface → property-getter slot table, computed once per interface
    /// instead of once per property read or object registration site.
    private var interfacePropertyGetterSlotsByInterface: [SymbolID: [KIRInterfacePropertyGetterSlot]] = [:]
    private var interfacePropertyGetterSlotByPropertyByInterface: [SymbolID: [SymbolID: Int]] = [:]
    /// Interface → property-setter slot table, derived from the cached getter
    /// table so eligibility, ordering, and the setter base stay in sync.
    private var interfacePropertySetterSlotsByInterface: [SymbolID: [KIRInterfacePropertySetterSlot]] = [:]
    private var interfacePropertySetterSlotByPropertyByInterface: [SymbolID: [SymbolID: Int]] = [:]

    func vtableImplementations(
        for nominalSymbol: SymbolID,
        sema: SemaModule
    ) -> [(slot: Int, dispatchMethod: SymbolID, implementation: SymbolID)] {
        if let cached = vtableImplementationsByNominal[nominalSymbol] {
            return cached
        }
        let computed = kirVtableImplementations(for: nominalSymbol, sema: sema)
        vtableImplementationsByNominal[nominalSymbol] = computed
        return computed
    }

    func vtablePropertyAccessorImplementations(
        for nominalSymbol: SymbolID,
        sema: SemaModule
    ) -> [(slot: Int, dispatchAccessor: SymbolID, implementation: SymbolID)] {
        if let cached = vtableAccessorImplementationsByNominal[nominalSymbol] {
            return cached
        }
        let computed = kirVtablePropertyAccessorImplementations(for: nominalSymbol, sema: sema)
        vtableAccessorImplementationsByNominal[nominalSymbol] = computed
        return computed
    }

    func transitiveInterfaceSupertypes(
        of nominalSymbol: SymbolID,
        sema: SemaModule
    ) -> [SymbolID] {
        if let cached = transitiveInterfaceSupertypesByNominal[nominalSymbol] {
            return cached
        }
        let computed = kirTransitiveInterfaceSupertypes(of: nominalSymbol, sema: sema)
        transitiveInterfaceSupertypesByNominal[nominalSymbol] = computed
        return computed
    }

    /// Effective itable implementation for `interfaceMethod` on `nominalSymbol`:
    /// the located override, or `interfaceMethod` itself when none is found.
    func itableImplementation(
        for interfaceMethod: SymbolID,
        in nominalSymbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID {
        if let cached = itableImplementationsByNominal[nominalSymbol]?[interfaceMethod] {
            return cached
        }
        let resolved = kirFindOverrideMethod(
            for: interfaceMethod,
            in: nominalSymbol,
            sema: sema,
            interner: interner,
            transitiveInterfaces: transitiveInterfaceSupertypes(of: nominalSymbol, sema: sema)
        ) ?? interfaceMethod
        itableImplementationsByNominal[nominalSymbol, default: [:]][interfaceMethod] = resolved
        return resolved
    }

    func interfacePropertyGetterSlots(
        for interfaceSymbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [KIRInterfacePropertyGetterSlot] {
        if let cached = interfacePropertyGetterSlotsByInterface[interfaceSymbol] {
            return cached
        }
        let computed = kirInterfacePropertyGetterSlots(
            interfaceSymbol: interfaceSymbol,
            sema: sema,
            interner: interner
        )
        interfacePropertyGetterSlotsByInterface[interfaceSymbol] = computed
        return computed
    }

    /// Itable slot of `interfaceProperty`'s getter on `interfaceSymbol`, or nil
    /// when the property does not participate in itable dispatch.
    func interfacePropertyGetterSlot(
        for interfaceProperty: SymbolID,
        in interfaceSymbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Int? {
        if let map = interfacePropertyGetterSlotByPropertyByInterface[interfaceSymbol] {
            return map[interfaceProperty]
        }
        var map: [SymbolID: Int] = [:]
        for slot in interfacePropertyGetterSlots(for: interfaceSymbol, sema: sema, interner: interner) {
            if let propertySymbol = slot.propertySymbol {
                map[propertySymbol] = slot.slot
            }
        }
        interfacePropertyGetterSlotByPropertyByInterface[interfaceSymbol] = map
        return map[interfaceProperty]
    }

    func interfacePropertySetterSlots(
        for interfaceSymbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [KIRInterfacePropertySetterSlot] {
        if let cached = interfacePropertySetterSlotsByInterface[interfaceSymbol] {
            return cached
        }
        let getterSlots = interfacePropertyGetterSlots(
            for: interfaceSymbol,
            sema: sema,
            interner: interner
        )
        let computed = kirInterfacePropertySetterSlots(from: getterSlots, sema: sema)
        interfacePropertySetterSlotsByInterface[interfaceSymbol] = computed
        return computed
    }

    /// Itable slot of `interfaceProperty`'s setter on `interfaceSymbol`, or
    /// nil when the property does not participate in interface dispatch.
    func interfacePropertySetterSlot(
        for interfaceProperty: SymbolID,
        in interfaceSymbol: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Int? {
        if let map = interfacePropertySetterSlotByPropertyByInterface[interfaceSymbol] {
            return map[interfaceProperty]
        }
        var map: [SymbolID: Int] = [:]
        for slot in interfacePropertySetterSlots(for: interfaceSymbol, sema: sema, interner: interner) {
            map[slot.propertySymbol] = slot.slot
        }
        interfacePropertySetterSlotByPropertyByInterface[interfaceSymbol] = map
        return map[interfaceProperty]
    }
}

func kirVtableImplementations(
    for nominalSymbol: SymbolID,
    sema: SemaModule
) -> [(slot: Int, dispatchMethod: SymbolID, implementation: SymbolID)] {
    guard let layout = sema.symbols.nominalLayout(for: nominalSymbol) else {
        return []
    }

    let virtualSlots = Set(layout.vtableSlots.compactMap { methodSymbol, slot -> Int? in
        guard let owner = sema.symbols.parentSymbol(for: methodSymbol),
              let ownerInfo = sema.symbols.symbol(owner),
              ownerInfo.flags.contains(.abstractType)
                  || ownerInfo.flags.contains(.openType)
                  || !sema.symbols.directSubtypes(of: owner).isEmpty,
              let symbol = sema.symbols.symbol(methodSymbol),
              symbol.kind == .function || symbol.kind == .property
        else {
            return nil
        }
        return slot
    })
    guard !virtualSlots.isEmpty else {
        return []
    }

    var candidatesBySlot: [Int: [(distance: Int, method: SymbolID)]] = [:]
    for (methodSymbol, slot) in layout.vtableSlots where virtualSlots.contains(slot) {
        guard let methodInfo = sema.symbols.symbol(methodSymbol),
              methodInfo.kind == .function || methodInfo.kind == .property,
              let owner = sema.symbols.parentSymbol(for: methodSymbol),
              let distance = kirNominalDistance(from: nominalSymbol, to: owner, sema: sema)
        else {
            continue
        }
        candidatesBySlot[slot, default: []].append((distance, methodSymbol))
    }

    return candidatesBySlot
        .compactMap { slot, candidates in
            // The most-derived declaration is the function pointer stored in
            // the vtable. Keep the root-most declaration as the ABI contract:
            // an override such as `ProbeMutableMap.put(String, Int)` may have
            // a more specific native representation than the generic
            // `AbstractMutableMap.put(K, V)` slot it replaces.
            guard let implementation = candidates.min(by: { lhs, rhs in
                lhs.distance == rhs.distance
                    ? lhs.method.rawValue > rhs.method.rawValue
                    : lhs.distance < rhs.distance
            }),
                let dispatchMethod = candidates.max(by: { lhs, rhs in
                    lhs.distance == rhs.distance
                        ? lhs.method.rawValue < rhs.method.rawValue
                        : lhs.distance < rhs.distance
                })
            else {
                return nil
            }
            return (
                slot: slot,
                dispatchMethod: dispatchMethod.method,
                implementation: kirVtableSlotImplementationSymbol(for: implementation.method, sema: sema)
            )
        }
        .sorted { lhs, rhs in
            if lhs.slot != rhs.slot { return lhs.slot < rhs.slot }
            return lhs.implementation.rawValue < rhs.implementation.rawValue
        }
}

/// KSP-928: `layout.vtableSlots` may contain real `.property` symbols (open
/// stored properties emit getters). The function pointer registered for such
/// a slot is the property's getter accessor; function symbols pass through.
private func kirVtableSlotImplementationSymbol(for symbol: SymbolID, sema: SemaModule) -> SymbolID {
    guard sema.symbols.symbol(symbol)?.kind == .property else {
        return symbol
    }
    return sema.symbols.extensionPropertyGetterAccessor(for: symbol)
        ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
}

func appendObjectVtableMethodRegistrations<C: RangeReplaceableCollection>(
    objectValue: KIRExprID,
    nominalSymbol: SymbolID,
    driver: KIRLoweringDriver,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout C
) where C.Element == KIRInstruction {
    let implementations = driver.ctx.nominalDispatchCache.vtableImplementations(
        for: nominalSymbol,
        sema: sema
    )
    if !implementations.isEmpty {
        let intType = sema.types.intType
        let registerCallee = interner.intern("kk_object_register_vtable_method")
        for implementation in implementations {
            let bridgeSymbol = itableBridgeSymbolForMethod(
                interfaceMethod: implementation.dispatchMethod,
                implementation: implementation.implementation,
                nominalSymbol: nominalSymbol,
                driver: driver,
                arena: arena,
                sema: sema,
                interner: interner
            )
            let slotExpr = arena.appendExpr(.intLiteral(Int64(implementation.slot)), type: intType)
            instructions.append(.constValue(result: slotExpr, value: .intLiteral(Int64(implementation.slot))))
            let methodFnExpr = arena.appendExpr(.symbolRef(bridgeSymbol), type: intType)
            instructions.append(.constValue(result: methodFnExpr, value: .symbolRef(bridgeSymbol)))
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

    appendObjectVtablePropertyAccessorRegistrations(
        objectValue: objectValue,
        nominalSymbol: nominalSymbol,
        driver: driver,
        sema: sema,
        cache: driver.ctx.nominalDispatchCache,
        arena: arena,
        interner: interner,
        instructions: &instructions
    )
    appendObjectAnyEqualsOverrideRegistration(
        objectValue: objectValue,
        nominalSymbol: nominalSymbol,
        sema: sema,
        cache: driver.ctx.nominalDispatchCache,
        arena: arena,
        interner: interner,
        instructions: &instructions
    )
    appendObjectAnyHashCodeOverrideRegistration(
        objectValue: objectValue,
        nominalSymbol: nominalSymbol,
        sema: sema,
        cache: driver.ctx.nominalDispatchCache,
        arena: arena,
        interner: interner,
        instructions: &instructions
    )
}

/// Mirror of `appendObjectAnyEqualsOverrideRegistration` for `Any.hashCode`:
/// hashed collections only see an erased handle, so the most-specific user
/// `hashCode` override is kept alongside each object.
private func appendObjectAnyHashCodeOverrideRegistration<C: RangeReplaceableCollection>(
    objectValue: KIRExprID,
    nominalSymbol: SymbolID,
    sema: SemaModule,
    cache: KIRNominalDispatchCache,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout C
) where C.Element == KIRInstruction {
    let anyFQName = [interner.intern("kotlin"), interner.intern("Any")]
    guard let anySymbol = sema.symbols.lookup(fqName: anyFQName),
          let anyHashCode = sema.symbols.lookupAll(
              fqName: anyFQName + [interner.intern("hashCode")]
          ).first(where: { sema.symbols.parentSymbol(for: $0) == anySymbol })
    else {
        return
    }
    let implementation = cache.itableImplementation(
        for: anyHashCode,
        in: nominalSymbol,
        sema: sema,
        interner: interner
    )
    guard implementation != anyHashCode,
          sema.symbols.symbol(implementation)?.flags.contains(.overrideMember) == true,
          let signature = sema.symbols.functionSignature(for: implementation),
          signature.parameterTypes.isEmpty,
          signature.returnType == sema.types.intType
    else {
        return
    }

    let intType = sema.types.intType
    let methodFnExpr = arena.appendExpr(.symbolRef(implementation), type: intType)
    instructions.append(.constValue(result: methodFnExpr, value: .symbolRef(implementation)))
    let registerResult = arena.appendTemporary(type: intType)
    instructions.append(.call(
        symbol: nil,
        callee: interner.intern("kk_object_register_hashcode_override"),
        arguments: [objectValue, methodFnExpr],
        result: registerResult,
        canThrow: false,
        thrownResult: nil
    ))
}

/// KSP-967: Generic equality in source-backed functions is lowered through
/// `kk_structural_eq`, where the concrete receiver type is unavailable. Keep
/// the most-specific real `Any.equals` override alongside each object so that
/// erased equality can still honor user-defined semantics.
private func appendObjectAnyEqualsOverrideRegistration<C: RangeReplaceableCollection>(
    objectValue: KIRExprID,
    nominalSymbol: SymbolID,
    sema: SemaModule,
    cache: KIRNominalDispatchCache,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout C
) where C.Element == KIRInstruction {
    let anyFQName = [interner.intern("kotlin"), interner.intern("Any")]
    guard let anySymbol = sema.symbols.lookup(fqName: anyFQName),
          let anyEquals = sema.symbols.lookupAll(
              fqName: anyFQName + [interner.intern("equals")]
          ).first(where: { sema.symbols.parentSymbol(for: $0) == anySymbol })
    else {
        return
    }
    let implementation = cache.itableImplementation(
        for: anyEquals,
        in: nominalSymbol,
        sema: sema,
        interner: interner
    )
    guard implementation != anyEquals,
          sema.symbols.symbol(implementation)?.flags.contains(.overrideMember) == true,
          let signature = sema.symbols.functionSignature(for: implementation),
          signature.parameterTypes.count == 1,
          signature.returnType == sema.types.booleanType
    else {
        return
    }

    let intType = sema.types.intType
    let methodFnExpr = arena.appendExpr(.symbolRef(implementation), type: intType)
    instructions.append(.constValue(result: methodFnExpr, value: .symbolRef(implementation)))
    let registerResult = arena.appendTemporary(type: intType)
    instructions.append(.call(
        symbol: nil,
        callee: interner.intern("kk_object_register_equals_override"),
        arguments: [objectValue, methodFnExpr],
        result: registerResult,
        canThrow: false,
        thrownResult: nil
    ))
}

/// Runtime Any dispatch only has an `Int` receiver and an `Int` string-handle
/// result, while Kotlin class methods use the flat String aggregate ABI.
func anyToStringBridgeSymbolForImplementation(
    _ implementation: SymbolID,
    driver: KIRLoweringDriver? = nil,
    arena: KIRArena,
    sema: SemaModule,
    interner: StringInterner
) -> SymbolID? {
    guard implementation.rawValue >= 0,
          let implementationSig = sema.symbols.functionSignature(for: implementation),
          let signatureReceiverType = implementationSig.receiverType,
          implementationSig.parameterTypes.isEmpty,
          case .stringStruct = sema.types.kind(of: implementationSig.returnType)
    else {
        return nil
    }
    let implementationFn = arena.function(for: implementation)
    let implementationReturnType = implementationFn?.returnType ?? implementationSig.returnType
    let receiverType = implementationFn?.params.first?.type ?? signatureReceiverType

    if let cached = driver?.ctx.anyToStringBridgeSymbolsByImplementation[implementation] {
        return cached
    }

    let bridgeFQName = [interner.intern("$anyToStringBridge"), interner.intern(String(implementation.rawValue))]
    if driver == nil, let cached = sema.symbols.lookup(fqName: bridgeFQName),
       arena.function(for: cached) != nil {
        return cached
    }
    let bridgeSymbol = driver?.ctx.allocateSyntheticGeneratedSymbol() ?? sema.symbols.define(
        kind: .function, name: bridgeFQName[1], fqName: bridgeFQName,
        declSite: nil, visibility: .private, flags: [.synthetic]
    )
    driver?.ctx.anyToStringBridgeSymbolsByImplementation[implementation] = bridgeSymbol
    let bridgeName = interner.intern(
        "kk_any_to_string_bridge_\(implementation.rawValue)_\(bridgeSymbol.rawValue)"
    )

    let receiverParam = KIRParameter(
        symbol: driver?.ctx.allocateSyntheticGeneratedSymbol() ?? sema.symbols.define(
            kind: .valueParameter, name: interner.intern("receiver"),
            fqName: bridgeFQName + [interner.intern("receiver")],
            declSite: nil, visibility: .private, flags: [.synthetic]
        ),
        type: receiverType
    )
    let receiverExpr = arena.appendExpr(
        .symbolRef(receiverParam.symbol),
        type: receiverParam.type
    )
    let rawReceiverKind = sema.types.kind(of: receiverType)
    let resolvedReceiverKind = resolveValueClassKind(
        rawReceiverKind,
        types: sema.types,
        symbols: sema.symbols
    )
    var body: [KIRInstruction] = [
        .beginBlock,
        .constValue(result: receiverExpr, value: .symbolRef(receiverParam.symbol)),
    ]
    // A value-class Any bridge receives the boxed underlying representation,
    // while the source implementation expects the unboxed value-class ABI.
    // Unbox the bridge receiver before calling the implementation; otherwise
    // `toString()` implementations that inspect their receiver recurse back
    // through the same Any override.
    let receiverForCall: KIRExprID
    if case let .classType(receiverClass) = rawReceiverKind,
       sema.symbols.symbol(receiverClass.classSymbol)?.kind == .enumClass {
        // Enum overrides consume ordinals; erased dispatch supplies a tagged box.
        let ordinal = arena.appendTemporary(type: receiverType)
        body.append(.call(
            symbol: nil,
            callee: ABILoweringPass.primitiveUnboxingCallee(for: .int, interner: interner),
            arguments: [receiverExpr], result: ordinal, canThrow: false, thrownResult: nil
        ))
        receiverForCall = ordinal
    } else if rawReceiverKind != resolvedReceiverKind,
       let unboxCallee = BoxingCalleeTable(interner: interner).unboxCallee(
           for: resolvedReceiverKind,
           requireNonNull: true
       )
    {
        let unboxedReceiver = arena.appendTemporary(
            type: sema.types.make(resolvedReceiverKind)
        )
        body.append(.call(
            symbol: nil,
            callee: unboxCallee,
            arguments: [receiverExpr],
            result: unboxedReceiver,
            canThrow: false,
            thrownResult: nil
        ))
        receiverForCall = unboxedReceiver
    } else {
        receiverForCall = receiverExpr
    }
    let callResult = arena.appendTemporary(type: implementationReturnType)
    let thrownResult: KIRExprID? = implementationSig.canThrow
        ? arena.appendTemporary(type: sema.types.nullableAnyType)
        : nil
    body.append(.call(
        symbol: implementation,
        callee: interner.intern("__any_to_string_impl_\(implementation.rawValue)"),
        arguments: [receiverForCall],
        result: callResult,
        canThrow: implementationSig.canThrow,
        thrownResult: thrownResult
    ))

    if let thrownResult {
        let continueLabel = driver?.ctx.makeLoopLabel() ?? 0
        let rethrowLabel = driver?.ctx.makeLoopLabel() ?? 1
        body.append(.jumpIfNotNull(value: thrownResult, target: rethrowLabel))
        body.append(.jump(continueLabel))
        body.append(.label(rethrowLabel))
        body.append(.rethrow(value: thrownResult))
        body.append(.label(continueLabel))
    }

    body.append(.returnValue(callResult))
    body.append(.endBlock)

    let bridgeDecl = arena.appendDecl(.function(KIRFunction(
        symbol: bridgeSymbol,
        name: bridgeName,
        params: [receiverParam],
        returnType: sema.types.intType,
        body: body,
        isSuspend: false,
        isInline: false
    )))
    driver?.ctx.appendGeneratedCallableDecl(bridgeDecl)
    if driver == nil {
        sema.symbols.setFunctionSignature(FunctionSignature(
            receiverType: receiverType, parameterTypes: [], returnType: sema.types.intType,
            isSuspend: false, canThrow: implementationSig.canThrow
        ), for: bridgeSymbol)
    }
    return bridgeSymbol
}

/// Registers the generated raw-string bridge used when a class or object
/// instance is stringified after its static type has been erased to `Any`.
func appendObjectAnyToStringRegistration<C: RangeReplaceableCollection>(
    objectValue: KIRExprID,
    nominalSymbol: SymbolID,
    driver: KIRLoweringDriver,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout C
) where C.Element == KIRInstruction {
    guard let nominalKind = sema.symbols.symbol(nominalSymbol)?.kind,
          nominalKind == .class || nominalKind == .object || nominalKind == .annotationClass,
          let implementation = resolveClassToStringSymbol(
              for: nominalSymbol,
              sema: sema,
              interner: interner
          ),
          let bridge = anyToStringBridgeSymbolForImplementation(
              implementation,
              driver: driver,
              arena: arena,
              sema: sema,
              interner: interner
          )
    else {
        return
    }

    let intType = sema.types.intType
    let bridgeExpr = arena.appendExpr(.symbolRef(bridge), type: intType)
    instructions.append(.constValue(result: bridgeExpr, value: .symbolRef(bridge)))
    let registerResult = arena.appendTemporary(type: intType)
    instructions.append(.call(
        symbol: nil,
        callee: interner.intern("kk_object_register_any_to_string"),
        arguments: [objectValue, bridgeExpr],
        result: registerResult,
        canThrow: false,
        thrownResult: nil
    ))
}

/// Registers the raw-string bridge for a value class independently of an
/// object allocation. ValueClassUnboxingPass removes the heap allocation and
/// therefore cannot retain the ordinary per-object registration above, while
/// an Any-erased value class still needs its nominal toString implementation.
func appendValueClassAnyToStringRegistration<C: RangeReplaceableCollection>(
    nominalSymbol: SymbolID,
    classID: Int64,
    driver: KIRLoweringDriver,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout C
) where C.Element == KIRInstruction {
    guard classID != 0,
          sema.symbols.symbol(nominalSymbol)?.flags.contains(.valueType) == true,
          let implementation = resolveClassToStringSymbol(
              for: nominalSymbol,
              sema: sema,
              interner: interner
          ),
          let bridge = anyToStringBridgeSymbolForImplementation(
              implementation,
              driver: driver,
              arena: arena,
              sema: sema,
              interner: interner
          )
    else {
        return
    }

    let intType = sema.types.intType
    let classIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
    instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))
    let bridgeExpr = arena.appendExpr(.symbolRef(bridge), type: intType)
    instructions.append(.constValue(result: bridgeExpr, value: .symbolRef(bridge)))
    let registerResult = arena.appendTemporary(type: intType)
    instructions.append(.call(
        symbol: nil,
        callee: interner.intern("kk_value_class_register_any_to_string"),
        arguments: [classIDExpr, bridgeExpr],
        result: registerResult,
        canThrow: false,
        thrownResult: nil
    ))
}

/// BUG-227: analog of `kirVtableImplementations` for property accessors.
/// Property-accessor keys in `layout.vtableSlots` are synthetic IDs (an
/// arithmetic transform of the underlying property's own symbol — see
/// `SyntheticSymbolScheme` — not real, symbol-table-registered entries), so
/// they cannot reuse `kirVtableImplementations`'s
/// `sema.symbols.symbol(methodSymbol)?.kind == .function` filter or its
/// `parentSymbol`-based ownership/distance lookup directly: both would treat
/// every property-accessor slot as "no owner found" and silently drop it.
/// This walks the same slot set, decoding each accessor entry back to its
/// original property to answer the identical question: for this concrete
/// class, which override in the chain is the closest (most specific)
/// implementation of the accessor occupying this slot?
func kirVtablePropertyAccessorImplementations(
    for nominalSymbol: SymbolID,
    sema: SemaModule
) -> [(slot: Int, dispatchAccessor: SymbolID, implementation: SymbolID)] {
    guard let layout = sema.symbols.nominalLayout(for: nominalSymbol) else {
        return []
    }

    let virtualSlots = Set(layout.vtableSlots.compactMap { accessorSymbol, slot -> Int? in
        guard let decoded = SyntheticSymbolScheme.decodedPropertyAccessor(accessorSymbol),
              let owner = sema.symbols.parentSymbol(for: decoded.property),
              let ownerInfo = sema.symbols.symbol(owner),
              ownerInfo.flags.contains(.abstractType)
                  || ownerInfo.flags.contains(.openType)
                  || !sema.symbols.directSubtypes(of: owner).isEmpty
        else {
            return nil
        }
        return slot
    })
    guard !virtualSlots.isEmpty else {
        return []
    }

    var candidatesBySlot: [Int: [(distance: Int, accessor: SymbolID)]] = [:]
    for (accessorSymbol, slot) in layout.vtableSlots where virtualSlots.contains(slot) {
        guard let decoded = SyntheticSymbolScheme.decodedPropertyAccessor(accessorSymbol),
              let owner = sema.symbols.parentSymbol(for: decoded.property),
              let distance = kirNominalDistance(from: nominalSymbol, to: owner, sema: sema)
        else {
            continue
        }
        candidatesBySlot[slot, default: []].append((distance, accessorSymbol))
    }

    return candidatesBySlot
        .compactMap { slot, candidates in
            // Keep the root-most declaration as the slot ABI contract and the
            // closest declaration as the function pointer to dispatch to.
            guard let dispatchAccessor = candidates.max(by: { lhs, rhs in
                lhs.distance == rhs.distance
                    ? lhs.accessor.rawValue < rhs.accessor.rawValue
                    : lhs.distance < rhs.distance
            }),
                let implementationAccessor = candidates.min(by: { lhs, rhs in
                    lhs.distance == rhs.distance
                        ? lhs.accessor.rawValue > rhs.accessor.rawValue
                        : lhs.distance < rhs.distance
                })
            else {
                return nil
            }
            let implementation: SymbolID = switch SyntheticSymbolScheme.decodedPropertyAccessor(implementationAccessor.accessor) {
            case let .some(decoded):
                switch decoded.kind {
                case .getter:
                    sema.symbols.extensionPropertyGetterAccessor(for: decoded.property)
                        ?? implementationAccessor.accessor
                case .setter:
                    sema.symbols.extensionPropertySetterAccessor(for: decoded.property)
                        ?? implementationAccessor.accessor
                }
            case .none:
                implementationAccessor.accessor
            }
            return (
                slot: slot,
                dispatchAccessor: dispatchAccessor.accessor,
                implementation: implementation
            )
        }
        .sorted { lhs, rhs in
            if lhs.slot != rhs.slot { return lhs.slot < rhs.slot }
            return lhs.implementation.rawValue < rhs.implementation.rawValue
        }
}

func appendObjectVtablePropertyAccessorRegistrations<C: RangeReplaceableCollection>(
    objectValue: KIRExprID,
    nominalSymbol: SymbolID,
    driver: KIRLoweringDriver,
    sema: SemaModule,
    cache: KIRNominalDispatchCache,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout C
) where C.Element == KIRInstruction {
    let implementations = cache.vtablePropertyAccessorImplementations(
        for: nominalSymbol,
        sema: sema
    )
    guard !implementations.isEmpty else {
        return
    }

    let intType = sema.types.intType
    let registerCallee = interner.intern("kk_object_register_vtable_method")
    let throwableMessageSlot = sema.symbols.throwableMessageGetterSlot(for: nominalSymbol, interner: interner)
    for implementation in implementations {
        // Runtime-allocated exceptions answer the Throwable `message` slot with
        // a raw-pointer bridge, so the slot's dispatch ABI is the raw String?
        // handle. Kotlin getters return the flat aggregate; adapt them through
        // a raw-return bridge.
        var accessorFn = implementation.implementation
        if implementation.slot == throwableMessageSlot {
            accessorFn = throwableMessageGetterBridgeSymbol(
                getter: implementation.implementation,
                nominalSymbol: nominalSymbol,
                driver: driver,
                arena: arena,
                sema: sema,
                interner: interner
            )
        } else if let decoded = SyntheticSymbolScheme.decodedPropertyAccessor(
            implementation.dispatchAccessor
        ),
            decoded.kind == .getter,
            let propertyType = sema.symbols.propertyType(for: decoded.property),
            let propertyOwner = sema.symbols.parentSymbol(for: decoded.property)
        {
            let interfaceReceiver = sema.types.make(.classType(ClassType(
                classSymbol: propertyOwner, args: [], nullability: .nonNull
            )))
            let interfaceSignature = FunctionSignature(
                receiverType: interfaceReceiver,
                parameterTypes: [],
                returnType: propertyType,
                canThrow: true
            )

            let implementationFunction = arena.function(for: implementation.implementation)
            let implementationMetadata = sema.symbols.functionSignature(for: implementation.implementation)
            let implementationProperty = sema.symbols.propertySymbol(forAccessor: implementation.implementation)
            let implementationPropertyType = implementationProperty.flatMap {
                sema.symbols.propertyType(for: $0)
            }
            let implementationReceiver = implementationFunction?.params.first?.type
                ?? implementationMetadata?.receiverType
                ?? sema.types.make(.classType(ClassType(
                    classSymbol: nominalSymbol, args: [], nullability: .nonNull
                )))
            let implementationSignature = FunctionSignature(
                receiverType: implementationReceiver,
                parameterTypes: [],
                returnType: implementationFunction?.returnType
                    ?? implementationMetadata?.returnType
                    ?? implementationPropertyType
                    ?? propertyType,
                canThrow: implementationMetadata?.canThrow ?? true
            )
            accessorFn = itableBridgeSymbolForMethod(
                interfaceMethod: implementation.dispatchAccessor,
                implementation: implementation.implementation,
                nominalSymbol: nominalSymbol,
                driver: driver,
                interfaceSignature: interfaceSignature,
                implementationSignature: implementationSignature,
                arena: arena,
                sema: sema,
                interner: interner
            )
        }
        let slotExpr = arena.appendExpr(.intLiteral(Int64(implementation.slot)), type: intType)
        instructions.append(.constValue(result: slotExpr, value: .intLiteral(Int64(implementation.slot))))
        let accessorFnExpr = arena.appendExpr(.symbolRef(accessorFn), type: intType)
        instructions.append(.constValue(result: accessorFnExpr, value: .symbolRef(accessorFn)))
        let registerResult = arena.appendTemporary(type: intType)
        instructions.append(.call(
            symbol: nil,
            callee: registerCallee,
            arguments: [objectValue, slotExpr, accessorFnExpr],
            result: registerResult,
            canThrow: false,
            thrownResult: nil
        ))
    }
}

/// Raw-returning bridge for a `Throwable.message` getter: calls the Kotlin
/// getter (flat `String?` aggregate) and returns the raw handle, relying on the
/// backend's String bridging at `returnValue`.
private func throwableMessageGetterBridgeSymbol(
    getter: SymbolID,
    nominalSymbol: SymbolID,
    driver: KIRLoweringDriver,
    arena: KIRArena,
    sema: SemaModule,
    interner: StringInterner
) -> SymbolID {
    if let cached = driver.ctx.throwableMessageBridgeSymbolsByGetter[getter] {
        return cached
    }
    let bridgeSymbol = driver.ctx.allocateSyntheticGeneratedSymbol()
    driver.ctx.throwableMessageBridgeSymbolsByGetter[getter] = bridgeSymbol

    let receiverType = sema.types.make(.classType(ClassType(
        classSymbol: nominalSymbol, args: [], nullability: .nonNull
    )))
    let receiverParam = KIRParameter(
        symbol: driver.ctx.allocateSyntheticGeneratedSymbol(),
        type: receiverType
    )
    let receiverExpr = arena.appendExpr(.symbolRef(receiverParam.symbol), type: receiverType)
    let messageType = sema.types.make(.stringStruct(.nullable))
    let callResult = arena.appendTemporary(type: messageType)
    let body: [KIRInstruction] = [
        .beginBlock,
        .constValue(result: receiverExpr, value: .symbolRef(receiverParam.symbol)),
        .call(
            symbol: getter,
            callee: interner.intern("get"),
            arguments: [receiverExpr],
            result: callResult,
            canThrow: false,
            thrownResult: nil
        ),
        .returnValue(callResult),
        .endBlock,
    ]
    let bridgeDecl = arena.appendDecl(.function(KIRFunction(
        symbol: bridgeSymbol,
        name: interner.intern("kk_throwable_message_bridge_\(getter.rawValue)_\(bridgeSymbol.rawValue)"),
        params: [receiverParam],
        returnType: sema.types.intType,
        body: body,
        isSuspend: false,
        isInline: false
    )))
    driver.ctx.appendGeneratedCallableDecl(bridgeDecl)
    return bridgeSymbol
}

public extension SymbolTable {
    /// Vtable slot of the `kotlin.Throwable.message` getter in `nominalSymbol`'s
    /// layout, or nil when the nominal does not inherit from Throwable. Shared
    /// by KIR vtable registration and the backend's virtual-call ABI choice,
    /// which must agree that this slot uses the raw String? handle ABI.
    func throwableMessageGetterSlot(for nominalSymbol: SymbolID, interner: StringInterner) -> Int? {
        guard let layout = nominalLayout(for: nominalSymbol) else {
            return nil
        }
        let throwableFQName = [interner.intern("kotlin"), interner.intern("Throwable")]
        let messageName = interner.intern("message")
        for (accessorSymbol, slot) in layout.vtableSlots {
            guard let decoded = SyntheticSymbolScheme.decodedPropertyAccessor(accessorSymbol),
                  decoded.kind == .getter,
                  symbol(decoded.property)?.name == messageName,
                  let owner = parentSymbol(for: decoded.property),
                  symbol(owner)?.fqName == throwableFQName
            else {
                continue
            }
            return slot
        }
        return nil
    }
}

/// Returns a bridge symbol for `implementation` when its ABI does not match
/// the vtable or itable dispatch signature. The bridge adapts erased generic
/// values, String aggregate/raw-pointer representation, and member-extension
/// receiver lists, then forwards to the implementation after checking narrowed
/// erased reference arguments.
func itableBridgeSymbolForMethod(
    interfaceMethod: SymbolID,
    implementation: SymbolID,
    nominalSymbol: SymbolID,
    driver: KIRLoweringDriver? = nil,
    interfaceSignature: FunctionSignature? = nil,
    implementationSignature: FunctionSignature? = nil,
    arena: KIRArena,
    sema: SemaModule,
    interner: StringInterner
) -> SymbolID {
    let barrierDefault = kirSpecialBuiltinBarrierDefault(
        for: interfaceMethod,
        sema: sema,
        interner: interner
    )
    guard implementation != interfaceMethod || barrierDefault != nil,
          implementation.rawValue >= 0 || SyntheticSymbolScheme.decodedPropertyAccessor(implementation) != nil,
          let interfaceSig = interfaceSignature ?? sema.symbols.functionSignature(for: interfaceMethod),
          let implSig = implementationSignature ?? sema.symbols.functionSignature(for: implementation)
    else {
        return implementation
    }
    let implementationFn = arena.function(for: implementation)
    // Nested singleton initializers register dispatch before their member bodies
    // are lowered. Ordinary source object methods already have their final ABI
    // in Sema, so their erasure bridges can reference the forthcoming definition.
    // Varargs, reified tokens, and member extensions alter the KIR parameter list.
    let hasForwardObjectSignature: Bool = {
        guard sema.symbols.symbol(nominalSymbol)?.kind == .object,
              sema.symbols.parentSymbol(for: implementation) == nominalSymbol,
              let implementationInfo = sema.symbols.symbol(implementation),
              implementationInfo.kind == .function,
              !implementationInfo.flags.contains(.abstractType),
              !implementationInfo.flags.contains(.synthetic),
              !implementationInfo.flags.contains(.memberExtension),
              sema.symbols.externalLinkName(for: implementation) == nil,
              !implSig.valueParameterIsVararg.contains(true),
              implSig.reifiedTypeParameterIndices.isEmpty,
              let receiverType = implSig.receiverType,
              case let .classType(receiverClass) = sema.types.kind(of: receiverType),
              receiverClass.classSymbol == nominalSymbol
        else { return false }
        return true
    }()
    guard implementationFn != nil || implementationSignature != nil || hasForwardObjectSignature else {
        return implementation
    }
    let implementationReturnType = implementationFn?.returnType ?? implSig.returnType

    func isStringAggregate(_ type: TypeID?) -> Bool {
        guard let type else { return false }
        if case .stringStruct = sema.types.kind(of: type) {
            return true
        }
        return false
    }

    let memberExtensionOwner = sema.symbols.symbol(interfaceMethod)?.kind == .function
        ? sema.symbols.memberExtensionOwnerSymbol(for: interfaceMethod)
        : nil
    func dispatchReceiverType(owner: SymbolID, signature: FunctionSignature) -> TypeID {
        let ownerTypeArgs = signature.typeParameterSymbols
            .prefix(signature.classTypeParameterCount)
            .map { TypeArg.invariant(sema.types.make(.typeParam(TypeParamType(
                symbol: $0, nullability: .nonNull
            )))) }
        return sema.types.make(.classType(ClassType(
            classSymbol: owner, args: ownerTypeArgs, nullability: .nonNull
        )))
    }
    let interfaceDispatchReceiver = memberExtensionOwner.map {
        dispatchReceiverType(owner: $0, signature: interfaceSig)
    }
    let interfaceReceiver = interfaceSig.receiverType
    let interfaceValueParamTypes = interfaceSig.parameterTypes.enumerated().map { index, elementType in
        guard interfaceSig.valueParameterIsVararg.indices.contains(index),
              interfaceSig.valueParameterIsVararg[index]
        else {
            return elementType
        }
        return primitiveVarargArrayType(elementType: elementType, sema: sema, interner: interner)
            ?? referenceVarargArrayType(elementType: elementType, sema: sema, interner: interner)
            ?? elementType
    }
    let interfaceParamTypes = [interfaceDispatchReceiver, interfaceReceiver].compactMap { $0 }
        + interfaceValueParamTypes
    let implementationDispatchOwner = sema.symbols.memberExtensionOwnerSymbol(for: implementation)
    let implementationDispatchReceiver = implementationDispatchOwner.map { owner in
        implementationFn?.params.first?.type
            ?? dispatchReceiverType(owner: owner, signature: implSig)
    }
    let implementationValueParamTypes = implSig.parameterTypes.enumerated().map { index, elementType in
        guard implSig.valueParameterIsVararg.indices.contains(index),
              implSig.valueParameterIsVararg[index]
        else {
            return elementType
        }
        return primitiveVarargArrayType(elementType: elementType, sema: sema, interner: interner)
            ?? referenceVarargArrayType(elementType: elementType, sema: sema, interner: interner)
            ?? elementType
    }
    let implementationParamTypes = implementationFn?.params.map(\.type)
        ?? ([implementationDispatchReceiver, implSig.receiverType].compactMap { $0 }
            + implementationValueParamTypes)

    guard implementationParamTypes.count == interfaceParamTypes.count else {
        return implementation
    }

    let receiverCount = interfaceDispatchReceiver == nil
        ? (interfaceReceiver == nil ? 0 : 1)
        : 2
    let containsBridgeReturnsFalseOnTypeMismatch = kirCollectionContainsBridgeMethod(
        interfaceMethod,
        sema: sema,
        interner: interner
    )
    // KUU-2954: special-builtins collection members carry a JVM type-safe
    // barrier — the erased `Object` slot answers the member's default instead
    // of reaching an implementation whose parameter cannot hold the value.
    // The barrier replaces the checkcast on those parameters: a rejected
    // argument returns the default rather than trapping.
    let barrierCheckTypes: [TypeID?] = implementationParamTypes.enumerated().map { index, implType -> TypeID? in
        guard barrierDefault != nil, index >= receiverCount else { return nil }
        return kirErasedDispatchBarrierCheckType(
            implementationParamType: implType,
            sema: sema
        )
    }
    let argumentCastTargets = implementationParamTypes.enumerated().map { index, implType -> TypeID? in
        guard index >= receiverCount, barrierCheckTypes[index] == nil else { return nil }
        return kirErasedDispatchArgumentCastTarget(
            implementationType: implType,
            dispatchType: interfaceParamTypes[index],
            sema: sema,
            allowNonTypeParameterDispatchType: containsBridgeReturnsFalseOnTypeMismatch && index == receiverCount
        )
    }

    var needsBridge = argumentCastTargets.contains { $0 != nil }
        || barrierCheckTypes.contains { $0 != nil }
    if isStringAggregate(implementationReturnType) != isStringAggregate(interfaceSig.returnType) {
        needsBridge = true
    }
    func isErasedValueSlot(_ type: TypeID) -> Bool {
        switch sema.types.kind(of: type) {
        case .typeParam, .any:
            return true
        default:
            return false
        }
    }
    func hasBoxableValueRepresentation(_ type: TypeID) -> Bool {
        let resolvedKind = resolveValueClassKind(
            sema.types.kind(of: type),
            types: sema.types,
            symbols: sema.symbols
        )
        return BoxingCalleeTable(interner: interner).boxCallee(for: resolvedKind, requireNonNull: true) != nil
    }
    let needsErasedValueReturnBoxing = isErasedValueSlot(interfaceSig.returnType)
        && hasBoxableValueRepresentation(implementationReturnType)
    let needsErasedValueReturnUnboxing: Bool = {
        guard isErasedValueSlot(implementationReturnType),
              case .primitive(_, .nonNull) = sema.types.kind(of: interfaceSig.returnType)
        else {
            return false
        }
        return true
    }()
    if needsErasedValueReturnBoxing || needsErasedValueReturnUnboxing {
        needsBridge = true
    }
    // Erased `T` and `Any` slots carry primitive arguments as boxes, while a
    // specialized implementation expects the raw primitive word.
    func needsErasedValueParamUnboxing(implType: TypeID, ifaceType: TypeID) -> Bool {
        guard isErasedValueSlot(ifaceType),
              case .primitive(_, .nonNull) = sema.types.kind(of: implType)
        else {
            return false
        }
        return true
    }
    func needsErasedValueParamBoxing(implType: TypeID, ifaceType: TypeID) -> Bool {
        guard isErasedValueSlot(implType),
              case .primitive(_, .nonNull) = sema.types.kind(of: ifaceType)
        else {
            return false
        }
        return true
    }
    func needsErasedValueParamAdaptation(implType: TypeID, ifaceType: TypeID) -> Bool {
        needsErasedValueParamUnboxing(implType: implType, ifaceType: ifaceType)
            || needsErasedValueParamBoxing(implType: implType, ifaceType: ifaceType)
    }
    // Enum values are raw ordinals everywhere except behind an interface or
    // `Any` slot, where they are `kk_enum_box_ordinal` boxes. An enum member
    // (or `$enumEntryDispatch$` helper) expects the raw ordinal receiver --
    // `F.f` re-boxes its receiver for an `Any`-typed callee, so a box pointer
    // passed straight through would be boxed a second time. Itable dispatch
    // always hands over the box, so the bridge unboxes it (`kk_unbox_int`
    // passes a raw ordinal through unchanged) before forwarding.
    let needsEnumReceiverUnboxing: Bool = {
        guard let interfaceReceiver,
              let implReceiver = implementationParamTypes.first,
              implReceiver != interfaceReceiver,
              case let .classType(receiverClass) = sema.types.kind(of: implReceiver),
              sema.symbols.symbol(receiverClass.classSymbol)?.kind == .enumClass
        else {
            return false
        }
        return true
    }()
    if needsEnumReceiverUnboxing {
        needsBridge = true
    }
    if !needsBridge {
        for (implType, ifaceType) in zip(implementationParamTypes, interfaceParamTypes) {
            if isStringAggregate(implType) != isStringAggregate(ifaceType)
                || needsErasedValueParamAdaptation(implType: implType, ifaceType: ifaceType)
            {
                needsBridge = true
                break
            }
        }
    }
    guard needsBridge else {
        return implementation
    }

    let cacheKey = "\(interfaceMethod.rawValue)|\(implementation.rawValue)"
    if let cached = driver?.ctx.itableBridgeSymbolsByKey[cacheKey] {
        return cached
    }
    let bridgeFQName = [interner.intern("$itableBridge"), interner.intern(cacheKey)]
    if driver == nil, let cached = sema.symbols.lookup(fqName: bridgeFQName),
       arena.function(for: cached) != nil {
        return cached
    }
    let bridgeSymbol = driver?.ctx.allocateSyntheticGeneratedSymbol() ?? sema.symbols.define(
        kind: .function, name: bridgeFQName[1], fqName: bridgeFQName,
        declSite: nil, visibility: .private, flags: [.synthetic]
    )
    driver?.ctx.itableBridgeSymbolsByKey[cacheKey] = bridgeSymbol

    let bridgeName = interner.intern("kk_itable_bridge_\(interfaceMethod.rawValue)_\(implementation.rawValue)_\(bridgeSymbol.rawValue)")

    var bridgeParams: [KIRParameter] = []
    func parameterSymbol(_ index: Int) -> SymbolID {
        if let driver { return driver.ctx.allocateSyntheticGeneratedSymbol() }
        let name = interner.intern("p\(index)")
        return sema.symbols.define(
            kind: .valueParameter, name: name, fqName: bridgeFQName + [name],
            declSite: nil, visibility: .private, flags: [.synthetic]
        )
    }
    for paramType in interfaceParamTypes {
        let paramSymbol = parameterSymbol(bridgeParams.count)
        bridgeParams.append(KIRParameter(symbol: paramSymbol, type: paramType))
    }

    var body: [KIRInstruction] = [.beginBlock]
    var bridgeParamExprs: [KIRExprID] = []
    for param in bridgeParams {
        let expr = arena.appendExpr(.symbolRef(param.symbol), type: param.type)
        body.append(.constValue(result: expr, value: .symbolRef(param.symbol)))
        bridgeParamExprs.append(expr)
    }
    let unboxingTable = BoxingCalleeTable(interner: interner)
    var forwardedArgExprs = bridgeParamExprs
    var nextLocalLabel: Int32 = 0
    func makeBridgeLabel() -> Int32 {
        if let driver { return driver.ctx.makeLoopLabel() }
        defer { nextLocalLabel += 1 }
        return nextLocalLabel
    }
    let barrierFailLabel: Int32? = barrierCheckTypes.contains(where: { $0 != nil })
        ? makeBridgeLabel()
        : nil
    if let barrierFailLabel {
        for (index, checkType) in barrierCheckTypes.enumerated() {
            guard let checkType else { continue }
            let token = RuntimeTypeCheckToken.encode(type: checkType, sema: sema, interner: interner)
            let tokenExpr = arena.appendExpr(.intLiteral(token), type: sema.types.intType)
            body.append(.constValue(result: tokenExpr, value: .intLiteral(token)))
            let isResult = arena.appendTemporary(type: sema.types.booleanType)
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_is"),
                arguments: [bridgeParamExprs[index], tokenExpr],
                result: isResult,
                canThrow: false,
                thrownResult: nil
            ))
            let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
            body.append(.constValue(result: zeroExpr, value: .intLiteral(0)))
            body.append(.jumpIfEqual(lhs: isResult, rhs: zeroExpr, target: barrierFailLabel))
        }
    }
    for (index, target) in argumentCastTargets.enumerated() {
        guard let target else { continue }
        let containsElementMismatch = containsBridgeReturnsFalseOnTypeMismatch && index == receiverCount
        let checkTarget = containsElementMismatch
            && !kirErasedDispatchImplementationAcceptsNull(implementationParamTypes[index], sema: sema)
            ? sema.types.withNullability(.nonNull, for: target)
            : target
        let token = RuntimeTypeCheckToken.encode(type: checkTarget, sema: sema, interner: interner)
        let tokenExpr = arena.appendExpr(.intLiteral(token), type: sema.types.intType)
        body.append(.constValue(result: tokenExpr, value: .intLiteral(token)))
        if containsElementMismatch {
            let boolType = sema.types.make(.primitive(.boolean, .nonNull))
            let typeMatches = arena.appendTemporary(type: boolType)
            body.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_is"),
                arguments: [bridgeParamExprs[index], tokenExpr],
                result: typeMatches,
                canThrow: false,
                thrownResult: nil
            ))
            let falseValue = arena.appendExpr(.boolLiteral(false), type: boolType)
            body.append(.constValue(result: falseValue, value: .boolLiteral(false)))
            body.append(.returnIfEqual(lhs: typeMatches, rhs: falseValue))
            continue
        }
        // Keep the erased representation until the implementation call performs
        // its ABI conversion (notably raw String handles to flat aggregates).
        let checked = arena.appendTemporary(type: interfaceParamTypes[index])
        let thrown = arena.appendTemporary(type: sema.types.nullableAnyType)
        body.append(.call(
            symbol: nil,
            callee: interner.intern("kk_op_cast"),
            arguments: [bridgeParamExprs[index], tokenExpr],
            result: checked,
            canThrow: true,
            thrownResult: thrown
        ))
        let continueLabel = makeBridgeLabel()
        let rethrowLabel = makeBridgeLabel()
        body.append(.jumpIfNotNull(value: thrown, target: rethrowLabel))
        body.append(.jump(continueLabel))
        body.append(.label(rethrowLabel))
        body.append(.rethrow(value: thrown))
        body.append(.label(continueLabel))
        forwardedArgExprs[index] = checked
    }
    if needsEnumReceiverUnboxing, let implReceiver = implementationParamTypes.first {
        let ordinal = arena.appendTemporary(type: implReceiver)
        body.append(.call(
            symbol: nil,
            callee: ABILoweringPass.primitiveUnboxingCallee(for: .int, interner: interner),
            arguments: [bridgeParamExprs[0]],
            result: ordinal,
            canThrow: false,
            thrownResult: nil
        ))
        forwardedArgExprs[0] = ordinal
    }
    for (index, implType) in implementationParamTypes.enumerated() {
        guard needsErasedValueParamUnboxing(implType: implType, ifaceType: interfaceParamTypes[index]),
              let unboxCallee = unboxingTable.unboxCallee(
                  for: implType, types: sema.types, requireNonNull: true, preferStaticPrimitive: true
              ) ?? unboxingTable.unboxCallee(for: implType, types: sema.types, requireNonNull: true)
        else { continue }
        let unboxed = arena.appendTemporary(type: implType)
        body.append(.call(
            symbol: nil,
            callee: unboxCallee,
            arguments: [forwardedArgExprs[index]],
            result: unboxed,
            canThrow: false,
            thrownResult: nil
        ))
        forwardedArgExprs[index] = unboxed
    }
    for (index, implType) in implementationParamTypes.enumerated() {
        guard needsErasedValueParamBoxing(implType: implType, ifaceType: interfaceParamTypes[index]) else {
            continue
        }
        // An inherited generic implementation receives the boxed form even
        // when its concrete interface slot supplies a raw primitive.
        forwardedArgExprs[index] = boxValueForAnySlot(
            forwardedArgExprs[index],
            sourceType: interfaceParamTypes[index],
            types: sema.types,
            symbols: sema.symbols,
            interner: interner,
            arena: arena,
            resultType: implType,
            requireNonNull: true,
            sema: sema,
            into: &body
        )
    }

    let callResult = arena.appendTemporary(type: implementationReturnType)
    let thrownResult: KIRExprID? = implSig.canThrow
        ? arena.appendTemporary(type: sema.types.nullableAnyType)
        : nil

    let implName = interner.intern("__itable_impl_\(implementation.rawValue)")

    body.append(.call(
        symbol: implementation,
        callee: implName,
        arguments: forwardedArgExprs,
        result: callResult,
        canThrow: implSig.canThrow,
        thrownResult: thrownResult
    ))

    if let thrownResult {
        let continueLabel = makeBridgeLabel()
        let rethrowLabel = makeBridgeLabel()
        body.append(.jumpIfNotNull(value: thrownResult, target: rethrowLabel))
        body.append(.jump(continueLabel))
        body.append(.label(rethrowLabel))
        body.append(.rethrow(value: thrownResult))
        body.append(.label(continueLabel))
    }

    let bridgeResult: KIRExprID
    if needsErasedValueReturnBoxing {
        bridgeResult = boxValueForAnySlot(
            callResult,
            sourceType: implementationReturnType,
            types: sema.types,
            symbols: sema.symbols,
            interner: interner,
            arena: arena,
            resultType: interfaceSig.returnType,
            requireNonNull: true,
            sema: sema,
            into: &body
        )
    } else if needsErasedValueReturnUnboxing,
              let unboxCallee = unboxingTable.unboxCallee(
                  for: interfaceSig.returnType,
                  types: sema.types,
                  requireNonNull: true,
                  preferStaticPrimitive: true
              )
    {
        let unboxed = arena.appendTemporary(type: interfaceSig.returnType)
        body.append(.call(
            symbol: nil,
            callee: unboxCallee,
            arguments: [callResult],
            result: unboxed,
            canThrow: false,
            thrownResult: nil
        ))
        bridgeResult = unboxed
    } else {
        bridgeResult = callResult
    }
    body.append(.returnValue(bridgeResult))
    if let barrierFailLabel, let barrierDefault {
        body.append(.label(barrierFailLabel))
        let defaultExpr: KIRExprID
        switch barrierDefault {
        case .booleanFalse:
            defaultExpr = arena.appendExpr(.boolLiteral(false), type: interfaceSig.returnType)
            body.append(.constValue(result: defaultExpr, value: .boolLiteral(false)))
        case .indexNegativeOne:
            defaultExpr = arena.appendExpr(.intLiteral(-1), type: interfaceSig.returnType)
            body.append(.constValue(result: defaultExpr, value: .intLiteral(-1)))
        case .nullValue:
            defaultExpr = arena.appendExpr(.null, type: interfaceSig.returnType)
            body.append(.constValue(result: defaultExpr, value: .null))
        }
        body.append(.returnValue(defaultExpr))
    }
    body.append(.endBlock)

    let bridgeDecl = arena.appendDecl(
        .function(
            KIRFunction(
                symbol: bridgeSymbol,
                name: bridgeName,
                params: bridgeParams,
                returnType: interfaceSig.returnType,
                body: body,
                isSuspend: false,
                isInline: false
            )
        )
    )
    driver?.ctx.appendGeneratedCallableDecl(bridgeDecl)
    if driver == nil {
        let bridgeSignature = interfaceDispatchReceiver == nil
            ? interfaceSig
            : FunctionSignature(
                parameterTypes: interfaceParamTypes,
                returnType: interfaceSig.returnType,
                canThrow: interfaceSig.canThrow
            )
        sema.symbols.setFunctionSignature(bridgeSignature, for: bridgeSymbol)
    }

    return bridgeSymbol
}

private func kirCollectionContainsBridgeMethod(
    _ method: SymbolID,
    sema: SemaModule,
    interner: StringInterner
) -> Bool {
    guard sema.symbols.symbol(method).map({ interner.resolve($0.name) == "contains" }) == true,
          sema.symbols.functionSignature(for: method)?.parameterTypes.count == 1,
          let owner = sema.symbols.parentSymbol(for: method),
          let fqName = sema.symbols.symbol(owner)?.fqName.map(interner.resolve)
    else {
        return false
    }

    let collectionContainsOwners: Set<[String]> = [
        ["kotlin", "collections", "Collection"],
        ["kotlin", "collections", "MutableCollection"],
        ["kotlin", "collections", "Set"],
        ["kotlin", "collections", "MutableSet"],
        ["kotlin", "collections", "List"],
        ["kotlin", "collections", "MutableList"],
        ["kotlin", "collections", "AbstractCollection"],
        ["kotlin", "collections", "AbstractMutableCollection"],
        ["kotlin", "collections", "AbstractSet"],
        ["kotlin", "collections", "AbstractMutableSet"],
        ["kotlin", "collections", "AbstractList"],
        ["kotlin", "collections", "AbstractMutableList"],
    ]
    return collectionContainsOwners.contains(fqName)
}

/// Registers a nominal type's vtable implementations on an object produced by
/// a runtime collection factory (for example `LinkedHashSet()` lowered to
/// `__kk_set_of`). Factory-returned boxes never pass through `kk_object_new`,
/// so the constructor-site registrations in `appendObjectVtableMethodRegistrations`
/// never ran for them; without this, an open member such as `LinkedHashSet.size`
/// dispatches through a vtable slot the box never had registered and the runtime
/// lookup traps.
///
/// Unlike `appendObjectVtableMethodRegistrations` this variant runs in driver-less
/// lowering passes (it only needs `KIRContext`-level services), so it cannot create
/// `itableBridgeSymbolForMethod` shims; the registered implementations are the
/// class's own external-link bridges, whose ABI already matches the erased vtable
/// signature.
func appendFactoryObjectVtableMethodRegistrations<C: RangeReplaceableCollection>(
    objectValue: KIRExprID,
    nominalSymbol: SymbolID,
    sema: SemaModule,
    cache: KIRNominalDispatchCache,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout C
) where C.Element == KIRInstruction {
    var implementationsBySlot: [Int: SymbolID] = [:]
    for entry in cache.vtableImplementations(for: nominalSymbol, sema: sema) {
        implementationsBySlot[entry.slot] = entry.implementation
    }
    for entry in cache.vtablePropertyAccessorImplementations(for: nominalSymbol, sema: sema) {
        implementationsBySlot[entry.slot] = entry.implementation
    }
    guard !implementationsBySlot.isEmpty else { return }

    let intType = sema.types.intType
    let registerCallee = interner.intern("kk_object_register_vtable_method")
    for (slot, implementation) in implementationsBySlot.sorted(by: { $0.key < $1.key }) {
        let slotExpr = arena.appendExpr(.intLiteral(Int64(slot)), type: intType)
        instructions.append(.constValue(result: slotExpr, value: .intLiteral(Int64(slot))))
        let methodFnExpr = arena.appendExpr(.symbolRef(implementation), type: intType)
        instructions.append(.constValue(result: methodFnExpr, value: .symbolRef(implementation)))
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

/// Registers every direct supertype edge in the ancestor graph of `childSymbol`.
/// Constructor sites used to emit only `child → direct parent`, so a never-
/// instantiated intermediate interface (`Ranked : Comparable<Ranked>`) never
/// contributed `Ranked → Comparable`. Erased `kk_compare_any` then could not
/// prove the operands were Comparable and fell back to pointer comparison.
func appendNominalSupertypeEdgeRegistrations<C: RangeReplaceableCollection>(
    childSymbol: SymbolID,
    extraDirectSupertypes: [SymbolID] = [],
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout C
) where C.Element == KIRInstruction {
    let intType = sema.types.intType
    var pending: [SymbolID] = [childSymbol]
    var visited: Set<SymbolID> = []

    while let current = pending.popLast() {
        guard visited.insert(current).inserted else { continue }
        var parents = sema.symbols.directSupertypes(for: current)
        if current == childSymbol {
            for extra in extraDirectSupertypes where !parents.contains(extra) {
                parents.append(extra)
            }
        }
        pending.append(contentsOf: parents)
        guard !parents.isEmpty else { continue }

        let currentTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: current,
            sema: sema,
            interner: interner
        )
        guard currentTypeID != 0 else { continue }
        let currentExpr = arena.appendExpr(.intLiteral(currentTypeID), type: intType)
        instructions.append(.constValue(result: currentExpr, value: .intLiteral(currentTypeID)))

        var registeredParents: Set<SymbolID> = []
        for parent in parents {
            guard registeredParents.insert(parent).inserted else { continue }
            let parentTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
                symbol: parent,
                sema: sema,
                interner: interner
            )
            guard parentTypeID != 0 else { continue }
            let parentExpr = arena.appendExpr(.intLiteral(parentTypeID), type: intType)
            instructions.append(.constValue(result: parentExpr, value: .intLiteral(parentTypeID)))
            let registerResult = arena.appendTemporary(type: intType)
            let superKind = sema.symbols.symbol(parent)?.kind
            let registerCallee: InternedString = if superKind == .interface {
                interner.intern("kk_type_register_iface")
            } else {
                interner.intern("kk_type_register_super")
            }
            instructions.append(.call(
                symbol: nil,
                callee: registerCallee,
                arguments: [currentExpr, parentExpr],
                result: registerResult,
                canThrow: false,
                thrownResult: nil
            ))
        }
    }
}

func appendObjectItableMethodRegistrations<C: RangeReplaceableCollection>(
    objectValue: KIRExprID,
    nominalSymbol: SymbolID,
    driver: KIRLoweringDriver,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    interfaceFilter: SymbolID? = nil,
    instructions: inout C
) where C.Element == KIRInstruction {
    guard let _ = sema.symbols.symbol(nominalSymbol),
          let objectLayout = sema.symbols.nominalLayout(for: nominalSymbol)
    else {
        return
    }

    let intType = sema.types.intType
    let interfaceSupertypes = driver.ctx.nominalDispatchCache.transitiveInterfaceSupertypes(
        of: nominalSymbol,
        sema: sema
    )
    for interfaceSymbol in interfaceSupertypes {
        if let interfaceFilter, interfaceSymbol != interfaceFilter { continue }
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
        for (methodSymbol, methodSlotInt) in kirItableMethodEntries(
            for: interfaceSymbol,
            interfaceLayout: interfaceLayout,
            sema: sema,
            interner: interner
        ) {
            let implementationSymbol = driver.ctx.nominalDispatchCache.itableImplementation(
                for: methodSymbol,
                in: nominalSymbol,
                sema: sema,
                interner: interner
            )
            if implementationSymbol == methodSymbol,
               sema.symbols.externalLinkName(for: methodSymbol) != nil
            {
                // No override exists and the interface member itself is a
                // runtime `__kk_*` bridge: registering it would re-enter the
                // same runtime op through this very itable slot and recurse.
                // Leave the slot empty so the op's own fallback answers the
                // call (e.g. MutableSet's default bulk bodies, or Map members
                // such as containsKey/containsValue left unimplemented).
                continue
            }
            let bridgeSymbol = itableBridgeSymbolForMethod(
                interfaceMethod: methodSymbol,
                implementation: implementationSymbol,
                nominalSymbol: nominalSymbol,
                driver: driver,
                implementationSignature: interfaceFilter == nil ? nil : sema.symbols.functionSignature(for: implementationSymbol),
                arena: arena,
                sema: sema,
                interner: interner
            )
            let methodSlot = Int64(methodSlotInt)
            let methodSlotExpr = arena.appendExpr(.intLiteral(methodSlot), type: intType)
            instructions.append(.constValue(result: methodSlotExpr, value: .intLiteral(methodSlot)))

            let methodFnExpr = arena.appendExpr(.symbolRef(bridgeSymbol), type: intType)
            instructions.append(.constValue(result: methodFnExpr, value: .symbolRef(bridgeSymbol)))

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

    appendObjectItablePropertyGetterRegistrations(
        objectValue: objectValue,
        nominalSymbol: nominalSymbol,
        sema: sema,
        cache: driver.ctx.nominalDispatchCache,
        arena: arena,
        interner: interner,
        interfaceFilter: interfaceFilter,
        instructions: &instructions
    )
    // Register interface property setters into the itable so a write through
    // an interface-typed receiver can dispatch to them.
    appendObjectItablePropertySetterRegistrations(
        objectValue: objectValue,
        nominalSymbol: nominalSymbol,
        sema: sema,
        cache: driver.ctx.nominalDispatchCache,
        arena: arena,
        interner: interner,
        interfaceFilter: interfaceFilter,
        instructions: &instructions
    )
}

/// BUG-200/KSP-1070: legacy or precompiled library metadata may omit the
/// covariant `MutableIterable.iterator(): MutableIterator<T>` entry from the
/// `MutableIterable` vtable layout. Source-backed layouts include the member
/// when available; add that exact method at slot zero for residual layouts so
/// interface dispatch remains compatible across both paths.
func kirItableMethodEntries(
    for interfaceSymbol: SymbolID,
    interfaceLayout: NominalLayout,
    sema: SemaModule,
    interner: StringInterner
) -> [(methodSymbol: SymbolID, methodSlot: Int)] {
    // Property getter slots are registered separately below. Keep them out of
    // the method table so runtime itables do not receive duplicate entries
    // when a source-backed interface exposes both kinds of slots.
    var methods = interfaceLayout.vtableSlots.filter {
        sema.symbols.symbol($0.key)?.kind == .function
    }
    let mutableIterableFQName = ["kotlin", "collections", "MutableIterable"].map(interner.intern)
    guard let symbol = sema.symbols.symbol(interfaceSymbol),
          symbol.fqName == mutableIterableFQName
    else {
        return methods
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key.rawValue < rhs.key.rawValue : lhs.value < rhs.value
            }
            .map { (methodSymbol: $0.key, methodSlot: $0.value) }
    }

    let iteratorFQName = mutableIterableFQName + [interner.intern("iterator")]
    if let iteratorSymbol = sema.symbols.lookup(fqName: iteratorFQName),
       methods[iteratorSymbol] == nil
    {
        methods[iteratorSymbol] = 0
    }
    return methods
        .sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.rawValue < rhs.key.rawValue : lhs.value < rhs.value
        }
        .map { (methodSymbol: $0.key, methodSlot: $0.value) }
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
    sema: SemaModule,
    interner _: StringInterner,
    transitiveInterfaces: [SymbolID]? = nil
) -> SymbolID? {
    var visited: Set<SymbolID> = []
    var current: SymbolID? = nominalSymbol
    while let nominal = current, visited.insert(nominal).inserted {
        if let found = kirFindMatchingMethod(
            matching: interfaceMethod,
            on: nominal,
            instanceOwner: nominalSymbol,
            sema: sema
        ) {
            return found
        }
        current = kirSuperclass(of: nominal, sema: sema)
    }

    // Interface default implementations live on the interface itself
    // (`Ranked.compareTo` for `Comparable.compareTo`). Prefer the closest
    // owner so a residual `Comparable.compareTo` does not win over Ranked.
    var bestDefault: (distance: Int, symbol: SymbolID)?
    let interfaceSupertypes = transitiveInterfaces
        ?? kirTransitiveInterfaceSupertypes(of: nominalSymbol, sema: sema)
    for interfaceSymbol in interfaceSupertypes {
        guard let found = kirFindMatchingMethod(
            matching: interfaceMethod,
            on: interfaceSymbol,
            instanceOwner: nominalSymbol,
            sema: sema,
            requireSourceBacked: true
        ) else {
            continue
        }
        let distance = kirNominalDistance(from: nominalSymbol, to: interfaceSymbol, sema: sema) ?? Int.max
        if let currentBest = bestDefault {
            if distance < currentBest.distance {
                bestDefault = (distance, found)
            }
        } else {
            bestDefault = (distance, found)
        }
    }
    return bestDefault?.symbol
}

private func kirFindMatchingMethod(
    matching interfaceMethod: SymbolID,
    on nominal: SymbolID,
    instanceOwner: SymbolID,
    sema: SemaModule,
    requireSourceBacked: Bool = false
) -> SymbolID? {
    guard let methodSym = sema.symbols.symbol(interfaceMethod),
          let ownerSym = sema.symbols.symbol(nominal)
    else {
        return nil
    }

    let interfaceSignature = sema.symbols.functionSignature(for: interfaceMethod)
    let interfaceParameterTypes = interfaceSignature?.parameterTypes
    let interfaceParamCount = interfaceParameterTypes?.count
    let children = sema.symbols.children(ofFQName: ownerSym.fqName)
    var firstCandidate: SymbolID?
    var arityMatch: SymbolID?
    for candidate in children {
        guard let candidateSym = sema.symbols.symbol(candidate),
              candidateSym.kind == .function,
              candidateSym.name == methodSym.name,
              sema.symbols.parentSymbol(for: candidate) == nominal
        else {
            continue
        }
        // Interface fallback must use a body-bearing source declaration;
        // synthetic residual declarations are not executable defaults.
        if requireSourceBacked,
           (!sema.symbols.isSourceBackedSymbol(candidate) || candidateSym.flags.contains(.abstractType))
        {
            continue
        }
        let candidateSignature = sema.symbols.functionSignature(for: candidate)
        // A generic method cannot implement a non-generic overload even when
        // its erased parameter is a wildcard. Receiver binders are separate.
        if let interfaceSignature, let candidateSignature,
           interfaceSignature.typeParameterSymbols.count - interfaceSignature.classTypeParameterCount
               != candidateSignature.typeParameterSymbols.count - candidateSignature.classTypeParameterCount
        {
            continue
        }
        let candidateParameterTypes = candidateSignature?.parameterTypes
        if let interfaceSignature, let candidateSignature,
           kirMethodSignatureMatches(source: interfaceSignature, target: candidateSignature,
                                     sourceOwner: sema.symbols.parentSymbol(for: interfaceMethod),
                                     targetOwner: nominal, instanceOwner: instanceOwner,
                                     sourceIsMemberExtension: sema.symbols.memberExtensionOwnerSymbol(for: interfaceMethod) != nil,
                                     targetIsMemberExtension: sema.symbols.memberExtensionOwnerSymbol(for: candidate) != nil,
                                     types: sema.types)
        {
            return candidate
        }
        // A known, incompatible overload must not replace an inherited default.
        if interfaceParameterTypes != nil, candidateParameterTypes != nil {
            continue
        }
        if firstCandidate == nil {
            firstCandidate = candidate
        }
        // BUG-166: retain arity/name fallback only for untracked signatures.
        if arityMatch == nil,
           let interfaceParamCount,
           candidateParameterTypes?.count == interfaceParamCount
        {
            arityMatch = candidate
        }
    }
    return arityMatch ?? firstCandidate
}

func kirMethodSignatureMatches(
    source: FunctionSignature,
    target: FunctionSignature,
    sourceOwner: SymbolID?,
    targetOwner: SymbolID,
    instanceOwner: SymbolID,
    sourceIsMemberExtension: Bool,
    targetIsMemberExtension: Bool,
    types: TypeSystem
) -> Bool {
    guard source.isSuspend == target.isSuspend,
          sourceIsMemberExtension == targetIsMemberExtension,
          methodUpperBoundsMatch(source: source, target: target, sourceOwner: sourceOwner,
                                 targetOwner: targetOwner, instanceOwner: instanceOwner, types: types)
    else { return false }
    if sourceIsMemberExtension {
        guard let sourceReceiverType = source.receiverType,
              let targetReceiverType = target.receiverType
        else { return false }
        let sourceMethodParameters = Array(source.typeParameterSymbols.dropFirst(source.classTypeParameterCount))
        let targetMethodParameters = Array(target.typeParameterSymbols.dropFirst(target.classTypeParameterCount))
        let specializedSourceReceiver = specializeMethodOwnerType(
            sourceReceiverType, owner: sourceOwner, instanceOwner: instanceOwner, types: types
        )
        let alignedSourceReceiver = alphaAlignedMethodType(
            specializedSourceReceiver,
            sourceParameters: sourceMethodParameters,
            targetParameters: targetMethodParameters,
            types: types
        )
        let specializedTargetReceiver = specializeMethodOwnerType(
            targetReceiverType, owner: targetOwner, instanceOwner: instanceOwner, types: types
        )
        guard methodIdentityParameterTypesMatch(
            candidateParameterTypes: [specializedTargetReceiver],
            interfaceParameterTypes: [alignedSourceReceiver],
            types: types
        ) else { return false }
    }
    let alignedSource = alignedMethodParameterTypes(source: source, target: target,
                                                    sourceOwner: sourceOwner, instanceOwner: instanceOwner, types: types)
    let specializedTarget = target.parameterTypes.map {
        specializeMethodOwnerType($0, owner: targetOwner, instanceOwner: instanceOwner, types: types)
    }
    // Method binders are declaration identity, not wildcards. Retain the
    // legacy class-parameter fallback for signatures without method binders.
    if source.typeParameterSymbols.count > source.classTypeParameterCount {
        return methodIdentityParameterTypesMatch(candidateParameterTypes: specializedTarget,
                                                 interfaceParameterTypes: alignedSource, types: types)
    }
    return kirOverrideParameterTypesMatch(candidateParameterTypes: specializedTarget,
                                         interfaceParameterTypes: alignedSource, types: types)
}

/// A class implementing an interface can declare several overloads sharing
/// the interface method's name (StringBuilder has multiple `append`
/// overloads for one `Appendable.append` per arity) — `lookupAll(fqName:)`
/// returns all of them, so `kirFindOverrideMethod` must pick the one whose
/// signature actually matches `interfaceMethod`, not just the first
/// same-named function on the class. Type parameters are treated as
/// wildcards on either side since a generic interface method's parameter
/// type may not be reified the same way on the implementing side.
func kirOverrideParameterTypesMatch(
    candidateParameterTypes: [TypeID],
    interfaceParameterTypes: [TypeID],
    types: TypeSystem
) -> Bool {
    methodIdentityParameterTypesMatch(candidateParameterTypes: candidateParameterTypes,
                                      interfaceParameterTypes: interfaceParameterTypes, types: types,
                                      allowTypeParameterWildcards: true)
}

func kirSuperclass(of nominalSymbol: SymbolID, sema: SemaModule) -> SymbolID? {
    guard let declaredSuperclass = sema.symbols.directSupertypes(for: nominalSymbol).first(where: { superSymbol in
        switch sema.symbols.symbol(superSymbol)?.kind {
        case .class, .enumClass, .object:
            true
        default:
            false
        }
    }) else {
        return nil
    }

    // Anonymous/local nominals can retain an expect declaration as their
    // semantic superclass edge even when a matching actual is present. Runtime
    // dispatch must walk the actual class so it finds body-bearing members.
    guard let expectSuperclass = sema.symbols.symbol(declaredSuperclass),
          expectSuperclass.flags.contains(.expectDeclaration),
          let actualSuperclass = sema.symbols.actualSymbol(for: declaredSuperclass),
          sema.symbols.symbol(actualSuperclass)?.kind == expectSuperclass.kind
    else {
        return declaredSuperclass
    }
    return actualSuperclass
}

private func kirNominalDistance(
    from nominalSymbol: SymbolID,
    to targetSymbol: SymbolID,
    sema: SemaModule
) -> Int? {
    var queue: [(symbol: SymbolID, distance: Int)] = [(nominalSymbol, 0)]
    var visited: Set<SymbolID> = []
    var head = 0

    while head < queue.count {
        let current = queue[head]
        head += 1
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
                // Some local nominals keep the expect declaration as their
                // direct edge while inheriting the actual declaration's
                // layout. Visit both symbols so slot selection can retain the
                // actual method's erased ABI as the dispatch contract.
                if superInfo.flags.contains(.expectDeclaration),
                   let actualSymbol = sema.symbols.actualSymbol(for: superSymbol),
                   sema.symbols.symbol(actualSymbol)?.kind == superInfo.kind
                {
                    queue.append((actualSymbol, current.distance + 1))
                }
            default:
                continue
            }
        }
    }

    return nil
}
