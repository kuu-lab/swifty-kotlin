@discardableResult
func emitNonThrowingCall<C: RangeReplaceableCollection>(
    callee: InternedString,
    arg: KIRExprID,
    resultType: TypeID?,
    arena: KIRArena,
    into instructions: inout C
) -> KIRExprID where C.Element == KIRInstruction {
    let result = arena.appendTemporary(type: resultType)
    emitNonThrowingCall(
        callee: callee,
        arg: arg,
        result: result,
        into: &instructions
    )
    return result
}

/// Boxes `value` (statically typed `sourceType`) for storage in an Any-erased
/// slot — vararg elements, array/collection elements, generateSequence seeds
/// and next-function results, and any other "primitive going into a
/// reference-typed slot" boundary. Resolves value classes/enums to their
/// underlying representation first (`resolveValueClassKind`) so a value class
/// or enum boxes via the correct callee instead of being silently skipped
/// (`.classType` never matches `BoxingCalleeTable`'s primitive-only lookup on
/// its own), then tags the box appropriately (`emitBoxCallWithValueClassTag`:
/// `kk_tag_value_class_box` for value classes, `kk_enum_box_ordinal` +
/// `$enumOrdinalToName$<encodedFqName>` for enums). Returns `value` unchanged when no
/// boxing is needed.
func boxValueForAnySlot<C: RangeReplaceableCollection>(
    _ value: KIRExprID,
    sourceType: TypeID,
    types: TypeSystem,
    symbols: SymbolTable?,
    interner: StringInterner,
    arena: KIRArena,
    resultType: TypeID? = nil,
    requireNonNull: Bool = false,
    boxingCalleeTable: BoxingCalleeTable? = nil,
    sema: SemaModule? = nil,
    cache: KIRNominalDispatchCache? = nil,
    into instructions: inout C
) -> KIRExprID where C.Element == KIRInstruction {
    let rawKind = types.kind(of: sourceType)
    let resolvedKind = resolveValueClassKind(rawKind, types: types, symbols: symbols)
    let table = boxingCalleeTable ?? BoxingCalleeTable(interner: interner)
    guard let boxCallee = table.boxCallee(for: resolvedKind, requireNonNull: requireNonNull) else {
        return value
    }
    let effectiveResultType = resultType ?? types.anyType
    let boxedResult = arena.appendTemporary(type: effectiveResultType)
    emitBoxCallWithValueClassTag(
        boxCallee: boxCallee,
        value: value,
        rawSourceKind: rawKind,
        result: boxedResult,
        resultType: effectiveResultType,
        types: types,
        symbols: symbols,
        interner: interner,
        arena: arena,
        sema: sema,
        cache: cache,
        into: &instructions
    )
    return boxedResult
}

/// A store into a `P?`-typed slot (nullable primitive class field, captured
/// variable cell, or backing-field global) must leave the slot
/// box-or-sentinel: a raw `Long`/`ULong`/`Double`/`Float` scalar whose bits
/// collide with `runtimeNullSentinelInt` would read as `null` to every null
/// check (KUU-854). Emitting a `.copy` through a `slotType`-typed temporary
/// lets ABILoweringPass pick the always-boxing `kk_box_*_nonnull` callee for
/// a non-null source while passing existing box/sentinel content through
/// verbatim. Returns `value` unchanged when `slotType` is not a nullable
/// primitive whose scalar can collide with the sentinel.
func normalizedValueForNullablePrimitiveSlot<C: RangeReplaceableCollection>(
    _ value: KIRExprID,
    slotType: TypeID,
    types: TypeSystem,
    arena: KIRArena,
    into instructions: inout C
) -> KIRExprID where C.Element == KIRInstruction {
    guard case let .primitive(primitive, .nullable) = types.kind(of: slotType),
          primitive.rawValueCollidesWithNullSentinel
    else {
        return value
    }
    let slot = arena.appendTemporary(type: slotType)
    instructions.append(.copy(from: value, to: slot))
    return slot
}

