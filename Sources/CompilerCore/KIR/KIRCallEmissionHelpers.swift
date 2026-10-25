/// External object-property getters use the singleton as a dispatch receiver,
/// just like an explicitly qualified member read. Package properties have no
/// receiver. Keep bare reads and generated global initializers on the same ABI.
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

/// Resolves value classes/enums to their underlying representation first
/// (`resolveValueClassKind`) so a value class or enum boxes via the correct
/// callee instead of being silently skipped (`.classType` never matches
/// `BoxingCalleeTable`'s primitive-only lookup on its own).
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
    if let symbols,
       let vcSymbol = nullableUnderlyingValueClassSymbol(of: rawKind, types: types, symbols: symbols)
    {
        let effectiveResultType = resultType ?? types.anyType
        let boxedResult = arena.appendTemporary(type: effectiveResultType)
        emitValueClassBoxCall(
            value: value, classSymbol: vcSymbol, result: boxedResult,
            resultType: effectiveResultType, types: types, symbols: symbols,
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
    instructions.append(.call(
        symbol: symbol,
        callee: callee,
        arguments: [arg],
        result: result,
        canThrow: false
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
        callee: callee,
        arguments: [arg],
        result: result,
        canThrow: true
    ))
}

/// External members lower to their runtime link name; the resolved symbol is
/// carried along so that source-defined members (e.g. bundled `kotlin.Pair`)
/// dispatch to the compiled function instead of a same-named runtime export,
/// and so that ABI lowering can unbox generic component results. `candidate`
/// is the resolved member itself, which `emitDestructuringComponentCall`
/// needs for virtual dispatch even when `symbol` is withheld from a direct call.
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
    /// An open `componentN` overridden in a subclass must dispatch on the
    /// receiver's runtime type (`val (x, y): P = Q(...)` calls `Q.component1`),
    /// while member extensions dispatch on their enclosing receiver and local
    /// component functions need their captured environment at the call site.
    /// Other non-virtual members fall back to the direct `symbol`/`callee` call.
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
        instructions.append(.call(
            symbol: symbol,
            callee: callee,
            arguments: arguments,
            result: result,
            canThrow: false
        ))
    }
}

/// Enum constants are raw ordinal Ints everywhere except when they round-trip
/// through an Any-erased slot (e.g. an element read out of
/// `values()`/`entries`, see `kk_enum_box_ordinal`), which leaves them as a
/// boxed handle. `kk_unbox_int` is a no-op pass-through on an
/// already-raw ordinal, so calling this on both operands of an enum
/// `==`/`when` comparison normalizes either representation to a raw ordinal
/// without needing to know which side (if either) is actually boxed.
///
/// Nullable enums are unboxed too: `kk_unbox_int` passes the null sentinel
/// through unchanged (and unwraps boxed handles to their ordinals), so a
/// null subject compares unequal to every raw ordinal instead of aliasing
/// the first entry. Non-enum static types are still passed through.
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

/// Resolves the enum class symbol of an equality operand's static type,
/// ignoring nullability (`E` and `E?` both resolve). `==`/`!=` and `when`
/// entry matching pick each operand's erased comparison form from this
/// (KUU-3027).
func enumEqualityOperandClassSymbol(_ staticType: TypeID?, sema: SemaModule) -> SymbolID? {
    guard let staticType,
          case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(staticType)),
          sema.symbols.symbol(classType.classSymbol)?.kind == .enumClass
    else {
        return nil
    }
    return classType.classSymbol
}

/// `kk_unbox_int` on an enum operand yields its ordinal and passes the null
/// sentinel through unchanged (the sentinel is not a registered pointer), so
/// a nullable enum slot still compares unequal to every entry and equal to
/// another null slot.
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

/// Boxes a *non-null* enum operand into the canonical enum-tagged box so a
/// structural `==` against an erased peer compares nominal enum identity
/// instead of aliasing the bare ordinal against a boxed scalar of the same
/// value (KUU-3027: `E.A == (0 as Any)` must be false while
/// `(E.A as Any) == E.A` stays true). A nullable enum operand already holds
/// the box-or-sentinel form, so callers leave it untouched.
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

