@discardableResult
func emitNonThrowingCall(
    callee: InternedString,
    arg: KIRExprID,
    resultType: TypeID?,
    arena: KIRArena,
    into instructions: inout [KIRInstruction]
) -> KIRExprID {
    let result = arena.appendTemporary(type: resultType)
    emitNonThrowingCall(
        callee: callee,
        arg: arg,
        result: result,
        into: &instructions
    )
    return result
}

func emitNonThrowingCall(
    callee: InternedString,
    arg: KIRExprID,
    result: KIRExprID,
    into instructions: inout [KIRInstruction]
) {
    instructions.append(.call(
        symbol: nil,
        callee: callee,
        arguments: [arg],
        result: result,
        canThrow: false,
        thrownResult: nil
    ))
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
func unboxIfEnumTyped(
    _ exprID: KIRExprID,
    staticType: TypeID?,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    into instructions: inout [KIRInstruction]
) -> KIRExprID {
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
func emitBoxCallWithValueClassTag(
    boxCallee: InternedString,
    value: KIRExprID,
    rawSourceKind: TypeKind,
    result: KIRExprID,
    resultType: TypeID?,
    types: TypeSystem,
    symbols: SymbolTable?,
    interner: StringInterner,
    arena: KIRArena,
    into instructions: inout [KIRInstruction]
) {
    func emitPlainBoxCall() {
        instructions.append(.call(
            symbol: nil, callee: boxCallee, arguments: [value],
            result: result, canThrow: false, thrownResult: nil
        ))
    }
    guard case let .classType(classType) = rawSourceKind,
          classType.nullability == .nonNull,
          let symbols,
          let sym = symbols.symbol(classType.classSymbol),
          sym.flags.contains(.valueType)
    else {
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
