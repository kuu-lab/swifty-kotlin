extension DataFlowSemaPhase {
    func javaThreadLocalReturnType(
        _ type: TypeID,
        fqName: [InternedString],
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        guard fqName.count == 4,
              fqName.starts(with: KnownCompilerNames(interner: interner).javaLangThreadLocalFQName),
              ["get", "initialValue"].contains(interner.resolve(fqName[3])),
              case .typeParam = types.kind(of: type)
        else { return type }
        return types.withNullability(.platformType, for: type)
    }
}