/// Normalizes both sides of an enum-aware `==`/`!=` (and `when` entry match,
/// which desugars to `==`) into a consistent erased form before the
/// structural-compare emission (KUU-3027):
///   - same enum class on both sides, either side nullable: unbox both to
///     ordinals — `kk_unbox_int` passes the null sentinel through, so `null`
///     still compares unequal to any entry and equal to another null slot.
///   - otherwise a *non-null* enum operand is boxed into its canonical
///     enum-tagged form, so `E.A == (0 as Any)` is false while
///     `(E.A as Any) == E.A` stays true. A nullable enum operand already
///     holds that box-or-sentinel form.
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

/// A value class whose *underlying representation can itself be null* — e.g.
/// `@JvmInline value class V(val x: String?)` — cannot reuse the payload
/// pointer for its `V?` slot: a null payload and a null wrapper would be
/// indistinguishable (KUU-3115). For such classes `V` keeps the raw payload
/// representation while `V?`/`Any`/interface/type-parameter slots carry a
/// nominal `RuntimeObjectBox` allocated by `kk_value_class_box`, tagged with
/// the class's stable nominal type ID.
///
/// Returns the class symbol when `kind` is exactly such a non-null
/// value-class type; nil otherwise. Uses `effectiveValueClassUnderlyingType`
/// so interface-implementing value classes — which stay boxed through the
/// ordinary `kk_object_new` path — are excluded the same way everywhere.
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
          let underlyingType = symbols.effectiveValueClassUnderlyingType(for: classType.classSymbol)
    else { return nil }
    var visited: Set<SymbolID> = [classType.classSymbol]
    return valueClassReprCanBeNull(underlyingType, types: types, symbols: symbols, visited: &visited)
        ? classType.classSymbol
        : nil
}

/// Whether a value-class underlying type's runtime representation can carry
/// null — i.e. the underlying type is itself nullable, is an erased type
/// parameter, or chains to another value class whose own payload can be null
/// (`@JvmInline value class V2(val x: V)` where `V`'s payload is nullable).
private func valueClassReprCanBeNull(
    _ type: TypeID,
    types: TypeSystem,
    symbols: SymbolTable,
    visited: inout Set<SymbolID>
) -> Bool {
    switch types.kind(of: type) {
    case .typeParam:
        // Erased generic slots can hold null regardless of the bound.
        return true
    case let .classType(classType) where classType.nullability == .nonNull:
        guard let sym = symbols.symbol(classType.classSymbol),
              sym.flags.contains(.valueType),
              visited.insert(classType.classSymbol).inserted,
              let inner = symbols.effectiveValueClassUnderlyingType(for: classType.classSymbol)
        else { return false }
        return valueClassReprCanBeNull(inner, types: types, symbols: symbols, visited: &visited)
    default:
        return types.nullability(of: type) != .nonNull
    }
}

/// True when `kind` is a slot type whose runtime value is a pointer that may
/// carry a `V?`-style nominal box — i.e. the `V` -> box conversion must run
/// `kk_value_class_box` (KUU-3115). `V` itself is the raw payload, so a
/// non-null slot of the same value class is *not* a box target.
func valueClassBoxTargetIsBoxed(_ kind: TypeKind, symbols: SymbolTable?) -> Bool {
    switch kind {
    case .any, .typeParam:
        return true
    case let .classType(classType):
        if classType.nullability != .nonNull { return true }
        // A different non-null classifier (e.g. an interface the value class
        // implements) is an object slot; the same value class is the payload.
        return symbols?.symbol(classType.classSymbol)?.flags.contains(.valueType) != true
    default:
        return false
    }
}

/// True when `kind` is a slot type whose runtime value may hold a nominal
/// value-class box that `kk_value_class_unbox` must unwrap back to the `V`
/// payload (KUU-3115). Any `.classType` qualifies: the helper's class-ID check
/// makes it a no-op for payloads that arrive already unboxed.
func valueClassUnboxSourceIsBoxed(_ kind: TypeKind, symbols: SymbolTable?) -> Bool {
    switch kind {
    case .any, .typeParam, .classType:
        return true
    default:
        return false
    }
}

/// Emits `kk_value_class_box(value, classID) -> result` — wraps a
/// nullable-underlying value class's raw payload in its nominal
/// `RuntimeObjectBox` so `V?`/`Any`/interface slots observe wrapper nullness
/// separately from payload nullness (KUU-3115).
func emitValueClassBoxCall<C: RangeReplaceableCollection>(
    value: KIRExprID,
    classSymbol: SymbolID,
    result: KIRExprID,
    resultType: TypeID?,
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
    instructions.append(.call(
        callee: interner.intern("kk_value_class_box"),
        arguments: [value, classIDExpr],
        result: result, canThrow: false
    ))
}

