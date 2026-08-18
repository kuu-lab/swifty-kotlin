
/// Synthetic stdlib stubs split from the KSP-697 collection residual registry:
/// List indexed members and IndexedValue<T>.
///
/// Split out to isolate merge conflicts between parallel stdlib PRs adding new
/// entries to this package.
extension DataFlowSemaPhase {

    func registerListIndexedMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        listFQName: [InternedString],
        listInterfaceSymbol: SymbolID,
        listTypeParamSymbol: SymbolID,
        listTypeParamType: TypeID,
        bundledIndex: BundledDeclarationIndex = .empty,
        skipStats: SyntheticStubSkipStatsCollector? = nil
    ) {
        let receiverType = types.make(.classType(ClassType(
            classSymbol: listInterfaceSymbol,
            args: [.out(listTypeParamType)],
            nullability: .nonNull
        )))

        // KSP-626: IndexedValue, withIndex, and forEachIndexed are bundled
        // Kotlin source in Stdlib/kotlin/collections/Iterators.kt.
        let listSymbol = listInterfaceSymbol

    }

    /// Create a type parameter `R` with upper bound `Comparable<R>` for use in
    /// selector-based HOF stubs (sortedBy, sortedByDescending, maxByOrNull, etc.).
    ///
    /// When `Comparable` is not yet registered, the `R` parameter is omitted and
    /// `selectorReturnType` falls back to `Any`, avoiding an unconstrained generic.
    ///
    /// - Returns: A tuple of `(rSymbol, rType, comparableRBounds)` when the
    ///   Comparable interface is available, or `nil` when it is not.
}
