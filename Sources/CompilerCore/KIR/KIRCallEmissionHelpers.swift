func externalGlobalPropertyGetterArguments<C: RangeReplaceableCollection>(
    for property: SymbolID,
    sema: SemaModule,
    arena: KIRArena,
    into instructions: inout C
) -> [KIRExprID] where C.Element == KIRInstruction {
    guard let owner = sema.symbols.parentSymbol(for: property),
          sema.symbols.symbol(owner)?.kind == .object
    else { return [] }
    let ownerType = sema.types.make(.classType(ClassType(
        classSymbol: owner, args: [], nullability: .nonNull
    )))
    let receiver = arena.appendExpr(.symbolRef(owner), type: ownerType)
    instructions.append(.constValue(result: receiver, value: .symbolRef(owner)))
    return [receiver]
}

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
    // A nullable-underlying value class has no primitive box callee; its `Any`
    // representation is the nominal `kk_value_class_box` box (KUU-3115).
    // A reference payload needs the same nominal wrapper: the underlying
    // object may be shared outside the value class, so it cannot be tagged
    // in place. `boxingCallee` emits the `kk_value_class_box` marker for
    // these at reference boundaries; an erased `Any` slot needs it too, or
    // `V(obj)` would arrive as the bare `obj` handle and compare equal to it
    // (KUU-3616).
    if let symbols,
       let vcSymbol = nullableUnderlyingValueClassSymbol(of: rawKind, types: types, symbols: symbols)
           ?? referenceBackedValueClassSymbol(of: rawKind, types: types, symbols: symbols)
    {
        let effectiveResultType = resultType ?? types.anyType
        let boxedResult = arena.appendTemporary(type: effectiveResultType)
        emitValueClassBoxCall(
            value: value, classSymbol: vcSymbol, result: boxedResult, types: types, symbols: symbols,
            interner: interner, arena: arena, into: &instructions
        )
        return boxedResult
    }
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
/// check (KUU-854), and `===` on `P?` operands is JVM reference equality on
/// the boxed value, which requires every nullable primitive slot — not just
/// sentinel-colliding ones — to hold the box (KUU-1385). Emitting a `.copy`
/// through a `slotType`-typed temporary lets ABILoweringPass pick the
/// always-boxing `kk_box_*` callee for a non-null source while passing
/// existing box/sentinel content through verbatim.
func normalizedValueForNullablePrimitiveSlot<C: RangeReplaceableCollection>(
    _ value: KIRExprID,
    slotType: TypeID,
    types: TypeSystem,
    arena: KIRArena,
    into instructions: inout C
) -> KIRExprID where C.Element == KIRInstruction {
    guard case let .primitive(_, nullability) = types.kind(of: slotType),
          nullability != .nonNull
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
    instructions.append(.call(symbol: symbol, callee: callee, arguments: [arg], result: result, canThrow: false))
}

func emitThrowingCall<C: RangeReplaceableCollection>(
    callee: InternedString,
    arg: KIRExprID,
    result: KIRExprID,
    into instructions: inout C
) where C.Element == KIRInstruction {
    instructions.append(.call(callee: callee, arguments: [arg], result: result, canThrow: true))
}

func resolveDestructuringComponentCallee(
    componentName: InternedString,
    receiverType: TypeID,
    semaChosen: SymbolID? = nil,
    sema: SemaModule,
    interner: StringInterner
) -> (symbol: SymbolID?, callee: InternedString, candidate: SymbolID?) {
    // Sema's choice wins: it also covers operator extensions (e.g. a user
    // `operator fun C.component1()`), which the member-only lookup misses.
    let chosen = semaChosen ?? TypeCheckHelpers().collectMemberFunctionCandidates(
        named: componentName,
        receiverType: receiverType,
        sema: sema,
        interner: interner
    ).first
    guard let chosen else {
        return (nil, componentName, nil)
    }
    let symbol = sema.symbols.isSourceBackedSymbol(chosen) ? chosen : nil
    if let linkName = sema.symbols.externalLinkName(for: chosen), !linkName.isEmpty {
        return (symbol, interner.intern(linkName), chosen)
    }
    return (symbol, componentName, chosen)
}