func emitNonThrowingCall<C: RangeReplaceableCollection>(
    callee: InternedString,
    arg: KIRExprID,
    result: KIRExprID,
    symbol: SymbolID? = nil,
    into instructions: inout C
) where C.Element == KIRInstruction {
    instructions.append(.call(
        symbol: symbol,
        callee: callee,
        arguments: [arg],
        result: result,
        canThrow: false,
        thrownResult: nil
    ))
}

/// Emits a runtime bridge call whose trailing `outThrown` channel must be
/// present even when the enclosing Kotlin function has no local catch block.
/// Try-lowering may route the call to its local exception slot later.
func emitThrowingCall<C: RangeReplaceableCollection>(
    callee: InternedString,
    arg: KIRExprID,
    result: KIRExprID,
    into instructions: inout C
) where C.Element == KIRInstruction {
    instructions.append(.call(
        symbol: nil,
        callee: callee,
        arguments: [arg],
        result: result,
        canThrow: true,
        thrownResult: nil
    ))
}

/// Resolve `componentN` for destructuring against `receiverType`.
///
/// External members lower to their runtime link name; the resolved symbol is
/// carried along so that source-defined members (e.g. bundled `kotlin.Pair`)
/// dispatch to the compiled function instead of a same-named runtime export,
/// and so that ABI lowering can unbox generic component results.
func resolveDestructuringComponentCallee(
    componentName: InternedString,
    receiverType: TypeID,
    sema: SemaModule,
    interner: StringInterner
) -> (symbol: SymbolID?, callee: InternedString) {
    let chosen = TypeCheckHelpers().collectMemberFunctionCandidates(
        named: componentName,
        receiverType: receiverType,
        sema: sema,
        interner: interner
    ).first
    guard let chosen else {
        return (nil, componentName)
    }
    let symbol = sema.symbols.isSourceBackedSymbol(chosen) ? chosen : nil
    if let linkName = sema.symbols.externalLinkName(for: chosen), !linkName.isEmpty {
        return (symbol, interner.intern(linkName))
    }
    return (symbol, componentName)
}

/// Unboxes `exprID` via `kk_unbox_int` when `staticType` is a concrete
/// (non-null) enum class, otherwise returns `exprID` unchanged.
///
/// Enum constants are raw ordinal Ints everywhere except when they round-trip
/// through an Any-erased slot (e.g. an element read out of
/// `values()`/`entries`, see `kk_enum_box_ordinal`), which leaves them as a
/// boxed handle. `kk_unbox_int` is a no-op pass-through on an
/// already-raw ordinal, so calling this on both operands of an enum
/// `==`/`when` comparison normalizes either representation to a raw ordinal
/// without needing to know which side (if either) is actually boxed.
///
/// Deliberately scoped to non-null enum types only: nullable enum
/// comparisons are unrelated to the values()/entries element bug this
/// exists for, and `kk_unbox_int` treats its null sentinel as ordinal 0,
/// which would misclassify a null as the first enum entry.
func unboxIfEnumTyped<C: RangeReplaceableCollection>(
    _ exprID: KIRExprID,
    staticType: TypeID?,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    into instructions: inout C
) -> KIRExprID where C.Element == KIRInstruction {
    guard let staticType,
          case let .classType(classType) = sema.types.kind(of: staticType),
          classType.nullability == .nonNull,
          let sym = sema.symbols.symbol(classType.classSymbol),
          sym.kind == .enumClass
    else {
        return exprID
    }
    let intType = sema.types.make(.primitive(.int, .nonNull))
    return emitNonThrowingCall(
        callee: ABILoweringPass.primitiveUnboxingCallee(for: .int, interner: interner),
        arg: exprID,
        resultType: intType,
        arena: arena,
        into: &instructions
    )
}

