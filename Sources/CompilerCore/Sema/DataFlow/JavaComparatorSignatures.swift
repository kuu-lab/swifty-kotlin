extension DataFlowSemaPhase {
    /// The bundled JVM `kotlin.Comparator` is mapped to `java.util.Comparator`,
    /// whose generic `compare` parameters are platform types at Kotlin call sites.
    /// Keep user-declared Kotlin interfaces strict by applying this only to the
    /// compiler-owned bundled signature.
    func javaComparatorParameterTypes(
        _ parameters: [TypeID],
        fqName: [InternedString],
        types: TypeSystem,
        interner: StringInterner
    ) -> [TypeID] {
        guard fqName.count == 3,
              interner.resolve(fqName[0]) == "kotlin",
              interner.resolve(fqName[1]) == "Comparator",
              interner.resolve(fqName[2]) == "compare",
              parameters.count == 2,
              let first = comparatorTypeParameterSymbol(parameters[0], types: types),
              comparatorTypeParameterSymbol(parameters[1], types: types) == first
        else { return parameters }

        return parameters.map { types.withNullability(.platformType, for: $0) }
    }

    private func comparatorTypeParameterSymbol(_ type: TypeID, types: TypeSystem) -> SymbolID? {
        guard case let .typeParam(parameter) = types.kind(of: type) else { return nil }
        return parameter.symbol
    }
}
