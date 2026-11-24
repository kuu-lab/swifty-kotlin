func runtimeArrayComponentTypeExpr<Instructions: RangeReplaceableCollection>(
    for type: TypeID,
    useReifiedToken: Bool = true,
    context: KIRLoweringContext? = nil,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout Instructions
) -> KIRExprID where Instructions.Element == KIRInstruction {
    var activeTypes: Set<TypeID> = []
    var activeParameters: Set<SymbolID> = []
    return boundedRuntimeArrayComponentTypeExpr(
        for: type, useReifiedToken: useReifiedToken, context: context, sema: sema,
        arena: arena, interner: interner, instructions: &instructions,
        activeTypes: &activeTypes, activeParameters: &activeParameters
    )
}

private func boundedRuntimeArrayComponentTypeExpr<Instructions: RangeReplaceableCollection>(
    for type: TypeID,
    useReifiedToken: Bool,
    context: KIRLoweringContext?,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout Instructions,
    activeTypes: inout Set<TypeID>,
    activeParameters: inout Set<SymbolID>
) -> KIRExprID where Instructions.Element == KIRInstruction {
    func integer(_ value: Int64) -> KIRExprID {
        let result = arena.appendExpr(.intLiteral(value), type: sema.types.intType)
        instructions.append(.constValue(result: result, value: .intLiteral(value)))
        return result
    }
    var insertedTypes: [TypeID] = []
    var insertedParameters: [SymbolID] = []
    defer {
        for type in insertedTypes { activeTypes.remove(type) }
        for parameter in insertedParameters { activeParameters.remove(parameter) }
    }
    var erased = sema.types.makeNonNullable(type)
    while true {
        guard activeTypes.count < 64, activeTypes.insert(erased).inserted else { return integer(0) }
        insertedTypes.append(erased)
        guard case let .typeParam(parameter) = sema.types.kind(of: erased) else { break }
        if useReifiedToken,
           sema.symbols.symbol(parameter.symbol)?.flags.contains(.reifiedTypeParameter) == true {
            let symbol = SyntheticSymbolScheme.reifiedKTypeSymbol(for: parameter.symbol)
            let capturedKType: KIRExprID
            if let captured = context?.localValue(for: symbol) {
                capturedKType = captured
            } else {
                let fallback = arena.appendExpr(.symbolRef(symbol), type: sema.types.intType)
                instructions.append(.constValue(result: fallback, value: .symbolRef(symbol)))
                capturedKType = fallback
            }
            let descriptor = arena.appendTemporary(type: sema.types.intType)
            instructions.append(.call(
                callee: interner.intern("__kk_ktype_component_descriptor"),
                arguments: [capturedKType], result: descriptor, canThrow: false
            ))
            return descriptor
        }
        guard activeParameters.insert(parameter.symbol).inserted else { return integer(0) }
        insertedParameters.append(parameter.symbol)
        erased = sema.types.makeNonNullable(
            sema.symbols.typeParameterUpperBounds(for: parameter.symbol).first ?? sema.types.anyType
        )
    }
    let nested: KIRExprID
    if let element = referenceArrayElementType(erased, sema: sema, interner: interner) {
        nested = boundedRuntimeArrayComponentTypeExpr(
            for: element, useReifiedToken: useReifiedToken, context: context, sema: sema,
            arena: arena, interner: interner, instructions: &instructions,
            activeTypes: &activeTypes, activeParameters: &activeParameters
        )
        guard arena.expr(nested) != .intLiteral(0) else { return nested }
    } else {
        nested = integer(0)
    }
    if case let .classType(nominal) = sema.types.kind(of: erased) {
        appendTypeAncestryRegistrations(
            rootSymbol: nominal.classSymbol, sema: sema, arena: arena,
            interner: interner, instructions: &instructions
        )
    }
    let token = integer(RuntimeTypeCheckToken.encode(type: erased, sema: sema, interner: interner))
    let descriptor = arena.appendTemporary(type: sema.types.intType)
    instructions.append(.call(callee: interner.intern("__kk_array_component_type"), arguments: [token, nested], result: descriptor, canThrow: false))
    return descriptor
}

func referenceArrayElementType(_ type: TypeID?, sema: SemaModule, interner: StringInterner) -> TypeID? {
    guard let type, case let .classType(nominal) = sema.types.kind(of: type),
          sema.symbols.symbol(nominal.classSymbol)?.fqName == [interner.intern("kotlin"), interner.intern("Array")],
          let argument = nominal.args.first else { return nil }
    switch argument {
    case let .invariant(type), let .out(type): return type
    case .in, .star: return sema.types.anyType
    }
}

@discardableResult
func appendRuntimeArrayComponentTag<Instructions: RangeReplaceableCollection>(
    _ array: KIRExprID,
    arrayType: TypeID?,
    context: KIRLoweringContext? = nil,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout Instructions
) -> KIRExprID where Instructions.Element == KIRInstruction {
    guard let typeID = runtimeArrayNominalTypeID(arrayType, sema: sema, interner: interner) else { return array }
    // KUU-3537: arrays are never constructed via kk_object_new, so their
    // declared supertypes (e.g. `IntArray : Cloneable`) would otherwise never
    // reach the runtime type graph — emit the ancestry edges at the same
    // point the nominal tag is applied, for both the native `typeParents`
    // table and the WASM `is_assignable` edge walk.
    if let arrayType, case let .classType(arrayClass) = sema.types.kind(of: arrayType) {
        appendTypeAncestryRegistrations(
            rootSymbol: arrayClass.classSymbol, sema: sema, arena: arena,
            interner: interner, instructions: &instructions
        )
    }
    let typeIDExpr = arena.appendExpr(.intLiteral(typeID), type: sema.types.intType)
    instructions.append(.constValue(result: typeIDExpr, value: .intLiteral(typeID)))
    let nominallyTagged = arena.appendTemporary(type: arrayType)
    instructions.append(.call(callee: interner.intern("kk_array_tag_type"), arguments: [array, typeIDExpr], result: nominallyTagged, canThrow: false))
    guard let element = referenceArrayElementType(arrayType, sema: sema, interner: interner) else { return nominallyTagged }
    let component = runtimeArrayComponentTypeExpr(
        for: element, context: context, sema: sema, arena: arena, interner: interner, instructions: &instructions
    )
    let result = arena.appendTemporary(type: arrayType)
    instructions.append(.call(
        callee: interner.intern("__kk_array_tag_component"),
        arguments: [nominallyTagged, component], result: result, canThrow: false
    ))
    return result
}
