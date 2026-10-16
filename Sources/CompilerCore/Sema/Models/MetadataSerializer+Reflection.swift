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
        let isCallable = symbol.kind == .function || symbol.kind == .constructor
        let indexedShape = isCallable ? symbols.importedMemberIndexShape(for: symbol.id) : nil
        // Prefer a signature already updated by semantic analysis. Otherwise
        // the index and shell flags contain the entire callable projection;
        // legacy/eager imports continue through the existing signature path.
        let signature: FunctionSignature?
        if !isCallable {
            signature = nil
        } else if indexedShape != nil {
            signature = symbols.functionSignatureIfKnown(for: symbol.id)
        } else {
            signature = symbols.functionSignature(for: symbol.id)
        }
        return MetadataRecord(
            kind: symbol.kind,
            visibility: symbol.visibility,
            constructorVisibilityInherited: symbol.kind == .constructor
                && symbol.flags.contains(.constructorVisibilityInherited),
            mangledName: "",
            fqName: symbol.fqName.map { interner.resolve($0) }.joined(separator: "."),
            arity: signature?.parameterTypes.count ?? indexedShape?.arity ?? 0,
            isSuspend: signature?.isSuspend ?? (indexedShape != nil && symbol.flags.contains(.suspendFunction)),
            isInline: (signature != nil || indexedShape != nil) && inlineFunctionSymbols.contains(symbol.id),
            declaredFieldCount: layout?.instanceFieldCount,
            declaredInstanceSizeWords: layout?.instanceSizeWords,
            superFQName: superFQNames.isEmpty ? nil : superFQNames.joined(separator: ","),
            isDataClass: symbol.flags.contains(.dataType),
            isSealedClass: symbol.flags.contains(.sealedType),
            isValueClass: symbol.flags.contains(.valueType)
        )
    }
}