extension CallLowerer {
    func emitDestructuringComponentCall(
        candidate: SymbolID?,
        symbol: SymbolID?,
        callee: InternedString,
        receiverExpr: ExprID?,
        receiverID: KIRExprID,
        result: KIRExprID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) {
        var arguments: [KIRExprID] = []
        var dispatchReceiverID = receiverID
        let isLocalFunction = candidate.flatMap { sema.symbols.symbol($0)?.flags.contains(.localFunction) } == true
        let isMemberExtension = candidate.map { sema.symbols.memberExtensionOwnerSymbol(for: $0) != nil } == true

        if isLocalFunction, let candidate {
            for capturedSymbol in sema.bindings.localFunctionCaptureSymbols(for: candidate) {
                guard let captureValue = driver.lambdaLowerer.captureValueExpr(
                    for: capturedSymbol,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                ) else {
                    assertionFailure("BuildKIRPhase: missing local component function capture '\(capturedSymbol)'")
                    continue
                }
                arguments.append(captureValue)
            }
        }

        if isMemberExtension, let candidate {
            guard let memberExtensionDispatchReceiver = memberExtensionDispatchReceiver(
                for: candidate,
                callExprID: nil,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            ) else {
                assertionFailure("BuildKIRPhase: member-extension component call has no dispatch receiver")
                return
            }
            dispatchReceiverID = memberExtensionDispatchReceiver
            arguments.append(memberExtensionDispatchReceiver)
        }
        arguments.append(receiverID)

        if !isLocalFunction, let virtualInstruction = tryEmitVirtualDispatch(
            chosenCallee: candidate,
            calleeName: callee,
            receiverExpr: isMemberExtension ? nil : receiverExpr,
            loweredReceiverID: dispatchReceiverID,
            isSuperCall: false,
            finalArguments: arguments,
            result: result,
            sema: sema,
            arena: arena,
            interner: interner
        ) {
            instructions.append(virtualInstruction)
            return
        }
        instructions.append(.call(symbol: symbol, callee: callee, arguments: arguments, result: result, canThrow: false))
    }
}

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

func enumEqualityOperandClassSymbol(_ staticType: TypeID?, sema: SemaModule) -> SymbolID? {
    guard let staticType,
          case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(staticType)),
          sema.symbols.symbol(classType.classSymbol)?.kind == .enumClass
    else {
        return nil
    }
    return classType.classSymbol
}

func unboxEnumOperandForEquality<C: RangeReplaceableCollection>(
    _ exprID: KIRExprID,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    into instructions: inout C
) -> KIRExprID where C.Element == KIRInstruction {
    let intType = sema.types.make(.primitive(.int, .nonNull))
    return emitNonThrowingCall(
        callee: ABILoweringPass.primitiveUnboxingCallee(for: .int, interner: interner),
        arg: exprID,
        resultType: intType,
        arena: arena,
        into: &instructions
    )
}

func boxEnumOperandForEquality<C: RangeReplaceableCollection>(
    _ exprID: KIRExprID,
    staticType: TypeID?,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    into instructions: inout C
) -> KIRExprID where C.Element == KIRInstruction {
    guard let staticType,
          case let .classType(classType) = sema.types.kind(of: staticType),
          classType.nullability == .nonNull
    else {
        return exprID
    }
    let boxed = arena.appendTemporary(type: sema.types.anyType)
    emitBoxCallWithValueClassTag(
        boxCallee: ABILoweringPass.primitiveBoxingCallee(for: .int, interner: interner),
        value: exprID,
        rawSourceKind: sema.types.kind(of: staticType),
        result: boxed,
        resultType: sema.types.anyType,
        types: sema.types,
        symbols: sema.symbols,
        interner: interner,
        arena: arena,
        sema: sema,
        into: &instructions
    )
    return boxed
}

