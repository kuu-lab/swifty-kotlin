/// Predicates for bundled Kotlin primitive-array factory declarations.
///
/// The declaration shape is stable across the primitive array families: a
/// top-level Kotlin function with one vararg parameter and a primitive-array
/// return type. Keep this structural so lowering does not grow one name-based
/// exception for every migrated factory.
func isSourceBackedPrimitiveArrayFactory(
    _ symbolID: SymbolID?,
    sema: SemaModule?,
    interner: StringInterner
) -> Bool {
    guard let symbolID,
          let sema,
          sema.symbols.isSourceBackedSymbol(symbolID),
          let symbol = sema.symbols.symbol(symbolID),
          sema.symbols.externalLinkName(for: symbolID) == nil,
          symbol.kind == .function,
          symbol.fqName.count == 2,
          interner.resolve(symbol.fqName[0]) == "kotlin",
          let signature = sema.symbols.functionSignature(for: symbolID),
          signature.parameterTypes.count == 1,
          signature.valueParameterIsVararg.first == true,
          isPrimitiveArrayType(signature.returnType, sema: sema, interner: interner)
    else {
        return false
    }
    return true
}

func isPrimitiveArrayType(
    _ type: TypeID,
    sema: SemaModule,
    interner: StringInterner
) -> Bool {
    let nonNullType = sema.types.makeNonNullable(type)
    guard let (classType, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema) else {
        return false
    }
    let knownNames = KnownCompilerNames(interner: interner)
    return classType.args.isEmpty
        && symbol.name != knownNames.array
        && knownNames.isArrayLikeName(symbol.name)
}

/// The local representation of a primitive vararg is its Kotlin primitive
/// array, not List<T>.  Keep the signature's element type unchanged for call
/// resolution; only the callee local and packed argument use this type.
func primitiveVarargArrayType(
    elementType: TypeID,
    sema: SemaModule,
    interner: StringInterner
) -> TypeID? {
    guard case let .primitive(primitive, .nonNull) = sema.types.kind(of: elementType) else {
        return nil
    }
    let arrayName = interner.intern(primitive.kotlinName + "Array")
    guard let arraySymbol = sema.symbols.lookup(fqName: [interner.intern("kotlin"), arrayName]) else {
        return nil
    }
    return sema.types.make(.classType(ClassType(
        classSymbol: arraySymbol,
        args: [],
        nullability: .nonNull
    )))
}

/// The local representation of a reference vararg is Kotlin's covariant array.
func referenceVarargArrayType(
    elementType: TypeID,
    sema: SemaModule,
    interner: StringInterner
) -> TypeID? {
    guard let arraySymbol = sema.symbols.lookup(fqName: [
        interner.intern("kotlin"),
        interner.intern("Array"),
    ]) else {
        return nil
    }
    return sema.types.make(.classType(ClassType(
        classSymbol: arraySymbol,
        args: [.out(elementType)],
        nullability: .nonNull
    )))
}

/// Returns the runtime nominal type ID for an array-shaped Kotlin type.
///
/// Arrays share one runtime storage representation, so lowering must preserve
/// the static array class at the point where the value is allocated or copied.
func runtimeArrayNominalTypeID(
    _ type: TypeID?,
    sema: SemaModule,
    interner: StringInterner
) -> Int64? {
    guard let type,
          let (classType, symbol) = resolveClassTypeSymbol(
              sema.types.makeNonNullable(type),
              sema: sema
          ),
          classType.args.isEmpty || symbol.name == KnownCompilerNames(interner: interner).array
    else {
        return nil
    }
    let knownNames = KnownCompilerNames(interner: interner)
    guard knownNames.isArrayLikeName(symbol.name) else {
        return nil
    }
    return RuntimeTypeCheckToken.stableNominalTypeID(
        symbol: symbol.id,
        sema: sema,
        interner: interner
    )
}
