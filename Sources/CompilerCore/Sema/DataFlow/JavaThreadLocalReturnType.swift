extension DataFlowSemaPhase {
    /// Java's unannotated T result permits both nullable and non-null Kotlin
    /// consumers and overrides. Metadata erases platform nullability, so restore
    /// this narrow interop contract after importing a source-backed declaration.
    func javaThreadLocalReturnType(
        _ type: TypeID,
        fqName: [InternedString],
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        guard fqName.count == 4,
              fqName.prefix(3).map({ interner.resolve($0) }) == ["java", "lang", "ThreadLocal"],
              ["get", "initialValue"].contains(interner.resolve(fqName[3])),
              case .typeParam = types.kind(of: type)
        else { return type }
        return types.withNullability(.platformType, for: type)
    }
}