func normalizeEnumEqualityOperands<C: RangeReplaceableCollection>(
    lhsID: KIRExprID,
    lhsType: TypeID?,
    rhsID: KIRExprID,
    rhsType: TypeID?,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    into instructions: inout C
) -> (lhs: KIRExprID, rhs: KIRExprID) where C.Element == KIRInstruction {
    let lhsEnumSymbol = enumEqualityOperandClassSymbol(lhsType, sema: sema)
    let rhsEnumSymbol = enumEqualityOperandClassSymbol(rhsType, sema: sema)
    if let lhsEnumSymbol, lhsEnumSymbol == rhsEnumSymbol {
        let ordinalLhs = unboxEnumOperandForEquality(
            lhsID, sema: sema, arena: arena, interner: interner, into: &instructions
        )
        let ordinalRhs = unboxEnumOperandForEquality(
            rhsID, sema: sema, arena: arena, interner: interner, into: &instructions
        )
        return (ordinalLhs, ordinalRhs)
    }
    var effectiveLhsID = lhsID
    var effectiveRhsID = rhsID
    if lhsEnumSymbol != nil {
        effectiveLhsID = boxEnumOperandForEquality(
            lhsID, staticType: lhsType, sema: sema, arena: arena,
            interner: interner, into: &instructions
        )
    }
    if rhsEnumSymbol != nil {
        effectiveRhsID = boxEnumOperandForEquality(
            rhsID, staticType: rhsType, sema: sema, arena: arena,
            interner: interner, into: &instructions
        )
    }
    return (effectiveLhsID, effectiveRhsID)
}

func nullableUnderlyingValueClassSymbol(
    of kind: TypeKind?,
    types: TypeSystem,
    symbols: SymbolTable?
) -> SymbolID? {
    guard case let .classType(classType) = kind,
          classType.nullability == .nonNull,
          let symbols,
          let sym = symbols.symbol(classType.classSymbol),
          sym.flags.contains(.valueType),
          let declaredUnderlyingType = symbols.effectiveValueClassUnderlyingType(for: classType.classSymbol)
    else { return nil }
    let underlyingType = types.substituteNominalTypeParameters(
        in: declaredUnderlyingType,
        owner: classType.classSymbol,
        ownerArgs: classType.args
    )
    var visited: Set<SymbolID> = [classType.classSymbol]
    return valueClassReprCanBeNull(underlyingType, types: types, symbols: symbols, visited: &visited)
        ? classType.classSymbol
        : nil
}

private func valueClassReprCanBeNull(
    _ type: TypeID,
    types: TypeSystem,
    symbols: SymbolTable,
    visited: inout Set<SymbolID>
) -> Bool {
    switch types.kind(of: type) {
    case .typeParam:
        return true
    case let .classType(classType) where classType.nullability == .nonNull:
        guard let sym = symbols.symbol(classType.classSymbol),
              sym.flags.contains(.valueType),
              visited.insert(classType.classSymbol).inserted,
              let declaredInner = symbols.effectiveValueClassUnderlyingType(for: classType.classSymbol)
        else { return false }
        let inner = types.substituteNominalTypeParameters(
            in: declaredInner,
            owner: classType.classSymbol,
            ownerArgs: classType.args
        )
        return valueClassReprCanBeNull(inner, types: types, symbols: symbols, visited: &visited)
    default:
        return types.nullability(of: type) != .nonNull
    }
}

func valueClassBoxTargetIsBoxed(_ kind: TypeKind, symbols: SymbolTable?) -> Bool {
    switch kind {
    case .any, .typeParam:
        return true
    case let .classType(classType):
        if classType.nullability != .nonNull { return true }
        return symbols?.symbol(classType.classSymbol)?.flags.contains(.valueType) != true
    default:
        return false
    }
}