/// Emits a primitive box call (`kk_box_int`/`kk_box_long`/...), and — when
/// `rawSourceKind` is a non-null value class — an additional
/// `kk_tag_value_class_box` call that tags the resulting box with the value
/// class's own stable nominal type ID.
///
/// Value classes are unboxed to their underlying primitive everywhere
/// (ValueClassUnboxingPass) except at reference-type boundaries, where every
/// boxing-callee lookup in ABILoweringPass and CollectionLiteralLoweringPass
/// resolves a value class to its underlying primitive kind first (so it can
/// reuse the ordinary `kk_box_*` callee). Without the extra tag, the
/// resulting box is indistinguishable from a plain boxed primitive, so
/// `is`/`as`/`KClass.isInstance` against the value class name would
/// incorrectly fail — and against the underlying primitive name would
/// incorrectly succeed. `rawSourceKind` must be the *unresolved* kind (i.e.
/// computed before resolving a value class to its underlying primitive) so
/// the value class identity is still visible.
func emitBoxCallWithValueClassTag<C: RangeReplaceableCollection>(
    boxCallee: InternedString,
    value: KIRExprID,
    rawSourceKind: TypeKind,
    result: KIRExprID,
    resultType: TypeID?,
    types: TypeSystem,
    symbols: SymbolTable?,
    interner: StringInterner,
    arena: KIRArena,
    sema: SemaModule? = nil,
    cache: KIRNominalDispatchCache? = nil,
    into instructions: inout C
) where C.Element == KIRInstruction {
    func emitPlainBoxCall() {
        instructions.append(.call(
            symbol: nil, callee: boxCallee, arguments: [value],
            result: result, canThrow: false, thrownResult: nil
        ))
    }
    guard case let .classType(classType) = rawSourceKind,
          classType.nullability == .nonNull,
          let symbols,
          let sym = symbols.symbol(classType.classSymbol)
    else {
        emitPlainBoxCall()
        return
    }
    // `.synthetic` enum classes (e.g. Platform.OsFamily, RegexOption — see
    // ensureSyntheticPlatformEnumClass / rewriteSyntheticEnumEntryRefs) are
    // header-only symbols with no source declSite: they never get a
    // `.nominalType` KIR declaration, so DataEnumSealedSynthesisPass never
    // synthesizes their `$enumOrdinalToName$<encodedFqName>` helper. Fall back to a
    // plain (untagged) box for these — same as before this function grew
    // enum awareness — rather than emitting a call to a helper that will
    // never exist.
    if sym.kind == .enumClass, !sym.flags.contains(.synthetic) {
        emitEnumOrdinalBoxCall(
            ordinal: value,
            classSymbol: classType.classSymbol,
            result: result,
            resultType: resultType,
            types: types,
            symbols: symbols,
            interner: interner,
            arena: arena,
            sema: sema,
            cache: cache,
            into: &instructions
        )
        return
    }
    guard sym.flags.contains(.valueType) else {
        emitPlainBoxCall()
        return
    }
    let classID = RuntimeTypeCheckToken.stableNominalTypeID(
        symbol: classType.classSymbol, symbols: symbols, interner: interner
    )
    guard classID != 0 else {
        emitPlainBoxCall()
        return
    }
    let boxedTemp = arena.appendTemporary(type: resultType)
    instructions.append(.call(
        symbol: nil, callee: boxCallee, arguments: [value],
        result: boxedTemp, canThrow: false, thrownResult: nil
    ))
    let intType = types.make(.primitive(.int, .nonNull))
    let classIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
    instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))
    let tagCallee = interner.intern("kk_tag_value_class_box")
    instructions.append(.call(
        symbol: nil, callee: tagCallee, arguments: [boxedTemp, classIDExpr],
        result: result, canThrow: false, thrownResult: nil
    ))
}

