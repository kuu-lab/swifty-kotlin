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
