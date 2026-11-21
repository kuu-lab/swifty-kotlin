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
        && (symbol.fqName.isEmpty
            || symbol.fqName == [interner.intern("kotlin"), symbol.name])
        && symbol.name != knownNames.array
        && knownNames.isArrayLikeName(symbol.name)
}

func primitiveVarargArrayType(
    elementType: TypeID,
    sema: SemaModule,
    interner: StringInterner
) -> TypeID? {
    primitiveVarargArrayType(elementType: elementType, symbols: sema.symbols, types: sema.types, interner: interner)
}

func primitiveVarargArrayType(
    elementType: TypeID, symbols: SymbolTable, types: TypeSystem, interner: StringInterner
) -> TypeID? {
    guard case let .primitive(primitive, .nonNull) = types.kind(of: elementType) else {
        return nil
    }
    let arrayName = interner.intern(primitive.kotlinName + "Array")
    guard let arraySymbol = symbols.lookupNominal(fqName: [interner.intern("kotlin"), arrayName]) else {
        return nil
    }
    return types.make(.classType(ClassType(
        classSymbol: arraySymbol,
        args: [],
        nullability: .nonNull
    )))
}

func referenceVarargArrayType(
    elementType: TypeID,
    sema: SemaModule,
    interner: StringInterner
) -> TypeID? {
    guard let arraySymbol = sema.symbols.lookupNominal(fqName: [
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
    guard symbol.fqName.isEmpty
        || symbol.fqName == [interner.intern("kotlin"), symbol.name],
          knownNames.isArrayLikeName(symbol.name) else {
        return nil
    }
    return RuntimeTypeCheckToken.stableNominalTypeID(
        symbol: symbol.id,
        sema: sema,
        interner: interner
    )
}