func valueClassUnboxSourceIsBoxed(_ kind: TypeKind, targetClassSymbol: SymbolID) -> Bool {
    switch kind {
    case .any, .typeParam:
        return true
    case let .classType(classType):
        return classType.nullability != .nonNull
            || classType.classSymbol != targetClassSymbol
    default:
        return false
    }
}

/// True when a `.nullAssert`/`!!` operand's static type is non-null AND its
/// runtime slot cannot encode a null value at all — a raw non-null
/// primitive, or the flat payload of a value class kept unboxed.
/// `kk_op_notnull` probes the slot for the null-sentinel bit pattern, but
/// for these operands that pattern is always a legitimate value —
/// `Long.MIN_VALUE`, `ULong`'s `2^63`, `-0.0`, or `V(null)` for a nullable
/// underlying type — never a null reference, so the probe can only fire
/// spuriously and lowering must skip it (KUU-3899). Reference-typed,
/// nullable, platform, and erased slots keep the probe: there the sentinel
/// still means a genuine null (or an illegible platform value, which JVM's
/// `Intrinsics.checkNotNull` reports the same way).
public func nullAssertProbeCannotBeNull(
    _ kind: TypeKind?,
    types: TypeSystem,
    symbols: SymbolTable?
) -> Bool {
    switch kind {
    case .primitive(_, .nonNull):
        return true
    default:
        return isNonNullUnboxedValueClassOperand(kind, symbols: symbols)
    }
}

func isNonNullUnboxedValueClassOperand(
    _ kind: TypeKind?,
    symbols: SymbolTable?
) -> Bool {
    guard case let .classType(classType) = kind,
          classType.nullability == .nonNull,
          let symbols,
          symbols.symbol(classType.classSymbol)?.flags.contains(.valueType) == true
    else { return false }
    return symbols.effectiveValueClassUnderlyingType(for: classType.classSymbol) != nil
}

func emitValueClassBoxCall<C: RangeReplaceableCollection>(
    value: KIRExprID,
    classSymbol: SymbolID,
    result: KIRExprID,
    types: TypeSystem,
    symbols: SymbolTable,
    interner: StringInterner,
    arena: KIRArena,
    into instructions: inout C
) where C.Element == KIRInstruction {
    let classID = RuntimeTypeCheckToken.stableNominalTypeID(
        symbol: classSymbol, symbols: symbols, interner: interner
    )
    let intType = types.make(.primitive(.int, .nonNull))
    let classIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
    instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))
    instructions.append(.call(callee: interner.intern("kk_value_class_box"), arguments: [value, classIDExpr], result: result, canThrow: false))
}

func emitValueClassUnboxCall<C: RangeReplaceableCollection>(
    value: KIRExprID,
    classSymbol: SymbolID,
    result: KIRExprID,
    types: TypeSystem,
    symbols: SymbolTable,
    interner: StringInterner,
    arena: KIRArena,
    into instructions: inout C
) where C.Element == KIRInstruction {
    let classID = RuntimeTypeCheckToken.stableNominalTypeID(
        symbol: classSymbol, symbols: symbols, interner: interner
    )
    let intType = types.make(.primitive(.int, .nonNull))
    let classIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
    instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))
    instructions.append(.call(callee: interner.intern("kk_value_class_unbox"), arguments: [value, classIDExpr], result: result, canThrow: false))
}