/// Boxes an enum ordinal via `kk_enum_box_ordinal(ordinal, name, classID)`
/// (BUG-177 / BUG-182), resolving `name` at runtime through the enum class's
/// `$enumOrdinalToName$<encodedFqName>` helper and tagging the box with the
/// enum class's stable nominal type ID so `is`/`as`/`as?`/`KClass.isInstance`
/// work after widening to `Any`.
///
/// The helper is called by `SymbolID` when available (e.g. for a precompiled
/// `.kklib` enum) and by bare name otherwise: boxing can be lowered *before*
/// DataEnumSealedSynthesisPass has run for source enums, so the Sema symbol
/// may not exist yet. Codegen resolves unnamed calls by scanning every KIR
/// function for one whose name and arity match (`resolveUnnamedInternalFunction`),
/// which by then includes the synthesized helper regardless of pass order.
func emitEnumOrdinalBoxCall<C: RangeReplaceableCollection>(
    ordinal: KIRExprID,
    classSymbol: SymbolID,
    result: KIRExprID,
    resultType: TypeID?,
    types: TypeSystem,
    symbols: SymbolTable,
    interner: StringInterner,
    arena: KIRArena,
    sema: SemaModule? = nil,
    cache: KIRNominalDispatchCache? = nil,
    into instructions: inout C
) where C.Element == KIRInstruction {
    guard let classSym = symbols.symbol(classSymbol),
          classSym.kind == .enumClass,
          !classSym.flags.contains(.synthetic)
    else {
        preconditionFailure("emitEnumOrdinalBoxCall requires a non-synthetic, source-backed enum class symbol")
    }

    // BUG-A: an Any-erased rendering of the box (println on a boxed
    // value, list/collection elements, etc.) must honor a user `toString()`
    // override the same way the direct, statically-typed path does --
    // otherwise a boxed `Op.MUL` prints "MUL" instead of "times".
    let nameHelperCallee: InternedString
    let helperSymbol: SymbolID?
    if let override = enumToStringOverrideHelper(for: classSym, symbols: symbols, interner: interner) {
        nameHelperCallee = override.name
        helperSymbol = override.symbol
    } else {
        nameHelperCallee = NameMangler.enumOrdinalToNameHelperName(for: classSym, interner: interner)
        helperSymbol = symbols.lookupAll(fqName: classSym.fqName + [nameHelperCallee]).first { id in
            symbols.symbol(id).map { $0.kind == .function } ?? false
        }
    }
    let nameResult = arena.appendTemporary(type: types.stringType)
    instructions.append(.call(
        symbol: helperSymbol, callee: nameHelperCallee, arguments: [ordinal],
        result: nameResult, canThrow: false, thrownResult: nil
    ))

    let classID = RuntimeTypeCheckToken.stableNominalTypeID(
        symbol: classSymbol, symbols: symbols, interner: interner
    )
    let intType = types.make(.primitive(.int, .nonNull))
    let classIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
    instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))

    let boxCallee = interner.intern("kk_enum_box_ordinal")
    instructions.append(.call(
        symbol: nil, callee: boxCallee, arguments: [ordinal, nameResult, classIDExpr],
        result: result, canThrow: false, thrownResult: nil
    ))

    // BUG-B: an enum value crossing into an interface-typed slot (e.g. `val
    // nm: Named = Dir.S`) is boxed here the same way it is for Any-erasure,
    // but a dynamic itable dispatch through that interface reference
    // (`nm.label`, or a bound `Named::label` reference) resolves its itable
    // slot per-*object* via `kk_object_register_itable_iface` -- the
    // registration every other heap object gets from its own `<init>`
    // (`appendObjectItableMethodRegistrations`). Enum entries never run a
    // constructor that could register it, so register it here instead, once
    // per box, using the enum class's statically known itable slot layout.
    appendEnumBoxItableRegistrations(
        boxedValue: result,
        classSymbol: classSymbol,
        types: types,
        symbols: symbols,
        interner: interner,
        arena: arena,
        sema: sema,
        cache: cache,
        into: &instructions
    )
}

