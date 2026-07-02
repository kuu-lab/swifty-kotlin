import Foundation

/// Compiler-private annotation used by Kotlin-source stdlib declarations to bind runtime ABI names.
extension DataFlowSemaPhase {
    func registerSyntheticKSwiftKRuntimeNameStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let internalPkg = ensurePackage(
            path: ["kswiftk", "internal"],
            symbols: symbols,
            interner: interner
        )
        let internalPkgSymbol = symbols.lookup(fqName: internalPkg)
        let annotationName = interner.intern(KnownCompilerAnnotation.kSwiftKRuntimeName.simpleName)
        let annotationSymbol = ensureAnnotationClassSymbol(
            named: KnownCompilerAnnotation.kSwiftKRuntimeName.simpleName,
            in: internalPkg,
            symbols: symbols,
            interner: interner
        )
        if let internalPkgSymbol {
            symbols.setParentSymbol(internalPkgSymbol, for: annotationSymbol)
        }

        appendKSwiftKRuntimeNameAnnotationMetadata(to: annotationSymbol, symbols: symbols)
        registerSyntheticStringAnnotationPropertyAndConstructor(
            ownerSymbol: annotationSymbol,
            ownerFQName: internalPkg + [annotationName],
            propertyName: "name",
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func appendKSwiftKRuntimeNameAnnotationMetadata(
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        let records = [
            MetadataAnnotationRecord(
                annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                arguments: ["AnnotationTarget.FUNCTION"]
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Retention",
                arguments: ["AnnotationRetention.BINARY"]
            ),
        ]

        var annotations = symbols.annotations(for: symbol)
        for record in records where !annotations.contains(record) {
            annotations.append(record)
        }
        symbols.setAnnotations(annotations, for: symbol)
    }
}