func unboxedValueClassReceiverExpr<C: RangeReplaceableCollection>(
    value: KIRExprID,
    receiverType: TypeID,
    types: TypeSystem,
    symbols: SymbolTable,
    interner: StringInterner,
    arena: KIRArena,
    into instructions: inout C
) -> KIRExprID where C.Element == KIRInstruction {
    let rawReceiverKind = types.kind(of: receiverType)
    guard case let .classType(receiverClass) = rawReceiverKind,
          receiverClass.nullability == .nonNull,
          symbols.symbol(receiverClass.classSymbol)?.flags.contains(.valueType) == true
    else {
        return value
    }
    if let valueClassSymbol = nullableUnderlyingValueClassSymbol(
        of: rawReceiverKind, types: types, symbols: symbols
    ) ?? referenceBackedValueClassSymbol(
        of: rawReceiverKind, types: types, symbols: symbols
    ) {
        // A value already statically typed as the non-null `V` carries the
        // raw payload representation — which *is* what member bodies consume
        // — even when the payload is itself a nominal box of the same class
        // (`VC(VC(5))` stores a boxed inner `VC` as `v`). Unboxing here would
        // strip that legitimate inner wrapper (KUU-4086). Only `V?`, erased
        // (`Any`/type-parameter), or foreign reference slots carry the outer
        // nominal box that `kk_value_class_unbox` removes.
        if let valueType = arena.exprType(value),
           case let .classType(valueClass) = types.kind(of: valueType),
           valueClass.nullability == .nonNull,
           valueClass.classSymbol == receiverClass.classSymbol
        {
            return value
        }
        let unboxedReceiver = arena.appendTemporary(type: receiverType)
        emitValueClassUnboxCall(
            value: value,
            classSymbol: valueClassSymbol,
            result: unboxedReceiver,
            types: types,
            symbols: symbols,
            interner: interner,
            arena: arena,
            into: &instructions
        )
        if let declaredUnderlyingType = symbols.effectiveValueClassUnderlyingType(for: valueClassSymbol) {
            let underlyingType = types.substituteNominalTypeParameters(
                in: declaredUnderlyingType,
                owner: valueClassSymbol,
                ownerArgs: receiverClass.args
            )
            if let primitiveUpperBound = resolvePrimitiveValueUpperBound(
                of: underlyingType,
                types: types,
                symbols: symbols
            ), case .primitive(_, .nonNull) = types.kind(of: primitiveUpperBound),
               let unboxCallee = BoxingCalleeTable(interner: interner).unboxCallee(
                   for: primitiveUpperBound,
                   types: types,
                   requireNonNull: true,
                   preferStaticPrimitive: true
               )
            {
                let primitiveReceiver = arena.appendTemporary(type: primitiveUpperBound)
                instructions.append(.call(
                    callee: unboxCallee,
                    arguments: [unboxedReceiver],
                    result: primitiveReceiver,
                    canThrow: false
                ))
                return primitiveReceiver
            }
        }
        return unboxedReceiver
    }
    let resolvedReceiverKind = resolveValueClassKind(rawReceiverKind, types: types, symbols: symbols)
    if case .primitive = resolvedReceiverKind,
       let unboxCallee = BoxingCalleeTable(interner: interner).unboxCallee(
           for: resolvedReceiverKind,
           requireNonNull: true
       )
    {
        let unboxedReceiver = arena.appendTemporary(type: types.make(resolvedReceiverKind))
        instructions.append(.call(
            callee: unboxCallee,
            arguments: [value],
            result: unboxedReceiver,
            canThrow: false
        ))
        return unboxedReceiver
    }
    return value
}

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
///
/// Nullable-underlying value classes are different again (KUU-3115): the
/// primitive box path cannot keep a null payload apart from a null wrapper,
/// so they box through `kk_value_class_box` instead of `kk_box_*` + tag.
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
        instructions.append(.call(callee: boxCallee, arguments: [value], result: result, canThrow: false))
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
    let enumHasOrdinalNameHelper = enumBoxingHasOrdinalNameHelper(
        sym, symbols: symbols, interner: interner
    )
    if enumHasOrdinalNameHelper {
        emitEnumOrdinalBoxCall(
            ordinal: value,
            classSymbol: classType.classSymbol,
            result: result,
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
    let primitiveBoxCallees: Set<InternedString> = [
        interner.intern("kk_box_long_nonnull"),
        interner.intern("kk_box_long_nonnull_static"),
        interner.intern("kk_box_ulong_nonnull"),
        interner.intern("kk_box_ulong_nonnull_static"),
    ]
    if primitiveBoxCallees.contains(boxCallee) {
        let classID = RuntimeTypeCheckToken.stableNominalTypeID(
            symbol: classType.classSymbol, symbols: symbols, interner: interner
        )
        guard classID != 0 else {
            emitPlainBoxCall()
            return
        }
        let intType = types.make(.primitive(.int, .nonNull))
        let classIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
        instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))
        let isUnsigned = boxCallee == interner.intern("kk_box_ulong_nonnull")
            || boxCallee == interner.intern("kk_box_ulong_nonnull_static")
        let isStatic = boxCallee == interner.intern("kk_box_long_nonnull_static")
            || boxCallee == interner.intern("kk_box_ulong_nonnull_static")
        let isUnsignedExpr = arena.appendExpr(.intLiteral(isUnsigned ? 1 : 0), type: intType)
        instructions.append(.constValue(result: isUnsignedExpr, value: .intLiteral(isUnsigned ? 1 : 0)))
        let isStaticExpr = arena.appendExpr(.intLiteral(isStatic ? 1 : 0), type: intType)
        instructions.append(.constValue(result: isStaticExpr, value: .intLiteral(isStatic ? 1 : 0)))
        instructions.append(.call(
            callee: interner.intern("kk_value_class_box_primitive"),
            arguments: [value, classIDExpr, isUnsignedExpr, isStaticExpr],
            result: result,
            canThrow: false
        ))
        return
    }
    // A nullable payload needs a nominal wrapper to distinguish `V(null)`
    // from null. A reference payload also needs a wrapper rather than tagging
    // the original object, which may be shared outside the value class.
    if boxCallee == interner.intern("kk_value_class_box")
        || nullableUnderlyingValueClassSymbol(of: rawSourceKind, types: types, symbols: symbols) != nil
    {
        emitValueClassBoxCall(
            value: value, classSymbol: classType.classSymbol, result: result, types: types, symbols: symbols,
            interner: interner, arena: arena, into: &instructions
        )
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
    instructions.append(.call(callee: boxCallee, arguments: [value], result: boxedTemp, canThrow: false))
    let intType = types.make(.primitive(.int, .nonNull))
    let classIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
    instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))
    let tagCallee = interner.intern("kk_tag_value_class_box")
    instructions.append(.call(callee: tagCallee, arguments: [boxedTemp, classIDExpr], result: result, canThrow: false))
}