/// Emits `kk_value_class_unbox(value, classID) -> result` — unwraps a
/// `V?`-slot nominal box back to the payload a `V`-typed slot expects
/// (KUU-3115). The call is idempotent: payloads and the null sentinel pass
/// through unchanged.
func emitValueClassUnboxCall<C: RangeReplaceableCollection>(
    value: KIRExprID,
    classSymbol: SymbolID,
    result: KIRExprID,
    resultType: TypeID?,
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
    instructions.append(.call(
        callee: interner.intern("kk_value_class_unbox"),
        arguments: [value, classIDExpr],
        result: result, canThrow: false
    ))
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
        instructions.append(.call(
            callee: boxCallee, arguments: [value],
            result: result, canThrow: false
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
    let enumHasOrdinalNameHelper = enumBoxingHasOrdinalNameHelper(
        sym, symbols: symbols, interner: interner
    )
    if enumHasOrdinalNameHelper {
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
    // A value class whose payload can itself be null needs the nominal
    // `RuntimeObjectBox` representation — `kk_box_*` on a null payload would
    // produce the null sentinel, losing `V(null)` (KUU-3115).
    if nullableUnderlyingValueClassSymbol(of: rawSourceKind, types: types, symbols: symbols) != nil {
        emitValueClassBoxCall(
            value: value, classSymbol: classType.classSymbol, result: result,
            resultType: resultType, types: types, symbols: symbols,
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
    instructions.append(.call(
        callee: boxCallee, arguments: [value],
        result: boxedTemp, canThrow: false
    ))
    let intType = types.make(.primitive(.int, .nonNull))
    let classIDExpr = arena.appendExpr(.intLiteral(classID), type: intType)
    instructions.append(.constValue(result: classIDExpr, value: .intLiteral(classID)))
    let tagCallee = interner.intern("kk_tag_value_class_box")
    instructions.append(.call(
        callee: tagCallee, arguments: [boxedTemp, classIDExpr],
        result: result, canThrow: false
    ))
}

/// True when `emitEnumOrdinalBoxCall` can resolve the entry name for this
/// enum class: source-backed enums always synthesize `$enumOrdinalToName$`,
/// while `.synthetic` header-only symbols (platform enums like
/// `RegexOption`/`OsFamily`, `.kklib` imports) may use it only when the
/// helper symbol is actually present (KUU-1364).
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
    instructions.append(.call(
        callee: interner.intern("kk_unbox_int"), arguments: [ordinal],
        result: normalizedOrdinal, canThrow: false
    ))

    // Master registers overridden toString implementations separately for
    // erased rendering, while enum.name continues to use the declared entry name.
    let nameHelperCallee = NameMangler.enumOrdinalToNameHelperName(for: classSym, interner: interner)
    let helperSymbol = symbols.lookupAll(fqName: classSym.fqName + [nameHelperCallee]).first { id in
        symbols.symbol(id).map { $0.kind == .function } ?? false
    }
    let nameResult = arena.appendTemporary(type: types.stringType)
    instructions.append(.call(
        symbol: helperSymbol, callee: nameHelperCallee, arguments: [normalizedOrdinal],
        result: nameResult, canThrow: false
    ))

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

/// Registers the producer-owned renderer for every box with this enum's nominal ID.
/// Imported enums must retain the producer's private entry dispatcher.
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
        // This ABI registers raw-string renderers by nominal ID, independent
        // of whether their payload is a value-class primitive or enum ordinal.
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
    }
}

/// An enum-owned implementation -- the enum class's own override, or the
/// `$enumEntryDispatch$` helper that switches on the ordinal to reach
/// entry-body overrides -- takes the raw ordinal as its receiver, so it is
/// registered through an `itableBridgeSymbolForMethod` bridge that unboxes the
/// dispatched box. An interface default body keeps the box as its receiver and
/// is registered as-is; anything else (an abstract member with no enum-owned
/// override, or an implementation inherited from `kotlin.Enum`) stays
/// unregistered as before.
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