private func appendEnumBoxItableRegistrations<C: RangeReplaceableCollection>(
    boxedValue: KIRExprID,
    classSymbol: SymbolID,
    types: TypeSystem,
    symbols: SymbolTable,
    interner: StringInterner,
    arena: KIRArena,
    sema: SemaModule?,
    cache: KIRNominalDispatchCache?,
    into instructions: inout C
) where C.Element == KIRInstruction {
    guard let objectLayout = symbols.nominalLayout(for: classSymbol) else {
        return
    }
    var pending = symbols.directSupertypes(for: classSymbol)
    var visited: Set<SymbolID> = []
    var interfaceSupertypes: [SymbolID] = []
    while let current = pending.popLast() {
        guard visited.insert(current).inserted else { continue }
        if symbols.symbol(current)?.kind == .interface {
            interfaceSupertypes.append(current)
        }
        pending.append(contentsOf: symbols.directSupertypes(for: current))
    }
    guard !interfaceSupertypes.isEmpty else { return }

    let intType = types.make(.primitive(.int, .nonNull))
    for interfaceSymbol in interfaceSupertypes.sorted(by: { $0.rawValue < $1.rawValue }) {
        guard let ifaceSlot = objectLayout.itableSlots[interfaceSymbol] else { continue }
        let interfaceTypeID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: interfaceSymbol, symbols: symbols, interner: interner
        )
        let interfaceTypeExpr = arena.appendExpr(.intLiteral(interfaceTypeID), type: intType)
        instructions.append(.constValue(result: interfaceTypeExpr, value: .intLiteral(interfaceTypeID)))
        let ifaceSlotExpr = arena.appendExpr(.intLiteral(Int64(ifaceSlot)), type: intType)
        instructions.append(.constValue(result: ifaceSlotExpr, value: .intLiteral(Int64(ifaceSlot))))
        let registerResult = arena.appendTemporary(type: intType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_object_register_itable_iface"),
            arguments: [boxedValue, interfaceTypeExpr, ifaceSlotExpr],
            result: registerResult,
            canThrow: false,
            thrownResult: nil
        ))
    }

    // The interface->slot mapping above only tells the runtime where an
    // interface's slots live; each member still needs a function pointer
    // registered at its slot -- what `appendObjectItableMethodRegistrations`
    // does from every other class's `<init>`, which this box never runs.
    // Both methods and property getters need the full `SemaModule` (nominal
    // layouts, member lookup), which not every caller of this boxing helper
    // has threaded through yet; skip them there rather than widen every call
    // site's signature.
    if let sema {
        appendEnumBoxItableMethodRegistrations(
            boxedValue: boxedValue,
            classSymbol: classSymbol,
            interfaceSymbols: interfaceSupertypes.sorted(by: { $0.rawValue < $1.rawValue }),
            objectLayout: objectLayout,
            sema: sema,
            cache: cache ?? KIRNominalDispatchCache(),
            interner: interner,
            arena: arena,
            into: &instructions
        )
        appendObjectItablePropertyGetterRegistrations(
            objectValue: boxedValue,
            nominalSymbol: classSymbol,
            sema: sema,
            cache: cache ?? KIRNominalDispatchCache(),
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }
}