func enumBoxingHasOrdinalNameHelper(
    _ sym: SemanticSymbol,
    symbols: SymbolTable,
    interner: StringInterner
) -> Bool {
    guard sym.kind == .enumClass else { return false }
    guard sym.flags.contains(.synthetic) else { return true }
    let probeName = NameMangler.enumOrdinalToNameHelperName(for: sym, interner: interner)
    return symbols.lookupAll(fqName: sym.fqName + [probeName]).contains { id in
        symbols.symbol(id).map { $0.kind == .function } ?? false
    }
}

func emitEnumOrdinalBoxCall<C: RangeReplaceableCollection>(
    ordinal: KIRExprID,
    classSymbol: SymbolID,
    result: KIRExprID,
    types: TypeSystem,
    symbols: SymbolTable,
    interner: StringInterner,
    arena: KIRArena,
    sema: SemaModule? = nil,
    cache: KIRNominalDispatchCache? = nil,
    into instructions: inout C
) where C.Element == KIRInstruction {
    guard let classSym = symbols.symbol(classSymbol),
          classSym.kind == .enumClass
    else {
        preconditionFailure("emitEnumOrdinalBoxCall requires an enum class symbol")
    }
    if classSym.flags.contains(.synthetic) {
        // Header-only synthetic enums never get a `$enumOrdinalToName$`
        // helper; `.kklib`-imported enums are synthetic-flagged but carry
        // theirs in the artifact, so only those with a resolvable helper
        // may proceed (KUU-1364).
        let probeName = NameMangler.enumOrdinalToNameHelperName(for: classSym, interner: interner)
        let helperExists = symbols.lookupAll(fqName: classSym.fqName + [probeName]).contains { id in
            symbols.symbol(id).map { $0.kind == .function } ?? false
        }
        precondition(helperExists,
                     "emitEnumOrdinalBoxCall requires a non-synthetic enum class symbol or an imported enum with a serialized helper")
    }

    // Casts can retain a tagged box while exposing a concrete enum type.
    // Normalize both raw and boxed inputs before reading or storing the
    // ordinal, so a reboxed enum cannot contain another handle as its value.
    let intType = types.make(.primitive(.int, .nonNull))
    let normalizedOrdinal = arena.appendTemporary(type: intType)
    instructions.append(.call(callee: interner.intern("kk_unbox_int"), arguments: [ordinal], result: normalizedOrdinal, canThrow: false))

    let nameHelperCallee = NameMangler.enumOrdinalToNameHelperName(for: classSym, interner: interner)
    let helperSymbol = symbols.lookupAll(fqName: classSym.fqName + [nameHelperCallee]).first { id in
        symbols.symbol(id).map { $0.kind == .function } ?? false
    }
    let nameResult = arena.appendTemporary(type: types.stringType)
    instructions.append(.call(symbol: helperSymbol, callee: nameHelperCallee, arguments: [normalizedOrdinal], result: nameResult, canThrow: false))

    let classID = RuntimeTypeCheckToken.stableNominalTypeID(
        symbol: classSymbol, symbols: symbols, interner: interner
    )
    let classIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
    instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))

    instructions.append(.call(
        callee: interner.intern("kk_enum_box_ordinal"),
        arguments: [normalizedOrdinal, nameResult, classIDExpr],
        result: result, canThrow: false
    ))

    if let sema {
        appendEnumAnyToStringRegistration(
            classSymbol: classSym, sema: sema,
            arena: arena, interner: interner, into: &instructions
        )
    }

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

