import Foundation

extension MetadataEncoder {
    /// Only fields serialized by RuntimeReflectionMetadataEmitter belong here.
    /// Library artifacts continue to use the complete buildRecord path.
    func buildRuntimeReflectionRecord(
        for symbol: SemanticSymbol,
        symbols: SymbolTable,
        interner: StringInterner,
        inlineFunctionSymbols: Set<SymbolID>
    ) -> MetadataRecord {
        let isNominal = Self.nominalKinds.contains(symbol.kind)
        let layout = isNominal ? symbols.nominalLayout(for: symbol.id) : nil
        let superFQNames = isNominal ? symbols.directSupertypes(for: symbol.id).compactMap {
            symbols.symbol($0)?.fqName.map { interner.resolve($0) }.joined(separator: ".")
        } : []
        let signature = symbol.kind == .function || symbol.kind == .constructor
            ? symbols.functionSignature(for: symbol.id) : nil
        return MetadataRecord(
            kind: symbol.kind,
            visibility: symbol.visibility,
            mangledName: "",
            fqName: symbol.fqName.map { interner.resolve($0) }.joined(separator: "."),
            arity: signature?.parameterTypes.count ?? 0,
            isSuspend: signature?.isSuspend ?? false,
            isInline: signature != nil && inlineFunctionSymbols.contains(symbol.id),
            declaredFieldCount: layout?.instanceFieldCount,
            declaredInstanceSizeWords: layout?.instanceSizeWords,
            superFQName: superFQNames.isEmpty ? nil : superFQNames.joined(separator: ","),
            isDataClass: symbol.flags.contains(.dataType),
            isSealedClass: symbol.flags.contains(.sealedType),
            isValueClass: symbol.flags.contains(.valueType)
        )
    }
}