/// Registers the itable method pointers of an enum box (see
/// `appendEnumBoxItableRegistrations`). An enum-owned implementation -- the
/// enum class's own override, or the `$enumEntryDispatch$` helper that
/// switches on the ordinal to reach entry-body overrides -- takes the raw
/// ordinal as its receiver, so it is registered through an
/// `itableBridgeSymbolForMethod` bridge that unboxes the dispatched box. An
/// interface default body keeps the box as its receiver and is registered
/// as-is; anything else (an abstract member with no enum-owned override, or
/// an implementation inherited from `kotlin.Enum`) stays unregistered as
/// before.
private func appendEnumBoxItableMethodRegistrations<C: RangeReplaceableCollection>(
    boxedValue: KIRExprID,
    classSymbol: SymbolID,
    interfaceSymbols: [SymbolID],
    objectLayout: NominalLayout,
    sema: SemaModule,
    cache: KIRNominalDispatchCache,
    interner: StringInterner,
    arena: KIRArena,
    into instructions: inout C
) where C.Element == KIRInstruction {
    guard let classInfo = sema.symbols.symbol(classSymbol) else { return }

    func entryDispatchHelper(for baseSymbol: SymbolID) -> SymbolID? {
        guard let baseInfo = sema.symbols.symbol(baseSymbol) else { return nil }
        let helperName = NameMangler.enumEntryDispatchHelperName(for: baseInfo, interner: interner)
        return sema.symbols.lookupAll(fqName: classInfo.fqName + [helperName]).first { candidate in
            sema.symbols.symbol(candidate)?.kind == .function
                && sema.symbols.parentSymbol(for: candidate) == classSymbol
                && sema.symbols.enumEntryDispatchBaseSymbol(for: candidate) == baseSymbol
        }
    }

    let intType = sema.types.intType
    let registerCallee = interner.intern("kk_object_register_itable_method")
    for interfaceSymbol in interfaceSymbols {
        guard let ifaceSlot = objectLayout.itableSlots[interfaceSymbol],
              let interfaceLayout = sema.symbols.nominalLayout(for: interfaceSymbol)
        else {
            continue
        }
        let entries = kirItableMethodEntries(
            for: interfaceSymbol, interfaceLayout: interfaceLayout, sema: sema, interner: interner
        )
        guard !entries.isEmpty else { continue }
        let ifaceSlotExpr = arena.appendExpr(.intLiteral(Int64(ifaceSlot)), type: intType)
        instructions.append(.constValue(result: ifaceSlotExpr, value: .intLiteral(Int64(ifaceSlot))))

        for (methodSymbol, methodSlot) in entries {
            let implementation = cache.itableImplementation(
                for: methodSymbol, in: classSymbol, sema: sema, interner: interner
            )
            // `registerEnumEntryDispatchFunctions` keys a helper on every
            // base an entry body overrides: the interface method itself, or
            // the enum's own override of it when the enum declares one.
            let target = entryDispatchHelper(for: methodSymbol)
                ?? entryDispatchHelper(for: implementation)
                ?? implementation
            let registered: SymbolID
            if sema.symbols.parentSymbol(for: target) == classSymbol {
                guard let implementationSignature = sema.symbols.functionSignature(for: target) else {
                    continue
                }
                registered = itableBridgeSymbolForMethod(
                    interfaceMethod: methodSymbol,
                    implementation: target,
                    nominalSymbol: classSymbol,
                    implementationSignature: implementationSignature,
                    arena: arena,
                    sema: sema,
                    interner: interner
                )
            } else if target == methodSymbol,
                      sema.symbols.parentSymbol(for: target) == interfaceSymbol,
                      let targetInfo = sema.symbols.symbol(target),
                      !targetInfo.flags.contains(.abstractType),
                      !targetInfo.flags.contains(.synthetic),
                      sema.symbols.externalLinkName(for: target) == nil
            {
                registered = target
            } else {
                continue
            }

            let methodSlotExpr = arena.appendExpr(.intLiteral(Int64(methodSlot)), type: intType)
            instructions.append(.constValue(result: methodSlotExpr, value: .intLiteral(Int64(methodSlot))))
            let methodFnExpr = arena.appendExpr(.symbolRef(registered), type: intType)
            instructions.append(.constValue(result: methodFnExpr, value: .symbolRef(registered)))
            let registerResult = arena.appendTemporary(type: intType)
            instructions.append(.call(
                symbol: nil,
                callee: registerCallee,
                arguments: [boxedValue, ifaceSlotExpr, methodSlotExpr, methodFnExpr],
                result: registerResult,
                canThrow: false,
                thrownResult: nil
            ))
        }
    }
}