func appendEnumAnyToStringRegistration<C: RangeReplaceableCollection>(
    classSymbol: SemanticSymbol,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    into instructions: inout C
) where C.Element == KIRInstruction {
    guard !classSymbol.flags.contains(.importedLibrary),
          let override = enumToStringOverrideHelper(for: classSymbol, symbols: sema.symbols, interner: interner),
          let bridge = anyToStringBridgeSymbolForImplementation(
              override.symbol, arena: arena, sema: sema, interner: interner
          )
    else { return }
    let intType = sema.types.intType
    let bridgeExpr = arena.appendExpr(.symbolRef(bridge), type: intType)
    instructions.append(.constValue(result: bridgeExpr, value: .symbolRef(bridge)))
    let classID = RuntimeTypeCheckToken.stableNominalTypeID(
        symbol: classSymbol.id, symbols: sema.symbols, interner: interner
    )
    let classIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
    instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))
    let registerResult = arena.appendTemporary(type: intType)
    instructions.append(.call(
        callee: interner.intern("kk_value_class_register_any_to_string"),
        arguments: [classIDExpr, bridgeExpr], result: registerResult,
        canThrow: false
    ))
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
            callee: interner.intern("kk_object_register_itable_iface"),
            arguments: [boxedValue, interfaceTypeExpr, ifaceSlotExpr],
            result: registerResult,
            canThrow: false
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
        appendObjectItablePropertySetterRegistrations(
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
                      // Imported members all carry `.synthetic`, so use the
                      // stub predicate (imported stdlib + empty link name) —
                      // a `kk_fn_*` interface default is a real body and must
                      // register (KUU-3258).
                      !sema.symbols.isSyntheticStubSymbol(target),
                      (sema.symbols.externalLinkName(for: target).map {
                          !$0.isEmpty && CallLowerer.isSourceBackedLinkName($0)
                      } ?? true)
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
                callee: registerCallee,
                arguments: [boxedValue, ifaceSlotExpr, methodSlotExpr, methodFnExpr],
                result: registerResult,
                canThrow: false
            ))
        }
    }
}
